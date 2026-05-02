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
    /// Sparkle 2.x auto-update controller. Penova is distributed
    /// direct-from-website (no Mac App Store), so it must ship its
    /// own update path. The service starts checking against
    /// SUFeedURL (Info.plist) on launch and surfaces a
    /// "Check for Updates…" menu item under the Penova app menu.
    @StateObject private var updater = UpdaterService()

    init() {
        // --smoke: run the end-to-end smoke harness and exit. No UI.
        if CommandLine.arguments.contains("--smoke") {
            registerCustomFonts()
            let failures = SmokeTest.run()
            exit(failures == 0 ? 0 : 1)
        }

        // --fix-headings: walk every scene in the most-recent project
        // and assign distinct headings from a hard-coded outline so the
        // sidebar isn't a column of identical "INT. NEW LOCATION - DAY"
        // rows. One-shot maintenance — print result and exit.
        if CommandLine.arguments.contains("--fix-headings") {
            do {
                let schema = Schema(PenovaSchema.models)
                let config = ModelConfiguration("Penova", schema: schema)
                let container = try ModelContainer(for: schema, configurations: [config])
                let ctx = ModelContext(container)
                guard let project = try ctx.fetch(FetchDescriptor<Project>(
                    sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]
                )).first else {
                    print("No project")
                    exit(1)
                }
                let outline: [(loc: SceneLocation, name: String, time: SceneTimeOfDay)] = [
                    (.interior, "SUVARNA JEWELLERY STORE", .dawn),
                    (.interior, "STORE BACKROOM",          .morning),
                    (.interior, "STORE FLOOR",             .morning),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "STORE BACKROOM",          .day),
                    (.exterior, "STORE FRONT",             .day),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "STORE FLOOR",             .continuous),
                    (.interior, "STORE FLOOR",             .later),
                    (.interior, "STORE BACKROOM",          .dusk),
                    (.interior, "PRIYA'S APARTMENT",       .night),
                    (.interior, "PRIYA'S APARTMENT",       .continuous),
                    (.interior, "COLLEGE HOSTEL ROOM",     .night),
                    (.interior, "STORE FLOOR",             .morning),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "STORE BACKROOM",          .day),
                    (.exterior, "STORE FRONT",             .evening),
                    (.interior, "STORE FLOOR",             .day),
                    (.exterior, "STORE STREET",            .evening),
                    (.interior, "IRANI CAFE",              .night),
                    (.interior, "PRIYA'S APARTMENT",       .night),
                    (.interior, "JEWELLERY WORKSHOP",      .day),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "STORE FLOOR",             .day),
                    (.exterior, "MARINE DRIVE",            .evening),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "STORE FLOOR",             .day),
                    (.interior, "PRIYA'S APARTMENT",       .night),
                ]
                let beats: [BeatType?] = [
                    .setup, .setup, .setup, .setup, .setup, .setup,
                    .inciting, .inciting, .inciting, .inciting,
                    .turn, .turn, .turn,
                    .setup,
                    .midpoint, .midpoint, .midpoint,
                    .turn, .turn, .climax,
                    .climax,
                    .resolution, .resolution, .resolution,
                    .resolution, .resolution, .resolution, .resolution,
                ]
                for ep in project.activeEpisodesOrdered {
                    let scenes = ep.scenesOrdered
                    for (i, scene) in scenes.enumerated() where i < outline.count {
                        let row = outline[i]
                        scene.location = row.loc
                        scene.locationName = row.name
                        scene.time = row.time
                        scene.rebuildHeading()
                        scene.beatType = beats[safe: i] ?? nil
                        scene.updatedAt = .now
                    }
                }
                try ctx.save()
                print("Updated \(min(outline.count, project.totalSceneCount)) scene headings + beats")
                exit(0)
            } catch {
                print("Fix-headings failed: \(error)")
                exit(1)
            }
        }

        // --render-pdf[=name]: open the production store, render the
        // most-recent project to PDF inside the app's sandboxed Documents
        // directory, print the resolved path + page count, exit.
        // Sandboxed app can't write to arbitrary /tmp paths so we
        // anchor under Documents which the user can browse via Finder.
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--render-pdf") }) {
            registerCustomFonts()
            let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render-pdf") }) ?? ""
            let nameSuffix: String
            if let eq = arg.firstIndex(of: "=") {
                nameSuffix = String(arg[arg.index(after: eq)...])
            } else {
                nameSuffix = "rendered.pdf"
            }
            do {
                let schema = Schema(PenovaSchema.models)
                let config = ModelConfiguration("Penova", schema: schema)
                let container = try ModelContainer(for: schema, configurations: [config])
                let ctx = ModelContext(container)
                guard let project = try ctx.fetch(FetchDescriptor<Project>(
                    sortBy: [SortDescriptor(\Project.updatedAt, order: .reverse)]
                )).first else {
                    print("No project in store")
                    exit(1)
                }
                let docs = try FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                )
                let url = docs.appendingPathComponent(nameSuffix)
                try ScreenplayPDFRenderer.render(project: project, to: url)
                let pages = ScreenplayPDFRenderer.measurePageCount(project: project)
                print("Rendered '\(project.title)' to \(url.path)")
                print("Script pages: \(pages)")
                exit(0)
            } catch {
                print("Render failed: \(error)")
                exit(1)
            }
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
            // Note: SwiftData's `ModelContext.undoManager` does not
            // reliably reverse persisted deletes after save(); see
            // PenovaTests/UndoSupportTests for the contract. Top-level
            // confirm-delete alerts are the user-facing safety net
            // until soft-delete tombstones land.
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
        // Default size on first launch needs room for the 640pt paper
        // PLUS the 260pt library sidebar PLUS the 300pt scene inspector
        // PLUS some breathing room. 1280×820 lands the paper centred in
        // the editor pane without horizontal scrolling — the user's
        // first impression is "this looks like a script", not a clipped
        // page. minWidth above still allows the user to drag the window
        // narrower; the paper is now adaptive (idealWidth: 640, maxWidth:
        // 640) so it gracefully shrinks rather than overflowing.
        .defaultSize(width: 1280, height: 820)
        .commands {
            // Sparkle "Check for Updates…" — sits under the app menu
            // (Penova → Check for Updates…) per macOS convention. The
            // CommandGroup(after: .appInfo) places it directly below
            // "About Penova", which is where every Sparkle-using app
            // (Highland, Fade In, OmniFocus, Things) puts it.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
                Divider()
                Button("Send Feedback…") {
                    PenovaMacFeedback.sendFeedback()
                }
            }

            // Help menu — Apple's convention puts feedback under Help
            // for users who didn't think to look in the app menu. We
            // provide both paths (Bear/Tot pattern).
            CommandGroup(replacing: .help) {
                Button("Penova Help") {
                    if let url = URL(string: "https://penova.pages.dev/support") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: [.command])

                Divider()

                Button("Send Feedback to Penova…") {
                    PenovaMacFeedback.sendFeedback()
                }
            }

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

            // Edit menu additions: line-level operations that don't
            // belong on the global Edit menu's stock entries (Cut/
            // Copy/Paste already work on text). These manipulate the
            // structural element rather than the text inside it.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Delete Line") {
                    NotificationCenter.default.post(
                        name: .penovaDeleteFocusedElement, object: nil
                    )
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Button("Insert Line Above") {
                    NotificationCenter.default.post(
                        name: .penovaInsertLineAbove, object: nil
                    )
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Insert Line Below") {
                    NotificationCenter.default.post(
                        name: .penovaInsertLineBelow, object: nil
                    )
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            // Project-level production menu: Reports + Lock toggle. Lives
            // under its own top-level menu so it shows up in the menu
            // bar between View and Window — the canonical macOS path
            // for users who haven't memorised every keyboard shortcut.
            CommandMenu("Production") {
                Button("Reports…") {
                    NotificationCenter.default.post(name: .penovaShowReports, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Lock Script for Production…") {
                    NotificationCenter.default.post(name: .penovaLockScript, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Unlock Script…") {
                    NotificationCenter.default.post(name: .penovaUnlockScript, object: nil)
                }

                Divider()

                Button("Start New Revision…") {
                    NotificationCenter.default.post(name: .penovaStartNewRevision, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }
    }
}

extension Notification.Name {
    static let penovaNewProject   = Notification.Name("penova.newProject")
    static let penovaNewScene     = Notification.Name("penova.newScene")
    static let penovaShowReports          = Notification.Name("penova.showReports")
    static let penovaLockScript           = Notification.Name("penova.lockScript")
    static let penovaUnlockScript         = Notification.Name("penova.unlockScript")
    static let penovaStartNewRevision     = Notification.Name("penova.startNewRevision")
    static let penovaDeleteFocusedElement = Notification.Name("penova.deleteFocusedElement")
    static let penovaInsertLineAbove      = Notification.Name("penova.insertLineAbove")
    static let penovaInsertLineBelow      = Notification.Name("penova.insertLineBelow")
    /// Set the focused element's kind to the given SceneElementKind raw value.
    /// userInfo: ["kind": SceneElementKind.rawValue]
    static let penovaSetElementKind = Notification.Name("penova.setElementKind")
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

// Helper used by --fix-headings outline mapping.
extension Array {
    subscript(safe idx: Int) -> Element? { indices.contains(idx) ? self[idx] : nil }
}
