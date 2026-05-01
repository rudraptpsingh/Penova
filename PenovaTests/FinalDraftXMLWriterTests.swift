//
//  FinalDraftXMLWriterTests.swift
//  PenovaTests
//
//  Builds a tiny project tree, runs FinalDraftXMLWriter, and asserts the
//  output contains the expected top-level element and one Paragraph Type
//  attribute for each of the six screenplay element kinds. We don't parse
//  the XML — string-contains is sufficient to guard against regressions
//  in the serializer.
//

import Testing
import Foundation
import SwiftData
import PenovaKit
@testable import Penova

@MainActor
@Suite struct FinalDraftXMLWriterTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    @Test func emitsAllParagraphTypes() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "FDX Smoke", logline: "Tiny.", genre: [.drama])
        ctx.insert(project)

        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)

        let scene = ScriptScene(locationName: "Diner", location: .interior, time: .night, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)

        let elements: [SceneElement] = [
            SceneElement(kind: .heading,       text: "INT. DINER - NIGHT",  order: 0),
            SceneElement(kind: .action,        text: "Maya enters.",         order: 1),
            SceneElement(kind: .character,     text: "MAYA",                 order: 2),
            SceneElement(kind: .parenthetical, text: "quietly",              order: 3),
            SceneElement(kind: .dialogue,      text: "You're late.",         order: 4, characterName: "MAYA"),
            SceneElement(kind: .transition,    text: "CUT TO:",              order: 5),
        ]
        for el in elements {
            el.scene = scene; scene.elements.append(el); ctx.insert(el)
        }
        try ctx.save()

        let xml = FinalDraftXMLWriter.xml(for: project)

        #expect(xml.contains("<FinalDraft"))
        #expect(xml.contains("<Content>"))
        #expect(xml.contains("</FinalDraft>"))
        #expect(xml.contains("Paragraph Type=\"Scene Heading\""))
        #expect(xml.contains("Paragraph Type=\"Action\""))
        #expect(xml.contains("Paragraph Type=\"Character\""))
        #expect(xml.contains("Paragraph Type=\"Dialogue\""))
        #expect(xml.contains("Paragraph Type=\"Parenthetical\""))
        #expect(xml.contains("Paragraph Type=\"Transition\""))
        // Apostrophe escaping.
        #expect(xml.contains("You&apos;re late."))
        // Parenthetical wrapping.
        #expect(xml.contains("<Text>(quietly)</Text>"))
        // Character cue uppercased.
        #expect(xml.contains("<Text>MAYA</Text>"))
    }

    @Test func escapesXMLMetaCharacters() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Esc & Co <Test>", logline: "", genre: [.drama])
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "Office", location: .interior, time: .day, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        let el = SceneElement(kind: .action, text: "A & B <c> \"d\" 'e'", order: 0)
        el.scene = scene; scene.elements.append(el); ctx.insert(el)
        try ctx.save()

        let xml = FinalDraftXMLWriter.xml(for: project)
        #expect(xml.contains("A &amp; B &lt;c&gt; &quot;d&quot; &apos;e&apos;"))
    }

    @Test func writesFileWithValidPrefix() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Writes File")
        ctx.insert(project)
        let ep = Episode(title: "E1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "Park", location: .exterior, time: .day, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        try ctx.save()

        let url = try FinalDraftXMLWriter.write(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
        #expect(url.pathExtension == "fdx")
        let head = String(data: data.prefix(64), encoding: .utf8) ?? ""
        #expect(head.hasPrefix("<?xml"))
    }
}
