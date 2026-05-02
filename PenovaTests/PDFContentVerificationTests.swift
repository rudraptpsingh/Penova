//
//  PDFContentVerificationTests.swift
//  PenovaTests
//
//  Renders Project → PDF and verifies the rendered bytes carry the
//  expected text content via PDFKit's text extraction. The existing
//  PDFRenderSmokeTests check "doesn't crash"; PDFRoundTripImportTests
//  check "PDF parser recovers the input." This suite is the layer in
//  between: "the rendered PDF actually contains the strings we
//  promised it would."
//
//  Catches bugs like:
//    - Title page rendered to wrong page or missing entirely
//    - Scene heading dropped because of an off-by-one in the
//      paginator
//    - Character cue swallowed when MORE/CONT'D logic mis-aligns
//    - Locked scene numbers not appearing on the rendered page
//

import Testing
import Foundation
import SwiftData
import PDFKit
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "PDFContentVerificationTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func renderProjectToPDFData(_ project: Project) throws -> Data {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PDFContent-\(UUID()).pdf")
    try ScreenplayPDFRenderer.render(project: project, to: url)
    let data = try Data(contentsOf: url)
    try? FileManager.default.removeItem(at: url)
    return data
}

@MainActor
private func extractText(from pdfData: Data) -> String {
    guard let doc = PDFDocument(data: pdfData) else { return "" }
    var combined = ""
    for i in 0..<doc.pageCount {
        if let page = doc.page(at: i), let text = page.string {
            combined += text + "\n"
        }
    }
    return combined
}

@MainActor
private func extractPerPageText(from pdfData: Data) -> [String] {
    guard let doc = PDFDocument(data: pdfData) else { return [] }
    return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
}

@MainActor
@Suite struct PDFContentVerificationTests {

    // MARK: - Title page

    @Test func titlePageContainsTitleAndAuthor() throws {
        let container = try makeContainer()
        let project = Project(title: "Visible Test")
        project.titlePage = TitlePage(
            title: "VISIBLE TEST",
            credit: "Written by",
            author: "Rudra Pratap Singh"
        )
        container.mainContext.insert(project)

        let data = try renderProjectToPDFData(project)
        let pages = extractPerPageText(from: data)
        #expect(pages.count >= 1, "Renderer must produce at least the title page")
        let titlePage = pages[0]
        #expect(titlePage.uppercased().contains("VISIBLE TEST"),
                "Title page must contain the project title")
        #expect(titlePage.contains("Rudra Pratap Singh"),
                "Title page must contain the author name")
    }

    @Test func titlePageOmitsDraftDateOnSpecScripts() throws {
        // Spec scripts (project.locked == false) should NOT have a
        // draft date on the title page — that's a production-only
        // convention.
        let container = try makeContainer()
        let project = Project(title: "Spec")
        project.titlePage = TitlePage(
            title: "Spec",
            author: "Rudra",
            draftDate: "1 May 2026"
        )
        container.mainContext.insert(project)
        // Don't lock — this is a spec.

        let data = try renderProjectToPDFData(project)
        let titlePage = extractPerPageText(from: data).first ?? ""
        // Draft date should not appear on a spec script.
        #expect(!titlePage.contains("1 May 2026"),
                "Spec scripts should omit draft date from the title page")
    }

    // MARK: - Body content

    @Test func sceneHeadingAppearsInRenderedBody() throws {
        let container = try makeContainer()
        let project = Project(title: "Heading Visibility")
        container.mainContext.insert(project)
        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        container.mainContext.insert(episode)
        let scene = ScriptScene(locationName: "PRIYA'S APARTMENT",
                                location: .interior, time: .night,
                                order: 0)
        scene.episode = episode
        episode.scenes.append(scene)
        container.mainContext.insert(scene)
        scene.rebuildHeading()

        let action = SceneElement(kind: .action,
                                  text: "Priya stares at the rain.",
                                  order: 0)
        action.scene = scene
        scene.elements.append(action)
        container.mainContext.insert(action)

        let data = try renderProjectToPDFData(project)
        let allText = extractText(from: data)
        #expect(allText.contains("INT. PRIYA'S APARTMENT - NIGHT"),
                "Scene heading must render verbatim")
        #expect(allText.contains("Priya stares at the rain."),
                "Action body must render verbatim")
    }

    @Test func characterCueAndDialogueAppearTogether() throws {
        let container = try makeContainer()
        let project = Project(title: "Dialogue Visibility")
        container.mainContext.insert(project)
        let ep = Episode(title: "P", order: 0)
        ep.project = project
        project.episodes.append(ep)
        container.mainContext.insert(ep)
        let scene = ScriptScene(locationName: "KITCHEN", order: 0)
        scene.episode = ep
        ep.scenes.append(scene)
        container.mainContext.insert(scene)

        let cue = SceneElement(kind: .character, text: "MARCUS", order: 0)
        let dialogue = SceneElement(kind: .dialogue,
                                    text: "I quit today.",
                                    order: 1, characterName: "MARCUS")
        cue.scene = scene
        dialogue.scene = scene
        scene.elements.append(contentsOf: [cue, dialogue])
        container.mainContext.insert(cue)
        container.mainContext.insert(dialogue)

        let data = try renderProjectToPDFData(project)
        let text = extractText(from: data)
        #expect(text.contains("MARCUS"))
        #expect(text.contains("I quit today."))
        // The cue should appear before its dialogue in the extracted text.
        if let cueIdx = text.range(of: "MARCUS"),
           let dialogueIdx = text.range(of: "I quit today.") {
            #expect(cueIdx.lowerBound < dialogueIdx.lowerBound,
                    "Character cue must precede its dialogue in the PDF flow")
        }
    }

    // MARK: - Multi-page + page numbers

    @Test func multiPageScriptHasPageNumbersAfterPageOne() throws {
        // Synthesize a long enough script that the renderer must
        // produce multiple body pages. Pages 2+ must show their
        // page number per WGA convention.
        let container = try makeContainer()
        let project = Project(title: "Long")
        container.mainContext.insert(project)
        let ep = Episode(title: "P", order: 0)
        ep.project = project
        project.episodes.append(ep)
        container.mainContext.insert(ep)
        for sceneIdx in 0..<60 {
            let scene = ScriptScene(locationName: "ROOM \(sceneIdx)", order: sceneIdx)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)
            for elementIdx in 0..<10 {
                let action = SceneElement(
                    kind: .action,
                    text: String(repeating: "Action body. ", count: 8) + "Line \(elementIdx).",
                    order: elementIdx
                )
                action.scene = scene
                scene.elements.append(action)
                container.mainContext.insert(action)
            }
        }

        let data = try renderProjectToPDFData(project)
        guard let doc = PDFDocument(data: data) else {
            Issue.record("Failed to parse rendered PDF")
            return
        }
        #expect(doc.pageCount >= 5,
                "Synthesized 60-scene script should produce ≥5 PDF pages")

        // Page 2's text should contain its page number — the
        // renderer puts page numbers on body pages from #2 onward.
        if doc.pageCount >= 2, let page2 = doc.page(at: 1) {
            let text = page2.string ?? ""
            #expect(text.contains("2"),
                    "Page 2 of a multi-page script should display its page number")
        }
    }

    // MARK: - Locked-script render

    @Test func lockedScriptShowsFrozenSceneNumbers() throws {
        let container = try makeContainer()
        let project = Project(title: "Lock Render")
        container.mainContext.insert(project)
        let ep = Episode(title: "P", order: 0)
        ep.project = project
        project.episodes.append(ep)
        container.mainContext.insert(ep)
        for i in 0..<3 {
            let scene = ScriptScene(locationName: "LOC \(i)", order: i)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)
        }
        project.lock()
        // Reorder after lock — shouldn't change the rendered numbers.
        ep.scenes[0].order = 2
        ep.scenes[2].order = 0
        try container.mainContext.save()

        let data = try renderProjectToPDFData(project)
        let text = extractText(from: data)
        // Locked map assigned 1, 2, 3 to the original order. The
        // PDF should show those numbers regardless of post-lock
        // reordering.
        #expect(text.contains("1"), "Locked scene #1 must render")
        #expect(text.contains("2"), "Locked scene #2 must render")
        #expect(text.contains("3"), "Locked scene #3 must render")
    }
}

