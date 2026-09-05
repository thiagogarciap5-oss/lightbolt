// functions/scan-quota.ts — per-device AI scan quota (Durable Object).
//
// One instance per device id. Holds a rolling 24h ledger of scan events so the
// daily caps (1 body scan, 3 meal scans) are enforced on the SERVER, not in the
// client where they could be reset by reinstalling the app or moving the clock.

import { DurableObject } from "cloudflare:workers";

export type QuotaKind = "body" | "meal";

const DEFAULT_WINDOW_MS = 24 * 60 * 60 * 1000;

function isKind(value: unknown): value is QuotaKind {
  return value === "body" || value === "meal";
}

export type QuotaVerdict = {
  allowed: boolean;
  kind: QuotaKind;
  used: number;
  limit: number;
  /** Epoch seconds at which the oldest event ages out and a slot frees up. */
  resetAt: number | null;
};

export class ScanQuota extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS scan_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        ts INTEGER NOT NULL
      )
    `);
    this.ctx.storage.sql.exec(
      "CREATE INDEX IF NOT EXISTS scan_events_kind_ts ON scan_events (kind, ts)",
    );
  }

  /** Lazy TTL eviction — anything outside the widest window we care about. */
  private prune(windowMs: number): void {
    this.ctx.storage.sql.exec("DELETE FROM scan_events WHERE ts < ?", Date.now() - windowMs);
  }

  private used(kind: QuotaKind, windowMs: number): number {
    const row = this.ctx.storage.sql
      .exec<{ n: number }>(
        "SELECT COUNT(*) AS n FROM scan_events WHERE kind = ? AND ts >= ?",
        kind,
        Date.now() - windowMs,
      )
      .toArray()[0];
    return Number(row?.n ?? 0);
  }

  /** When the oldest live event expires, a slot frees up. */
  private resetAt(kind: QuotaKind, windowMs: number): number | null {
    const row = this.ctx.storage.sql
      .exec<{ ts: number }>(
        "SELECT ts FROM scan_events WHERE kind = ? AND ts >= ? ORDER BY ts ASC LIMIT 1",
        kind,
        Date.now() - windowMs,
      )
      .toArray()[0];
    return row ? Math.round((Number(row.ts) + windowMs) / 1000) : null;
  }

  private verdict(kind: QuotaKind, limit: number, windowMs: number, allowed: boolean): QuotaVerdict {
    return {
      allowed,
      kind,
      used: this.used(kind, windowMs),
      limit,
      resetAt: this.resetAt(kind, windowMs),
    };
  }

  override async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "POST" && url.pathname === "/consume") {
      const body = (await request.json().catch(() => ({}))) as {
        kind?: unknown;
        limit?: unknown;
        windowMs?: unknown;
      };
      if (!isKind(body.kind)) return Response.json({ error: "invalid kind" }, { status: 400 });

      const limit = Math.max(0, Math.min(50, Math.trunc(Number(body.limit) || 0)));
      const windowMs = Number.isFinite(Number(body.windowMs)) && Number(body.windowMs) > 0
        ? Number(body.windowMs)
        : DEFAULT_WINDOW_MS;

      this.prune(windowMs);

      if (this.used(body.kind, windowMs) >= limit) {
        return Response.json(this.verdict(body.kind, limit, windowMs, false));
      }

      this.ctx.storage.sql.exec(
        "INSERT INTO scan_events (kind, ts) VALUES (?, ?)",
        body.kind,
        Date.now(),
      );
      return Response.json(this.verdict(body.kind, limit, windowMs, true));
    }

    // Refund: a reserved slot is returned when the upstream provider failed,
    // so a provider outage never costs the user their daily allowance.
    if (request.method === "POST" && url.pathname === "/release") {
      const body = (await request.json().catch(() => ({}))) as { kind?: unknown };
      if (!isKind(body.kind)) return Response.json({ error: "invalid kind" }, { status: 400 });
      this.ctx.storage.sql.exec(
        "DELETE FROM scan_events WHERE id = (SELECT id FROM scan_events WHERE kind = ? ORDER BY id DESC LIMIT 1)",
        body.kind,
      );
      return Response.json({ ok: true });
    }

    if (request.method === "GET" && url.pathname === "/status") {
      const windowMs = DEFAULT_WINDOW_MS;
      const bodyLimit = Math.max(0, Math.trunc(Number(url.searchParams.get("bodyLimit")) || 0));
      const mealLimit = Math.max(0, Math.trunc(Number(url.searchParams.get("mealLimit")) || 0));
      this.prune(windowMs);
      return Response.json({
        bodyUsed: this.used("body", windowMs),
        bodyLimit,
        bodyResetAt: this.resetAt("body", windowMs),
        mealUsed: this.used("meal", windowMs),
        mealLimit,
        mealResetAt: this.resetAt("meal", windowMs),
      });
    }

    return Response.json({ error: "not found" }, { status: 404 });
  }
}
