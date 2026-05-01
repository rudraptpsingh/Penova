# Penova landing page

Static site served at https://penova.pages.dev (Cloudflare Pages,
direct upload — no Git provider connection).

## Layout

```
docs/
├── index.html           Mac-first landing (hero / workflow / iOS section)
├── support.html         Support + contact
├── privacy.html         Privacy policy
├── appcast.xml          Sparkle update feed (Mac)
├── _headers             Cloudflare Pages routing rules (DMG content-type, etc.)
├── img/                 iOS screenshots
└── img/mac/             Mac mockup renders (regenerate via headless Chrome,
                         see "Regenerating Mac shots" below)
└── releases/
    ├── Penova.dmg               (latest, stable filename)
    └── Penova-1.0.0.dmg         (versioned)
```

## Deploy

One command from anywhere with `wrangler` installed and authed:

```sh
npx wrangler pages deploy docs --project-name penova
```

The Cloudflare account `rudra.ptp.singh@gmail.com` already owns the
`penova` project; `npx wrangler whoami` confirms the auth.

## Cloudflare Web Analytics

The beacon script in every HTML page references
`{{CLOUDFLARE_BEACON_TOKEN}}` — replace with your real token.

To set it up:

1. https://dash.cloudflare.com → Analytics & Logs → Web Analytics
2. Add a site for `penova.pages.dev`
3. Copy the 32-char beacon token
4. `find docs -name '*.html' -exec sed -i '' 's/{{CLOUDFLARE_BEACON_TOKEN}}/<token>/g' {} +`
5. Re-deploy.

Cloudflare Pages also has an opt-in built-in Real-User Monitoring
(Pages → your project → Analytics → Web Analytics). If you turn that
on, this beacon tag is redundant — pick one.

## Regenerating Mac shots

The screenshots under `img/mac/` are headless-Chrome renders of the
HTML mockups in `mockups/mac/`. To refresh:

```sh
for f in library focus index-cards outline title-page export search empty-state; do
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1440,900 \
    --screenshot="docs/img/mac/${f}.png" \
    "file://$PWD/mockups/mac/${f}.html"
done
```

## Per-release flow (Mac)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. `PENOVA_TEAM_ID=2657RFZCWF PENOVA_NOTARY_PROFILE=rudra-notary tools/notarize-mac.sh`
3. Copy the resulting `build/Penova.dmg` into:
   - `docs/releases/Penova-X.Y.Z.dmg` (versioned)
   - `docs/releases/Penova.dmg` (overwrite the stable filename)
4. `tools/sign-update.sh build/Penova.dmg --version X.Y.Z` — copy the
   `<item>` block, prepend it to `docs/appcast.xml` (newest first).
5. `npx wrangler pages deploy docs --project-name penova`
