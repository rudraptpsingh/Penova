//
//  PenovaApp.swift
//  Penova
//
//  App entry. Forces dark mode (MVP is dark-only) and installs the
//  root `RootView` that hosts the tab bar + navigation stacks.
//

import SwiftUI
import SwiftData
import UIKit
import PenovaKit

@main
struct PenovaApp: App {
    let container: ModelContainer
    @StateObject private var auth = AuthSession()

    init() {
        // One-time sanity check: warn (in debug) if our custom fonts weren't
        // registered. Nothing crashes — SwiftUI silently falls back to system
        // when a font is missing, so without this we'd ship "Penova" rendered
        // in SF Pro without ever noticing.
        #if DEBUG
        verifyCustomFonts()
        #endif

        do {
            let schema = Schema(PenovaSchema.models)
            let config = ModelConfiguration("Penova", schema: schema)
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
                .tint(PenovaColor.amber)
                .environmentObject(auth)
                .task {
                    // Cold-launch credential check: if the user revoked
                    // Penova in iOS Settings → Apple ID, we drop the
                    // stale local credential so they're surfaced as
                    // anonymous on the next sign-in prompt.
                    await auth.verifyCurrentCredential()
                }
        }
        .modelContainer(container)
    }
}

#if DEBUG
private func verifyCustomFonts() {
    let required: [String] = [
        PenovaFont.interRegular, PenovaFont.interMedium,
        PenovaFont.interSemiBold, PenovaFont.interBold,
        PenovaFont.robotoMono, PenovaFont.robotoMonoMed,
        PenovaFont.playfair
    ]
    for name in required where UIFont(name: name, size: 12) == nil {
        print("⚠️  Penova: missing custom font '\(name)'. Check Info.plist UIAppFonts.")
    }
}
#endif
