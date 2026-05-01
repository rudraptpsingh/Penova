//
//  PreferencesStoreTests.swift
//  PenovaTests
//
//  F5 — opt-in anonymous usage stats. The toggle MUST default to off,
//  MUST persist across re-instantiation, and MUST be settable both ways.
//

import XCTest
@testable import PenovaKit

final class PreferencesStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "penova.tests.preferences"

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

    func test_analyticsEnabled_defaultsToFalse() {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertFalse(store.analyticsEnabled,
            "Penova's brand promise: opt-in only. Toggle must default to OFF.")
    }

    func test_analyticsEnabled_persistsAcrossReinit() {
        let a = PreferencesStore(defaults: defaults)
        a.analyticsEnabled = true

        let b = PreferencesStore(defaults: defaults)
        XCTAssertTrue(b.analyticsEnabled, "Toggle should survive re-init.")
    }

    func test_analyticsEnabled_canBeToggledBack() {
        let store = PreferencesStore(defaults: defaults)
        store.analyticsEnabled = true
        store.analyticsEnabled = false
        XCTAssertFalse(store.analyticsEnabled)

        // And the off state persists too.
        let next = PreferencesStore(defaults: defaults)
        XCTAssertFalse(next.analyticsEnabled)
    }

    func test_analyticsLastSent_roundTrips() throws {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertNil(store.analyticsLastSent)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.analyticsLastSent = now

        let next = PreferencesStore(defaults: defaults)
        let stored = try XCTUnwrap(next.analyticsLastSent)
        XCTAssertEqual(stored.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
