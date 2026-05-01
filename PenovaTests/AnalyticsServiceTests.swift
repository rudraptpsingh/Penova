//
//  AnalyticsServiceTests.swift
//  PenovaTests
//
//  F5 — opt-in anonymous usage stats. These tests pin down the contract:
//
//    • record() increments only the named counter
//    • flushIfDue() does NOTHING when the toggle is off
//    • flushIfDue() does NOTHING when last-sent < 24h ago
//    • flushIfDue() does NOTHING when counters are empty
//    • flushIfDue() resets counters + stamps lastSent on a 2xx
//    • flushIfDue() preserves counters on a non-2xx
//    • Endpoint URL is the documented one — no remote-config drift
//

import XCTest
@testable import PenovaKit

final class AnalyticsServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "penova.tests.analytics"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Helpers

    /// Build a service backed by an isolated PreferencesStore and an
    /// in-memory transport that records every request and returns
    /// whatever (Data, URLResponse) tuple the test sets up.
    private func makeService(
        enabled: Bool = false,
        lastSent: Date? = nil,
        respond: @escaping @Sendable (URLRequest) -> (Data, URLResponse)
    ) -> (AnalyticsService, PreferencesStore, RequestRecorder) {
        let prefs = PreferencesStore(defaults: defaults)
        prefs.analyticsEnabled = enabled
        prefs.analyticsLastSent = lastSent

        let rec = RequestRecorder()
        let svc = AnalyticsService(prefs: prefs) { req in
            rec.record(req)
            return respond(req)
        }
        return (svc, prefs, rec)
    }

    private static func ok(for req: URLRequest) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(
            url: req.url ?? AnalyticsService.endpoint,
            statusCode: 204, httpVersion: nil, headerFields: nil
        )!
        return (Data(), resp)
    }

    private static func server500(for req: URLRequest) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(
            url: req.url ?? AnalyticsService.endpoint,
            statusCode: 500, httpVersion: nil, headerFields: nil
        )!
        return (Data(), resp)
    }

    // MARK: Recording

    func test_record_incrementsTheRightCounter() async {
        let (svc, _, _) = makeService { Self.ok(for: $0) }
        svc.record(.scriptOpened)
        svc.record(.scriptOpened)
        svc.record(.scriptCreated)
        svc.record(.exportRun)
        svc.record(.reportViewed)

        // record() hops through a serial queue + main; let it land.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let c = await MainActor.run { svc.pendingCounters }
        XCTAssertEqual(c.scriptsOpened, 2)
        XCTAssertEqual(c.scriptsCreated, 1)
        XCTAssertEqual(c.exportsRun, 1)
        XCTAssertEqual(c.reportsViewed, 1)
    }

    // MARK: flushIfDue gating — the brand-critical tests

    func test_flush_doesNothing_whenDisabled() async {
        let (svc, _, rec) = makeService(enabled: false) { Self.ok(for: $0) }
        svc.record(.scriptOpened)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let outcome = await svc.flushIfDue()
        XCTAssertEqual(outcome, .skippedDisabled,
            "A disabled toggle MUST NOT trigger a network request. This is the brand-critical guard.")
        XCTAssertEqual(rec.count, 0,
            "No URLRequest should have been issued.")
    }

    func test_flush_doesNothing_whenLastSentLessThan24hAgo() async {
        let lastSent = Date().addingTimeInterval(-60 * 60) // 1h ago
        let (svc, _, rec) = makeService(enabled: true, lastSent: lastSent) {
            Self.ok(for: $0)
        }
        svc.record(.scriptOpened)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let outcome = await svc.flushIfDue()
        XCTAssertEqual(outcome, .skippedNotDue)
        XCTAssertEqual(rec.count, 0)
    }

    func test_flush_doesNothing_whenCountersEmpty() async {
        let (svc, _, rec) = makeService(enabled: true) { Self.ok(for: $0) }
        let outcome = await svc.flushIfDue()
        XCTAssertEqual(outcome, .skippedNoCounters)
        XCTAssertEqual(rec.count, 0)
    }

    // MARK: flushIfDue happy path

    func test_flush_postsThenResets_onSuccess() async {
        let (svc, prefs, rec) = makeService(enabled: true) { Self.ok(for: $0) }
        svc.record(.scriptOpened)
        svc.record(.exportRun)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let outcome = await svc.flushIfDue()
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(rec.count, 1)

        // Counters reset.
        let c = await MainActor.run { svc.pendingCounters }
        XCTAssertEqual(c, AnalyticsCounters())

        // lastSent stamped.
        XCTAssertNotNil(prefs.analyticsLastSent)
    }

    func test_flush_targetsTheDocumentedEndpoint() async {
        let (svc, _, rec) = makeService(enabled: true) { Self.ok(for: $0) }
        svc.record(.scriptOpened)
        try? await Task.sleep(nanoseconds: 50_000_000)
        _ = await svc.flushIfDue()

        XCTAssertEqual(rec.lastRequest?.url?.absoluteString,
                       "https://penova.pages.dev/v1/ping",
                       "The endpoint URL is part of the public privacy policy. Don't change it without updating docs/privacy.html.")
        XCTAssertEqual(rec.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(rec.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
    }

    func test_flush_payloadShape_matchesContract() async throws {
        let (svc, _, rec) = makeService(enabled: true) { Self.ok(for: $0) }
        svc.record(.scriptOpened)
        svc.record(.scriptCreated)
        svc.record(.exportRun)
        try? await Task.sleep(nanoseconds: 50_000_000)
        _ = await svc.flushIfDue()

        let body = try XCTUnwrap(rec.lastRequest?.httpBody)
        let payload = try JSONDecoder().decode(AnalyticsPayload.self, from: body)
        XCTAssertEqual(payload.v, 1)
        XCTAssertTrue(payload.os == "macos" || payload.os == "ios",
            "os must be macos or ios (the only platforms the server accepts).")
        XCTAssertEqual(payload.counters.scriptsOpened, 1)
        XCTAssertEqual(payload.counters.scriptsCreated, 1)
        XCTAssertEqual(payload.counters.exportsRun, 1)
        XCTAssertEqual(payload.counters.reportsViewed, 0)

        // Size sanity — the brand promise is "smaller than 1 KB".
        XCTAssertLessThan(body.count, 1024,
            "Payload must stay under 1 KB to honor the privacy-page promise.")
    }

    func test_flush_preservesCounters_onServerError() async {
        let (svc, prefs, _) = makeService(enabled: true) { Self.server500(for: $0) }
        svc.record(.scriptOpened)
        svc.record(.exportRun)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let outcome = await svc.flushIfDue()
        XCTAssertEqual(outcome, .failed(500))

        let c = await MainActor.run { svc.pendingCounters }
        XCTAssertEqual(c.scriptsOpened, 1)
        XCTAssertEqual(c.exportsRun, 1)
        XCTAssertNil(prefs.analyticsLastSent,
            "A failed flush must not stamp lastSent — otherwise the user loses a day.")
    }

    // MARK: Endpoint constant

    func test_endpoint_isTheDocumentedURL() {
        XCTAssertEqual(AnalyticsService.endpoint.absoluteString,
                       "https://penova.pages.dev/v1/ping")
    }
}

// MARK: - Test fixtures

/// Records every URLRequest the service emits so tests can assert on count + shape.
private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func record(_ req: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        requests.append(req)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }
}
