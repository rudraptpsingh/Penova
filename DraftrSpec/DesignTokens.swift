//
//  DesignTokens.swift
//  Draftr
//
//  Single source of truth for the Draftr design system.
//  Extracted from Figma file: Draftr — iOS App Design (page "01 · Tokens").
//  All values mirror the Figma Variables 1:1.
//
//  Design principles (non-negotiable):
//   1. Write the page. Hide the app. Editor is sacred — no chrome.
//   2. One accent: amber = primary action. Never decorative.
//   3. jade = confirmed, ember = destructive, slate = info / neutral-accent. One meaning each.
//   4. Flat. Only the bottom sheet has elevation.
//   5. Three radii only: 8 (chip), 12 (card), 9999 (CTA / avatar).
//   6. Spacing ladder: 4 / 8 / 12 / 16 / 24 / 40 / 64. Nothing in between.
//   7. Motion: 120 / 200 / 320 ms, one easing (0.2, 0.8, 0.2, 1).
//   8. Two fonts: Inter (UI), Roboto Mono (script content).
//   9. Dark mode is the only mode (MVP).
//

import SwiftUI

// MARK: - Colors

public enum DraftrColor {
    // Surfaces — dark canvas
    public static let ink0    = Color(hex: 0x0B0A08) // Canvas
    public static let ink2    = Color(hex: 0x15130F) // Card
    public static let ink3    = Color(hex: 0x1F1C17) // Elevated
    public static let ink4    = Color(hex: 0x2A2620) // Divider
    public static let ink5    = Color(hex: 0x3A352D) // Hover line

    // Neutrals — light content
    public static let snow    = Color(hex: 0xF5F0E6) // Primary text
    public static let snow2   = Color(hex: 0xE8E2D4) // Secondary
    public static let snow3   = Color(hex: 0xBDB6A6) // Muted
    public static let snow4   = Color(hex: 0x8B8476) // Tertiary

    // Accents — semantic
    public static let amber        = Color(hex: 0xE89B3C) // Primary action
    public static let amberPressed = Color(hex: 0xC27F28)
    public static let amberHover   = Color(hex: 0xF2B968)
    public static let jade         = Color(hex: 0x7FA388) // Confirmed
    public static let ember        = Color(hex: 0xC65D5D) // Destructive
    public static let slate        = Color(hex: 0x7C8A94) // Info / neutral-accent

    // Editor surface
    public static let paper     = Color(hex: 0xF5F0E6) // Script page
    public static let paperLine = Color(hex: 0xD4CBBB) // Ruling
}

// MARK: - Typography
//
// Fonts are Inter (UI) and Roboto Mono (script content).
// For SwiftUI-native scaling, you can also map these to `.dynamicTypeSize`
// variants using SF Pro. MVP uses fixed sizes with manual Dynamic Type opt-in.

public enum DraftrFont {
    // Family names used by the bundled `.ttf` files (add to Info.plist UIAppFonts).
    public static let inter          = "Inter"
    public static let interBold      = "Inter-Bold"
    public static let interSemiBold  = "Inter-SemiBold"
    public static let interMedium    = "Inter-Medium"
    public static let interRegular   = "Inter-Regular"
    public static let robotoMono     = "RobotoMono-Regular"
    public static let robotoMonoMed  = "RobotoMono-Medium"
    // Brand serif — used for the "D" mark and wordmark so splash + app icon
    // share the same glyph shape. Variable font, weight axis 400–900.
    public static let playfair       = "PlayfairDisplay-Regular"

    // Brand display — Playfair Display for Draftr wordmark / icon mark.
    public static let splashMark = Font.custom(playfair, size: 88).weight(.heavy)
    public static let splashWord = Font.custom(playfair, size: 36).weight(.bold)

    // Type ramp — one-to-one with Figma type styles.
    public static let hero       = Font.custom(interBold,     size: 28) // "Your stories await writing."
    public static let title      = Font.custom(interBold,     size: 22) // "Ek Raat Mumbai Mein"
    public static let bodyLarge  = Font.custom(interSemiBold, size: 17) // "Ep 1 — Arrival"
    public static let bodyMedium = Font.custom(interMedium,   size: 15) // "Edited today at 4:02 PM"
    public static let body       = Font.custom(interRegular,  size: 15) // Long descriptions
    public static let bodySmall  = Font.custom(interRegular,  size: 13) // Tertiary
    public static let labelCaps  = Font.custom(interSemiBold, size: 11) // "ACTIVE PROJECTS" — tracked 12%
    public static let labelTiny  = Font.custom(interMedium,   size: 10) // "PROTAGONIST"
    public static let monoScript = Font.custom(robotoMonoMed, size: 13) // "INT. MUMBAI LOCAL TRAIN — NIGHT"
}

// Letter spacing (tracking) for capital labels. SwiftUI expresses this via
// `.tracking(_:)`. Tracked 12% on 11pt ≈ 1.32 points.
public enum DraftrTracking {
    public static let labelCaps: CGFloat = 1.32  // 12% of 11pt
    public static let labelTiny: CGFloat = 1.0   // 10% of 10pt
}

// MARK: - Spacing

public enum DraftrSpace {
    public static let xs: CGFloat  = 4
    public static let s: CGFloat   = 8
    public static let sm: CGFloat  = 12
    public static let m: CGFloat   = 16
    public static let l: CGFloat   = 24
    public static let xl: CGFloat  = 40
    public static let xxl: CGFloat = 64
}

// MARK: - Radii

public enum DraftrRadius {
    public static let sm: CGFloat   = 8     // chip · tag
    public static let md: CGFloat   = 12    // card · sheet
    public static let full: CGFloat = 9999  // CTA · avatar
}

// MARK: - Motion

public enum DraftrMotion {
    public static let fast: Double = 0.120  // micro · press, tap
    public static let base: Double = 0.200  // standard transitions
    public static let slow: Double = 0.320  // sheet / modal

    // Single easing curve across the app: cubic-bezier(0.2, 0.8, 0.2, 1)
    public static let easing = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: base)
    public static let easingFast = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: fast)
    public static let easingSlow = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: slow)
}

// MARK: - Helpers

extension Color {
    /// Hex initializer — usage: `Color(hex: 0xE89B3C)`.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
