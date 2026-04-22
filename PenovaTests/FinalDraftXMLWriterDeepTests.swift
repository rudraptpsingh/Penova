//
//  FinalDraftXMLWriterDeepTests.swift
//  PenovaTests
//
//  Deeper coverage for the FDX writer: escaping, ordering across episodes,
//  synthetic scene-heading insertion, empty-project XML validity, and a
//  full XMLParser integration pass on three sample projects.
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
@Suite struct FinalDraftXMLWriterDeepTests {

    // MARK: - helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    @discardableResult
    private func addScene(
        to ep: Episode,
        ctx: ModelContext,
        order: Int,
        location: String = "Room",
        elements: [(SceneElementKind, String)] = []
    ) -> ScriptScene {
        let scene = ScriptScene(locationName: location, location: .interior, time: .day, order: order)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        for (i, (kind, text)) in elements.enumerated() {
            let el = SceneElement(kind: kind, text: text, order: i)
            el.scene = scene; scene.elements.append(el); ctx.insert(el)
        }
        return scene
    }

    private func parseSucceeds(_ xml: String) -> Bool {
        guard let data = xml.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        return parser.parse()
    }

    // MARK: - Paragraph round-trip for each kind

    @Test func roundTripEachParagraphType() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "RT", logline: "", genre: [.drama])
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.heading, "INT. ROOM - DAY"),
            (.action, "She sits."),
            (.character, "MAYA"),
            (.parenthetical, "quietly"),
            (.dialogue, "Hi."),
            (.transition, "CUT TO:"),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        for kind in ["Scene Heading", "Action", "Character", "Parenthetical", "Dialogue", "Transition"] {
            #expect(xml.contains("Paragraph Type=\"\(kind)\""),
                    "missing paragraph type \(kind)")
        }
    }

    // MARK: - Escape — each char individually

    @Test func escapeAmpersand() {
        #expect(FinalDraftXMLWriter.escape("A & B") == "A &amp; B")
    }

    @Test func escapeLessThan() {
        #expect(FinalDraftXMLWriter.escape("<c>") == "&lt;c&gt;")
    }

    @Test func escapeDoubleQuote() {
        #expect(FinalDraftXMLWriter.escape("\"d\"") == "&quot;d&quot;")
    }

    @Test func escapeApostrophe() {
        #expect(FinalDraftXMLWriter.escape("'e'") == "&apos;e&apos;")
    }

    @Test func escapeLeavesPlainTextAlone() {
        #expect(FinalDraftXMLWriter.escape("hello world 123") == "hello world 123")
    }

    @Test func escapeCombinedString() {
        #expect(FinalDraftXMLWriter.escape("A & B <c> \"d\" 'e'")
                == "A &amp; B &lt;c&gt; &quot;d&quot; &apos;e&apos;")
    }

    // MARK: - Empty project

    @Test func emptyProjectProducesParseableXML() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Empty")
        ctx.insert(project)
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.hasPrefix("<?xml"))
        #expect(xml.contains("DocumentType=\"Script\""))
        #expect(parseSucceeds(xml), "empty-project XML must parse")
    }

    // MARK: - Multi-episode ordering

    @Test func multiEpisodeEmitsScenesInOrder() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Series")
        ctx.insert(project)

        let ep1 = Episode(title: "E1", order: 0)
        ep1.project = project; project.episodes.append(ep1); ctx.insert(ep1)
        let ep2 = Episode(title: "E2", order: 1)
        ep2.project = project; project.episodes.append(ep2); ctx.insert(ep2)

        addScene(to: ep1, ctx: ctx, order: 0, location: "E1S1", elements: [
            (.heading, "INT. E1S1 - DAY"), (.action, "E1S1 action")
        ])
        addScene(to: ep1, ctx: ctx, order: 1, location: "E1S2", elements: [
            (.heading, "INT. E1S2 - DAY"), (.action, "E1S2 action")
        ])
        addScene(to: ep2, ctx: ctx, order: 0, location: "E2S1", elements: [
            (.heading, "INT. E2S1 - DAY"), (.action, "E2S1 action")
        ])
        addScene(to: ep2, ctx: ctx, order: 1, location: "E2S2", elements: [
            (.heading, "INT. E2S2 - DAY"), (.action, "E2S2 action")
        ])
        try ctx.save()

        let xml = FinalDraftXMLWriter.xml(for: project)
        let markers = ["E1S1 action", "E1S2 action", "E2S1 action", "E2S2 action"]
        var last = xml.startIndex
        for marker in markers {
            if let r = xml.range(of: marker, range: last..<xml.endIndex) {
                last = r.upperBound
            } else {
                Issue.record("Marker \(marker) missing or out of order")
            }
        }
        #expect(parseSucceeds(xml))
    }

    // MARK: - Synthetic scene heading insertion

    @Test func syntheticSceneHeadingWhenFirstElementIsNotHeading() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Synthetic")
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = addScene(to: ep, ctx: ctx, order: 0, location: "Kitchen", elements: [
            (.action, "Water boils.")
        ])
        // scene.heading is derived from locationName + location + time.
        let expectedHeading = scene.heading.uppercased()
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("<Paragraph Type=\"Scene Heading\"><Text>\(FinalDraftXMLWriter.escape(expectedHeading))</Text></Paragraph>"))
    }

    @Test func noDuplicateHeadingWhenExplicitHeadingFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "NoDup")
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, location: "Kitchen", elements: [
            (.heading, "INT. KITCHEN - DAY"),
            (.action, "Boil."),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        let count = xml.components(separatedBy: "Paragraph Type=\"Scene Heading\"").count - 1
        #expect(count == 1, "expected exactly one scene heading paragraph, got \(count)")
    }

    // MARK: - Prefix / DocumentType

    @Test func outputStartsWithXMLDeclaration() throws {
        let container = try makeContainer()
        let project = Project(title: "X"); container.mainContext.insert(project)
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.hasPrefix("<?xml"))
    }

    @Test func outputContainsDocumentTypeScript() throws {
        let container = try makeContainer()
        let project = Project(title: "X"); container.mainContext.insert(project)
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("DocumentType=\"Script\""))
    }

    // MARK: - XMLParser integration on three projects

    @Test func parseEmptyProject() throws {
        let container = try makeContainer()
        let project = Project(title: "Empty"); container.mainContext.insert(project)
        #expect(parseSucceeds(FinalDraftXMLWriter.xml(for: project)))
    }

    @Test func parseOneSceneProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "One"); ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.heading, "INT. ROOM - DAY"),
            (.action, "She stands."),
            (.character, "MAYA"),
            (.dialogue, "Hello."),
        ])
        try ctx.save()
        #expect(parseSucceeds(FinalDraftXMLWriter.xml(for: project)))
    }

    @Test func parseMultiEpisodeProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Multi <&\"'>"); ctx.insert(project)
        let ep1 = Episode(title: "E1", order: 0)
        ep1.project = project; project.episodes.append(ep1); ctx.insert(ep1)
        let ep2 = Episode(title: "E2", order: 1)
        ep2.project = project; project.episodes.append(ep2); ctx.insert(ep2)
        addScene(to: ep1, ctx: ctx, order: 0, elements: [(.action, "A & B <c>")])
        addScene(to: ep2, ctx: ctx, order: 0, elements: [(.dialogue, "I'm \"in\".")])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(parseSucceeds(xml))
    }

    // MARK: - Edge: whitespace-only dialogue

    @Test func whitespaceOnlyDialogueDoesNotBreakParse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "WS"); ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.character, "MAYA"),
            (.dialogue, "   "),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        // The paragraph is still emitted; we don't require it to be
        // suppressed, but the document must remain parseable.
        #expect(parseSucceeds(xml))
    }

    // MARK: - Character cue mid-stream isn't tagged as dialogue

    @Test func characterCueMidStreamStaysCharacter() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Cue"); ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.action, "Rain falls."),
            (.character, "MARCUS"),
            (.dialogue, "Finally."),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        // The MARCUS paragraph must be Character, not Dialogue.
        #expect(xml.contains("<Paragraph Type=\"Character\"><Text>MARCUS</Text></Paragraph>"))
        // And the surrounding lines exist.
        #expect(xml.contains("Rain falls."))
        #expect(xml.contains("Finally."))
    }

    // MARK: - Parenthetical wrapping at writer level

    @Test func parentheticalWrappingAddsParensWhenMissing() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "P"); ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.parenthetical, "quietly"),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("<Text>(quietly)</Text>"))
    }

    @Test func parentheticalWrappingLeavesParensAlone() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "P2"); ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        addScene(to: ep, ctx: ctx, order: 0, elements: [
            (.parenthetical, "(beat)"),
        ])
        try ctx.save()
        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("<Text>(beat)</Text>"))
        #expect(!xml.contains("<Text>((beat))</Text>"))
    }
}
