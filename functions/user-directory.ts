// functions/user-directory.ts — global identity + family plan registry.
//
// ONE singleton instance (id "global"). Usernames must be unique across every
// user in the app and members must be findable by exact username, so this data
// cannot be partitioned per-device like the scan quota is: it needs a single
// authority. Everything lives in the instance's SQLite database.
//
// This object holds NO health data. Usernames, avatars, family links and
// feedback only.

import { DurableObject } from "cloudflare:workers";

/** Additional members the owner can add. Owner + 4 = 5 people on the plan. */
export const FAMILY_CAPACITY = 4;

const USERNAME_MIN = 3;
const USERNAME_MAX = 50;
/** ~400 KB of base64 ≈ 300 KB of JPEG, comfortably inside the 2 MB row cap. */
const AVATAR_MAX_BASE64 = 400_000;

const PASSWORD_MIN = 8;
const PASSWORD_MAX = 200;
/**
 * The Workers runtime hard-caps a single PBKDF2 call at 100,000 iterations and
 * throws above it, so OWASP-grade cost is reached by chaining rounds instead:
 * each round re-feeds the previous digest as key material.
 * 3 x 100,000 = 300,000 effective iterations.
 */
const PBKDF2_ITERATIONS = 100_000;
const PBKDF2_ROUNDS = 3;
/** Failed sign-ins tolerated inside the window before an account cools down. */
const LOGIN_MAX_FAILURES = 8;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;

export type PasswordVerdict = { ok: true; password: string } | { ok: false; reason: string };

/**
 * Passwords are only rejected for being short, absurdly long or empty-ish.
 * No character-class theatre: length is what actually buys entropy, and the
 * hash below is what actually protects the value at rest.
 */
export function validatePassword(raw: unknown): PasswordVerdict {
  if (typeof raw !== "string") return { ok: false, reason: "Choose a password." };
  const password = raw.normalize("NFKC");
  if (password.trim().length === 0) return { ok: false, reason: "Choose a password." };
  if ([...password].length < PASSWORD_MIN) {
    return { ok: false, reason: `At least ${PASSWORD_MIN} characters.` };
  }
  if ([...password].length > PASSWORD_MAX) return { ok: false, reason: "That password is too long." };
  return { ok: true, password };
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/**
 * PBKDF2-HMAC-SHA256, chained over `rounds` passes to clear the runtime's
 * per-call iteration ceiling. Plaintext passwords are never stored or logged.
 */
async function derivePasswordHash(
  password: string,
  salt: Uint8Array,
  iterations: number,
  rounds: number = PBKDF2_ROUNDS,
): Promise<string> {
  let material: Uint8Array = new TextEncoder().encode(password);
  let digest = new Uint8Array(32);

  for (let round = 0; round < Math.max(1, rounds); round += 1) {
    const key = await crypto.subtle.importKey("raw", material as BufferSource, "PBKDF2", false, ["deriveBits"]);
    const bits = await crypto.subtle.deriveBits(
      { name: "PBKDF2", hash: "SHA-256", salt: salt as BufferSource, iterations },
      key,
      256,
    );
    digest = new Uint8Array(bits);
    material = digest;
  }

  return toBase64(digest);
}

/** Length-independent, timing-safe string comparison. */
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export type UsernameVerdict =
  | { ok: true; display: string; key: string }
  | { ok: false; reason: string };

/**
 * Usernames accept any language: Latin, Cyrillic, Arabic, CJK, emoji — the
 * only rejections are whitespace, invisible control characters and "@" (which
 * would make usernames read like email addresses). Uniqueness is decided on a
 * NFKC-normalized, case-folded key so "Ana" and "ana" are the same person.
 */
export function normalizeUsername(raw: unknown): UsernameVerdict {
  if (typeof raw !== "string") return { ok: false, reason: "Enter a username." };

  const display = raw.trim().normalize("NFKC");
  const length = [...display].length;

  if (length === 0) return { ok: false, reason: "Enter a username." };
  if (length < USERNAME_MIN) return { ok: false, reason: `At least ${USERNAME_MIN} characters.` };
  if (length > USERNAME_MAX) return { ok: false, reason: `At most ${USERNAME_MAX} characters.` };
  if (/\s/u.test(display)) return { ok: false, reason: "No spaces — try a dot or underscore." };
  if (/\p{C}/u.test(display)) return { ok: false, reason: "That contains invisible characters." };
  if (display.includes("@")) return { ok: false, reason: "Usernames can't contain @." };

  return { ok: true, display, key: display.toLocaleLowerCase() };
}

type UserRow = {
  user_id: string;
  username: string;
  username_key: string;
  avatar: string | null;
  avatar_mime: string | null;
  stripe_customer_id: string | null;
  plan: string;
  auth_user_id: string | null;
  password_hash: string | null;
  password_salt: string | null;
  password_iterations: number | null;
  password_rounds: number | null;
  /** 1 = complimentary Family Plan granted for testing, with no Stripe behind it. */
  comp_plan: number | null;
  created_at: number;
  updated_at: number;
};

type MemberRow = { owner_id: string; member_id: string; joined_at: number };

type InviteRow = {
  id: string;
  owner_id: string;
  invitee_id: string;
  status: string;
  created_at: number;
  resolved_at: number | null;
};

export type PublicUser = {
  userId: string;
  username: string;
  hasAvatar: boolean;
  avatarVersion: number;
};

function publicUser(row: UserRow): PublicUser {
  return {
    userId: row.user_id,
    username: row.username,
    hasAvatar: Boolean(row.avatar),
    avatarVersion: row.updated_at,
  };
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status });
}

export class UserDirectory extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    const sql = this.ctx.storage.sql;

    sql.exec(`
      CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        username_key TEXT NOT NULL,
        avatar TEXT,
        avatar_mime TEXT,
        stripe_customer_id TEXT,
        plan TEXT NOT NULL DEFAULT 'none',
        auth_user_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    `);
    sql.exec("CREATE UNIQUE INDEX IF NOT EXISTS users_username_key ON users (username_key)");

    // Password columns arrived after the first release; add them in place so
    // existing accounts keep working and can set a password later.
    for (const column of [
      "password_hash TEXT",
      "password_salt TEXT",
      "password_iterations INTEGER",
      "password_rounds INTEGER",
      "comp_plan INTEGER",
    ]) {
      try {
        sql.exec(`ALTER TABLE users ADD COLUMN ${column}`);
      } catch {
        // Already present — nothing to do.
      }
    }

    sql.exec(`
      CREATE TABLE IF NOT EXISTS login_failures (
        username_key TEXT PRIMARY KEY,
        failures INTEGER NOT NULL,
        first_failed_at INTEGER NOT NULL
      )
    `);

    sql.exec(`
      CREATE TABLE IF NOT EXISTS family_members (
        owner_id TEXT NOT NULL,
        member_id TEXT NOT NULL PRIMARY KEY,
        joined_at INTEGER NOT NULL
      )
    `);
    sql.exec("CREATE INDEX IF NOT EXISTS family_members_owner ON family_members (owner_id)");

    sql.exec(`
      CREATE TABLE IF NOT EXISTS invites (
        id TEXT PRIMARY KEY,
        owner_id TEXT NOT NULL,
        invitee_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        resolved_at INTEGER
      )
    `);
    sql.exec("CREATE INDEX IF NOT EXISTS invites_invitee ON invites (invitee_id, status)");
    sql.exec("CREATE INDEX IF NOT EXISTS invites_owner ON invites (owner_id, status)");
  }

  // MARK: Reads

  private user(userId: string): UserRow | null {
    return (
      this.ctx.storage.sql
        .exec<UserRow>("SELECT * FROM users WHERE user_id = ?", userId)
        .toArray()[0] ?? null
    );
  }

  private userByKey(key: string): UserRow | null {
    return (
      this.ctx.storage.sql
        .exec<UserRow>("SELECT * FROM users WHERE username_key = ?", key)
        .toArray()[0] ?? null
    );
  }

  private members(ownerId: string): UserRow[] {
    const rows = this.ctx.storage.sql
      .exec<MemberRow>("SELECT * FROM family_members WHERE owner_id = ? ORDER BY joined_at ASC", ownerId)
      .toArray();
    return rows.map((row) => this.user(row.member_id)).filter((row): row is UserRow => row !== null);
  }

  private pendingInvitesFromOwner(ownerId: string): { invite: InviteRow; user: UserRow | null }[] {
    return this.ctx.storage.sql
      .exec<InviteRow>(
        "SELECT * FROM invites WHERE owner_id = ? AND status = 'pending' ORDER BY created_at ASC",
        ownerId,
      )
      .toArray()
      .map((invite) => ({ invite, user: this.user(invite.invitee_id) }));
  }

  private membershipOf(userId: string): MemberRow | null {
    return (
      this.ctx.storage.sql
        .exec<MemberRow>("SELECT * FROM family_members WHERE member_id = ?", userId)
        .toArray()[0] ?? null
    );
  }

  /** Occupied seats = accepted members + invitations still awaiting an answer. */
  private seatsUsed(ownerId: string): number {
    const members = this.ctx.storage.sql
      .exec<{ n: number }>("SELECT COUNT(*) AS n FROM family_members WHERE owner_id = ?", ownerId)
      .toArray()[0];
    const invites = this.ctx.storage.sql
      .exec<{ n: number }>(
        "SELECT COUNT(*) AS n FROM invites WHERE owner_id = ? AND status = 'pending'",
        ownerId,
      )
      .toArray()[0];
    return Number(members?.n ?? 0) + Number(invites?.n ?? 0);
  }

  // MARK: Router

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    const payload = method === "POST"
      ? ((await request.json().catch(() => ({}))) as Record<string, unknown>)
      : {};

    if (method === "POST" && path === "/username/check") return this.checkUsername(payload);
    if (method === "POST" && path === "/username/claim") return this.claimUsername(payload);
    // Password hashing is the only CPU-heavy path in here; a throw would
    // otherwise surface as an opaque platform 503 instead of a usable message.
    if (method === "POST" && path === "/auth/register") {
      try {
        return await this.register(payload);
      } catch (error) {
        console.error("register_failed", String(error));
        return json({ error: "We couldn't create that account. Try again." }, 500);
      }
    }
    if (method === "POST" && path === "/auth/login") {
      try {
        return await this.login(payload);
      } catch (error) {
        console.error("login_failed", String(error));
        return json({ error: "We couldn't sign you in. Try again." }, 500);
      }
    }
    if (method === "POST" && path === "/avatar") return this.setAvatar(payload);
    if (method === "GET" && path === "/avatar") return this.readAvatar(url);
    if (method === "GET" && path === "/account") return this.account(url);
    if (method === "GET" && path === "/search") return this.search(url);
    if (method === "POST" && path === "/billing") return this.syncBilling(payload);
    if (method === "POST" && path === "/invite") return this.invite(payload);
    if (method === "POST" && path === "/invite/respond") return this.respondToInvite(payload);
    if (method === "POST" && path === "/family/remove") return this.removeMember(payload);
    if (method === "POST" && path === "/family/leave") return this.leaveFamily(payload);
    if (method === "POST" && path === "/family/disband") return this.disband(payload);
    if (method === "POST" && path === "/testing/family") return this.grantCompFamily(payload);

    return json({ error: "not found" }, 404);
  }

  // MARK: Usernames

  private checkUsername(payload: Record<string, unknown>): Response {
    const verdict = normalizeUsername(payload.username);
    if (!verdict.ok) return json({ available: false, reason: verdict.reason });

    const owner = this.userByKey(verdict.key);
    const requesterId = typeof payload.userId === "string" ? payload.userId : null;

    if (owner && owner.user_id !== requesterId) {
      return json({ available: false, reason: "That username is already taken." });
    }
    return json({ available: true, username: verdict.display });
  }

  private claimUsername(payload: Record<string, unknown>): Response {
    const userId = typeof payload.userId === "string" ? payload.userId.trim() : "";
    if (userId.length < 8 || userId.length > 128) return json({ error: "Invalid account id." }, 400);

    const verdict = normalizeUsername(payload.username);
    if (!verdict.ok) return json({ error: verdict.reason }, 400);

    const holder = this.userByKey(verdict.key);
    if (holder && holder.user_id !== userId) {
      return json({ error: "That username is already taken.", taken: true }, 409);
    }

    const authUserId = typeof payload.authUserId === "string" ? payload.authUserId : null;
    const now = Date.now();
    const existing = this.user(userId);

    if (existing) {
      this.ctx.storage.sql.exec(
        "UPDATE users SET username = ?, username_key = ?, auth_user_id = COALESCE(?, auth_user_id), updated_at = ? WHERE user_id = ?",
        verdict.display,
        verdict.key,
        authUserId,
        now,
        userId,
      );
    } else {
      this.ctx.storage.sql.exec(
        `INSERT INTO users (user_id, username, username_key, plan, auth_user_id, created_at, updated_at)
         VALUES (?, ?, ?, 'none', ?, ?, ?)`,
        userId,
        verdict.display,
        verdict.key,
        authUserId,
        now,
        now,
      );
    }

    const row = this.user(userId);
    return json({ ok: true, user: row ? publicUser(row) : null });
  }

  // MARK: Password accounts

  /**
   * Creates the account in one shot: unique username plus a password hash.
   * Also used to attach a password to an account that was created earlier by
   * an OAuth sign-in.
   */
  private async register(payload: Record<string, unknown>): Promise<Response> {
    const userId = typeof payload.userId === "string" ? payload.userId.trim() : "";
    if (userId.length < 8 || userId.length > 128) return json({ error: "Invalid account id." }, 400);

    const verdict = normalizeUsername(payload.username);
    if (!verdict.ok) return json({ error: verdict.reason }, 400);

    const secret = validatePassword(payload.password);
    if (!secret.ok) return json({ error: secret.reason }, 400);

    const holder = this.userByKey(verdict.key);
    if (holder && holder.user_id !== userId) {
      return json({ error: "That username is already taken.", taken: true }, 409);
    }

    const salt = crypto.getRandomValues(new Uint8Array(16));
    const hash = await derivePasswordHash(secret.password, salt, PBKDF2_ITERATIONS);
    const authUserId = typeof payload.authUserId === "string" ? payload.authUserId : null;
    const now = Date.now();
    const existing = this.user(userId);

    if (existing) {
      this.ctx.storage.sql.exec(
        `UPDATE users
         SET username = ?, username_key = ?, password_hash = ?, password_salt = ?, password_iterations = ?,
             password_rounds = ?, auth_user_id = COALESCE(?, auth_user_id), updated_at = ?
         WHERE user_id = ?`,
        verdict.display,
        verdict.key,
        hash,
        toBase64(salt),
        PBKDF2_ITERATIONS,
        PBKDF2_ROUNDS,
        authUserId,
        now,
        userId,
      );
    } else {
      this.ctx.storage.sql.exec(
        `INSERT INTO users
           (user_id, username, username_key, plan, auth_user_id, password_hash, password_salt,
            password_iterations, password_rounds, created_at, updated_at)
         VALUES (?, ?, ?, 'none', ?, ?, ?, ?, ?, ?, ?)`,
        userId,
        verdict.display,
        verdict.key,
        authUserId,
        hash,
        toBase64(salt),
        PBKDF2_ITERATIONS,
        PBKDF2_ROUNDS,
        now,
        now,
      );
    }

    this.clearLoginFailures(verdict.key);
    const row = this.user(userId);
    return json({ ok: true, user: row ? publicUser(row) : null });
  }

  /**
   * Verifies a username/password pair and hands back the account id so a new
   * device can adopt the existing identity instead of starting over.
   */
  private async login(payload: Record<string, unknown>): Promise<Response> {
    const verdict = normalizeUsername(payload.username);
    if (!verdict.ok) return json({ error: "Check your username and password." }, 401);

    if (this.isLockedOut(verdict.key)) {
      return json({ error: "Too many attempts. Wait 15 minutes and try again." }, 429);
    }

    const password = typeof payload.password === "string" ? payload.password.normalize("NFKC") : "";
    const row = this.userByKey(verdict.key);

    if (!row || !row.password_hash || !row.password_salt) {
      this.recordLoginFailure(verdict.key);
      // Deliberately identical to a wrong password: never confirm which
      // usernames exist to someone guessing.
      return json({ error: "Check your username and password." }, 401);
    }

    const attempt = await derivePasswordHash(
      password,
      fromBase64(row.password_salt),
      row.password_iterations ?? PBKDF2_ITERATIONS,
      row.password_rounds ?? PBKDF2_ROUNDS,
    );
    if (!constantTimeEquals(attempt, row.password_hash)) {
      this.recordLoginFailure(verdict.key);
      return json({ error: "Check your username and password." }, 401);
    }

    this.clearLoginFailures(verdict.key);
    return json({ ok: true, user: publicUser(row) });
  }

  private isLockedOut(key: string): boolean {
    const row = this.ctx.storage.sql
      .exec<{ failures: number; first_failed_at: number }>(
        "SELECT failures, first_failed_at FROM login_failures WHERE username_key = ?",
        key,
      )
      .toArray()[0];
    if (!row) return false;
    if (Date.now() - Number(row.first_failed_at) > LOGIN_WINDOW_MS) {
      this.clearLoginFailures(key);
      return false;
    }
    return Number(row.failures) >= LOGIN_MAX_FAILURES;
  }

  private recordLoginFailure(key: string): void {
    const now = Date.now();
    const row = this.ctx.storage.sql
      .exec<{ failures: number; first_failed_at: number }>(
        "SELECT failures, first_failed_at FROM login_failures WHERE username_key = ?",
        key,
      )
      .toArray()[0];

    if (!row || now - Number(row.first_failed_at) > LOGIN_WINDOW_MS) {
      this.ctx.storage.sql.exec(
        "INSERT OR REPLACE INTO login_failures (username_key, failures, first_failed_at) VALUES (?, 1, ?)",
        key,
        now,
      );
      return;
    }
    this.ctx.storage.sql.exec(
      "UPDATE login_failures SET failures = failures + 1 WHERE username_key = ?",
      key,
    );
  }

  private clearLoginFailures(key: string): void {
    this.ctx.storage.sql.exec("DELETE FROM login_failures WHERE username_key = ?", key);
  }

  // MARK: Avatar

  private setAvatar(payload: Record<string, unknown>): Response {
    const userId = typeof payload.userId === "string" ? payload.userId : "";
    const row = this.user(userId);
    if (!row) return json({ error: "Create a username first." }, 404);

    const raw = payload.imageBase64;
    if (raw === null || raw === undefined || raw === "") {
      this.ctx.storage.sql.exec(
        "UPDATE users SET avatar = NULL, avatar_mime = NULL, updated_at = ? WHERE user_id = ?",
        Date.now(),
        userId,
      );
      return json({ ok: true, hasAvatar: false, avatarVersion: Date.now() });
    }

    if (typeof raw !== "string") return json({ error: "Invalid image." }, 400);
    const base64 = raw.includes(",") ? raw.slice(raw.indexOf(",") + 1) : raw;
    if (base64.length > AVATAR_MAX_BASE64) return json({ error: "That picture is too large." }, 413);

    const mime = typeof payload.mimeType === "string" && payload.mimeType.startsWith("image/")
      ? payload.mimeType
      : "image/jpeg";
    const now = Date.now();
    this.ctx.storage.sql.exec(
      "UPDATE users SET avatar = ?, avatar_mime = ?, updated_at = ? WHERE user_id = ?",
      base64,
      mime,
      now,
      userId,
    );
    return json({ ok: true, hasAvatar: true, avatarVersion: now });
  }

  private readAvatar(url: URL): Response {
    const userId = url.searchParams.get("userId") ?? "";
    const row = this.user(userId);
    if (!row?.avatar) return json({ error: "no avatar" }, 404);
    return json({ avatar: row.avatar, mime: row.avatar_mime ?? "image/jpeg", version: row.updated_at });
  }

  // MARK: Account snapshot

  private account(url: URL): Response {
    const userId = url.searchParams.get("userId") ?? "";
    const row = this.user(userId);
    if (!row) return json({ user: null, plan: "none", family: null, membership: null, pendingInvite: null });

    const membership = this.membershipOf(userId);
    const owner = membership ? this.user(membership.owner_id) : null;

    const pending = this.ctx.storage.sql
      .exec<InviteRow>(
        "SELECT * FROM invites WHERE invitee_id = ? AND status = 'pending' ORDER BY created_at ASC LIMIT 1",
        userId,
      )
      .toArray()[0];
    const inviteOwner = pending ? this.user(pending.owner_id) : null;

    const isComp = row.comp_plan === 1;
    const family = row.plan === "family"
      ? {
          capacity: FAMILY_CAPACITY,
          seatsUsed: this.seatsUsed(userId),
          members: this.members(userId).map(publicUser),
          invites: this.pendingInvitesFromOwner(userId).map(({ invite, user }) => ({
            inviteId: invite.id,
            createdAt: invite.created_at,
            user: user ? publicUser(user) : null,
          })),
        }
      : null;

    return json({
      user: publicUser(row),
      plan: row.plan,
      comp: isComp,
      stripeCustomerId: row.stripe_customer_id,
      family,
      membership: membership && owner
        ? {
            ownerId: owner.user_id,
            ownerUsername: owner.username,
            ownerCustomerId: owner.stripe_customer_id,
            ownerComp: owner.comp_plan === 1,
            joinedAt: membership.joined_at,
          }
        : null,
      pendingInvite: pending && inviteOwner
        ? { inviteId: pending.id, ownerId: inviteOwner.user_id, ownerUsername: inviteOwner.username }
        : null,
    });
  }

  // MARK: Search

  private search(url: URL): Response {
    const verdict = normalizeUsername(url.searchParams.get("username"));
    if (!verdict.ok) return json({ found: false, reason: verdict.reason });

    const requesterId = url.searchParams.get("requesterId") ?? "";
    const row = this.userByKey(verdict.key);
    if (!row) return json({ found: false, reason: "No LightBolt user with that username." });

    if (row.user_id === requesterId) {
      return json({ found: true, user: publicUser(row), status: "self" });
    }

    const membership = this.membershipOf(row.user_id);
    if (membership) {
      return json({
        found: true,
        user: publicUser(row),
        status: membership.owner_id === requesterId ? "member" : "in_other_family",
      });
    }
    if (row.plan === "family" || row.plan === "individual") {
      return json({ found: true, user: publicUser(row), status: "has_own_plan" });
    }

    const invited = this.ctx.storage.sql
      .exec<InviteRow>(
        "SELECT * FROM invites WHERE invitee_id = ? AND status = 'pending' LIMIT 1",
        row.user_id,
      )
      .toArray()[0];
    if (invited) {
      return json({
        found: true,
        user: publicUser(row),
        status: invited.owner_id === requesterId ? "invited" : "invited_elsewhere",
      });
    }

    return json({ found: true, user: publicUser(row), status: "available" });
  }

  // MARK: Billing link

  /**
   * The Worker resolves the live plan at Stripe and writes it here. Losing the
   * family plan dissolves the group so seats can't outlive the subscription.
   */
  private syncBilling(payload: Record<string, unknown>): Response {
    const userId = typeof payload.userId === "string" ? payload.userId : "";
    const row = this.user(userId);
    if (!row) return json({ ok: false, reason: "unknown user" });

    const plan = payload.plan === "family" || payload.plan === "individual" ? payload.plan : "none";
    const customerId = typeof payload.customerId === "string" ? payload.customerId : null;

    // A complimentary test plan has no Stripe subscription behind it, so the
    // usual "Stripe is the truth" reconciliation would wipe it on every read.
    if (row.comp_plan === 1) return json({ ok: true, plan: row.plan, comp: true });

    this.ctx.storage.sql.exec(
      "UPDATE users SET plan = ?, stripe_customer_id = COALESCE(?, stripe_customer_id), updated_at = ? WHERE user_id = ?",
      plan,
      customerId,
      Date.now(),
      userId,
    );

    if (plan !== "family") this.dissolve(userId);
    return json({ ok: true, plan });
  }

  /** Frees every seat and cancels outstanding invitations for an owner. */
  private dissolve(ownerId: string): void {
    this.ctx.storage.sql.exec("DELETE FROM family_members WHERE owner_id = ?", ownerId);
    this.ctx.storage.sql.exec(
      "UPDATE invites SET status = 'cancelled', resolved_at = ? WHERE owner_id = ? AND status = 'pending'",
      Date.now(),
      ownerId,
    );
  }

  /**
   * TEST MODE: grants this account a Family Plan with no payment attached, so
   * the owner-only flows (invite, seat meter, accept/decline) can be exercised
   * end to end. Revoking it drops the plan and frees everyone it was holding.
   */
  private grantCompFamily(payload: Record<string, unknown>): Response {
    const userId = typeof payload.userId === "string" ? payload.userId : "";
    const revoke = payload.revoke === true;
    const row = this.user(userId);
    if (!row) return json({ error: "Create your account first." }, 404);

    if (revoke) {
      this.ctx.storage.sql.exec(
        "UPDATE users SET plan = 'none', comp_plan = 0, updated_at = ? WHERE user_id = ?",
        Date.now(),
        userId,
      );
      this.dissolve(userId);
      return json({ ok: true, plan: "none", comp: false });
    }

    if (this.membershipOf(userId)) {
      return json({ error: "You're on someone else's family plan — leave it first." }, 409);
    }

    this.ctx.storage.sql.exec(
      "UPDATE users SET plan = 'family', comp_plan = 1, updated_at = ? WHERE user_id = ?",
      Date.now(),
      userId,
    );
    return json({ ok: true, plan: "family", comp: true, capacity: FAMILY_CAPACITY });
  }

  private disband(payload: Record<string, unknown>): Response {
    const ownerId = typeof payload.ownerId === "string" ? payload.ownerId : "";
    this.dissolve(ownerId);
    return json({ ok: true });
  }

  // MARK: Invitations

  private invite(payload: Record<string, unknown>): Response {
    const ownerId = typeof payload.ownerId === "string" ? payload.ownerId : "";
    const targetId = typeof payload.targetUserId === "string" ? payload.targetUserId : "";

    const owner = this.user(ownerId);
    const target = this.user(targetId);
    if (!owner) return json({ error: "Create a username first." }, 404);
    if (!target) return json({ error: "That user no longer exists." }, 404);
    if (owner.user_id === target.user_id) return json({ error: "You're already on your own plan." }, 400);
    if (owner.plan !== "family") return json({ error: "Only a Family Plan owner can invite members." }, 403);

    if (this.membershipOf(target.user_id)) {
      return json({ error: "They're already on a family plan." }, 409);
    }
    const already = this.ctx.storage.sql
      .exec<InviteRow>("SELECT * FROM invites WHERE invitee_id = ? AND status = 'pending' LIMIT 1", target.user_id)
      .toArray()[0];
    if (already) {
      return json(
        { error: already.owner_id === ownerId ? "You've already invited them." : "They already have a pending invitation." },
        409,
      );
    }
    if (this.seatsUsed(ownerId) >= FAMILY_CAPACITY) {
      return json({ error: `Your plan is full — you plus ${FAMILY_CAPACITY} members.` }, 409);
    }

    const id = crypto.randomUUID();
    this.ctx.storage.sql.exec(
      "INSERT INTO invites (id, owner_id, invitee_id, status, created_at) VALUES (?, ?, ?, 'pending', ?)",
      id,
      ownerId,
      target.user_id,
      Date.now(),
    );

    return json({
      ok: true,
      invite: { inviteId: id, user: publicUser(target) },
      seatsUsed: this.seatsUsed(ownerId),
      capacity: FAMILY_CAPACITY,
    });
  }

  private respondToInvite(payload: Record<string, unknown>): Response {
    const inviteId = typeof payload.inviteId === "string" ? payload.inviteId : "";
    const userId = typeof payload.userId === "string" ? payload.userId : "";
    const accept = payload.accept === true;

    const invite = this.ctx.storage.sql
      .exec<InviteRow>("SELECT * FROM invites WHERE id = ?", inviteId)
      .toArray()[0];
    if (!invite) return json({ error: "That invitation no longer exists." }, 404);
    if (invite.invitee_id !== userId) return json({ error: "That invitation isn't yours." }, 403);
    if (invite.status !== "pending") return json({ ok: true, status: invite.status });

    const now = Date.now();

    if (!accept) {
      // Declining deletes the pending record outright, which hands the seat
      // straight back to the owner. Nothing is written to the invitee's
      // account, so a decline leaves them exactly as they were.
      this.ctx.storage.sql.exec("DELETE FROM invites WHERE id = ?", inviteId);
      return json({ ok: true, status: "declined" });
    }

    const owner = this.user(invite.owner_id);
    if (!owner || owner.plan !== "family") {
      this.ctx.storage.sql.exec(
        "UPDATE invites SET status = 'cancelled', resolved_at = ? WHERE id = ?",
        now,
        inviteId,
      );
      return json({ error: "That family plan is no longer active." }, 409);
    }

    const seatsTaken = this.ctx.storage.sql
      .exec<{ n: number }>("SELECT COUNT(*) AS n FROM family_members WHERE owner_id = ?", invite.owner_id)
      .toArray()[0];
    if (Number(seatsTaken?.n ?? 0) >= FAMILY_CAPACITY) {
      this.ctx.storage.sql.exec(
        "UPDATE invites SET status = 'cancelled', resolved_at = ? WHERE id = ?",
        now,
        inviteId,
      );
      return json({ error: "That plan filled up before you answered." }, 409);
    }

    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO family_members (owner_id, member_id, joined_at) VALUES (?, ?, ?)",
      invite.owner_id,
      userId,
      now,
    );
    this.ctx.storage.sql.exec(
      "UPDATE invites SET status = 'accepted', resolved_at = ? WHERE id = ?",
      now,
      inviteId,
    );
    // Any other plan that was courting this user loses its claim.
    this.ctx.storage.sql.exec(
      "UPDATE invites SET status = 'cancelled', resolved_at = ? WHERE invitee_id = ? AND status = 'pending'",
      now,
      userId,
    );

    return json({ ok: true, status: "accepted", ownerUsername: owner.username });
  }

  private removeMember(payload: Record<string, unknown>): Response {
    const ownerId = typeof payload.ownerId === "string" ? payload.ownerId : "";
    const target = typeof payload.memberId === "string" ? payload.memberId : "";

    const membership = this.membershipOf(target);
    if (membership && membership.owner_id === ownerId) {
      this.ctx.storage.sql.exec("DELETE FROM family_members WHERE member_id = ?", target);
      return json({ ok: true, removed: true });
    }

    // Cancelling an invitation that hasn't been answered yet.
    const invite = this.ctx.storage.sql
      .exec<InviteRow>(
        "SELECT * FROM invites WHERE owner_id = ? AND invitee_id = ? AND status = 'pending' LIMIT 1",
        ownerId,
        target,
      )
      .toArray()[0];
    if (invite) {
      this.ctx.storage.sql.exec(
        "UPDATE invites SET status = 'cancelled', resolved_at = ? WHERE id = ?",
        Date.now(),
        invite.id,
      );
      return json({ ok: true, removed: true, wasInvite: true });
    }

    return json({ ok: true, removed: false });
  }

  private leaveFamily(payload: Record<string, unknown>): Response {
    const userId = typeof payload.userId === "string" ? payload.userId : "";
    this.ctx.storage.sql.exec("DELETE FROM family_members WHERE member_id = ?", userId);
    return json({ ok: true });
  }
}
