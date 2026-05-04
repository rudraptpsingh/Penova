//
//  StyleCheckServiceTests.swift
//  PenovaTests
//
//  Pins the StyleCheckService contract:
//   • adverb / cliché / passive scanners flag the right spans
//   • adverb stop-list keeps "ugly" / "family" / "fly" off the list
//   • cliché matcher anchors on word boundaries and longest-match-wins
//   • passive scanner is conservative — only flags high-signal patterns
//   • element-level scoping skips dialogue/character/heading
//   • parentheticals get adverbs only
//   • offsets round-trip back to a Swift Range<String.Index>
//
//  Tests are intentionally small and many — each one is a contract pin.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "StyleCheckServiceTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
@Suite struct StyleCheckServiceTests {

    // MARK: - Empty / trivial input

    @Test func emptyStringReturnsNoMarks() {
        #expect(StyleCheckService.marks(in: "").isEmpty)
    }

    @Test func cleanTextReturnsNoMarks() {
        let text = "Sarah crosses the lot. The neon sign of the diner buzzes overhead."
        #expect(StyleCheckService.marks(in: text).isEmpty)
    }

    @Test func emptyKindSetReturnsNoMarks() {
        let text = "She moves quickly toward the door."
        #expect(StyleCheckService.marks(in: text, kinds: []).isEmpty)
    }

    // MARK: - Adverb scanner

    @Test func detectsCommonAdverb() {
        let text = "She walks quickly to the door."
        let marks = StyleCheckService.marks(in: text, kinds: [.adverb])
        #expect(marks.count == 1)
        #expect(marks.first?.matched == "quickly")
        #expect(marks.first?.kind == .adverb)
    }

    @Test func detectsMultipleAdverbs() {
        let text = "He moves quietly. She watches carefully."
        let kinds = StyleCheckService.marks(in: text, kinds: [.adverb])
            .map(\.matched)
        #expect(kinds == ["quietly", "carefully"])
    }

    @Test func adverbStopListExcludesUgly() {
        let text = "An ugly room with a friendly cat."
        #expect(StyleCheckService.marks(in: text, kinds: [.adverb]).isEmpty)
    }

    @Test func adverbStopListExcludesFamily() {
        // "family" ends in -ly but isn't an adverb.
        let text = "His family arrives at the station."
        #expect(StyleCheckService.marks(in: text, kinds: [.adverb]).isEmpty)
    }

    @Test func adverbScannerSkipsTooShortWords() {
        // "fly", "ply" are 3 letters — don't match.
        let text = "The fly buzzes."
        #expect(StyleCheckService.marks(in: text, kinds: [.adverb]).isEmpty)
    }

    @Test func adverbCaseInsensitive() {
        let text = "QUICKLY she runs."
        let marks = StyleCheckService.marks(in: text, kinds: [.adverb])
        #expect(marks.count == 1)
        #expect(marks.first?.matched == "QUICKLY")
    }

    // MARK: - Cliché scanner

    @Test func detectsShortCliche() {
        let text = "We see the door open."
        let marks = StyleCheckService.marks(in: text, kinds: [.cliche])
        #expect(marks.count == 1)
        #expect(marks.first?.matched.lowercased() == "we see")
    }

    @Test func detectsBeginsTo() {
        let text = "He begins to walk away."
        let marks = StyleCheckService.marks(in: text, kinds: [.cliche])
        #expect(marks.count == 1)
        #expect(marks.first?.matched == "begins to")
    }

    @Test func detectsLongCliche() {
        let text = "He has the kind of tired that sleep doesn't fix."
        let marks = StyleCheckService.marks(in: text, kinds: [.cliche])
        #expect(marks.count == 1)
        // Longest-match-wins: should match the long phrase, not the
        // shorter "tired that sleep doesn't fix" embedded inside.
        #expect(
            marks.first?.matched.lowercased()
                == "the kind of tired that sleep doesn't fix"
        )
    }

    @Test func clicheWordBoundaryGuard() {
        // "begins" not followed by " to" should not match "begins to".
        let text = "The film begins. She turns away."
        #expect(StyleCheckService.marks(in: text, kinds: [.cliche]).isEmpty)
    }

    @Test func clicheCaseInsensitive() {
        let text = "WE SEE the headlights cut through fog."
        let marks = StyleCheckService.marks(in: text, kinds: [.cliche])
        #expect(marks.count == 1)
    }

    // MARK: - Passive-voice scanner

    @Test func detectsIsBeingPattern() {
        let text = "He is being careful with his hands."
        let marks = StyleCheckService.marks(in: text, kinds: [.passive])
        #expect(marks.count == 1)
        #expect(marks.first?.matched.lowercased().hasPrefix("is being") == true)
    }

    @Test func detectsWasBeingPattern() {
        let text = "She was being followed."
        let marks = StyleCheckService.marks(in: text, kinds: [.passive])
        #expect(marks.count == 1)
    }

    @Test func detectsBeVerbPlusParticiple() {
        let text = "The door was watched by no one."
        let marks = StyleCheckService.marks(in: text, kinds: [.passive])
        #expect(marks.count == 1)
        #expect(marks.first?.matched.lowercased() == "was watched")
    }

    @Test func passiveDoesNotFlagActiveSentence() {
        // "is happening" — progressive but not in our flag list.
        let text = "Something is happening at the platform."
        #expect(StyleCheckService.marks(in: text, kinds: [.passive]).isEmpty)
    }

    @Test func passiveBeingTakesPrecedenceOverParticiple() {
        // Should produce one mark, not two overlapping ones.
        let text = "He is being watched."
        let marks = StyleCheckService.marks(in: text, kinds: [.passive])
        #expect(marks.count == 1)
        #expect(marks.first?.matched.lowercased() == "is being watched")
    }

    // MARK: - Multi-rule integration

    @Test func mixedTextProducesAllThreeKinds() {
        let text = """
        He is being careful. She moves quickly. We see the door close.
        """
        let marks = StyleCheckService.marks(in: text)
        let kinds = Set(marks.map(\.kind))
        #expect(kinds == [.adverb, .cliche, .passive])
    }

    @Test func marksAreSortedByLocation() {
        let text = "We see her quickly close the door, which is being slammed."
        let marks = StyleCheckService.marks(in: text)
        let locs = marks.map(\.location)
        #expect(locs == locs.sorted())
    }

    @Test func kindsFilterIsRespected() {
        let text = "She walks quickly. We see the door."
        let onlyAdverbs = StyleCheckService.marks(in: text, kinds: [.adverb])
        let onlyCliches = StyleCheckService.marks(in: text, kinds: [.cliche])
        #expect(onlyAdverbs.allSatisfy { $0.kind == .adverb })
        #expect(onlyCliches.allSatisfy { $0.kind == .cliche })
    }

    // MARK: - Range round-trip

    @Test func rangeRoundTripsBackToSubstring() {
        let text = "She moves quickly toward the door."
        let mark = try! #require(
            StyleCheckService.marks(in: text, kinds: [.adverb]).first
        )
        let range = try! #require(mark.range(in: text))
        #expect(String(text[range]) == "quickly")
    }

    @Test func nsRangeMatchesLocationLength() {
        let text = "She walks quietly."
        let mark = try! #require(
            StyleCheckService.marks(in: text, kinds: [.adverb]).first
        )
        #expect(mark.nsRange.location == mark.location)
        #expect(mark.nsRange.length == mark.length)
    }

    // MARK: - Unicode safety

    @Test func unicodeOffsetsAreUTF16() {
        // Devanagari + Latin mix exercises NSString UTF-16 indexing.
        let text = "एक रात — She moves quickly."
        let marks = StyleCheckService.marks(in: text, kinds: [.adverb])
        #expect(marks.count == 1)
        let mark = marks[0]
        // The matched substring must be exactly "quickly" via the helper.
        let range = try! #require(mark.range(in: text))
        #expect(String(text[range]) == "quickly")
    }

    // MARK: - Element-level scoping

    @Test func actionElementGetsAllChecks() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let el = SceneElement(
            kind: .action,
            text: "He is being careful. She moves quickly.",
            order: 0
        )
        ctx.insert(el)
        let marks = StyleCheckService.marks(for: el)
        let kinds = Set(marks.map(\.kind))
        #expect(kinds == [.adverb, .passive])
    }

    @Test func dialogueElementIsSkipped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let el = SceneElement(
            kind: .dialogue,
            text: "I was watched by everyone, quickly and quietly.",
            order: 0
        )
        ctx.insert(el)
        #expect(StyleCheckService.marks(for: el).isEmpty)
    }

    @Test func parentheticalGetsAdverbOnly() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let el = SceneElement(
            kind: .parenthetical,
            text: "(quietly, beginning to weep)",
            order: 0
        )
        ctx.insert(el)
        let marks = StyleCheckService.marks(for: el)
        // "quietly" → adverb. "beginning to" is NOT one of the cliché
        // forms (we list "begins to" / "starts to") so no cliché.
        #expect(marks.count == 1)
        #expect(marks.first?.kind == .adverb)
        #expect(marks.first?.matched == "quietly")
    }

    @Test func headingElementIsSkipped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let el = SceneElement(
            kind: .heading,
            text: "INT. MUMBAI LOCAL TRAIN — NIGHT",
            order: 0
        )
        ctx.insert(el)
        #expect(StyleCheckService.marks(for: el).isEmpty)
    }

    // MARK: - Scene-level aggregation

    @Test func sceneAggregatesMarksAcrossElements() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Style Test")
        ctx.insert(project)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "TRAIN", order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)

        let action = SceneElement(
            kind: .action,
            text: "He is being careful.",
            order: 0
        )
        action.scene = scene; scene.elements.append(action); ctx.insert(action)

        let dialogue = SceneElement(
            kind: .dialogue,
            text: "I am being watched.",
            order: 1,
            characterName: "ARJUN"
        )
        dialogue.scene = scene; scene.elements.append(dialogue); ctx.insert(dialogue)

        let paren = SceneElement(
            kind: .parenthetical,
            text: "(quietly)",
            order: 2
        )
        paren.scene = scene; scene.elements.append(paren); ctx.insert(paren)

        let summary = StyleCheckService.marks(for: scene)
        // Two elements with marks: the action, the parenthetical.
        // The dialogue is skipped despite containing "is being watched".
        #expect(summary.count == 2)
        #expect(summary[0].element.kind == .action)
        #expect(summary[1].element.kind == .parenthetical)
        #expect(summary[0].marks.count == 1)
        #expect(summary[1].marks.count == 1)
    }
}
