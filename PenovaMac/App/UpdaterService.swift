//
//  UpdaterService.swift
//  Penova for Mac
//
//  Sparkle 2.x auto-update integration. The Penova Mac app is
//  distributed direct-from-website (NOT via the Mac App Store), so
//  it must ship its own update mechanism. Sparkle is the de-facto
//  standard for this on macOS; Highland, Fade In, OmniFocus,
//  Things, etc. all use it.
//
//  How it works:
//   • At launch (and every 24h thereafter), Sparkle fetches the
//     appcast.xml feed at SUFeedURL (set in Info.plist).
//   • If a newer version is published, the user sees a standard
//     "A new version of Penova is available" dialog.
//   • The downloaded DMG is verified against SUPublicEDKey before
//     install, so a compromised CDN can't push malicious updates.
//   • The user can also force a check via "Penova → Check for
//     Updates…" in the menu bar.
//
//  Setup is owned by `tools/sparkle-keys.sh` (key generation),
//  `tools/sign-update.sh` (per-release signing), and the appcast
//  publishing recipe in RELEASE.md.
//

import SwiftUI
import Sparkle

/// Hosts the SPUStandardUpdaterController. Lifetime is tied to the
/// app via @StateObject in PenovaMacApp.
///
/// **DEBUG builds**: Sparkle is intentionally NOT started. The
/// SUPublicEDKey placeholder in Info.plist isn't a real key, the
/// feed URL isn't hosted on dev hardware, and any auto-check would
/// pop a confusing "couldn't reach update server" alert at launch.
/// The "Check for Updates…" menu item still appears so contributors
/// can confirm the wiring, but it's disabled with a tooltip.
///
/// **RELEASE builds**: full Sparkle. Auto-checks every 24h per
/// Info.plist `SUScheduledCheckInterval`; the user-visible
/// "Check for Updates…" menu item under the Penova app menu
/// triggers an immediate check.
@MainActor
final class UpdaterService: ObservableObject {

    #if DEBUG
    /// Stubbed in debug — see class doc.
    let isLive: Bool = false
    private let _controller: SPUStandardUpdaterController? = nil
    #else
    /// True once Sparkle is up and the user can actually check.
    let isLive: Bool = true
    private let _controller: SPUStandardUpdaterController?
    #endif

    init() {
        #if DEBUG
        // No-op. Sparkle never starts in debug; see class doc.
        #else
        self._controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    /// Trigger an immediate user-visible check. No-op in DEBUG.
    func checkForUpdates() {
        _controller?.checkForUpdates(nil)
    }

    /// Whether the menu item should be enabled.
    var canCheck: Bool {
        #if DEBUG
        return false
        #else
        return _controller?.updater.canCheckForUpdates ?? false
        #endif
    }
}

/// Standalone Button suitable for embedding inside `Commands { }`.
/// Auto-disables while a check is in flight or in DEBUG builds.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheck)
        .help(
            updater.isLive
                ? "Look for a newer version of Penova."
                : "Updates only run in shipped builds. (Debug build of Penova has Sparkle disabled.)"
        )
    }
}
