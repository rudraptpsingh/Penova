// docs/functions/v1/ping.ts
//
// Penova v1.1 — opt-in anonymous usage stats endpoint.
//
// This Cloudflare Pages Function receives a once-per-day, ≤1KB payload of
// aggregate counters from Penova for Mac/iOS *only* when the user has
// explicitly toggled "Help improve Penova by sharing anonymous usage data"
// ON in Settings. Off by default; never fires when off; the app drops the
// payload on the floor if the toggle is off.
//
// What we accept:
//   POST application/json (≤2KB hard cap; typical body is <1KB)
//
// What we store (Cloudflare KV, binding name `STATS_KV`):
//   key:   agg:YYYY-MM-DD:<os>:<appVersion>:<locale>
//   value: { scriptsOpened, scriptsCreated, exportsRun, reportsViewed }
//
// What we DON'T store:
//   - The IP address (Cloudflare's edge sees it; we never read or persist it)
//   - Any device identifier, install ID, account ID, or device model
//   - Filenames, paths, script content, or anything user-authored
//
// Source of truth: this file is the entire backend. There is no other
// service. Code lives at https://github.com/<repo>/blob/main/docs/functions/v1/ping.ts.

interface Env {
  STATS_KV?: KVNamespace;
}

interface Counters {
  scriptsOpened: number;
  scriptsCreated: number;
  exportsRun: number;
  reportsViewed: number;
}

interface PingBody {
  v: number;
  appVersion: string;
  appBuild: string;
  os: string;
  osVersion: string;
  locale: string;
  counters: Counters;
}

const MAX_BYTES = 2048;
const ALLOWED_OS = new Set(["macos", "ios"]);

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function badRequest(reason: string): Response {
  return new Response(JSON.stringify({ error: reason }), {
    status: 400,
    headers: {
      "Content-Type": "application/json",
      "X-Penova-Logging": "no-ip-stored",
      ...CORS_HEADERS,
    },
  });
}

function isFiniteNonNegativeInt(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n) && Number.isInteger(n) && n >= 0 && n < 1_000_000;
}

function isShortString(s: unknown, max: number): s is string {
  return typeof s === "string" && s.length > 0 && s.length <= max;
}

function validate(body: unknown): { ok: true; body: PingBody } | { ok: false; reason: string } {
  if (!body || typeof body !== "object") return { ok: false, reason: "body must be a JSON object" };
  const b = body as Record<string, unknown>;

  if (b.v !== 1) return { ok: false, reason: "unsupported v" };
  if (!isShortString(b.appVersion, 32)) return { ok: false, reason: "invalid appVersion" };
  if (!isShortString(b.appBuild, 32)) return { ok: false, reason: "invalid appBuild" };
  if (!isShortString(b.os, 16)) return { ok: false, reason: "invalid os" };
  if (!ALLOWED_OS.has(b.os as string)) return { ok: false, reason: "os must be macos or ios" };
  if (!isShortString(b.osVersion, 32)) return { ok: false, reason: "invalid osVersion" };
  if (!isShortString(b.locale, 16)) return { ok: false, reason: "invalid locale" };

  const c = b.counters;
  if (!c || typeof c !== "object") return { ok: false, reason: "missing counters" };
  const cc = c as Record<string, unknown>;
  if (!isFiniteNonNegativeInt(cc.scriptsOpened)) return { ok: false, reason: "invalid scriptsOpened" };
  if (!isFiniteNonNegativeInt(cc.scriptsCreated)) return { ok: false, reason: "invalid scriptsCreated" };
  if (!isFiniteNonNegativeInt(cc.exportsRun)) return { ok: false, reason: "invalid exportsRun" };
  if (!isFiniteNonNegativeInt(cc.reportsViewed)) return { ok: false, reason: "invalid reportsViewed" };

  return {
    ok: true,
    body: {
      v: 1,
      appVersion: b.appVersion as string,
      appBuild: b.appBuild as string,
      os: b.os as string,
      osVersion: b.osVersion as string,
      locale: b.locale as string,
      counters: {
        scriptsOpened: cc.scriptsOpened as number,
        scriptsCreated: cc.scriptsCreated as number,
        exportsRun: cc.exportsRun as number,
        reportsViewed: cc.reportsViewed as number,
      },
    },
  };
}

function todayUTC(): string {
  // YYYY-MM-DD in UTC. We deliberately use UTC so day boundaries are
  // stable across timezones — the user's local clock doesn't matter,
  // only that we bucket sends per UTC day.
  return new Date().toISOString().slice(0, 10);
}

// Sanitize a path component so a malicious payload can't write keys
// like "agg::::" or inject characters that break our key scheme.
function sanitize(s: string): string {
  return s.replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 32);
}

async function bumpCounters(kv: KVNamespace, body: PingBody): Promise<void> {
  const key = [
    "agg",
    todayUTC(),
    sanitize(body.os),
    sanitize(body.appVersion),
    sanitize(body.locale),
  ].join(":");

  const prevRaw = await kv.get(key);
  const prev: Counters = prevRaw
    ? (JSON.parse(prevRaw) as Counters)
    : { scriptsOpened: 0, scriptsCreated: 0, exportsRun: 0, reportsViewed: 0 };

  const next: Counters = {
    scriptsOpened: prev.scriptsOpened + body.counters.scriptsOpened,
    scriptsCreated: prev.scriptsCreated + body.counters.scriptsCreated,
    exportsRun: prev.exportsRun + body.counters.exportsRun,
    reportsViewed: prev.reportsViewed + body.counters.reportsViewed,
  };

  // 90-day TTL — long enough to look at month-over-month, short enough
  // that a deleted-key drift scrubs itself.
  await kv.put(key, JSON.stringify(next), { expirationTtl: 60 * 60 * 24 * 90 });
}

export const onRequestOptions: PagesFunction<Env> = async () => {
  return new Response(null, { status: 204, headers: CORS_HEADERS });
};

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  // Body size guard — read as text first so we can measure before parsing.
  const text = await request.text();
  if (text.length > MAX_BYTES) {
    return badRequest("payload too large");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return badRequest("invalid JSON");
  }

  const result = validate(parsed);
  if (!result.ok) {
    return badRequest(result.reason);
  }

  // KV is optional in dev: if the binding isn't set we still return 204
  // so the app's flush path is exercised end-to-end. The operator
  // README documents how to bind STATS_KV in production.
  if (env.STATS_KV) {
    try {
      await bumpCounters(env.STATS_KV, result.body);
    } catch {
      // Never log; never fail the user-visible request shape on a
      // KV blip. The app retries tomorrow.
    }
  }

  return new Response(null, {
    status: 204,
    headers: {
      "X-Penova-Logging": "no-ip-stored",
      ...CORS_HEADERS,
    },
  });
};

// Any other verb → 405. Keeps GET probes from being misinterpreted.
export const onRequest: PagesFunction<Env> = async ({ request }) => {
  if (request.method === "POST") {
    // Won't reach here — onRequestPost handles POST. Defensive.
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  return new Response("method not allowed", {
    status: 405,
    headers: {
      "Allow": "POST, OPTIONS",
      ...CORS_HEADERS,
    },
  });
};
