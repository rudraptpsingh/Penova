//
//  PreferencesStore.swift
//  PenovaKit
//
//  Tiny @Published facade over UserDefaults for cross-platform user
//  preferences. Today this only covers F5 (opt-in anonymous analytics);
//  future preferences plug in here so we don't sprinkle UserDefaults
//  reads/writes across the app.
//
//  Why a singleton + ObservableObject? Settings UI on Mac and iOS both
//  bind a SwiftUI `Toggle` to `prefs.analyticsEnabled`. AnalyticsService
//  reads the same flag from the same instance, so the moment the user
//  flips the toggle off, the next flushIfDue() bails out.
//
//  We do NOT persist any of this in CloudKit or sync via iCloud — these
//  are local user preferences that should NOT travel between devices.
//  A user who opts out on their iPhone should not be opted into stats
//  on their Mac. (The toggle is per-install for this reason.)
//

import Foundation
import Combine

public final class PreferencesStore: ObservableObject {
    public static let shared = PreferencesStore()

    /// User has opted in to sending anonymous usage stats. False by
    /// default. Persisted across launches via UserDefaults.
    @Published public var analyticsEnabled: Bool {
        didSet {
            defaults.set(analyticsEnabled, forKey: Keys.analyticsEnabled)
        }
    }

    /// Timestamp of the last successful POST to the ping endpoint.
    /// `nil` means "never sent" — the next flush will fire as soon as
    /// the toggle is on. Stored as a Date in UserDefaults.
    public var analyticsLastSent: Date? {
        get { defaults.object(forKey: Keys.analyticsLastSent) as? Date }
        set { defaults.set(newValue, forKey: Keys.analyticsLastSent) }
    }

    private let defaults: UserDefaults

    enum Keys {
        public static let analyticsEnabled  = "penova.analytics.enabled"
        public static let analyticsLastSent = "penova.analytics.lastSent"
    }

    /// Designated initializer. Tests inject a non-standard suite so they
    /// don't poison the real defaults plist. Production callers always
    /// reach for `.shared`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // .bool(forKey:) returns false for missing keys, which matches
        // our "off by default" contract. We don't need a sentinel.
        self.analyticsEnabled = defaults.bool(forKey: Keys.analyticsEnabled)
    }
}
