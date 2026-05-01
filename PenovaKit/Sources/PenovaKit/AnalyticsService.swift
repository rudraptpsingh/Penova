//
//  AnalyticsService.swift
//  PenovaKit
//
//  Penova v1.1 — F5 opt-in anonymous usage stats.
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  IMPORTANT: This service NEVER fires when                        │
//  │  PreferencesStore.shared.analyticsEnabled is false.              │
//  │  The guard is at the top of `flushIfDue()` — every code path     │
//  │  that talks to the network goes through that guard.              │
//  └──────────────────────────────────────────────────────────────────┘
//
//  How it works:
//    • The app records events (`scriptOpened`, `scriptCreated`,
//      `exportRun`, `reportViewed`) by calling `record(_:)`.
//    • Counters live in memory only until a flush succeeds.
//    • `flushIfDue()` runs on launch and every 6 hours from a Timer.
//      If the toggle is on AND we haven't sent in >24h, it POSTs the
//      payload to https://penova.pages.dev/v1/ping. On 2xx, counters
//      reset and `analyticsLastSent` is stamped. On any failure, the
//      counters survive and the next scheduled tick retries.
//    • The endpoint URL is hardcoded — there is no remote-config knob,
//      no env switching. One place to point a finger at.
//
//  What's intentionally NOT in the payload:
//    - Install ID / UUID
//    - Device model / serial / hardware identifier
//    - User name / email / Apple ID / iCloud account
//    - Filenames, paths, or any document content
//    - IP address (we don't add it; Cloudflare's edge sees it and we
//      explicitly don't store it server-side either)
//

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Public API

public enum AnalyticsEvent: Sendable {
    case scriptOpened
    case scriptCreated
    case exportRun
    case reportViewed
}

public struct AnalyticsCounters: Codable, Equatable, Sendable {
    public var scriptsOpened: Int
    public var scriptsCreated: Int
    public var exportsRun: Int
    public var reportsViewed: Int

    public init(
        scriptsOpened: Int = 0,
        scriptsCreated: Int = 0,
        exportsRun: Int = 0,
        reportsViewed: Int = 0
    ) {
        self.scriptsOpened = scriptsOpened
        self.scriptsCreated = scriptsCreated
        self.exportsRun = exportsRun
        self.reportsViewed = reportsViewed
    }

    public var isEmpty: Bool {
        scriptsOpened == 0 && scriptsCreated == 0 && exportsRun == 0 && reportsViewed == 0
    }
}

/// The shape we POST to the endpoint. Versioned via `v` so a future
/// schema change doesn't strand old clients silently.
public struct AnalyticsPayload: Codable, Equatable, Sendable {
    public var v: Int
    public var appVersion: String
    public var appBuild: String
    public var os: String
    public var osVersion: String
    public var locale: String
    public var counters: AnalyticsCounters
}

/// Result of a flush attempt — exposed for tests to assert on.
public enum AnalyticsFlushOutcome: Equatable, Sendable {
    case skippedDisabled
    case skippedNotDue
    case skippedNoCounters
    case sent
    case failed(Int)   // HTTP status code, 0 == network error
}

// Network indirection so unit tests can substitute a no-network closure.
public typealias AnalyticsTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public final class AnalyticsService: ObservableObject {

    public static let shared = AnalyticsService()

    /// Hardcoded; intentional. There is no remote-config switching, no
    /// staging override. If the URL ever changes we'll cut a new app
    /// version that points to the new URL.
    public static let endpoint = URL(string: "https://penova.pages.dev/v1/ping")!

    /// Aggregate the user has accumulated since the last successful
    /// send. Settings UI shows this verbatim in the "View what's been
    /// sent" sheet so the user can audit the exact payload.
    @Published public private(set) var pendingCounters = AnalyticsCounters()

    /// Re-published copy of `PreferencesStore.shared.analyticsLastSent`
    /// so the Settings UI can render it without touching defaults.
    @Published public private(set) var lastSent: Date?

    private let prefs: PreferencesStore
    private let transport: AnalyticsTransport
    private let queue = DispatchQueue(label: "penova.analytics.serial")
    private var timer: Timer?
    /// Source-of-truth counters live here, mutated only inside `queue`.
    /// `pendingCounters` (the @Published property) is a main-thread
    /// mirror updated after every queue mutation. Two storage
    /// locations is a small price for thread-safe `record(_:)` from any
    /// caller AND a correctly-published view-model property.
    private var lockedCounters = AnalyticsCounters()

    /// Minimum time between successful sends. The user may launch the
    /// app a hundred times a day; we still only send once.
    private let minSendInterval: TimeInterval = 24 * 60 * 60

    /// How often we self-check whether a flush is due.
    private let pollInterval: TimeInterval = 6 * 60 * 60

    public init(
        prefs: PreferencesStore = .shared,
        transport: @escaping AnalyticsTransport = { req in
            try await URLSession.shared.data(for: req)
        }
    ) {
        self.prefs = prefs
        self.transport = transport
        self.lastSent = prefs.analyticsLastSent
    }

    // MARK: Recording

    /// Increment the appropriate in-memory counter. Cheap; safe to call
    /// from any thread (we serialize on `queue`). NOT gated by the
    /// toggle — recording continues even when stats are disabled, but
    /// the counters never leave the device unless the toggle is on. If
    /// the user turns the toggle off, the next flush guard skips, and
    /// the counters stay in memory until the user either re-enables it
    /// or quits the app.
    public func record(_ event: AnalyticsEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            switch event {
            case .scriptOpened:  self.lockedCounters.scriptsOpened  += 1
            case .scriptCreated: self.lockedCounters.scriptsCreated += 1
            case .exportRun:     self.lockedCounters.exportsRun     += 1
            case .reportViewed:  self.lockedCounters.reportsViewed  += 1
            }
            let snapshot = self.lockedCounters
            DispatchQueue.main.async {
                self.pendingCounters = snapshot
            }
        }
    }

    // MARK: Flush scheduling

    /// Kick off the periodic flush timer + perform an initial flush
    /// check. App entry points call this once on launch.
    public func startScheduling() {
        Task { await self.flushIfDue() }

        // RunLoop on main; Timer fires every 6 hours.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let t = Timer.scheduledTimer(
                withTimeInterval: self.pollInterval,
                repeats: true
            ) { [weak self] _ in
                Task { await self?.flushIfDue() }
            }
            // Tolerance lets the OS coalesce wakeups → minor power win.
            t.tolerance = 60
            self.timer = t
        }
    }

    /// Build a payload from current counters and POST it, if and only
    /// if the user has opted in AND we haven't sent in the last 24h
    /// AND there is something to send.
    @discardableResult
    public func flushIfDue(now: Date = .init()) async -> AnalyticsFlushOutcome {
        // 1. Hard gate. Never fire when disabled.
        guard prefs.analyticsEnabled else { return .skippedDisabled }

        // 2. Throttle. Once per 24h.
        if let last = prefs.analyticsLastSent,
           now.timeIntervalSince(last) < minSendInterval {
            return .skippedNotDue
        }

        // 3. Don't send empty bodies — wastes the user's network and
        //    pollutes our aggregate with no-op rows. Read the
        //    serial-queue copy for thread safety.
        let snapshot = await withCheckedContinuation { (cont: CheckedContinuation<AnalyticsCounters, Never>) in
            queue.async { cont.resume(returning: self.lockedCounters) }
        }
        if snapshot.isEmpty { return .skippedNoCounters }

        let payload = makePayload(counters: snapshot)
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            return .failed(0)
        }

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        // Be a polite client — short timeouts so we never block a
        // background task for minutes if penova.pages.dev is slow.
        req.timeoutInterval = 15

        do {
            let (_, response) = try await transport(req)
            guard let http = response as? HTTPURLResponse else {
                return .failed(0)
            }
            if (200..<300).contains(http.statusCode) {
                // On success, atomically subtract the snapshot from
                // the locked counters (preserves any events recorded
                // during the in-flight POST), republish, and stamp the
                // last-sent time.
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    queue.async {
                        var c = self.lockedCounters
                        c.scriptsOpened  = max(0, c.scriptsOpened  - snapshot.scriptsOpened)
                        c.scriptsCreated = max(0, c.scriptsCreated - snapshot.scriptsCreated)
                        c.exportsRun     = max(0, c.exportsRun     - snapshot.exportsRun)
                        c.reportsViewed  = max(0, c.reportsViewed  - snapshot.reportsViewed)
                        self.lockedCounters = c
                        DispatchQueue.main.async {
                            self.pendingCounters = c
                            let stamp = Date()
                            self.prefs.analyticsLastSent = stamp
                            self.lastSent = stamp
                            cont.resume()
                        }
                    }
                }
                return .sent
            }
            return .failed(http.statusCode)
        } catch {
            return .failed(0)
        }
    }

    /// Visible for tests / Settings UI: build the exact payload that
    /// would be sent right now.
    public func makePayload(counters: AnalyticsCounters? = nil) -> AnalyticsPayload {
        let c = counters ?? pendingCounters
        let info = Bundle.main.infoDictionary
        let appVersion = (info?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let appBuild   = (info?["CFBundleVersion"] as? String) ?? "0"
        let os: String
        #if os(macOS)
        os = "macos"
        #else
        os = "ios"
        #endif
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        // Locale.current.identifier on iOS 17+ is e.g. "en_US"; we
        // canonicalize to BCP-47 "en-US" for friendlier aggregation.
        let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")

        return AnalyticsPayload(
            v: 1,
            appVersion: appVersion,
            appBuild: appBuild,
            os: os,
            osVersion: osVersion,
            locale: locale,
            counters: c
        )
    }
}

