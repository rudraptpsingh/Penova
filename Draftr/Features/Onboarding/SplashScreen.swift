//
//  SplashScreen.swift
//  Draftr
//
//  S01 — Brand moment. The "D" glyph and tagline sit centred for the ~1.2 s
//  it takes to decide onboarding vs. root. No progress indicator — this is
//  the first frame the user sees and it should feel settled, not loading.
//

import SwiftUI

struct SplashScreen: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            DraftrColor.ink0.ignoresSafeArea()
            VStack(spacing: DraftrSpace.m) {
                Text("D")
                    .font(DraftrFont.splashMark)
                    .foregroundStyle(DraftrColor.amber)
                Text("Draftr")
                    .font(DraftrFont.splashWord)
                    .foregroundStyle(DraftrColor.snow)
                Text(Copy.splash.tagline)
                    .font(DraftrFont.body)
                    .foregroundStyle(DraftrColor.snow3)
            }
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.96)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appear = true }
            }
        }
    }
}
