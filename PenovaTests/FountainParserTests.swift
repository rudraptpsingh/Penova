//
//  FountainParserTests.swift
//  PenovaTests
//
//  Direct-exercises FountainParser and FountainHeadingSplit classifiers.
//  Covers scene-heading variants, character cues, parentheticals,
//  transitions, unicode, and a 100-line stress sample.
//

import Testing
import Foundation
import SwiftData
import PenovaKit
@testable import Penova

@MainActor
@Suite struct FountainParserTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    // MARK: - Heading split variants

    @Test func intDinerNightSplitsCorrectly() {
        let s = FountainHeadingSplit.split("INT. DINER - NIGHT")
        #expect(s.location == .interior)
        #expect(s.locationName == "DINER")
        #expect(s.time == .night)
    }

    @Test func extRooftopNoTimeDefaultsToDay() {
        // Parser's SceneTimeOfDay fallback when no recognised time is " ".
        let s = FountainHeadingSplit.split("EXT. ROOFTOP")
        #expect(s.location == .exterior)
        #expect(s.locationName == "ROOFTOP")
        // Fallback is `.day` — locked in.
        #expect(s.time == .day)
    }

    @Test func intExtCarDaySplitsAsBoth() {
        let s = FountainHeadingSplit.split("INT./EXT. CAR - DAY")
        #expect(s.location == .both)
        #expect(s.locationName == "CAR")
        #expect(s.time == .day)
    }

    @Test func estCitySplitsAsExterior() {
        let s = FountainHeadingSplit.split("EST. CITY")
        // EST. (establishing) classified as exterior per the switch in split().
        #expect(s.location == .exterior)
        #expect(s.locationName == "CITY")
    }

    // MARK: - Classifiers (isSceneHeading / isTransition / isCharacterCue / isParenthetical)

    @Test func sceneHeadingPrefixesDetected() {
        #expect(FountainParser.isSceneHeading("INT. ROOM - DAY"))
        #expect(FountainParser.isSceneHeading("EXT. BEACH"))
        #expect(FountainParser.isSceneHeading("EST. CITY"))
        #expect(FountainParser.isSceneHeading("INT./EXT. CAR - NIGHT"))
        // Forced heading with leading "."
        #expect(FountainParser.isSceneHeading(".BLACK"))
        // Mixed-case action line is not a heading.
        #expect(!FountainParser.isSceneHeading("Jane walks in slowly."))
    }

    @Test func cutToClassifiedAsTransition() {
        #expect(FountainParser.isTransition("CUT TO:"))
    }

    @Test func fadeOutClassifiedAsTransition() {
        // The implementation treats "FADE OUT." as a transition. Lock this in.
        #expect(FountainParser.isTransition("FADE OUT."))
    }

    @Test func parentheticalClassifier() {
        #expect(FountainParser.isParenthetical("(quietly)"))
        #expect(!FountainParser.isParenthetical("quietly"))
        #expect(!FountainParser.isParenthetical("("))
        #expect(!FountainParser.isParenthetical(")"))
    }

    @Test func emptyParensClassifiedAsParenthetical() {
        // "()" has count == 2 and starts/ends with parens → treated as parenthetical
        // by the current classifier. Document this behaviour.
        #expect(FountainParser.isParenthetical("()"))
    }

    @Test func characterCueNeedsNextLine() {
        #expect(FountainParser.isCharacterCue("JANE", next: "Hi there."))
        #expect(!FountainParser.isCharacterCue("JANE", next: nil))
        #expect(!FountainParser.isCharacterCue("JANE", next: "   "))
        // Mixed case is not a cue.
        #expect(!FountainParser.isCharacterCue("Jane", next: "Hi there."))
        // A transition-looking line is not a cue.
        #expect(!FountainParser.isCharacterCue("CUT TO:", next: "Next."))
    }

    // MARK: - Document-level parse

    @Test func allCapsFollowedByDialogueProducesCharacterPlusDialogue() {
        let src = """
        INT. ROOM - DAY

        JANE
        Hello world.
        """
        let doc = FountainParser.parse(src)
        #expect(doc.scenes.count == 1)
        let kinds = doc.scenes[0].elements.map(\.kind)
        #expect(kinds.contains(.character))
        #expect(kinds.contains(.dialogue))
        let dialogue = doc.scenes[0].elements.first(where: { $0.kind == .dialogue })
        #expect(dialogue?.text == "Hello world.")
    }

    @Test func parentheticalAfterCharacterCue() {
        let src = """
        INT. ROOM - DAY

        JANE
        (quietly)
        Hello.
        """
        let doc = FountainParser.parse(src)
        let kinds = doc.scenes[0].elements.map(\.kind)
        #expect(kinds.contains(.parenthetical))
        #expect(kinds.contains(.dialogue))
    }

    @Test func transitionRecognized() {
        let src = """
        INT. ROOM - DAY

        Stuff.

        CUT TO:

        EXT. BEACH - DAY

        Waves.
        """
        let doc = FountainParser.parse(src)
        let allKinds = doc.scenes.flatMap { $0.elements.map(\.kind) }
        #expect(allKinds.contains(.transition))
    }

    @Test func mixedCaseLineIsAction() {
        let src = """
        INT. ROOM - DAY

        Jane walks in slowly and surveys the empty space.
        """
        let doc = FountainParser.parse(src)
        let kinds = doc.scenes[0].elements.map(\.kind)
        #expect(kinds == [.action])
        #expect(doc.scenes[0].elements[0].text.contains("Jane walks"))
    }

    @Test func blankLinesSeparateElements() {
        let src = """
        INT. ROOM - DAY

        First action.

        Second action.
        """
        let doc = FountainParser.parse(src)
        let actions = doc.scenes[0].elements.filter { $0.kind == .action }
        #expect(actions.count == 2)
    }

    @Test func titlePageBlockIsCapturedAndExcludedFromScenes() {
        let src = """
        Title: My Script
        Author: Jane Writer
        Draft date: 2024-01-01

        INT. ROOM - DAY

        A beat.
        """
        let doc = FountainParser.parse(src)
        #expect(doc.titlePage["title"] == "My Script")
        #expect(doc.titlePage["author"] == "Jane Writer")
        #expect(doc.titlePage["draft date"] == "2024-01-01")
        #expect(doc.scenes.count == 1)
    }

    @Test func unicodeSurvivesParsing() {
        let src = """
        INT. CAFÉ — DAY

        JOSÉ
        “Hola.” — He grins.
        """
        let doc = FountainParser.parse(src)
        #expect(doc.scenes.count == 1)
        // Heading keeps the em dash.
        #expect(doc.scenes[0].heading.contains("CAFÉ"))
        let dialogue = doc.scenes[0].elements.first(where: { $0.kind == .dialogue })
        #expect(dialogue != nil)
        #expect(dialogue?.text.contains("Hola") == true)
    }

    @Test func hundredLineFountainParsesCleanly() {
        var lines: [String] = ["Title: Stress", "Author: Bot", ""]
        for i in 0..<12 {
            lines.append("INT. LOCATION \(i) - DAY")
            lines.append("")
            lines.append("Action beats unfold \(i).")
            lines.append("")
            lines.append("HERO")
            lines.append("Line \(i).")
            lines.append("")
        }
        // Ensure we're > 100 lines.
        while lines.count < 110 { lines.append("More action.") ; lines.append("") }
        let src = lines.joined(separator: "\n")
        let doc = FountainParser.parse(src)
        #expect(doc.scenes.count == 12)
        // Every scene should have at least one dialogue element.
        for s in doc.scenes {
            #expect(s.elements.contains(where: { $0.kind == .dialogue }))
        }
    }

    // MARK: - Round-trip: export → parse → compare element count

    @Test func roundTripElementCountMatches() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "RT")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Cafe", location: .interior, time: .day, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        let els: [(SceneElementKind, String)] = [
            (.heading, s.heading),
            (.action, "Jane sits."),
            (.character, "JANE"),
            (.parenthetical, "(softly)"),
            (.dialogue, "Hi."),
            (.transition, "CUT TO:")
        ]
        for (i, pair) in els.enumerated() {
            let e = SceneElement(kind: pair.0, text: pair.1, order: i)
            e.scene = s; s.elements.append(e); ctx.insert(e)
        }
        try ctx.save()

        let fountain = FountainExporter.export(project: p)
        let parsed = FountainParser.parse(fountain)

        // The transition lives in a trailing (empty) second scene because
        // the exporter emits it after the scene block and the parser
        // tolerates a transition between scenes by synthesising a
        // placeholder. Collect all elements across all parsed scenes.
        let parsedAll = parsed.scenes.flatMap { $0.elements }
        // Character + parenthetical + dialogue + action + transition survive.
        // Parser does NOT re-emit heading as a `heading` element — the
        // heading lives on `scene.heading` instead. So the parsed element
        // count excludes the heading element.
        let nonHeadingInput = els.filter { $0.0 != .heading }
        #expect(parsedAll.count == nonHeadingInput.count,
                "parsed=\(parsedAll.count) input-non-heading=\(nonHeadingInput.count)")

        // Heading text match.
        #expect(parsed.scenes[0].heading.contains("CAFE"))
    }

    @Test func roundTripDialogueWithSpecialCharsPreserved() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Special RT")
        ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)
        let s = ScriptScene(locationName: "Roof", location: .exterior, time: .night, order: 0)
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
        for (i, pair) in [
            (SceneElementKind.heading, s.heading),
            (.character, "JANE"),
            (.dialogue, "Tom & I said \"no\" — then he smiled.")
        ].enumerated() {
            let e = SceneElement(kind: pair.0, text: pair.1, order: i)
            e.scene = s; s.elements.append(e); ctx.insert(e)
        }
        try ctx.save()

        let fountain = FountainExporter.export(project: p)
        let parsed = FountainParser.parse(fountain)
        let d = parsed.scenes[0].elements.first(where: { $0.kind == .dialogue })
        #expect(d?.text.contains("Tom & I") == true)
        #expect(d?.text.contains("\"no\"") == true)
        #expect(d?.text.contains("—") == true)
    }
}
