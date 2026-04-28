//
//  AuthSession.swift
//  Penova
//
//  Owns the user's Sign in with Apple identity and exposes it as an
//  ObservableObject the rest of the app can read or mutate. Backed by
//  UserDefaults so credentials survive launches without a server.
//
//  What "real" sign-in means in an offline-first app:
//   - Apple authorization completes on-device. We persist the stable
//     user id, the formatted full name (first sign-in only — Apple
//     doesn't return it again), and the email (could be a relay).
//   - On every cold launch, we ask Apple
//     `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`
//     to detect whether the user revoked Penova in iOS Settings →
//     Apple ID. If revoked, we drop the local credential so the next
//     launch shows them as anonymous and offers re-sign-in.
//   - Sign-out is a local clear; we don't try to revoke Apple-side
//     because that's the user's job from system settings.
//

import Foundation
import AuthenticationServices

@MainActor
public final class AuthSession: ObservableObject {

    public enum Status: Equatable {
        case unknown
        case anonymous
        case signedIn
        case revoked
    }

    @Published public private(set) var userId: String
    @Published public private(set) var fullName: String
    @Published public private(set) var email: String
    @Published public private(set) var status: Status = .unknown

    private let defaults: UserDefaults
    private let provider: ASAuthorizationAppleIDProvider

    private static let userIdKey   = "penova.auth.userId"
    private static let fullNameKey = "penova.auth.fullName"
    private static let emailKey    = "penova.auth.email"

    public init(
        defaults: UserDefaults = .standard,
        provider: ASAuthorizationAppleIDProvider = .init()
    ) {
        self.defaults = defaults
        self.provider = provider
        self.userId   = defaults.string(forKey: Self.userIdKey)   ?? ""
        self.fullName = defaults.string(forKey: Self.fullNameKey) ?? ""
        self.email    = defaults.string(forKey: Self.emailKey)    ?? ""
        self.status   = userId.isEmpty ? .anonymous : .unknown
    }

    public var isSignedIn: Bool { !userId.isEmpty && status != .revoked }

    /// Friendly-cased display name for the signed-in user, or a fallback
    /// when they skipped sign-in or never gave us a name.
    public var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Friend" : trimmed
    }

    // MARK: - Sign in

    /// Persist a credential bundle returned by `SignInWithAppleButton`.
    /// The fullName is captured ONCE — Apple never returns it again on
    /// subsequent sign-ins to the same app. Email may be a private
    /// relay address; treat both as opaque labels we surface in UI.
    public func saveCredential(_ credential: ASAuthorizationAppleIDCredential) {
        userId = credential.user
        defaults.set(credential.user, forKey: Self.userIdKey)

        if let n = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formatted = formatter.string(from: n)
                .trimmingCharacters(in: .whitespaces)
            if !formatted.isEmpty {
                fullName = formatted
                defaults.set(formatted, forKey: Self.fullNameKey)
            }
        }
        if let e = credential.email,
           !e.trimmingCharacters(in: .whitespaces).isEmpty {
            email = e
            defaults.set(e, forKey: Self.emailKey)
        }
        status = .signedIn
    }

    // MARK: - Verify on launch

    /// Ask Apple whether our stored credential is still valid. Apple
    /// answers asynchronously without a network round-trip in most
    /// cases (the answer comes from the device's keychain). Call from
    /// `.task` on the root view.
    public func verifyCurrentCredential() async {
        guard !userId.isEmpty else {
            status = .anonymous
            return
        }
        let probedId = userId
        let result: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { cont in
            provider.getCredentialState(forUserID: probedId) { state, _ in
                cont.resume(returning: state)
            }
        }
        switch result {
        case .authorized:
            status = .signedIn
        case .revoked, .notFound:
            // The user pulled access from Settings → Apple ID, or the
            // device is fresh and our id no longer maps. Drop the
            // stale credential so the UI offers re-sign-in.
            clearLocal()
            status = .revoked
        case .transferred:
            status = .signedIn   // family-sharing transfer; treat as still valid
        @unknown default:
            status = .unknown
        }
    }

    // MARK: - Sign out

    public func signOut() {
        clearLocal()
        status = .anonymous
    }

    private func clearLocal() {
        userId = ""
        fullName = ""
        email = ""
        defaults.removeObject(forKey: Self.userIdKey)
        defaults.removeObject(forKey: Self.fullNameKey)
        defaults.removeObject(forKey: Self.emailKey)
    }

    // MARK: - Convenience for new-project autofill

    /// A pre-filled contact block in the same shape `Project.contactBlock`
    /// uses, derived from the signed-in user. Empty for anonymous users.
    public var defaultContactBlock: String {
        var lines: [String] = []
        if !fullName.isEmpty { lines.append(fullName) }
        if !email.isEmpty    { lines.append(email) }
        return lines.joined(separator: "\n")
    }
}
