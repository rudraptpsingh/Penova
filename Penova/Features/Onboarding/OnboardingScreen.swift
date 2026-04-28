//
//  OnboardingScreen.swift
//  Penova
//
//  Two onboarding pager cards plus a Sign in with Apple stage. "Skip"
//  finishes onboarding as an anonymous user; real Apple sign-in stores
//  the user id + full name + email locally so Settings can surface the
//  user's name without a network round-trip.
//
//  Architecture note: Penova is offline-first by design. There is no
//  Penova server, so there's nothing to exchange the Apple nonce
//  *with*. Apple's authorization completes on-device — the credential
//  bundle that lands in UserDefaults is the production artefact, not a
//  placeholder. If a future cloud-sync milestone introduces a backend,
//  add nonce verification then; the current behaviour is intentional
//  for an offline-only app.
//

import SwiftUI
import AuthenticationServices

struct OnboardingScreen: View {
    let onFinish: () -> Void

    @AppStorage("penova.auth.userId") private var appleUserId: String = ""
    @AppStorage("penova.auth.fullName") private var fullName: String = ""
    @AppStorage("penova.auth.email") private var email: String = ""

    @State private var page: Int = 0
    @State private var authError: String?

    var body: some View {
        ZStack {
            PenovaColor.ink0.ignoresSafeArea()
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
                    .padding(.vertical, PenovaSpace.m)

                footer
                    .padding(.horizontal, PenovaSpace.l)
                    .padding(.bottom, PenovaSpace.xl)
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

    private func pageCard(icon: PenovaIcon, title: String, body: String) -> some View {
        VStack(spacing: PenovaSpace.l) {
            Spacer()
            PenovaIconView(icon, size: 72, color: PenovaColor.amber)
            Text(title)
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
                .multilineTextAlignment(.center)
            Text(body)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PenovaSpace.l)
            Spacer()
        }
        .padding(PenovaSpace.l)
    }

    private var signInCard: some View {
        VStack(spacing: PenovaSpace.l) {
            Spacer()
            PenovaIconView(.focus, size: 72, color: PenovaColor.amber)
            Text("Your work, on your terms.")
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
                .multilineTextAlignment(.center)
            Text("Sign in to personalize the title page on your exports with your name and email. Or skip — everything you write stays on this phone either way.")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PenovaSpace.l)

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
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
            .padding(.horizontal, PenovaSpace.l)

            Spacer()
        }
        .padding(PenovaSpace.l)
    }

    // MARK: - Chrome

    private var pageIndicator: some View {
        HStack(spacing: PenovaSpace.s) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i == page ? PenovaColor.amber : PenovaColor.ink4)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: PenovaSpace.m) {
            Button(page == 2 ? "Skip" : Copy.common.skip) {
                onFinish()
            }
            .font(PenovaFont.body)
            .foregroundStyle(PenovaColor.snow3)
            Spacer()
            PenovaButton(
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
