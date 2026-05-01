# Releasing Penova for Mac

Penova ships through `.github/workflows/release.yml` on every git tag
matching `v*.*.*`. The pipeline archives, signs, notarizes, staples,
DMG-wraps, signs the Sparkle update entry, and deploys the website
update — end to end. This file documents the one-time secret setup the
workflow depends on, the cutting-a-release flow, and the manual
fallback when CI is unavailable.

## TL;DR — cutting a release

```sh
git checkout main && git pull
git tag -a v1.2.0 -m "Release 1.2.0

## What's new

- Smart paste from anywhere
- iCloud Drive support for Fountain folder mode
- A-numbering for inserts after page lock"
git push --tags
```

The workflow takes ~12-15 minutes and:

1. Updates `project.yml` to `MARKETING_VERSION: "1.2.0"` and
   `CURRENT_PROJECT_VERSION: "120"`.
2. Builds + signs + notarizes a fresh DMG.
3. Adds a new `<item>` to `docs/appcast.xml` (Sparkle's update feed).
4. Updates `docs/releases/Penova.dmg` and `docs/releases/Penova-1.2.0.dmg`.
5. Bumps version refs across `docs/index.html`, `docs/blog/*.html`,
   `docs/support.html`, `docs/privacy.html`.
6. Generates `docs/release-notes/1.2.0.html` from your tag annotation.
7. Deploys the updated `docs/` to Cloudflare Pages.
8. Creates a GitHub Release with the DMG attached.
9. Opens a PR back to `main` with the version bumps so the next
   release knows what the previous one was.

The tag annotation supports basic Markdown — bullets become `<ul>`,
`## ` lines become `<h2>`, plain lines become `<p>`. Sparkle's update
dialog renders the result.

## One-time secret setup

All secrets live in **Settings → Secrets and variables → Actions** on
the GitHub repo. Each one is a single value with no surrounding
quotes.

### Apple signing

| Secret | What it is | How to get it |
|---|---|---|
| `APPLE_DEVELOPER_ID_CERT_P12` | Base64-encoded `.p12` of your Developer ID Application certificate | See "Exporting the cert" below |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | The password you set when exporting the `.p12` | (you set this when exporting) |
| `APPLE_ID` | The Apple ID that owns the Developer Program membership | e.g. `you@example.com` |
| `APPLE_TEAM_ID` | 10-character team ID from developer.apple.com → Membership | e.g. `2657RFZCWF` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password generated at appleid.apple.com → Sign-In and Security → App-Specific Passwords | (generate fresh; don't reuse a real password) |

#### Exporting the cert

1. Open Keychain Access on the Mac that has the Developer ID Application
   certificate installed.
2. Find the certificate (search "Developer ID Application: Your Name").
3. Right-click it → **Export "Developer ID Application: …"…**.
4. Save as a `.p12` with a password you'll remember.
5. Encode it: `base64 -i developer-id.p12 -o developer-id.p12.txt`
6. Paste the contents of that text file into the
   `APPLE_DEVELOPER_ID_CERT_P12` secret on GitHub.
7. Securely delete the `.p12` and `.txt` files locally afterward.

### Sparkle update signing

| Secret | What it is | How to get it |
|---|---|---|
| `SPARKLE_ED_PRIVATE_KEY` | Base64 of your Sparkle EdDSA private key | `base64 -i ~/.local/share/Sparkle/private.key` |

The key was created the first time `tools/sparkle-keys.sh` ran. The
public counterpart is hard-coded into `PenovaMac/App/Info.plist` as
`SUPublicEDKey`. **Don't ever rotate the EdDSA key without also pushing
a new Info.plist with the new public key — every existing 1.x install
will refuse the update otherwise.**

### Cloudflare Pages

| Secret | What it is | How to get it |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | API token with Pages:Edit permission | dash.cloudflare.com → My Profile → API Tokens → Create Token → "Edit Cloudflare Pages" template |
| `CLOUDFLARE_ACCOUNT_ID` | Account ID from the Cloudflare dashboard | dash.cloudflare.com → right sidebar → Account ID |

### Runner-only

| Secret | What it is | How to get it |
|---|---|---|
| `KEYCHAIN_PASSWORD` | Random password for the runner's temporary keychain | `openssl rand -base64 32` (any random value; not used after the run) |

## Manual fallback

If GitHub Actions is unavailable or you're cutting a release from a
laptop with the dev keychain set up, the same pipeline runs from a
shell:

```sh
# 1. Bump the version in project.yml.
sed -i '' 's/MARKETING_VERSION: "1.1.0"/MARKETING_VERSION: "1.2.0"/g' project.yml
sed -i '' 's/CURRENT_PROJECT_VERSION: "11"/CURRENT_PROJECT_VERSION: "120"/g' project.yml

# 2. Notarize.
PENOVA_TEAM_ID="$YOUR_TEAM_ID" \
  PENOVA_NOTARY_PROFILE="rudra-notary" \
  bash tools/notarize-mac.sh

# 3. Sign the Sparkle update entry.
bash tools/sign-update.sh build/Penova.dmg \
  --version 1.2.0 --build 120 \
  --notes-url "https://penova.pages.dev/release-notes/1.2.0.html"

# 4. Stage the DMG into docs/releases/.
cp build/Penova.dmg docs/releases/Penova-1.2.0.dmg
cp build/Penova.dmg docs/releases/Penova.dmg

# 5. Paste the <item> block from step 3 into docs/appcast.xml as the
#    new top-most <item> entry. (Newest first.)

# 6. Update version strings on the public site.
find docs -name '*.html' -print0 | xargs -0 sed -i '' \
  -e "s|Penova-1.1.0.dmg|Penova-1.2.0.dmg|g" \
  -e "s|v1.1.0|v1.2.0|g" \
  -e "s|Download Penova 1.1.0|Download Penova 1.2.0|g" \
  -e "s|\"softwareVersion\": \"1.1.0\"|\"softwareVersion\": \"1.2.0\"|g"

# 7. Write release-notes/1.2.0.html (or copy + edit a previous one).

# 8. Deploy.
npx wrangler pages deploy docs --project-name penova \
  --branch main --commit-dirty=true

# 9. Tag + push.
git tag -a v1.2.0 -m "Release 1.2.0"
git push --tags
```

When the tag eventually pushes, the GitHub Actions workflow will
notice the version is already in `appcast.xml` and the
`update_appcast.py` helper makes the operation idempotent — it won't
duplicate the entry.

## Auditing the release

After a release lands, verify:

```sh
curl -sI https://penova.pages.dev/releases/Penova.dmg | head -1     # 200
curl -sI https://penova.pages.dev/releases/Penova-1.2.0.dmg | head -1 # 200
curl -s  https://penova.pages.dev/appcast.xml | grep '1.2.0'        # has new item
curl -sI https://penova.pages.dev/release-notes/1.2.0.html | head -1 # 200
```

Then open the Mac app → **Penova → Check for Updates…** and confirm
Sparkle offers the new version. If Sparkle says "you're up to date"
when it shouldn't, the most common causes are:

- `<sparkle:shortVersionString>` in the new `<item>` doesn't outrank
  the running app's `CFBundleShortVersionString`.
- The `sparkle:edSignature` in the new `<item>` doesn't verify against
  the bundled `SUPublicEDKey`. (Most often: someone rotated the EdDSA
  private key without also bumping the public key in Info.plist.)
- Cloudflare's CDN is still serving the old appcast — wait 60s or
  curl with `-H "Cache-Control: no-cache"` to verify.

## Rolling back a bad release

```sh
# 1. Edit docs/appcast.xml and remove the <item> block for the bad version.
# 2. Move docs/releases/Penova.dmg back to point at the previous good DMG.
cp docs/releases/Penova-1.1.0.dmg docs/releases/Penova.dmg
# 3. Re-deploy.
npx wrangler pages deploy docs --project-name penova \
  --branch main --commit-dirty=true
```

The bad version's GitHub Release stays around for forensics; nothing
else needs cleanup. Existing users who already auto-updated to the bad
version will need a manual remediation path (re-download and reinstall
from `Penova-1.1.0.dmg`).
