# Shipping Penova

This is the operator's manual for getting a Penova release out the
door. Two distribution targets:

- **iOS** — TestFlight beta then App Store. Uses `xcrun altool` to
  upload to App Store Connect.
- **macOS** — direct download from `https://penova.app`. Developer ID
  signed, notarized, stapled, packaged in a DMG, and shipped through
  Sparkle's auto-update mechanism.

Every command below assumes:

```sh
brew install xcodegen        # once
xcrun --install              # Xcode command-line tools
```

---

## One-time setup

### 1. Apple Developer credentials

You need:

- An active **Apple Developer Program** membership.
- The bundle identifiers `com.rudrapratapsingh.penova` (iOS) and
  `com.rudrapratapsingh.penova.mac` (macOS) registered in
  [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
  with the Sign in with Apple capability enabled.
- An app record in [App Store Connect](https://appstoreconnect.apple.com)
  matching the iOS bundle ID, primary language English (UK), category
  Productivity (secondary Entertainment).
- A **Developer ID Application** certificate installed in your login
  keychain. Get it via Xcode → Settings → Accounts → Manage
  Certificates → + Developer ID Application.
- An **app-specific password** generated at
  [appleid.apple.com](https://appleid.apple.com).

### 2. notarytool keychain profile

Stash credentials so `notarytool` can submit silently:

```sh
xcrun notarytool store-credentials penova-notary \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "abcd-efgh-ijkl-mnop"   # the app-specific one
```

### 3. Sparkle EdDSA key pair (Mac only, ONCE)

```sh
# Build PenovaMac at least once so Sparkle's bin/ tools resolve:
xcodegen
xcodebuild build -scheme PenovaMac -destination 'platform=macOS' -quiet

# Generate the keys:
tools/sparkle-keys.sh
```

The script prints a public key. Copy it into
`PenovaMac/App/Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>{{paste here}}</string>
```

The private key is now in your login keychain. Never re-run
`sparkle-keys.sh` after first release — your shipped users' apps
would refuse all future updates.

### 4. Environment variables

Add to your shell rc (e.g. `~/.zshrc`) or use a `.env` file you
source before each release:

```sh
export PENOVA_TEAM_ID="ABCDE12345"
export PENOVA_NOTARY_PROFILE="penova-notary"
export PENOVA_APPLE_ID="you@example.com"
export PENOVA_APP_PASSWORD="abcd-efgh-ijkl-mnop"
```

---

## macOS release

> **Distribution:** Direct download. Free. Notarized.
> Auto-updates via Sparkle.

### Per-release steps

```sh
# Bump versions in project.yml (PenovaMac → MARKETING_VERSION,
# CURRENT_PROJECT_VERSION) — or pass them via env vars below.

PENOVA_VERSION=1.0.1 PENOVA_BUILD_NUMBER=42 tools/notarize-mac.sh
```

The script does:

1. `xcodegen` — regenerates the Xcode project.
2. `xcodebuild archive` — Developer ID signed, hardened runtime on.
3. `xcodebuild -exportArchive` — produces `build/release-mac/Penova.app`.
4. `xcrun notarytool submit` — uploads the .app, waits for the
   notary verdict (1–5 min typically).
5. `xcrun stapler staple` — pins the notarization ticket to the .app
   so Gatekeeper trusts it offline.
6. `hdiutil create` — wraps it in a UDZO DMG.
7. Notarizes + staples the DMG too (the DMG itself needs its own
   ticket, otherwise the user's Mac will warn on first download).

Output: `build/Penova.dmg`. Verify Gatekeeper accepts it:

```sh
spctl --assess --type open --context context:primary-signature -vvv build/Penova.dmg
```

### Sign + publish the update

```sh
tools/sign-update.sh build/Penova.dmg \
  --version 1.0.1 \
  --build 42 \
  --notes-url https://penova.app/release-notes/1.0.1.html
```

This prints an `<item>` block. Append it to the top of
`public/appcast.xml` (newest first) and ship both files:

```sh
# Pseudo-code — substitute your real CDN.
scp build/Penova.dmg     production:/var/www/penova.app/releases/
scp public/appcast.xml   production:/var/www/penova.app/appcast.xml
```

Within 24 hours every running Penova installation will check the
appcast, fetch the new DMG, verify the EdDSA signature against its
embedded `SUPublicEDKey`, and prompt the user to install. Users can
also force a check via **Penova → Check for Updates…** in the menu
bar.

### Manual rollback

If a release is bad: replace `appcast.xml` with the previous version
(remove the broken `<item>` block). Already-installed users will not
re-download a version they already have, and new users get the
older one. Keep a `releases/archive/` folder with every shipped DMG
so you can serve any prior version on demand.

---

## iOS release

> **Distribution:** App Store Connect → TestFlight → App Review.

### Per-release steps

```sh
PENOVA_VERSION=1.0.1 PENOVA_BUILD_NUMBER=42 tools/upload-ios-testflight.sh
```

The script does:

1. `xcodegen` — regenerates the project.
2. `xcodebuild archive` — App Store signed, generic iOS device.
3. `xcodebuild -exportArchive` — produces `build/release-ios/Penova.ipa`.
4. `xcrun altool --upload-app` — uploads to App Store Connect.

Wait ~10–20 min for processing. The build then appears under
**Penova → TestFlight** in App Store Connect.

### Tester flow

- **Internal testers** (up to 100, your team) see the build the
  moment it processes.
- **External testers** (up to 10 000, public link) require a one-time
  Beta App Review (~24h on first submission, then ~hours).
- **App Review** for the public App Store is initiated separately
  via App Store Connect → Penova → Distribution → "Submit for review."

### Bumping build numbers

App Store Connect rejects a duplicate `CFBundleVersion`. The script
accepts `PENOVA_BUILD_NUMBER` for one-off overrides; otherwise edit
`project.yml`'s `CURRENT_PROJECT_VERSION` and bump it for every
upload regardless of `MARKETING_VERSION`.

---

## App Store metadata

The iOS app store record needs:

- **App name** — Penova
- **Subtitle** — Write the page. Hide the app.
- **Promotional text (170 chars)** — A dark-first screenplay editor
  built for writers on the phone. Industry-format PDFs, FDX, and
  Fountain. Voice capture in हिन्दी and four flavours of English.
- **Keywords** — screenplay, screenwriter, fdx, fountain, dialogue,
  storyboard, hindi, dictation, drama, script
- **Category** — Productivity (primary), Entertainment (secondary)
- **Privacy** — `Penova/Resources/PrivacyInfo.xcprivacy` declares
  zero tracking, zero data collection, with required-reason codes
  for UserDefaults (`CA92.1`), file timestamp (`C617.1`), disk space
  (`E174.1`), system boot time (`35F9.1`).
- **Support URL** — https://penova.app/support
- **Privacy policy URL** — https://penova.app/privacy
- **Marketing URL** — https://penova.app

---

## Pre-flight checklist

Before pressing the button on either target:

- [ ] All tests pass: `xcodebuild test -project Penova.xcodeproj -scheme Penova -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- [ ] PenovaMac smoke runs clean: `Penova.app/Contents/MacOS/Penova --smoke`
- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped in `project.yml`
- [ ] `git tag -a vX.Y.Z` annotated tag pushed
- [ ] (Mac) Public release notes HTML published at the URL referenced
      from the appcast item
- [ ] (iOS) "What to Test" notes drafted in App Store Connect for
      TestFlight users

---

## Troubleshooting

**`notarytool` reports "Invalid Signature".** The hardened runtime
must be enabled (it is, in `project.yml: ENABLE_HARDENED_RUNTIME = YES`)
and the Developer ID Application certificate must be in the login
keychain (not System or any other). Re-run with
`-allowProvisioningUpdates` and watch the export log.

**Sparkle: "The update has an invalid signature".** The DMG was
signed with a different EdDSA private key than the one whose public
counterpart is embedded in the running app. You probably re-ran
`sparkle-keys.sh` — recover by restoring the original private key
from a backup, or accept that all existing installs are bricked
from auto-updating and ship a "manual reinstall" notice.

**altool: "ITMS-90683: Missing purpose string"** — Edit
`Penova/App/Info.plist` and add the `NSXxxUsageDescription` key for
the API the linker pulled in.

**`hdiutil create` fails with "Resource busy"** — A previous run
left the DMG mounted. Run `hdiutil detach /Volumes/Penova` and retry.
