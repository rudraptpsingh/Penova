//
//  DraftrApp.swift
//  Draftr
//
//  App entry. Forces dark mode (MVP is dark-only) and installs the
//  root `RootView` that hosts the tab bar + navigation stacks.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct DraftrApp: App {
    let container: ModelContainer

    init() {
        // One-time sanity check: warn (in debug) if our custom fonts weren't
        // registered. Nothing crashes — SwiftUI silently falls back to system
        // when a font is missing, so without this we'd ship "Draftr" rendered
        // in SF Pro without ever noticing.
        #if DEBUG
        verifyCustomFonts()
        #endif

        do {
            let schema = Schema(DraftrSchema.models)
            let config = ModelConfiguration("Draftr", schema: schema)
            container = try ModelContainer(for: schema, configurations: [config])
            SeedData.installIfNeeded(in: container.mainContext)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppFlowView()
                .preferredColorScheme(.dark)
                .tint(DraftrColor.amber)
        }
        .modelContainer(container)
    }
}

#if DEBUG
private func verifyCustomFonts() {
    let required: [String] = [
        DraftrFont.interRegular, DraftrFont.interMedium,
        DraftrFont.interSemiBold, DraftrFont.interBold,
        DraftrFont.robotoMono, DraftrFont.robotoMonoMed,
        DraftrFont.playfair
    ]
    for name in required where UIFont(name: name, size: 12) == nil {
        print("⚠️  Draftr: missing custom font '\(name)'. Check Info.plist UIAppFonts.")
    }
}
#endif
