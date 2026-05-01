// docs/functions/v1/dashboard.ts
//
// Tiny operator dashboard for the opt-in analytics endpoint.
//
//   GET /v1/dashboard?key=<STATS_DASHBOARD_KEY>
//
// Returns a JSON snapshot of every aggregate counter currently in KV.
// Protected by a shared secret (env var `STATS_DASHBOARD_KEY`). Without
// the right key, returns 401 — the response body never leaks any data.
//
// This is deliberately a hidden URL: there is no UI, no password reset,
// no rate limiter. Operator runs:
//
//   wrangler pages secret put STATS_DASHBOARD_KEY
//
// to set the secret, then `curl 'https://penova.pages.dev/v1/dashboard?key=…'`.

interface Env {
  STATS_KV?: KVNamespace;
  STATS_DASHBOARD_KEY?: string;
}

// Constant-time string compare to defeat timing-attack scraping. (KV
// list is async + cached so timing leaks are unlikely, but cheap to do.)
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const url = new URL(request.url);
  const provided = url.searchParams.get("key") ?? "";
  const expected = env.STATS_DASHBOARD_KEY ?? "";

  if (!expected || !safeEqual(provided, expected)) {
    return new Response("unauthorized", { status: 401 });
  }

  if (!env.STATS_KV) {
    return new Response(JSON.stringify({ error: "STATS_KV not bound" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  // List all keys with prefix `agg:`. Cloudflare KV's list is paginated;
  // for our scale (one row per (date,os,version,locale) per day) a
  // single pass with a generous limit is fine.
  const rows: Array<{ key: string; value: unknown }> = [];
  let cursor: string | undefined = undefined;
  for (let i = 0; i < 20; i++) {
    const list: KVNamespaceListResult<unknown> = await env.STATS_KV.list({
      prefix: "agg:",
      limit: 1000,
      cursor,
    });
    for (const k of list.keys) {
      const raw = await env.STATS_KV.get(k.name);
      let parsed: unknown = raw;
      try {
        parsed = raw ? JSON.parse(raw) : null;
      } catch {
        // Leave as raw string if not JSON.
      }
      rows.push({ key: k.name, value: parsed });
    }
    if (list.list_complete) break;
    cursor = list.cursor;
  }

  // Roll up totals across all keys for a quick "is this thing on" check.
  const totals: Record<string, number> = {
    scriptsOpened: 0,
    scriptsCreated: 0,
    exportsRun: 0,
    reportsViewed: 0,
  };
  for (const row of rows) {
    const v = row.value as Record<string, unknown> | null;
    if (!v || typeof v !== "object") continue;
    for (const k of Object.keys(totals)) {
      const n = v[k];
      if (typeof n === "number" && Number.isFinite(n)) totals[k] += n;
    }
  }

  return new Response(
    JSON.stringify(
      {
        rowCount: rows.length,
        totals,
        rows,
        generatedAt: new Date().toISOString(),
      },
      null,
      2,
    ),
    {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    },
  );
};
