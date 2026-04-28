//
//  AuthSessionTests.swift
//  PenovaTests
//
//  Covers AuthSession's local credential persistence + sign-out. The
//  Apple-side `getCredentialState` round-trip needs a real Apple ID so
//  we test the parts of the session that don't require it: storing,
//  reading, clearing, and the contact-block default we feed into new
//  projects.
//

import Testing
import Foundation
@testable import Penova

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "penova.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

@MainActor
@Suite struct AuthSessionTests {

    @Test func anonymousByDefault() {
        let session = AuthSession(defaults: makeIsolatedDefaults())
        #expect(session.isSignedIn == false)
        #expect(session.userId.isEmpty)
        #expect(session.fullName.isEmpty)
        #expect(session.email.isEmpty)
        #expect(session.status == .anonymous)
    }

    @Test func displayNameFallsBackToFriend() {
        let session = AuthSession(defaults: makeIsolatedDefaults())
        #expect(session.displayName == "Friend")
    }

    @Test func defaultContactBlockIsEmptyForAnonymous() {
        let session = AuthSession(defaults: makeIsolatedDefaults())
        #expect(session.defaultContactBlock.isEmpty)
    }

    @Test func signOutClearsLocalCredentials() {
        let defaults = makeIsolatedDefaults()
        defaults.set("U-1234", forKey: "penova.auth.userId")
        defaults.set("Aaron Sorkin", forKey: "penova.auth.fullName")
        defaults.set("aaron@example.com", forKey: "penova.auth.email")
        let session = AuthSession(defaults: defaults)
        #expect(session.userId == "U-1234")
        #expect(session.fullName == "Aaron Sorkin")
        #expect(session.email == "aaron@example.com")

        session.signOut()
        #expect(session.userId.isEmpty)
        #expect(session.fullName.isEmpty)
        #expect(session.email.isEmpty)
        #expect(session.status == .anonymous)
        #expect(defaults.string(forKey: "penova.auth.userId") == nil)
    }

    @Test func defaultContactBlockComposesFromStoredFields() {
        let defaults = makeIsolatedDefaults()
        defaults.set("U-1234", forKey: "penova.auth.userId")
        defaults.set("Penova Test", forKey: "penova.auth.fullName")
        defaults.set("penova@example.com", forKey: "penova.auth.email")
        let session = AuthSession(defaults: defaults)
        #expect(session.defaultContactBlock == "Penova Test\npenova@example.com")
    }

    @Test func defaultContactBlockOmitsEmptyEmail() {
        let defaults = makeIsolatedDefaults()
        defaults.set("U-1234", forKey: "penova.auth.userId")
        defaults.set("Penova Test", forKey: "penova.auth.fullName")
        let session = AuthSession(defaults: defaults)
        #expect(session.defaultContactBlock == "Penova Test")
    }

    @Test func loadStoredCredentialMarksUnknownUntilVerify() {
        // Simulates a relaunch with a previously-stored credential.
        // The session should NOT instantly assume signed-in until
        // verifyCurrentCredential() has talked to Apple — but the
        // userId IS already populated so the UI can render an
        // "(verifying...)" placeholder if it wants to.
        let defaults = makeIsolatedDefaults()
        defaults.set("U-1234", forKey: "penova.auth.userId")
        defaults.set("Aaron", forKey: "penova.auth.fullName")
        let session = AuthSession(defaults: defaults)
        #expect(session.userId == "U-1234")
        #expect(session.fullName == "Aaron")
        #expect(session.status == .unknown)
        // isSignedIn is true unless explicitly revoked, so the rest of
        // the UI can act on stored credentials immediately. The Apple
        // verification on launch is a soft check that *downgrades* if
        // revocation is detected.
        #expect(session.isSignedIn == true)
    }
}
