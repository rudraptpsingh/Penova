//
//  FeedbackComposer.swift
//  PenovaKit
//
//  Builds the prefilled mailto URL for the in-app "Send Feedback…" menu
//  item. Honors Penova's no-servers stance: nothing leaves the user's
//  machine without an explicit Send action in their mail client.
//
//  The diagnostic block is intentionally minimal — app version + build,
//  OS version + architecture, locale, and a UTC timestamp. No serial
//  numbers, no hostnames, no usernames, no file paths.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum FeedbackComposer {

    /// Recipient address. Penova is a solo project; this lands directly
    /// in the developer's inbox. Stays on `rudra.ptp.singh@gmail.com`
    /// per the founder's preference.
    public static let recipient = "rudra.ptp.singh@gmail.com"

    /// Returns a `mailto:` URL with subject + diagnostic-block prefilled.
    /// The user types their feedback above the separator line.
    public static func mailtoURL(now: Date = .now) -> URL? {
        let subject = subjectLine()
        let body = bodyTemplate(now: now)
        guard
            let escapedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let escapedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        let raw = "mailto:\(recipient)?subject=\(escapedSubject)&body=\(escapedBody)"
        return URL(string: raw)
    }

    /// Plain-text fallback: same diagnostic info as the mailto, but
    /// designed for users without a configured mail client. The Mac
    /// "Send Feedback…" alert offers a "Copy diagnostic info" button
    /// that drops this onto the pasteboard so the user can paste it
    /// into webmail.
    public static func clipboardFallback(now: Date = .now) -> String {
        """
        \(subjectLine())

        [Please describe your feedback above this line]

        \(diagnosticBlock(now: now))
        """
    }

    // MARK: - Internals

    static func subjectLine() -> String {
        "Penova feedback — \(versionAndBuild())"
    }

    static func bodyTemplate(now: Date) -> String {
        """
        [Please describe your feedback above this line.]

        \(diagnosticBlock(now: now))
        """
    }

    static func diagnosticBlock(now: Date) -> String {
        """
        — diagnostic info (please keep) —
        App:        Penova \(versionAndBuild())
        Platform:   \(platformDescription())
        Locale:     \(localeIdentifier())
        Date:       \(utcTimestamp(now))
        """
    }

    // MARK: Bundle / system reads

    /// "1.0.0 (142)" — short version + bundle build number.
    public static func versionAndBuild() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// "macOS 14.4.1 (arm64)" or "iPhone 15 — iOS 17.4" — enough to
    /// repro a bug, nothing more.
    public static func platformDescription() -> String {
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        #if os(macOS)
        var arch = "unknown"
        var sysinfo = utsname()
        if uname(&sysinfo) == 0 {
            withUnsafePointer(to: &sysinfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    arch = String(cString: $0)
                }
            }
        }
        return "macOS \(osStr) (\(arch))"
        #elseif os(iOS) || os(visionOS)
        let model = UIDevice.current.model
        return "\(model) — iOS \(osStr)"
        #else
        return "Apple platform \(osStr)"
        #endif
    }

    static func localeIdentifier() -> String {
        Locale.current.identifier
    }

    static func utcTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        return f.string(from: date)
    }
}
