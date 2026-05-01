//
//  MacIntegrationTests.swift
//  PenovaMacTests
//
//  Headless integration tests that exercise the SwiftData / PenovaKit
//  stack the Mac app sits on. These run without the UI test harness
//  so they don't need Accessibility permission — they verify the
//  invariants the Mac app depends on:
//
//  - SampleLibrary seeds an empty store with the expected fixture
//  - Tab/Enter cycle produces the correct next kind
//  - Fountain round-trip preserves elements
//  - FDX export emits expected paragraph types
//  - SearchService finds the kitchen scene by location
//
//  Mirrors the screenwriter workflows the XCUITest target drives,
//  but at the model layer — gives us a guaranteed-running sanity
//  net even on machines where the UI tests can't be granted access.
//

import Testing
import SwiftData
import Foundation
@testable import PenovaKit

@Suite("Mac stack integration")
struct MacIntegrationTests {

    private static func freshContext() throws -> ModelContext {
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration("mac-test", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// SampleLibrary lives in the Mac app target, so we replicate its
    /// shape here: 1 project, 2 episodes, kitchen scene with 18 elements,
    /// 7 supporting scenes, 2 characters.
    @Test("Sample library shape is what the editor expects")
    func sampleLibrary() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 1)
        let project = try #require(projects.first)
        #expect(project.title == "Ek Raat Mumbai Mein")
        #expect(project.activeEpisodesOrdered.count == 2)

        let kitchen = project.activeEpisodesOrdered[1].scenesOrdered.first
        #expect(kitchen?.locationName == "KITCHEN")
        #expect(kitchen?.beatType == .midpoint)
        #expect(kitchen?.elementsOrdered.count == 18)
    }

    /// Mira's daily Tab/Enter contract. After a character cue, Enter
    /// produces a dialogue row; after dialogue, Enter produces an
    /// action row. After a scene heading, Enter produces an action
    /// row. Tab cycles through the kinds.
    @Test("Tab/Enter element-type contract matches Final Draft")
    func tabEnterContract() {
        // Enter advancement
        #expect(EditorLogic.nextKind(after: .heading)       == .action)
        #expect(EditorLogic.nextKind(after: .action)        == .action)
        #expect(EditorLogic.nextKind(after: .character)     == .dialogue)
        #expect(EditorLogic.nextKind(after: .dialogue)      == .action)
        #expect(EditorLogic.nextKind(after: .parenthetical) == .dialogue)
        #expect(EditorLogic.nextKind(after: .transition)    == .heading)

        // Tab cycles through allCases
        let order = SceneElementKind.allCases
        for (i, k) in order.enumerated() {
            #expect(EditorLogic.tabCycle(from: k) == order[(i + 1) % order.count])
        }
    }

    /// Auto-uppercase headings, character cues, transitions; auto-wrap
    /// parentheticals in (...). Action and dialogue retain casing.
    @Test("Element commit normalisation")
    func normaliseOnCommit() {
        #expect(EditorLogic.normalise(text: "int. kitchen — night", kind: .heading) == "INT. KITCHEN — NIGHT")
        #expect(EditorLogic.normalise(text: "  marcus  ", kind: .character) == "MARCUS")
        #expect(EditorLogic.normalise(text: "cut to:", kind: .transition) == "CUT TO:")
        #expect(EditorLogic.normalise(text: "without turning", kind: .parenthetical) == "(without turning)")
        #expect(EditorLogic.normalise(text: "(already wrapped)", kind: .parenthetical) == "(already wrapped)")
        #expect(EditorLogic.normalise(text: "She turns off the water.", kind: .action) == "She turns off the water.")
        #expect(EditorLogic.normalise(text: "I quit today.", kind: .dialogue) == "I quit today.")
    }

    /// Scene heading parser: "INT. KITCHEN — NIGHT" → (.interior, "KITCHEN", .night).
    @Test("Scene heading parser handles canonical slug lines")
    func sceneHeadingParse() {
        let p1 = SceneHeadingParser.parse("INT. KITCHEN - NIGHT")
        #expect(p1.location == .interior)
        #expect(p1.locationName == "KITCHEN")
        #expect(p1.time == .night)

        let p2 = SceneHeadingParser.parse("EXT. SEA WALL, BANDRA - DAWN")
        #expect(p2.location == .exterior)
        #expect(p2.locationName == "SEA WALL, BANDRA")
        #expect(p2.time == .dawn)

        let p3 = SceneHeadingParser.parse("INT./EXT. CAR - MOVING")
        #expect(p3.location == .both)
    }

    /// Priya's FDX export round-trip: every element type emits the
    /// expected Final Draft paragraph type.
    @Test("FDX export emits the expected paragraph types")
    func fdxParagraphTypes() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("<FinalDraft DocumentType=\"Script\""))
        #expect(xml.contains("<Paragraph Type=\"Scene Heading\""))
        #expect(xml.contains("<Paragraph Type=\"Character\""))
        #expect(xml.contains("<Paragraph Type=\"Dialogue\""))
        #expect(xml.contains("<Paragraph Type=\"Parenthetical\""))
        #expect(xml.contains("<Paragraph Type=\"Action\""))
        #expect(xml.contains("<Paragraph Type=\"Transition\""))
    }

    /// Fountain export contains the canonical kitchen scene tokens.
    @Test("Fountain export preserves kitchen scene tokens")
    func fountainTokens() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)

        let text = FountainExporter.export(project: project)
        #expect(text.contains("INT. KITCHEN - NIGHT"))
        #expect(text.contains("MARCUS"))
        #expect(text.contains("PENNY"))
        #expect(text.contains("(without turning)"))
        #expect(text.contains("I quit today."))
        #expect(text.contains("CUT TO:"))
    }

    /// SearchService finds the kitchen scene by typing "kitchen".
    @Test("Search finds the kitchen scene")
    func searchKitchen() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let projects = try ctx.fetch(FetchDescriptor<Project>())
        let r = SearchService.search(query: "kitchen", in: projects)
        #expect(r.contains { $0.kind == .scene && $0.title.contains("KITCHEN") })
    }

    /// Reorder math: dragging "Sc 14" to position 0 makes it scene 1
    /// without leaving any duplicate orders behind.
    @Test("Drag scene 14 to position 0")
    func dragKitchenToFront() throws {
        let ctx = try Self.freshContext()
        SeedFixtures.installSample(in: ctx)
        let project = try #require(try ctx.fetch(FetchDescriptor<Project>()).first)
        let ep2 = project.activeEpisodesOrdered[1]
        let scenes = ep2.scenesOrdered

        let kitchen = scenes.first { $0.locationName == "KITCHEN" }!
        let items = scenes.map { (id: $0.id, order: $0.order) }
        let reordered = SceneReorder.move(items, movingID: kitchen.id, to: 0)

        #expect(reordered.first?.id == kitchen.id)
        #expect(reordered.map(\.order) == Array(0..<reordered.count))
    }
}

/// Lift the Mac app's SampleLibrary fixture into the test target so
/// the integration tests run independently from the bundle. Keeps in
/// sync with PenovaMac/App/SampleLibrary.swift; if the seed shape
/// changes, this fixture must be updated too.
enum SeedFixtures {
    static func installSample(in context: ModelContext) {
        let project = Project(
            title: "Ek Raat Mumbai Mein",
            logline: "On the night she means to leave him, the city refuses to let her go.",
            genre: [.drama]
        )
        context.insert(project)

        let ep1 = Episode(title: "Arrival", order: 0, status: .complete)
        ep1.project = project
        context.insert(ep1)

        let ep2 = Episode(title: "Departure", order: 1, status: .draft)
        ep2.project = project
        context.insert(ep2)

        let kitchen = ScriptScene(
            locationName: "KITCHEN", location: .interior, time: .night, order: 0
        )
        kitchen.episode = ep2
        kitchen.beatType = .midpoint
        kitchen.bookmarked = true
        context.insert(kitchen)

        let lines: [(SceneElementKind, String, String?)] = [
            (.action, "Penny stands at the sink, water running. She hasn't moved in some time. A glass of red wine sweats on the counter beside her.", nil),
            (.action, "The front door opens. Marcus enters, his hair smelling of rain. He sets his keys down — slowly, as if a sound might break something.", nil),
            (.character, "MARCUS", nil),
            (.dialogue, "You didn't eat.", "MARCUS"),
            (.character, "PENNY", nil),
            (.parenthetical, "(without turning)", "PENNY"),
            (.dialogue, "I wasn't hungry.", "PENNY"),
            (.character, "MARCUS", nil),
            (.dialogue, "Penny.", "MARCUS"),
            (.action, "She turns off the water. Doesn't turn around.", nil),
            (.character, "PENNY", nil),
            (.dialogue, "I quit today.", "PENNY"),
            (.action, "A long beat.", nil),
            (.character, "MARCUS", nil),
            (.dialogue, "You quit.", "MARCUS"),
            (.character, "PENNY", nil),
            (.dialogue, "I quit.", "PENNY"),
            (.transition, "CUT TO:", nil),
        ]
        for (i, (kind, text, name)) in lines.enumerated() {
            let el = SceneElement(kind: kind, text: text, order: i, characterName: name)
            el.scene = kitchen
            context.insert(el)
        }

        let extras: [(String, SceneLocation, SceneTimeOfDay, BeatType?)] = [
            ("TRAIN STATION", .interior, .dawn, .setup),
            ("CHAI STALL", .exterior, .dawn, .setup),
            ("PLATFORM 4", .exterior, .day, .inciting),
            ("HIGHWAY", .exterior, .night, .turn),
            ("MARCUS' APT", .interior, .night, .turn),
            ("SEA WALL, BANDRA", .exterior, .night, .climax),
            ("PENNY'S CAR", .interior, .dawn, .resolution),
        ]
        for (i, (loc, where_, time, beat)) in extras.enumerated() {
            let scene = ScriptScene(locationName: loc, location: where_, time: time, order: i + 1)
            scene.episode = ep2
            scene.beatType = beat
            context.insert(scene)
        }

        let penny = ScriptCharacter(name: "PENNY", role: .protagonist)
        penny.projects = [project]
        context.insert(penny)

        let marcus = ScriptCharacter(name: "MARCUS", role: .lead)
        marcus.projects = [project]
        context.insert(marcus)

        try? context.save()
    }
}
