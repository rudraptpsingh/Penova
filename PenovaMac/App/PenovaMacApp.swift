//
//  PenovaMacApp.swift
//  Penova for Mac
//
//  Mac entry point. Forces dark mode (the only supported scheme), wires
//  the SwiftData container that PenovaKit's @Model classes live in, and
//  hosts the LibraryWindow scene which presents the three-pane shell.
//

import SwiftUI
import SwiftData
import AppKit
import PenovaKit

@main
struct PenovaMacApp: App {
    let container: ModelContainer

    init() {
        // --smoke: run the end-to-end smoke harness and exit. No UI.
        if CommandLine.arguments.contains("--smoke") {
            registerCustomFonts()
            let failures = SmokeTest.run()
            exit(failures == 0 ? 0 : 1)
        }

        // Register bundled custom fonts (Inter, Roboto Mono, Playfair Display)
        // so SwiftUI's `Font.custom(...)` resolves on macOS the same way it
        // does on iOS via Info.plist UIAppFonts.
        registerCustomFonts()

        let env = ProcessInfo.processInfo.environment
        let inMemory = env["PENOVA_TEST_RESET_STORE"] == "1"

        do {
            let schema = Schema(PenovaSchema.models)
            // Local-only for the v1 dev scaffold. CloudKit wires up later.
            let config: ModelConfiguration
            if inMemory {
                PenovaLog.app.info("PENOVA_TEST_RESET_STORE: using in-memory store")
                config = ModelConfiguration("Penova-test", schema: schema, isStoredInMemoryOnly: true)
            } else {
                config = ModelConfiguration("Penova", schema: schema)
            }
            container = try ModelContainer(for: schema, configurations: [config])
            SampleLibrary.installIfNeeded(in: container.mainContext)
            let projectCount = (try? container.mainContext.fetchCount(FetchDescriptor<Project>())) ?? 0
            PenovaLog.app.info("App started, library has \(projectCount, privacy: .public) projects")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Penova") {
            LibraryWindowView()
                .frame(minWidth: 1024, minHeight: 640)
                .preferredColorScheme(.dark)
                .tint(PenovaColor.amber)
        }
        .modelContainer(container)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Replace the default New… command with one that produces a Project,
            // then forward via NotificationCenter — the in-window state listens.
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    NotificationCenter.default.post(name: .penovaNewProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Scene") {
                    NotificationCenter.default.post(name: .penovaNewScene, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let penovaNewProject = Notification.Name("penova.newProject")
    static let penovaNewScene   = Notification.Name("penova.newScene")
}

// MARK: - Font registration

private func registerCustomFonts() {
    let names = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
        "RobotoMono-Regular", "RobotoMono-Medium",
        "PlayfairDisplay",
    ]
    for name in names {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
            #if DEBUG
            print("⚠️  Penova: missing bundled font \(name).ttf")
            #endif
            continue
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            #if DEBUG
            if let err = error?.takeRetainedValue() {
                print("⚠️  Penova: failed to register \(name): \(err)")
            }
            #endif
        }
    }
}
