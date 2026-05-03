//
//  TableReadTests.swift
//  PenovaTests
//
//  Pins the contracts for the Voiced Table Read feature foundation:
//    • VoiceCatalogue   — preset list, lookup, auto-suggest heuristic
//    • VoiceAssignment  — @Model CRUD, idempotent assign, auto-assign
//    • TableReadEngine  — queue building from scene elements, settings
//                          respected, voice resolution fall-throughs
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "TableReadTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func makeProject(in ctx: ModelContext) -> Project {
    let p = Project(title: "Ek Raat Mumbai Mein")
    ctx.insert(p)
    let ep = Episode(title: "Arrival", order: 0)
    ep.project = p
    p.episodes.append(ep)
    ctx.insert(ep)
    let scene = ScriptScene(
        locationName: "MUMBAI LOCAL TRAIN",
        location: .interior,
        time: .night,
        order: 0
    )
    scene.episode = ep
    ep.scenes.append(scene)
    ctx.insert(scene)
    return p
}

@MainActor
private func addElements(
    _ items: [(SceneElementKind, String, String?)],
    to scene: ScriptScene,
    in ctx: ModelContext
) {
    for (i, (kind, text, name)) in items.enumerated() {
        let el = SceneElement(kind: kind, text: text, order: i, characterName: name)
        el.scene = scene
        scene.elements.append(el)
        ctx.insert(el)
    }
}

// MARK: - VoiceCatalogue

@Suite struct VoiceCatalogueTests {

    @Test func eightPresetsShipByDefault() {
        #expect(VoiceCatalogue.presets.count == 8)
    }

    @Test func presetIDsAreUnique() {
        let ids = VoiceCatalogue.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func narratorPresetExistsWithKnownID() {
        let narrator = VoiceCatalogue.preset(id: VoiceCatalogue.narratorID)
        #expect(narrator != nil)
        #expect(narrator?.gender == .neutral)
    }

    @Test func presetLookupByID() {
        #expect(VoiceCatalogue.preset(id: "system-vihaan")?.displayName == "Vihaan")
    }

    @Test func presetLookupReturnsNilForUnknown() {
        #expect(VoiceCatalogue.preset(id: "system-nope") == nil)
    }

    @Test func suggestPrefersGenderMatch() {
        let male = VoiceCatalogue.suggest(gender: .male)
        let female = VoiceCatalogue.suggest(gender: .female)
        #expect(male.gender == .male)
        #expect(female.gender == .female)
    }

    @Test func suggestPrefersAgeMatch() {
        let young = VoiceCatalogue.suggest(approximateAge: 22)
        let old = VoiceCatalogue.suggest(approximateAge: 65)
        #expect(young.contains(age: 22))
        #expect(old.contains(age: 65))
    }

    @Test func suggestNeverReturnsNarratorForSpeakingCharacters() {
        // Even with zero hints, suggest() should not return the
        // narrator preset — that's only for action lines.
        for _ in 0..<10 {
            let preset = VoiceCatalogue.suggest()
            #expect(preset.id != VoiceCatalogue.narratorID)
        }
    }
}

// MARK: - VoiceAssignment service

@MainActor
@Suite struct VoiceAssignmentServiceTests {

    @Test func assignsAndFetches() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        _ = try VoiceAssignmentService.assign(
            voice: "system-vihaan",
            to: "ARJUN",
            in: project,
            context: ctx
        )
        let map = try VoiceAssignmentService.assignments(for: project, context: ctx)
        #expect(map["ARJUN"]?.voiceID == "system-vihaan")
    }

    @Test func uppercasesCharacterName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        _ = try VoiceAssignmentService.assign(
            voice: "system-aanya",
            to: "Zaina",
            in: project,
            context: ctx
        )
        let map = try VoiceAssignmentService.assignments(for: project, context: ctx)
        #expect(map["ZAINA"] != nil)
        #expect(map["Zaina"] == nil)
    }

    @Test func assignTwiceUpdatesNotDuplicates() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        _ = try VoiceAssignmentService.assign(
            voice: "system-vihaan",
            to: "ARJUN",
            in: project,
            context: ctx
        )
        _ = try VoiceAssignmentService.assign(
            voice: "system-rohan",
            to: "ARJUN",
            in: project,
            context: ctx
        )
        let map = try VoiceAssignmentService.assignments(for: project, context: ctx)
        #expect(map.count == 1)
        #expect(map["ARJUN"]?.voiceID == "system-rohan")
    }

    @Test func removeDeletesRow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        _ = try VoiceAssignmentService.assign(
            voice: "system-vihaan",
            to: "ARJUN",
            in: project,
            context: ctx
        )
        try VoiceAssignmentService.remove(
            characterName: "ARJUN",
            in: project,
            context: ctx
        )
        let map = try VoiceAssignmentService.assignments(for: project, context: ctx)
        #expect(map.isEmpty)
    }

    @Test func parseAgeHandlesIntAndPhrase() {
        #expect(VoiceAssignmentService.parseAge("38") == 38)
        #expect(VoiceAssignmentService.parseAge("mid-30s") == 30)
        #expect(VoiceAssignmentService.parseAge("early forties") == nil)
        #expect(VoiceAssignmentService.parseAge(nil) == nil)
        #expect(VoiceAssignmentService.parseAge("") == nil)
    }

    @Test func suggestForCharacterUsesAge() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "P"); ctx.insert(p)
        let c = ScriptCharacter(
            name: "Aanya",
            role: .lead,
            ageText: "27",
            occupation: "engineer",
            traits: []
        )
        ctx.insert(c)

        let voiceID = VoiceAssignmentService.suggest(for: c)
        let preset = VoiceCatalogue.preset(id: voiceID)
        #expect(preset != nil)
        #expect(preset?.contains(age: 27) == true)
    }

    @Test func autoAssignMissingAddsRowsForRosterCharacters() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)

        let arjun = ScriptCharacter(name: "ARJUN", role: .protagonist, ageText: "32")
        let zaina = ScriptCharacter(name: "ZAINA", role: .lead, ageText: "29")
        ctx.insert(arjun); ctx.insert(zaina)
        project.characters = [arjun, zaina]

        let added = try VoiceAssignmentService.autoAssignMissing(
            in: project,
            context: ctx
        )
        #expect(added == 2)
        let map = try VoiceAssignmentService.assignments(for: project, context: ctx)
        #expect(map.count == 2)
    }
}

// MARK: - TableReadEngine

@MainActor
@Suite struct TableReadEngineTests {

    @Test func emptySceneProducesEmptyQueue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!

        let q = TableReadEngine.queue(for: scene, assignments: [:])
        #expect(q.isEmpty)
    }

    @Test func actionLineProducesNarratorItem() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [(.action, "The carriage is half empty.", nil)],
            to: scene, in: ctx
        )

        let q = TableReadEngine.queue(for: scene, assignments: [:])
        #expect(q.count == 1)
        #expect(q.first?.kind == .action)
        #expect(q.first?.voiceID == VoiceCatalogue.narratorID)
        #expect(q.first?.characterName == nil)
    }

    @Test func dialogueResolvesAssignedVoice() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.character, "ARJUN", nil),
                (.dialogue, "How did you —", "ARJUN")
            ],
            to: scene, in: ctx
        )

        let row = try VoiceAssignmentService.assign(
            voice: "system-vihaan",
            to: "ARJUN",
            in: project,
            context: ctx
        )
        let map = ["ARJUN": row]

        let q = TableReadEngine.queue(for: scene, assignments: map)
        #expect(q.count == 1)
        #expect(q.first?.kind == .dialogue)
        #expect(q.first?.voiceID == "system-vihaan")
        #expect(q.first?.characterName == "ARJUN")
    }

    @Test func dialogueWithoutAssignmentFallsBackToSuggestion() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.character, "ZAINA", nil),
                (.dialogue, "You're getting off at Dadar.", "ZAINA")
            ],
            to: scene, in: ctx
        )

        let q = TableReadEngine.queue(for: scene, assignments: [:])
        #expect(q.count == 1)
        // Fallback voice is whatever VoiceCatalogue.suggest() picks —
        // never narrator.
        #expect(q.first?.voiceID != VoiceCatalogue.narratorID)
    }

    @Test func headingTransitionAndCharacterCueSkipped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.heading, "INT. MUMBAI LOCAL TRAIN — NIGHT", nil),
                (.character, "ARJUN", nil),
                (.dialogue, "I didn't.", "ARJUN"),
                (.transition, "CUT TO:", nil),
            ],
            to: scene, in: ctx
        )

        let q = TableReadEngine.queue(for: scene, assignments: [:])
        // Only the dialogue is voiced.
        #expect(q.count == 1)
        #expect(q.first?.kind == .dialogue)
    }

    @Test func parentheticalsHiddenByDefault() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.character, "ARJUN", nil),
                (.parenthetical, "(quietly)", "ARJUN"),
                (.dialogue, "How did you —", "ARJUN")
            ],
            to: scene, in: ctx
        )

        let q = TableReadEngine.queue(for: scene, assignments: [:])
        // Parenthetical skipped; dialogue voiced.
        #expect(q.count == 1)
        #expect(q.first?.kind == .dialogue)
    }

    @Test func parentheticalsIncludedWhenSettingEnabled() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.character, "ARJUN", nil),
                (.parenthetical, "(quietly)", "ARJUN"),
                (.dialogue, "How did you —", "ARJUN")
            ],
            to: scene, in: ctx
        )

        var settings = TableReadEngine.Settings.default
        settings.readParentheticals = true
        let q = TableReadEngine.queue(for: scene, assignments: [:], settings: settings)
        #expect(q.count == 2)
        #expect(q.first?.kind == .parenthetical)
        // Parens stripped from text.
        #expect(q.first?.text == "quietly")
    }

    @Test func actionLinesRespectSetting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let scene = project.activeEpisodesOrdered.first!.scenesOrdered.first!
        addElements(
            [
                (.action, "Rain streaks the window.", nil),
                (.character, "ARJUN", nil),
                (.dialogue, "I didn't.", "ARJUN")
            ],
            to: scene, in: ctx
        )

        var settings = TableReadEngine.Settings.default
        settings.readActionLines = false
        let q = TableReadEngine.queue(for: scene, assignments: [:], settings: settings)
        // Dialogue only — action skipped.
        #expect(q.count == 1)
        #expect(q.first?.kind == .dialogue)
    }

    @Test func paceClampedToReasonableRange() {
        #expect(TableReadEngine.Settings(pace: 0.1).pace == 0.5)
        #expect(TableReadEngine.Settings(pace: 5.0).pace == 2.0)
        #expect(TableReadEngine.Settings(pace: 1.25).pace == 1.25)
    }

    @Test func episodeQueueFlattensScenes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = makeProject(in: ctx)
        let ep = project.activeEpisodesOrdered.first!
        let scene1 = ep.scenesOrdered.first!
        addElements(
            [(.action, "Scene one.", nil)],
            to: scene1, in: ctx
        )

        let scene2 = ScriptScene(
            locationName: "DADAR PLATFORM",
            location: .exterior, time: .dusk, order: 1
        )
        scene2.episode = ep
        ep.scenes.append(scene2)
        ctx.insert(scene2)
        addElements(
            [(.action, "Scene two.", nil)],
            to: scene2, in: ctx
        )

        let q = TableReadEngine.queue(for: ep, assignments: [:])
        #expect(q.count == 2)
        #expect(q[0].text == "Scene one.")
        #expect(q[1].text == "Scene two.")
    }

    @Test func stripParenthesesIdempotent() {
        #expect(TableReadEngine.stripParentheses("(quietly)") == "quietly")
        #expect(TableReadEngine.stripParentheses("quietly") == "quietly")
        #expect(TableReadEngine.stripParentheses("  (whisper)  ") == "whisper")
    }
}
