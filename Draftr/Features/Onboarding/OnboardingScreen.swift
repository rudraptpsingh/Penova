//
//  OnboardingScreen.swift
//  Draftr
//
//  S02/S03 — Two pager cards plus a Sign in with Apple stage. "Skip"
//  finishes onboarding as an anonymous user; real Apple sign-in stores
//  a user id + full name + email for Settings to surface later.
//
// STUB: OnboardingScreen — real Sign in with Apple backend exchange (nonce, server
//       verification, account linking) lands with the subscription work. For now
//       credentials are stored in UserDefaults on device only. See STUBS.md.
//

import SwiftUI
import AuthenticationServices

struct OnboardingScreen: View {
    let onFinish: () -> Void

    @AppStorage("draftr.auth.userId") private var appleUserId: String = ""
    @AppStorage("draftr.auth.fullName") private var fullName: String = ""
    @AppStorage("draftr.auth.email") private var email: String = ""

    @State private var page: Int = 0
    @State private var authError: String?

    var body: some View {
        ZStack {
            DraftrColor.ink0.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageCard(
                        icon: .scripts,
                        title: Copy.onboarding.step1Title,
                        body: Copy.onboarding.step1Body
                    ).tag(0)

                    pageCard(
                        icon: .characters,
                        title: Copy.onboarding.step2Title,
                        body: Copy.onboarding.step2Body
                    ).tag(1)

                    signInCard.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                pageIndicator
                    .padding(.vertical, DraftrSpace.m)

                footer
                    .padding(.horizontal, DraftrSpace.l)
                    .padding(.bottom, DraftrSpace.xl)
            }
        }
        .alert("Sign-in failed",
               isPresented: Binding(
                get: { authError != nil },
                set: { if !$0 { authError = nil } }
               )) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            Text(authError ?? "")
        }
    }

    // MARK: - Pages

    private func pageCard(icon: DraftrIcon, title: String, body: String) -> some View {
        VStack(spacing: DraftrSpace.l) {
            Spacer()
            DraftrIconView(icon, size: 72, color: DraftrColor.amber)
            Text(title)
                .font(DraftrFont.hero)
                .foregroundStyle(DraftrColor.snow)
                .multilineTextAlignment(.center)
            Text(body)
                .font(DraftrFont.body)
                .foregroundStyle(DraftrColor.snow3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DraftrSpace.l)
            Spacer()
        }
        .padding(DraftrSpace.l)
    }

    private var signInCard: some View {
        VStack(spacing: DraftrSpace.l) {
            Spacer()
            DraftrIconView(.focus, size: 72, color: DraftrColor.amber)
            Text("Your work, on your terms.")
                .font(DraftrFont.hero)
                .foregroundStyle(DraftrColor.snow)
                .multilineTextAlignment(.center)
            Text("Sign in with Apple to back up your scripts across your devices. Or skip — everything you write stays on this phone.")
                .font(DraftrFont.body)
                .foregroundStyle(DraftrColor.snow3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DraftrSpace.l)

            SignInWithAppleButton(.signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    handleAppleResult(result)
                }
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
            .padding(.horizontal, DraftrSpace.l)

            Spacer()
        }
        .padding(DraftrSpace.l)
    }

    // MARK: - Chrome

    private var pageIndicator: some View {
        HStack(spacing: DraftrSpace.s) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? DraftrColor.amber : DraftrColor.ink4)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DraftrSpace.m) {
            Button(page == 2 ? "Skip" : Copy.common.skip) {
                onFinish()
            }
            .font(DraftrFont.body)
            .foregroundStyle(DraftrColor.snow3)
            Spacer()
            DraftrButton(
                title: page == 2 ? Copy.onboarding.start : Copy.common.next,
                variant: .primary,
                size: .compact
            ) {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
        }
    }

    // MARK: - Apple sign-in

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                appleUserId = credential.user
                if let n = credential.fullName {
                    let formatter = PersonNameComponentsFormatter()
                    let formatted = formatter.string(from: n)
                    if !formatted.isEmpty { fullName = formatted }
                }
                if let e = credential.email, !e.isEmpty { email = e }
            }
            onFinish()
        case .failure(let error):
            // Cancellations should not be loud.
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            authError = error.localizedDescription
        }
    }
}
