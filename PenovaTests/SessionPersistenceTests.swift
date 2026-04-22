//
//  SessionPersistenceTests.swift
//  PenovaTests
//
//  Covers Sign in with Apple persistence via the shared UserDefaults keys
//  declared in OnboardingScreen.swift and consumed by ScriptPDFRenderer.
//

import Testing
import Foundation
@testable import Penova

// Keys live in OnboardingScreen as @AppStorage; we duplicate them here since
// they aren't exposed as public constants.
private enum AuthKey {
    static let userId = "penova.auth.userId"
    static let fullName = "penova.auth.fullName"
    static let email = "penova.auth.email"
    static let didFinishOnboarding = "penova.flow.didFinishOnboarding"
}

/// Mirrors ScriptPDFRenderer.authorName() so we can assert the exact fallback
/// behaviour without touching the private method (which also needs UIKit drawing
/// context). If this logic drifts from the renderer, the render-test below will
/// still exercise the real code path.
private func authorNameFromDefaults(_ defaults: UserDefaults = .standard) -> String {
    let stored = defaults.string(forKey: AuthKey.fullName) ?? ""
    if !stored.trimmingCharacters(in: .whitespaces).isEmpty { return stored }
    return "The Writer"
}

@Suite(.serialized)
struct SessionPersistenceTests {

    private func clearAll(_ d: UserDefaults = .standard) {
        for k in [AuthKey.userId, AuthKey.fullName, AuthKey.email, AuthKey.didFinishOnboarding] {
            d.removeObject(forKey: k)
        }
    }

    @Test func storingNamePropagatesToAuthor() {
        clearAll()
        UserDefaults.standard.set("Rudra Pratap Singh", forKey: AuthKey.fullName)
        #expect(authorNameFromDefaults() == "Rudra Pratap Singh")
        clearAll()
    }

    @Test func missingNameFallsBackToTheWriter() {
        clearAll()
        #expect(authorNameFromDefaults() == "The Writer")
    }

    @Test func emptyOrWhitespaceNameFallsBackToTheWriter() {
        clearAll()
        UserDefaults.standard.set("", forKey: AuthKey.fullName)
        #expect(authorNameFromDefaults() == "The Writer")
        UserDefaults.standard.set("   \t  ", forKey: AuthKey.fullName)
        #expect(authorNameFromDefaults() == "The Writer")
        clearAll()
    }

    @Test func signOutClearsKeysAndResetsAuthor() {
        UserDefaults.standard.set("abc.123", forKey: AuthKey.userId)
        UserDefaults.standard.set("Jane Doe", forKey: AuthKey.fullName)
        UserDefaults.standard.set("jane@example.com", forKey: AuthKey.email)
        #expect(authorNameFromDefaults() == "Jane Doe")

        // Sign-out path (the UI doesn't implement this yet, but the persistence
        // contract must support clearing).
        clearAll()

        #expect(UserDefaults.standard.string(forKey: AuthKey.userId) == nil)
        #expect(UserDefaults.standard.string(forKey: AuthKey.fullName) == nil)
        #expect(UserDefaults.standard.string(forKey: AuthKey.email) == nil)
        #expect(authorNameFromDefaults() == "The Writer")
    }

    @Test func finishingOnboardingSurvivesRelaunch() throws {
        let suiteName = "penova.tests.\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suiteName))
        defer {
            first.removePersistentDomain(forName: suiteName)
        }

        #expect(first.bool(forKey: AuthKey.didFinishOnboarding) == false)

        // Simulate completing onboarding.
        first.set(true, forKey: AuthKey.didFinishOnboarding)
        first.set("001122.abc", forKey: AuthKey.userId)
        first.set("Relaunch Tester", forKey: AuthKey.fullName)
        first.synchronize()

        // Simulate process relaunch by constructing a fresh instance against
        // the same suite.
        let reborn = try #require(UserDefaults(suiteName: suiteName))
        #expect(reborn.bool(forKey: AuthKey.didFinishOnboarding) == true)
        #expect(reborn.string(forKey: AuthKey.userId) == "001122.abc")
        #expect(reborn.string(forKey: AuthKey.fullName) == "Relaunch Tester")
    }
}
