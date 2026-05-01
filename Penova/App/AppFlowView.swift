//
//  AppFlowView.swift
//  Penova
//
//  The gate between a cold launch and the tab bar. Orchestrates three
//  stages:
//
//    .splash       — 1.2 s brand moment on first paint
//    .onboarding   — two-card pager + Sign in with Apple (skippable)
//    .main         — RootView (tab bar)
//
//  "Did onboarding complete" is a @AppStorage flag so repeat launches
//  skip straight to .main. Sign-in state is a separate flag; skipping
//  still finishes onboarding but marks the account as anonymous.
//

import SwiftUI
import PenovaKit

struct AppFlowView: View {
    enum Stage { case splash, onboarding, main }

    @AppStorage("penova.flow.didFinishOnboarding") private var didFinishOnboarding: Bool = false
    @State private var stage: Stage = .splash

    var body: some View {
        ZStack {
            switch stage {
            case .splash:
                SplashScreen()
                    .transition(.opacity)
            case .onboarding:
                OnboardingScreen(onFinish: {
                    didFinishOnboarding = true
                    withAnimation(.easeInOut(duration: 0.35)) { stage = .main }
                })
                .transition(.opacity)
            case .main:
                RootView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            if ScreenshotMode.isActive {
                didFinishOnboarding = true
                stage = .main
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    stage = didFinishOnboarding ? .main : .onboarding
                }
            }
        }
    }
}
