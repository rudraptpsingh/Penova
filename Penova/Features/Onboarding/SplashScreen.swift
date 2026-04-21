//
//  SplashScreen.swift
//  Penova
//
//  S01 — Brand moment. The "P" glyph and tagline sit centred for the ~1.2 s
//  it takes to decide onboarding vs. root. No progress indicator — this is
//  the first frame the user sees and it should feel settled, not loading.
//

import SwiftUI

struct SplashScreen: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            PenovaColor.ink0.ignoresSafeArea()
            VStack(spacing: PenovaSpace.m) {
                Text("P")
                    .font(PenovaFont.splashMark)
                    .foregroundStyle(PenovaColor.amber)
                Text("Penova")
                    .font(PenovaFont.splashWord)
                    .foregroundStyle(PenovaColor.snow)
                Text(Copy.splash.tagline)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
            }
            .opacity(appear ? 1 : 0)
            .scaleEffect(appear ? 1 : 0.96)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appear = true }
            }
        }
    }
}
