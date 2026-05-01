//
//  PastePromptPill.swift
//  PenovaKit
//
//  F4 — Inline "screenplay format detected" pill. Shown overlaid above
//  the editor at the cursor position when the smart-paste detector
//  returns `.maybeScreenplay`. Two actions:
//
//    • Convert            — parse the paste through FountainParser /
//                            the lite parser and insert structured
//                            elements.
//    • Keep as plain text  — fall back to inserting the paste as a
//                            single Action element.
//
//  Auto-dismisses after 5 seconds, defaulting to plain (the safer
//  outcome). Uses Penova's design tokens (amber accent, ink card
//  surface) and stays under 32pt tall so it doesn't push the
//  editor down or block the line being typed on.
//

import SwiftUI

public struct PastePromptPill: View {
    /// Called when the user taps "Convert".
    let onConvert: () -> Void
    /// Called when the user taps "Keep as plain text" or the pill
    /// auto-dismisses (default = plain paste).
    let onKeepPlain: () -> Void
    /// How long to wait before auto-dismissing.
    public var autoDismissAfter: Duration = .seconds(5)

    public init(
        onConvert: @escaping () -> Void,
        onKeepPlain: @escaping () -> Void,
        autoDismissAfter: Duration = .seconds(5)
    ) {
        self.onConvert = onConvert
        self.onKeepPlain = onKeepPlain
        self.autoDismissAfter = autoDismissAfter
    }

    public var body: some View {
        HStack(spacing: PenovaSpace.s) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PenovaColor.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Screenplay format detected")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(PenovaColor.snow3)
                Text("Convert the paste into structured elements?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(1)
            }

            Spacer(minLength: PenovaSpace.s)

            Button(action: onConvert) {
                Text("Convert")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PenovaColor.ink0)
                    .padding(.horizontal, PenovaSpace.s)
                    .padding(.vertical, 4)
                    .background(PenovaColor.amber)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Convert paste to screenplay elements")

            Button(action: onKeepPlain) {
                Text("Keep as plain text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(.horizontal, PenovaSpace.s)
                    .padding(.vertical, 4)
                    .background(PenovaColor.ink3)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keep paste as plain text")
        }
        .padding(.horizontal, PenovaSpace.sm)
        .padding(.vertical, PenovaSpace.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: PenovaRadius.sm)
                .fill(PenovaColor.ink2.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PenovaRadius.sm)
                .strokeBorder(PenovaColor.amber.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .frame(maxHeight: 32)
        .task {
            try? await Task.sleep(for: autoDismissAfter)
            // Auto-dismiss → default to plain paste.
            onKeepPlain()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: 16) {
        PastePromptPill(
            onConvert: { print("convert") },
            onKeepPlain: { print("plain") },
            autoDismissAfter: .seconds(60)
        )
    }
    .padding(40)
    .background(PenovaColor.ink0)
    .preferredColorScheme(.dark)
}
