# Penova Pages Functions

This folder hosts the tiny serverless backend that backs Penova's **opt-in**
anonymous-usage-stats feature (Settings → "Help improve Penova by sharing
anonymous usage data").

There is one user-facing endpoint and one operator-only endpoint:

| Path             | Verb | Purpose                                                |
| ---------------- | ---- | ------------------------------------------------------ |
| `/v1/ping`       | POST | Receive a ≤1KB aggregate-counter payload from the apps |
| `/v1/dashboard`  | GET  | Operator-only JSON snapshot, gated by a shared secret  |

Both functions live alongside the static site under `docs/`, so the existing
`npx wrangler pages deploy docs` workflow ships them automatically.

## Privacy-by-default contract

- The toggle in the app is **OFF** by default. The apps NEVER POST anything
  unless the user explicitly turned the toggle ON.
- The payload is aggregate counters only — no script content, no filenames,
  no install ID, no device model.
- We do not log or store the request IP. Cloudflare's edge sees it (we can't
  prevent that), but our code never reads `cf-connecting-ip` and the function
  response includes an explicit `X-Penova-Logging: no-ip-stored` header.

## One-time setup (operator)

These steps happen once per Cloudflare account. They cannot be done from
the function code itself — they require `wrangler` or the Cloudflare
dashboard.

### 1. Create the KV namespace

```bash
npx wrangler kv:namespace create STATS_KV
# → outputs an `id` like 7a8b9c…  (copy it)
```

### 2. Bind it to the Pages project

In the Cloudflare dashboard:

> Pages → `penova` project → Settings → Functions → KV namespace bindings

Add a binding:

- **Variable name:** `STATS_KV`
- **KV namespace:** the one created above

(Equivalent: add it under `[[kv_namespaces]]` in `wrangler.toml` if you
prefer config-as-code.)

### 3. Set the dashboard secret

Pick a long random string and store it as the dashboard auth key:

```bash
openssl rand -hex 32 | npx wrangler pages secret put STATS_DASHBOARD_KEY \
    --project-name=penova
```

Save the value somewhere safe — without it, the dashboard returns 401.

### 4. Deploy

```bash
cd /path/to/penova
npx wrangler pages deploy docs --project-name=penova
```

## Verifying it's live

```bash
# Healthy ping (returns 204 No Content):
curl -i -X POST https://penova.pages.dev/v1/ping \
    -H 'Content-Type: application/json' \
    -d '{
      "v": 1,
      "appVersion": "1.0.0",
      "appBuild": "142",
      "os": "macos",
      "osVersion": "14.4.1",
      "locale": "en-US",
      "counters": {"scriptsOpened":1,"scriptsCreated":0,"exportsRun":0,"reportsViewed":0}
    }'

# Dashboard (replace KEY):
curl 'https://penova.pages.dev/v1/dashboard?key=YOUR_DASHBOARD_KEY' | jq .
```

The response includes a header `X-Penova-Logging: no-ip-stored` so
external monitors can confirm the no-logging promise.

## Removing analytics

If we ever decide to retire the feature:

1. Flip the app toggle to do nothing (or remove the UI), ship a build.
2. Delete the KV namespace in the Cloudflare dashboard — that removes
   every byte of stored aggregate.
3. Delete `docs/functions/v1/ping.ts` and `dashboard.ts`, redeploy.

Because we never stored IPs or identifiers, there is nothing to scrub.
