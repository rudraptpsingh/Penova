//
//  PenovaMacFeedback.swift
//  Penova for Mac
//
//  Bridges the cross-platform `FeedbackComposer` (in PenovaKit) into
//  AppKit's URL-open + clipboard APIs. The Mac menu item triggers
//  `sendFeedback()` which:
//
//    1. Asks NSWorkspace to open the prefilled mailto URL
//    2. If no mail client is configured (or open fails), shows an
//       alert with a "Copy diagnostic info" button that drops the
//       same diagnostic block onto the pasteboard so the user can
//       paste into webmail.
//
//  No analytics, no logging — the menu item is a pure user-initiated
//  action. Penova does not record that the user pressed it.
//

import AppKit
import PenovaKit

enum PenovaMacFeedback {

    static func sendFeedback() {
        guard let url = FeedbackComposer.mailtoURL() else {
            offerClipboardFallback(reason: .urlBuildFailed)
            return
        }
        // NSWorkspace.shared.open(_:) returns Bool synchronously on
        // macOS — true if a handler was found and launched, false if
        // there's no registered mail client. We fall back to the
        // alert in either failure case.
        if !NSWorkspace.shared.open(url) {
            offerClipboardFallback(reason: .noMailClient)
        }
    }

    // MARK: - Fallback

    private enum FallbackReason {
        case urlBuildFailed
        case noMailClient
    }

    private static func offerClipboardFallback(reason: FallbackReason) {
        let alert = NSAlert()
        switch reason {
        case .urlBuildFailed:
            alert.messageText = "Couldn't open your mail client"
            alert.informativeText = """
            We can't compose the email automatically right now. \
            Tap "Copy diagnostic info" to paste it into your browser or any \
            other mail tool, and send to \(FeedbackComposer.recipient).
            """
        case .noMailClient:
            alert.messageText = "No mail client configured"
            alert.informativeText = """
            macOS doesn't have a default mail app set up. Tap "Copy \
            diagnostic info" to paste it into your browser or any other \
            mail tool, and send to \(FeedbackComposer.recipient).
            """
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy diagnostic info")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(
                FeedbackComposer.clipboardFallback(),
                forType: .string
            )
        }
    }
}
