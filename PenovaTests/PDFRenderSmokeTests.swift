//
//  PDFRenderSmokeTests.swift
//  PenovaTests
//
//  Invokes ScriptPDFRenderer on a small Project+Scene tree and asserts it
//  produces a non-empty PDF file. We don't parse the PDF.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct PDFRenderSmokeTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
            configurations: config
        )
    }

    @Test func rendersNonEmptyPDF() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let project = Project(title: "Smoke Test", logline: "A tiny script.", genre: [.drama])
        ctx.insert(project)

        let ep = Episode(title: "Pilot", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)

        let scene = ScriptScene(locationName: "Coffee Shop", location: .interior, time: .day, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)

        let heading = SceneElement(kind: .heading, text: scene.heading, order: 0)
        let action = SceneElement(kind: .action, text: "JANE sips her latte.", order: 1)
        let character = SceneElement(kind: .character, text: "JANE", order: 2)
        let dialogue = SceneElement(kind: .dialogue, text: "It's cold.", order: 3, characterName: "JANE")
        for el in [heading, action, character, dialogue] {
            el.scene = scene
            scene.elements.append(el)
            ctx.insert(el)
        }
        try ctx.save()

        // Make sure the author fallback is exercised (key is either set or not).
        UserDefaults.standard.set("Test Author", forKey: "penova.auth.fullName")
        defer { UserDefaults.standard.removeObject(forKey: "penova.auth.fullName") }

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
        // Valid PDFs start with "%PDF-".
        let prefix = data.prefix(5)
        #expect(prefix == Data("%PDF-".utf8))
    }

    @Test func rendersWithMissingAuthorName() throws {
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")

        let container = try makeContainer()
        let ctx = container.mainContext
        let project = Project(title: "Anonymous")
        ctx.insert(project)
        let ep = Episode(title: "Ep 1", order: 0)
        ep.project = project; project.episodes.append(ep); ctx.insert(ep)
        let scene = ScriptScene(locationName: "Desert", location: .exterior, time: .night, order: 0)
        scene.episode = ep; ep.scenes.append(scene); ctx.insert(scene)
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: project)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)
    }
}
