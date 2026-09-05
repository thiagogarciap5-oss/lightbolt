// functions/index.ts — Fit backend (Cloudflare Worker)
//
// Routes:
//   GET  /ping                     health check
//   POST /create-payment-intent    Stripe monthly subscription -> PaymentSheet client secret
//   GET  /subscription-status      is a given Stripe customer currently subscribed
//   POST /cancel-subscription      cancel a customer's subscription (immediately by default)
//   POST /create-setup-intent      SetupIntent for changing the card on file
//   POST /update-payment-method    promote a saved card to customer + subscription default
//   GET  /payment-method           brand/last4 of the card currently on file
//   POST /analyze-meal             2D meal photo -> Gemini Flash -> structured macros JSON
//   GET  /scan-quota               remaining body/meal scans in the rolling 24h window
//   POST /scan-quota/claim         reserve the daily body-scan slot before the on-device solve
//   POST /scan-quota/release       refund that slot when the on-device solve fails
//   POST /username/check           is a username free (unique across every user)
//   POST /username/claim           reserve / rename a username
//   POST /auth/register            claim a username with a password
//   POST /auth/login               sign back in from any device
//   POST /profile/avatar           upload or delete the profile picture
//   GET  /profile/avatar           serve a user's profile picture as an image
//   GET  /account                  one-shot snapshot: profile, plan, family, invite, access
//   GET  /user-search              exact-username lookup for family invitations
//   POST /family/invite            owner invites a user to a seat
//   POST /family/invite/respond    invitee accepts or declines
//   POST /family/remove            owner removes a member or cancels an invite
//   POST /family/leave             member leaves the plan
//   POST /family/disband           server-side cleanup when an owner's plan lapses
//
// Focus Lock tasks are NOT generated here. The app ships a deterministic
// 30,000-task vault (10,000 per difficulty) that runs fully offline.
//
// AI architecture (deliberate, for cloud cost control):
//   Tab 2 Food Scanner  -> Gemini Flash (cheap, 2D vision, 3x/day). Cloud.
//   Tab 3 Body Scanner  -> 100% on-device. AVFoundation + Vision run the whole
//                          measurement pipeline on the user's chip. No frames,
//                          no photos and no measurements are ever uploaded, and
//                          there is no third-party scanning vendor. The server's
//                          only involvement is metering the 1-per-24h allowance.

export { ScanQuota } from "./scan-quota";
export { UserDirectory } from "./user-directory";

import { FAMILY_CAPACITY } from "./user-directory";

type Env = {
  DO: Fetcher;
  STRIPE_SECRET_KEY: string;
  STRIPE_PRICE_ID: string;
  EXPO_PUBLIC_TOOLKIT_URL: string;
  EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: string;
};

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const STRIPE_API = "https://api.stripe.com/v1";
const STRIPE_VERSION = "2024-06-20";
const DEFAULT_PRICE_ID = "price_1U2kHRC6bUwmRNQKYphhsMCN";
/** Family Plan — $70/month, covers the owner plus 5 members. */
const FAMILY_PRICE_ID = "price_1UB0xVC6bUwmRNQK2khSQqkx";
const VISION_MODEL = "google/gemini-3-flash";

/** Hard daily caps, enforced server-side for every user regardless of subscription. */
const DAILY_BODY_SCANS = 1;
const DAILY_MEAL_SCANS = 3;
const QUOTA_WINDOW_MS = 24 * 60 * 60 * 1000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/** Stripe expects application/x-www-form-urlencoded with bracket notation for nested values. */
function encodeForm(value: unknown, prefix = ""): string[] {
  const out: string[] = [];
  if (value === null || value === undefined) return out;
  if (Array.isArray(value)) {
    value.forEach((item, index) => out.push(...encodeForm(item, `${prefix}[${index}]`)));
    return out;
  }
  if (typeof value === "object") {
    for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
      out.push(...encodeForm(nested, prefix ? `${prefix}[${key}]` : key));
    }
    return out;
  }
  out.push(`${encodeURIComponent(prefix)}=${encodeURIComponent(String(value))}`);
  return out;
}

type StripeCall = {
  path: string;
  method?: "GET" | "POST" | "DELETE";
  body?: Record<string, unknown>;
  apiVersion?: string;
};

async function stripeRequest<T>(env: Env, call: StripeCall): Promise<T> {
  const secret = env.STRIPE_SECRET_KEY;
  if (!secret) throw new Error("STRIPE_SECRET_KEY is not configured on the server");

  const method = call.method ?? "POST";
  const encoded = call.body ? encodeForm(call.body).join("&") : "";
  const sendsQuery = method === "GET" || method === "DELETE";
  const url = sendsQuery && encoded ? `${STRIPE_API}${call.path}?${encoded}` : `${STRIPE_API}${call.path}`;

  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${secret}`,
      "Stripe-Version": call.apiVersion ?? STRIPE_VERSION,
      ...(method === "POST" ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body: method === "POST" ? encoded : undefined,
  });

  const text = await response.text();
  let parsed: unknown = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = null;
  }

  if (!response.ok) {
    const message =
      (parsed as { error?: { message?: string } } | null)?.error?.message ??
      `Stripe request failed (${response.status})`;
    console.error("stripe_error", { path: call.path, status: response.status, message });
    throw new Error(message);
  }
  return parsed as T;
}

// MARK: - Scan quota (Durable Object backed)

type QuotaVerdict = {
  allowed: boolean;
  kind: "body" | "meal";
  used: number;
  limit: number;
  resetAt: number | null;
};

/** Device ids are opaque client-generated UUIDs; keep them sane before using as a DO key. */
function normalizeDeviceId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length < 8 || trimmed.length > 128) return null;
  return /^[A-Za-z0-9._:-]+$/.test(trimmed) ? trimmed : null;
}

function quotaRequest(deviceId: string, path: string, init?: RequestInit): Request {
  const request = new Request(`https://internal${path}`, init);
  request.headers.set("X-Rork-DO-Class", "ScanQuota");
  request.headers.set("X-Rork-DO-Id", deviceId);
  return request;
}

/** Reserves one slot of the daily allowance. Returns the verdict either way. */
async function consumeQuota(env: Env, deviceId: string, kind: "body" | "meal", limit: number): Promise<QuotaVerdict> {
  const response = await env.DO.fetch(
    quotaRequest(deviceId, "/consume", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ kind, limit, windowMs: QUOTA_WINDOW_MS }),
    }),
  );
  if (!response.ok) throw new Error(`quota check failed (${response.status})`);
  return (await response.json()) as QuotaVerdict;
}

/** Gives the slot back when the upstream analysis failed through no fault of the user. */
async function releaseQuota(env: Env, deviceId: string, kind: "body" | "meal"): Promise<void> {
  await env.DO
    .fetch(
      quotaRequest(deviceId, "/release", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind }),
      }),
    )
    .catch((error: unknown) => console.warn("quota_release_failed", String(error)));
}

function quotaExceeded(verdict: QuotaVerdict): Response {
  const noun = verdict.kind === "body" ? "body scan" : "meal photo";
  const plural = verdict.limit === 1 ? noun : `${noun}s`;
  return json(
    {
      error: `Daily limit reached — ${verdict.limit} ${plural} per 24 hours. Try again later.`,
      quota: true,
      used: verdict.used,
      limit: verdict.limit,
      resetAt: verdict.resetAt,
    },
    429,
  );
}

async function scanQuotaStatus(request: Request, env: Env): Promise<Response> {
  const deviceId = normalizeDeviceId(new URL(request.url).searchParams.get("deviceId"));
  if (!deviceId) return json({ error: "deviceId is required" }, 400);
  try {
    const response = await env.DO.fetch(
      quotaRequest(deviceId, `/status?bodyLimit=${DAILY_BODY_SCANS}&mealLimit=${DAILY_MEAL_SCANS}`, {
        method: "GET",
      }),
    );
    if (!response.ok) throw new Error(`status failed (${response.status})`);
    return json(await response.json());
  } catch (error) {
    console.error("scan_quota_status_failed", String(error));
    return json({ error: "Could not read your scan allowance." }, 500);
  }
}

/**
 * Body scanning runs entirely on the user's device, so there is no analysis
 * request for the server to meter. The app claims its single daily slot here
 * immediately before the on-device solve, which keeps the 1-per-24h cap
 * authoritative on the server rather than in a client the user can reinstall.
 */
async function claimBodyScan(request: Request, env: Env): Promise<Response> {
  let payload: { deviceId?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const deviceId = normalizeDeviceId(payload.deviceId);
  if (!deviceId) return json({ error: "deviceId is required" }, 400);

  let verdict: QuotaVerdict;
  try {
    verdict = await consumeQuota(env, deviceId, "body", DAILY_BODY_SCANS);
  } catch (error) {
    console.error("body_quota_failed", String(error));
    return json({ error: "Could not verify your daily scan allowance." }, 503);
  }
  if (!verdict.allowed) return quotaExceeded(verdict);

  return json({ claimed: true, used: verdict.used, limit: verdict.limit, resetAt: verdict.resetAt });
}

/** Refunds a claimed slot when the on-device solve couldn't produce a measurement. */
async function releaseBodyScan(request: Request, env: Env): Promise<Response> {
  let payload: { deviceId?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const deviceId = normalizeDeviceId(payload.deviceId);
  if (!deviceId) return json({ error: "deviceId is required" }, 400);

  await releaseQuota(env, deviceId, "body");
  return json({ released: true });
}

type StripeCustomer = { id: string };
type StripeSubscription = {
  id: string;
  status: string;
  current_period_end?: number;
  latest_invoice?: {
    id?: string;
    payment_intent?: { id?: string; client_secret?: string; status?: string } | string | null;
    confirmation_secret?: { client_secret?: string } | null;
  } | null;
};

/**
 * Creates (or reuses) a Stripe customer, opens a monthly subscription in
 * `default_incomplete` state, and returns the PaymentSheet bootstrap payload.
 */
async function createPaymentIntent(request: Request, env: Env): Promise<Response> {
  let payload: {
    customerId?: unknown;
    email?: unknown;
    currency?: unknown;
    amount?: unknown;
    plan?: unknown;
    userId?: unknown;
  } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const email = typeof payload.email === "string" && payload.email.includes("@") ? payload.email : undefined;
  const currency = typeof payload.currency === "string" && payload.currency.length === 3 ? payload.currency : "usd";
  const isFamily = payload.plan === "family";
  const priceId = isFamily ? FAMILY_PRICE_ID : env.STRIPE_PRICE_ID || DEFAULT_PRICE_ID;
  const accountId = normalizeAccountId(payload.userId);

  try {
    let customerId = typeof payload.customerId === "string" && payload.customerId.startsWith("cus_")
      ? payload.customerId
      : undefined;

    if (customerId) {
      // Validate the client-supplied id; a stale/rotated id must not break checkout.
      try {
        await stripeRequest<StripeCustomer>(env, { path: `/customers/${customerId}`, method: "GET" });
      } catch {
        customerId = undefined;
      }
    }

    if (!customerId) {
      const customer = await stripeRequest<StripeCustomer>(env, {
        path: "/customers",
        body: { ...(email ? { email } : {}), metadata: { app: "fit" } },
      });
      customerId = customer.id;
    }

    const subscription = await stripeRequest<StripeSubscription>(env, {
      path: "/subscriptions",
      body: {
        customer: customerId,
        items: [{ price: priceId }],
        payment_behavior: "default_incomplete",
        payment_settings: { save_default_payment_method: "on_subscription" },
        expand: ["latest_invoice.payment_intent"],
        metadata: { app: "fit", currency, plan: isFamily ? "family" : "individual", ...(accountId ? { accountId } : {}) },
      },
    });

    // Bind the Stripe customer to the account now so the family registry can
    // resolve the plan even if the app is killed right after paying.
    if (accountId) {
      await directoryPost(env, "/billing", {
        userId: accountId,
        plan: "none",
        customerId,
      }).catch(() => undefined);
    }

    const invoice = subscription.latest_invoice;
    const intent = typeof invoice?.payment_intent === "object" ? invoice?.payment_intent : null;
    const clientSecret = intent?.client_secret ?? invoice?.confirmation_secret?.client_secret ?? null;

    if (!clientSecret) {
      console.error("missing_client_secret", { subscriptionId: subscription.id, status: subscription.status });
      return json({ error: "Stripe did not return a client secret for this subscription." }, 502);
    }

    const ephemeralKey = await stripeRequest<{ secret: string }>(env, {
      path: "/ephemeral_keys",
      body: { customer: customerId },
      apiVersion: STRIPE_VERSION,
    }).catch(() => null);

    return json({
      clientSecret,
      customerId,
      subscriptionId: subscription.id,
      subscriptionStatus: subscription.status,
      ephemeralKeySecret: ephemeralKey?.secret ?? null,
      plan: isFamily ? "family" : "individual",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("create_payment_intent_failed", message);
    return json({ error: message }, 500);
  }
}

/**
 * Cancels every live subscription for a customer. Immediate by default: the
 * user asked to stop being charged, so billing halts right now and access
 * drops back to the paywall. Pass `atPeriodEnd: true` to keep access until the
 * already-paid period runs out instead.
 */
async function cancelSubscription(request: Request, env: Env): Promise<Response> {
  let payload: { customerId?: unknown; atPeriodEnd?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const customerId = typeof payload.customerId === "string" && payload.customerId.startsWith("cus_")
    ? payload.customerId
    : null;
  if (!customerId) return json({ error: "customerId is required" }, 400);

  const atPeriodEnd = payload.atPeriodEnd === true;

  try {
    const result = await stripeRequest<{ data: StripeSubscription[] }>(env, {
      path: "/subscriptions",
      method: "GET",
      body: { customer: customerId, status: "all", limit: 10 },
    });
    const live = result.data.filter(
      (s) => s.status === "active" || s.status === "trialing" || s.status === "past_due" || s.status === "incomplete",
    );

    if (live.length === 0) {
      return json({ cancelled: true, immediate: true, endsAt: null, message: "No active subscription found." });
    }

    let endsAt: number | null = null;
    for (const sub of live) {
      const updated = atPeriodEnd
        ? await stripeRequest<StripeSubscription>(env, {
            path: `/subscriptions/${sub.id}`,
            body: { cancel_at_period_end: true },
          })
        : await stripeRequest<StripeSubscription>(env, {
            path: `/subscriptions/${sub.id}`,
            method: "DELETE",
          });
      endsAt = updated.current_period_end ?? endsAt;
    }

    return json({ cancelled: true, immediate: !atPeriodEnd, endsAt });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("cancel_subscription_failed", message);
    return json({ error: message }, 500);
  }
}

/**
 * Opens a SetupIntent so the user can attach a different card. Returned to the
 * app as a PaymentSheet bootstrap in setup mode — no charge is made.
 */
async function createSetupIntent(request: Request, env: Env): Promise<Response> {
  let payload: { customerId?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const customerId = typeof payload.customerId === "string" && payload.customerId.startsWith("cus_")
    ? payload.customerId
    : null;
  if (!customerId) return json({ error: "customerId is required" }, 400);

  try {
    const intent = await stripeRequest<{ id: string; client_secret: string }>(env, {
      path: "/setup_intents",
      body: {
        customer: customerId,
        usage: "off_session",
        payment_method_types: ["card"],
        metadata: { app: "fit", purpose: "update_card" },
      },
    });

    const ephemeralKey = await stripeRequest<{ secret: string }>(env, {
      path: "/ephemeral_keys",
      body: { customer: customerId },
      apiVersion: STRIPE_VERSION,
    }).catch(() => null);

    return json({
      clientSecret: intent.client_secret,
      setupIntentId: intent.id,
      customerId,
      ephemeralKeySecret: ephemeralKey?.secret ?? null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("create_setup_intent_failed", message);
    return json({ error: message }, 500);
  }
}

/**
 * After a SetupIntent succeeds, promote the newly saved card to the customer's
 * default and repoint every live subscription at it, so the next renewal bills
 * the new card.
 */
async function updatePaymentMethod(request: Request, env: Env): Promise<Response> {
  let payload: { customerId?: unknown; setupIntentId?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const customerId = typeof payload.customerId === "string" && payload.customerId.startsWith("cus_")
    ? payload.customerId
    : null;
  const setupIntentId = typeof payload.setupIntentId === "string" && payload.setupIntentId.startsWith("seti_")
    ? payload.setupIntentId
    : null;
  if (!customerId || !setupIntentId) return json({ error: "customerId and setupIntentId are required" }, 400);

  try {
    const intent = await stripeRequest<{ payment_method?: string | null; status?: string }>(env, {
      path: `/setup_intents/${setupIntentId}`,
      method: "GET",
    });

    const paymentMethodId = intent.payment_method;
    if (!paymentMethodId) {
      return json({ error: "That card was not saved. Please try again." }, 400);
    }

    await stripeRequest(env, {
      path: `/customers/${customerId}`,
      body: { invoice_settings: { default_payment_method: paymentMethodId } },
    });

    const result = await stripeRequest<{ data: StripeSubscription[] }>(env, {
      path: "/subscriptions",
      method: "GET",
      body: { customer: customerId, status: "all", limit: 10 },
    });
    const live = result.data.filter(
      (s) => s.status === "active" || s.status === "trialing" || s.status === "past_due" || s.status === "unpaid",
    );
    for (const sub of live) {
      await stripeRequest(env, {
        path: `/subscriptions/${sub.id}`,
        body: { default_payment_method: paymentMethodId },
      });
    }

    const card = await describeCard(env, paymentMethodId);
    return json({ updated: true, ...card });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("update_payment_method_failed", message);
    return json({ error: message }, 500);
  }
}

type StripePaymentMethod = {
  id: string;
  card?: { brand?: string; last4?: string; exp_month?: number; exp_year?: number } | null;
};

async function describeCard(env: Env, paymentMethodId: string): Promise<{
  brand: string | null;
  last4: string | null;
  expMonth: number | null;
  expYear: number | null;
}> {
  try {
    const method = await stripeRequest<StripePaymentMethod>(env, {
      path: `/payment_methods/${paymentMethodId}`,
      method: "GET",
    });
    return {
      brand: method.card?.brand ?? null,
      last4: method.card?.last4 ?? null,
      expMonth: method.card?.exp_month ?? null,
      expYear: method.card?.exp_year ?? null,
    };
  } catch {
    return { brand: null, last4: null, expMonth: null, expYear: null };
  }
}

/** Brand + last4 of the card LightBolt will bill next. */
async function paymentMethodStatus(request: Request, env: Env): Promise<Response> {
  const customerId = new URL(request.url).searchParams.get("customerId");
  if (!customerId?.startsWith("cus_")) return json({ error: "customerId is required" }, 400);

  try {
    const customer = await stripeRequest<{
      invoice_settings?: { default_payment_method?: string | null } | null;
    }>(env, { path: `/customers/${customerId}`, method: "GET" });

    let paymentMethodId = customer.invoice_settings?.default_payment_method ?? null;

    if (!paymentMethodId) {
      const methods = await stripeRequest<{ data: StripePaymentMethod[] }>(env, {
        path: "/payment_methods",
        method: "GET",
        body: { customer: customerId, type: "card", limit: 1 },
      });
      paymentMethodId = methods.data[0]?.id ?? null;
    }

    if (!paymentMethodId) {
      return json({ hasCard: false, brand: null, last4: null, expMonth: null, expYear: null });
    }

    const card = await describeCard(env, paymentMethodId);
    return json({ hasCard: Boolean(card.last4), ...card });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("payment_method_status_failed", message);
    return json({ error: message }, 500);
  }
}

async function subscriptionStatus(request: Request, env: Env): Promise<Response> {
  const customerId = new URL(request.url).searchParams.get("customerId");
  if (!customerId?.startsWith("cus_")) return json({ error: "customerId is required" }, 400);

  try {
    const result = await stripeRequest<{ data: StripeSubscription[] }>(env, {
      path: "/subscriptions",
      method: "GET",
      body: { customer: customerId, status: "all", limit: 5 },
    });
    const live = result.data.find((s) => s.status === "active" || s.status === "trialing");
    return json({
      active: Boolean(live),
      status: live?.status ?? result.data[0]?.status ?? "none",
      currentPeriodEnd: live?.current_period_end ?? null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown Stripe failure";
    console.error("subscription_status_failed", message);
    return json({ error: message }, 500);
  }
}

type MealAnalysis = {
  mealName: string;
  estimatedGrams: number;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  confidence: number;
  items: string[];
};

const MEAL_SYSTEM_PROMPT = `You are a precise nutrition estimation engine for a fitness app.
Analyse the food visible in the photo and reply with ONLY a compact JSON object, no markdown fences, matching:
{"mealName":string,"estimatedGrams":number,"calories":number,"protein":number,"carbs":number,"fat":number,"confidence":number,"items":string[]}
Rules:
- mealName: short human label, max 4 words, title case.
- estimatedGrams: total edible weight of the portion shown.
- calories/protein/carbs/fat: totals for the portion shown; grams for macros; integers.
- confidence: 0..1 how certain you are the photo contains identifiable food.
- items: the individual foods you identified.
- If the photo contains no food at all, return mealName "No Food Detected", zeros, confidence 0, and an empty items array.`;

function extractJsonObject(raw: string): unknown {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start === -1 || end <= start) return null;
  try {
    return JSON.parse(raw.slice(start, end + 1));
  } catch {
    return null;
  }
}

function toFiniteNumber(value: unknown, fallback = 0): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? Math.round(parsed * 10) / 10 : fallback;
}

/** Accepts a base64 meal photo and returns safely-decoded macro estimates. */
async function analyzeMeal(request: Request, env: Env): Promise<Response> {
  let payload: { imageBase64?: unknown; mimeType?: unknown; note?: unknown; deviceId?: unknown } = {};
  try {
    payload = (await request.json()) as typeof payload;
  } catch {
    return json({ error: "Malformed JSON body" }, 400);
  }

  const imageBase64 = typeof payload.imageBase64 === "string" ? payload.imageBase64.trim() : "";
  if (imageBase64.length < 128) return json({ error: "imageBase64 is required" }, 400);

  const deviceId = normalizeDeviceId(payload.deviceId);
  if (!deviceId) return json({ error: "deviceId is required" }, 400);

  // Reserve one of the 3 daily meal photos BEFORE spending any AI credits.
  let verdict: QuotaVerdict;
  try {
    verdict = await consumeQuota(env, deviceId, "meal", DAILY_MEAL_SCANS);
  } catch (error) {
    console.error("meal_quota_failed", String(error));
    return json({ error: "Could not verify your daily scan allowance." }, 503);
  }
  if (!verdict.allowed) return quotaExceeded(verdict);

  const mimeType = typeof payload.mimeType === "string" && payload.mimeType.startsWith("image/")
    ? payload.mimeType
    : "image/jpeg";
  const note = typeof payload.note === "string" && payload.note.length < 240 ? payload.note : "";
  const dataUrl = imageBase64.startsWith("data:") ? imageBase64 : `data:${mimeType};base64,${imageBase64}`;

  const toolkitUrl = (env.EXPO_PUBLIC_TOOLKIT_URL || "https://toolkit.rork.com").replace(/\/$/, "");

  try {
    const upstream = await fetch(`${toolkitUrl}/v2/vercel/v1/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: VISION_MODEL,
        temperature: 0.2,
        messages: [
          { role: "system", content: MEAL_SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: note ? `Extra context from the user: ${note}` : "Analyse this meal." },
              { type: "image_url", image_url: { url: dataUrl } },
            ],
          },
        ],
      }),
    });

    const raw = await upstream.text();
    if (!upstream.ok) {
      console.error("vision_upstream_error", { status: upstream.status, body: raw.slice(0, 400) });
      await releaseQuota(env, deviceId, "meal");
      return json(
        { error: "AI service is temporarily down, we are currently trying to fix it.", aiDown: true },
        503,
      );
    }

    const parsedEnvelope = extractJsonObject(raw) as
      | { choices?: Array<{ message?: { content?: unknown } }> }
      | null;
    const content = parsedEnvelope?.choices?.[0]?.message?.content;
    const text = typeof content === "string"
      ? content
      : Array.isArray(content)
        ? content.map((part) => (typeof part === "object" && part && "text" in part ? String((part as { text: unknown }).text) : "")).join("")
        : "";

    const analysisRaw = extractJsonObject(text) as Partial<MealAnalysis> | null;
    if (!analysisRaw || typeof analysisRaw.mealName !== "string") {
      console.error("vision_decode_failed", text.slice(0, 300));
      await releaseQuota(env, deviceId, "meal");
      return json({ error: "Could not read the nutrition result. Retake the photo." }, 422);
    }

    const analysis: MealAnalysis = {
      mealName: analysisRaw.mealName.slice(0, 60),
      estimatedGrams: toFiniteNumber(analysisRaw.estimatedGrams),
      calories: Math.round(toFiniteNumber(analysisRaw.calories)),
      protein: toFiniteNumber(analysisRaw.protein),
      carbs: toFiniteNumber(analysisRaw.carbs),
      fat: toFiniteNumber(analysisRaw.fat),
      confidence: Math.min(1, Math.max(0, toFiniteNumber(analysisRaw.confidence))),
      items: Array.isArray(analysisRaw.items)
        ? analysisRaw.items.filter((i): i is string => typeof i === "string").slice(0, 12)
        : [],
    };

    if (analysis.confidence < 0.15 || analysis.calories === 0) {
      // A photo with no food in it should not burn one of the three slots.
      await releaseQuota(env, deviceId, "meal");
      return json({ error: "No food detected in that photo." }, 422);
    }

    return json({ ...analysis, quotaUsed: verdict.used, quotaLimit: verdict.limit });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown analysis failure";
    console.error("analyze_meal_failed", message);
    await releaseQuota(env, deviceId, "meal");
    return json(
      { error: "AI service is temporarily down, we are currently trying to fix it.", aiDown: true },
      503,
    );
  }
}

// MARK: - Identity, family plan and feedback

type PlanName = "none" | "individual" | "family";

type LivePlan = { active: boolean; plan: PlanName; currentPeriodEnd: number | null };

type StripeSubscriptionWithItems = StripeSubscription & {
  items?: { data: Array<{ price?: { id?: string } | null }> } | null;
};

/** Routes into the single global identity/family registry. */
async function directory<T>(
  env: Env,
  path: string,
  init?: RequestInit,
): Promise<{ status: number; body: T }> {
  const request = new Request(`https://internal${path}`, init);
  request.headers.set("X-Rork-DO-Class", "UserDirectory");
  request.headers.set("X-Rork-DO-Id", "global");
  const response = await env.DO.fetch(request);
  const body = (await response.json().catch(() => ({}))) as T;
  return { status: response.status, body };
}

async function directoryPost<T>(env: Env, path: string, payload: unknown): Promise<{ status: number; body: T }> {
  return directory<T>(env, path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

/** Client-supplied account ids are opaque UUIDs minted on the device. */
function normalizeAccountId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length < 8 || trimmed.length > 128) return null;
  return /^[A-Za-z0-9._:-]+$/.test(trimmed) ? trimmed : null;
}

/**
 * Resolves what a Stripe customer is actually paying for right now. The plan is
 * derived from the price on the live subscription — never from the client — so
 * a family seat can't be faked.
 */
async function livePlan(env: Env, customerId: string | null | undefined): Promise<LivePlan> {
  if (!customerId?.startsWith("cus_")) return { active: false, plan: "none", currentPeriodEnd: null };
  try {
    const result = await stripeRequest<{ data: StripeSubscriptionWithItems[] }>(env, {
      path: "/subscriptions",
      method: "GET",
      body: { customer: customerId, status: "all", limit: 10 },
    });
    const live = result.data.find((s) => s.status === "active" || s.status === "trialing");
    if (!live) return { active: false, plan: "none", currentPeriodEnd: null };

    const isFamily = (live.items?.data ?? []).some((item) => item.price?.id === FAMILY_PRICE_ID);
    return {
      active: true,
      plan: isFamily ? "family" : "individual",
      currentPeriodEnd: live.current_period_end ?? null,
    };
  } catch (error) {
    console.error("live_plan_failed", String(error));
    return { active: false, plan: "none", currentPeriodEnd: null };
  }
}

type DirectoryAccount = {
  user: { userId: string; username: string; hasAvatar: boolean; avatarVersion: number } | null;
  plan: PlanName;
  /** True when the Family Plan was granted for testing rather than bought. */
  comp?: boolean;
  stripeCustomerId: string | null;
  family: {
    capacity: number;
    seatsUsed: number;
    members: Array<{ userId: string; username: string; hasAvatar: boolean; avatarVersion: number }>;
    invites: Array<{ inviteId: string; createdAt: number; user: { userId: string; username: string; hasAvatar: boolean; avatarVersion: number } | null }>;
  } | null;
  membership: {
    ownerId: string;
    ownerUsername: string;
    ownerCustomerId: string | null;
    ownerComp?: boolean;
    joinedAt: number;
  } | null;
  pendingInvite: { inviteId: string; ownerId: string; ownerUsername: string } | null;
};

/** A comp plan behaves exactly like a live family subscription, minus billing. */
const COMP_FAMILY: LivePlan = { active: true, plan: "family", currentPeriodEnd: null };

/**
 * One call the app makes on every launch: who you are, what you're paying for,
 * who is on your family plan, and whether an invitation is waiting for you.
 * Stripe is the source of truth for the plan; the registry is reconciled to it
 * on every read so a lapsed subscription can't leave seats granted.
 */
async function accountSnapshot(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const userId = normalizeAccountId(url.searchParams.get("userId"));
  if (!userId) return json({ error: "userId is required" }, 400);

  const customerHint = url.searchParams.get("customerId");

  try {
    let snapshot = (await directory<DirectoryAccount>(env, `/account?userId=${encodeURIComponent(userId)}`)).body;

    const ownCustomer = snapshot.stripeCustomerId ?? (customerHint?.startsWith("cus_") ? customerHint : null);
    const isComp = snapshot.comp === true;
    const own = isComp ? COMP_FAMILY : await livePlan(env, ownCustomer);

    // Reconcile: the registry follows Stripe, not the other way round. A comp
    // test plan is exempt — there is no subscription for it to be reconciled to.
    if (
      !isComp
      && snapshot.user
      && (snapshot.plan !== own.plan || (ownCustomer && ownCustomer !== snapshot.stripeCustomerId))
    ) {
      await directoryPost(env, "/billing", { userId, plan: own.plan, customerId: ownCustomer });
      snapshot = (await directory<DirectoryAccount>(env, `/account?userId=${encodeURIComponent(userId)}`)).body;
    }

    let membershipActive = false;
    if (snapshot.membership) {
      const ownerPlan = snapshot.membership.ownerComp === true
        ? COMP_FAMILY
        : await livePlan(env, snapshot.membership.ownerCustomerId);
      membershipActive = ownerPlan.active && ownerPlan.plan === "family";
      if (!membershipActive) {
        // The owner's family plan ended — release the seat rather than leave
        // the member holding access nobody is paying for.
        await directoryPost(env, "/family/disband", { ownerId: snapshot.membership.ownerId });
        snapshot = (await directory<DirectoryAccount>(env, `/account?userId=${encodeURIComponent(userId)}`)).body;
      }
    }

    return json({
      user: snapshot.user,
      plan: own.plan,
      subscriptionActive: own.active,
      currentPeriodEnd: own.currentPeriodEnd,
      isFamilyOwner: own.active && own.plan === "family",
      family: own.active && own.plan === "family" ? snapshot.family : null,
      membership: membershipActive ? snapshot.membership : null,
      pendingInvite: snapshot.pendingInvite,
      hasAccess: own.active || membershipActive,
      isCompPlan: isComp,
      capacity: FAMILY_CAPACITY,
    });
  } catch (error) {
    console.error("account_snapshot_failed", String(error));
    return json({ error: "Could not load your account." }, 500);
  }
}

async function usernameCheck(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const result = await directoryPost<Record<string, unknown>>(env, "/username/check", payload);
  return json(result.body, result.status);
}

async function usernameClaim(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.userId)) return json({ error: "userId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/username/claim", payload);
  return json(result.body, result.status);
}

/** Registration: username + password in a single call. */
async function authRegister(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.userId)) return json({ error: "userId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/auth/register", payload);
  return json(result.body, result.status);
}

/** Sign-in from a new device: returns the account id to adopt locally. */
async function authLogin(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const result = await directoryPost<Record<string, unknown>>(env, "/auth/login", payload);
  return json(result.body, result.status);
}

async function avatarUpload(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.userId)) return json({ error: "userId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/avatar", payload);
  return json(result.body, result.status);
}

/** Serves a profile picture as a real image so SwiftUI can load it directly. */
async function avatarImage(request: Request, env: Env): Promise<Response> {
  const userId = normalizeAccountId(new URL(request.url).searchParams.get("userId"));
  if (!userId) return json({ error: "userId is required" }, 400);

  const result = await directory<{ avatar?: string; mime?: string; version?: number }>(
    env,
    `/avatar?userId=${encodeURIComponent(userId)}`,
  );
  if (result.status !== 200 || !result.body.avatar) return json({ error: "no avatar" }, 404);

  try {
    const binary = atob(result.body.avatar);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
    return new Response(bytes, {
      headers: {
        ...CORS,
        "Content-Type": result.body.mime ?? "image/jpeg",
        "Cache-Control": "public, max-age=60",
      },
    });
  } catch {
    return json({ error: "no avatar" }, 404);
  }
}

async function userSearch(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const username = url.searchParams.get("username") ?? "";
  const requesterId = normalizeAccountId(url.searchParams.get("requesterId")) ?? "";
  const result = await directory<Record<string, unknown>>(
    env,
    `/search?username=${encodeURIComponent(username)}&requesterId=${encodeURIComponent(requesterId)}`,
  );
  return json(result.body, result.status);
}

/** Only a customer with a live Family Plan at Stripe may hand out a seat. */
async function familyInvite(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const ownerId = normalizeAccountId(payload.ownerId);
  const targetUserId = normalizeAccountId(payload.targetUserId);
  if (!ownerId || !targetUserId) return json({ error: "ownerId and targetUserId are required" }, 400);

  const snapshot = (await directory<DirectoryAccount>(env, `/account?userId=${encodeURIComponent(ownerId)}`)).body;
  const owner = snapshot.comp === true ? COMP_FAMILY : await livePlan(env, snapshot.stripeCustomerId);
  if (!owner.active || owner.plan !== "family") {
    return json({ error: "An active Family Plan is required to invite members." }, 403);
  }

  const result = await directoryPost<Record<string, unknown>>(env, "/invite", { ownerId, targetUserId });
  return json(result.body, result.status);
}

async function familyRespond(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.userId)) return json({ error: "userId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/invite/respond", payload);
  return json(result.body, result.status);
}

async function familyRemove(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.ownerId)) return json({ error: "ownerId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/family/remove", payload);
  return json(result.body, result.status);
}

/**
 * TEST MODE: grants this account a Family Plan with no Stripe subscription, so
 * the owner-only flows (invite, seat meter, accept/decline) can be walked
 * through end to end. Pass `revoke: true` to hand it back.
 */
async function testingFamilyPlan(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  const userId = normalizeAccountId(payload.userId);
  if (!userId) return json({ error: "userId is required" }, 400);

  const result = await directoryPost<Record<string, unknown>>(env, "/testing/family", {
    userId,
    revoke: payload.revoke === true,
  });
  return json(result.body, result.status);
}

async function familyLeave(request: Request, env: Env): Promise<Response> {
  const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!normalizeAccountId(payload.userId)) return json({ error: "userId is required" }, 400);
  const result = await directoryPost<Record<string, unknown>>(env, "/family/leave", payload);
  return json(result.body, result.status);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const path = new URL(request.url).pathname.replace(/\/+$/, "") || "/";

    if (path === "/ping") return json({ ok: true, now: new Date().toISOString() });
    if (path === "/create-payment-intent" && request.method === "POST") return createPaymentIntent(request, env);
    if (path === "/subscription-status" && request.method === "GET") return subscriptionStatus(request, env);
    if (path === "/cancel-subscription" && request.method === "POST") return cancelSubscription(request, env);
    if (path === "/create-setup-intent" && request.method === "POST") return createSetupIntent(request, env);
    if (path === "/update-payment-method" && request.method === "POST") return updatePaymentMethod(request, env);
    if (path === "/payment-method" && request.method === "GET") return paymentMethodStatus(request, env);
    if (path === "/analyze-meal" && request.method === "POST") return analyzeMeal(request, env);
    if (path === "/scan-quota" && request.method === "GET") return scanQuotaStatus(request, env);
    if (path === "/scan-quota/claim" && request.method === "POST") return claimBodyScan(request, env);
    if (path === "/scan-quota/release" && request.method === "POST") return releaseBodyScan(request, env);
    if (path === "/username/check" && request.method === "POST") return usernameCheck(request, env);
    if (path === "/username/claim" && request.method === "POST") return usernameClaim(request, env);
    if (path === "/auth/register" && request.method === "POST") return authRegister(request, env);
    if (path === "/auth/login" && request.method === "POST") return authLogin(request, env);
    if (path === "/profile/avatar" && request.method === "POST") return avatarUpload(request, env);
    if (path === "/profile/avatar" && request.method === "GET") return avatarImage(request, env);
    if (path === "/account" && request.method === "GET") return accountSnapshot(request, env);
    if (path === "/user-search" && request.method === "GET") return userSearch(request, env);
    if (path === "/family/invite" && request.method === "POST") return familyInvite(request, env);
    if (path === "/family/invite/respond" && request.method === "POST") return familyRespond(request, env);
    if (path === "/family/remove" && request.method === "POST") return familyRemove(request, env);
    if (path === "/family/leave" && request.method === "POST") return familyLeave(request, env);
    if (path === "/testing/family-plan" && request.method === "POST") return testingFamilyPlan(request, env);

    return json({ error: "not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
