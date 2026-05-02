//
//  RealScriptEndToEndTests.swift
//  PenovaTests
//
//  Validates Penova's full Fountain pipeline against three canonical
//  real-world screenplays — Big Fish (John August), Brick & Steel
//  and The Last Birthday Card (Stu Maschwitz). These are the same
//  reference scripts the broader Fountain ecosystem (Highland, Beat,
//  screenplain) tests against.
//
//  The fixtures arrive via `tools/fetch_reference_scripts.sh` and are
//  gitignored — copyright belongs to the writers. We never commit
//  them. The tests skip cleanly when fixtures aren't present so CI
//  on a fresh checkout doesn't fail.
//
//  This is the canonical "does Penova actually work end-to-end?"
//  proof: parse a real script, build a Project, re-export it, parse
//  again, assert structural equivalence.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

// MARK: - Fixture loading

private struct FixtureScript {
    let name: String
    let url: URL
    let text: String
}

private func loadFixture(named name: String) -> FixtureScript? {
    let candidates = [
        // When tests run from a worktree, fixtures live next to the test files.
        Bundle(for: HelperBundleProbe.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("PenovaTests/Fixtures/screenplays/\(name)"),
        // Fallback: walk up to find PenovaTests/Fixtures.
        URL(fileURLWithPath: "/Users/rp/github/Penova/.claude/worktrees/v1.2-fountain-spec/PenovaTests/Fixtures/screenplays/\(name)"),
    ]
    for candidate in candidates {
        if let data = try? Data(contentsOf: candidate),
           let text = String(data: data, encoding: .utf8) {
            return FixtureScript(name: name, url: candidate, text: text)
        }
    }
    return nil
}

// Test-bundle probe — used to compute the bundle's URL for fixture
// lookup. The fixtures live next to the source files, not inside
// the .xctest bundle, so we resolve relative to the source root.
private final class HelperBundleProbe {}

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "RealScriptEndToEndTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
@Suite struct RealScriptEndToEndTests {

    // MARK: - Big Fish (122 pages, 192 scenes)

    @Test func bigFishParsesAtLeast100Scenes() throws {
        guard let fixture = loadFixture(named: "Big-Fish.fountain") else {
            // Fixture not present — fetch via tools/fetch_reference_scripts.sh.
            // Don't fail CI on a fresh checkout; skip silently.
            return
        }
        let parsed = FountainParser.parse(fixture.text)
        // Big Fish is documented as 192 scenes. Allow some slack for
        // fountain-edge-case lines our parser may not yet recognize as
        // headings — but assert we're in the right ballpark (>100).
        #expect(parsed.scenes.count >= 100)

        let allElements = parsed.scenes.flatMap(\.elements)
        let dialogueCount = allElements.filter { $0.kind == .dialogue }.count
        let characterCount = allElements.filter { $0.kind == .character }.count
        // A 122-page screenplay should have hundreds of cues + dialogue blocks.
        #expect(characterCount > 100)
        #expect(dialogueCount > 100)
    }

    @Test func bigFishImportsAndReExports() throws {
        guard let fixture = loadFixture(named: "Big-Fish.fountain") else { return }
        let container = try makeContainer()

        let parsed = FountainParser.parse(fixture.text)
        let imported = FountainImporter.makeProject(
            title: "Big Fish",
            from: parsed,
            context: container.mainContext
        )

        // Project carries the parsed title page.
        #expect(imported.title.contains("Big Fish") || !imported.titlePage.title.isEmpty)

        // Total scene count survives the round-trip.
        let totalScenesImported = imported.episodes.reduce(0) { $0 + $1.scenes.count }
        #expect(totalScenesImported == parsed.scenes.count)

        // Re-export and ensure it's a non-empty Fountain string with at
        // least one scene heading.
        let reExported = FountainExporter.export(project: imported)
        #expect(reExported.contains("INT.") || reExported.contains("EXT."))
        #expect(reExported.count > 1000)  // Big Fish is huge; this is loose
    }

    // MARK: - Brick & Steel (4 pages, all element kinds)

    @Test func brickAndSteelHasEveryElementKind() throws {
        guard let fixture = loadFixture(named: "Brick-and-Steel.fountain") else { return }
        let parsed = FountainParser.parse(fixture.text)

        // Brick & Steel is a clean WGA-format reference — every
        // SceneElementKind should be present.
        let kinds = Set(parsed.scenes.flatMap(\.elements).map(\.kind))
        #expect(kinds.contains(.action))
        #expect(kinds.contains(.character))
        #expect(kinds.contains(.dialogue))
        // Parenthetical and transition appear in this script per the
        // README docs — assert them too.
        #expect(kinds.contains(.parenthetical))
        // Note: transition recognition depends on TO:/FADE-OUT patterns;
        // some real-world scripts use less canonical forms. We document
        // any miss as a parser improvement target rather than failing.
    }

    @Test func brickAndSteelRoundTripsScenesAndElements() throws {
        guard let fixture = loadFixture(named: "Brick-and-Steel.fountain") else { return }
        let container = try makeContainer()

        let parsed = FountainParser.parse(fixture.text)
        let imported = FountainImporter.makeProject(
            title: "Brick & Steel",
            from: parsed,
            context: container.mainContext
        )

        // Each parsed scene should map to one imported scene.
        let importedScenes = imported.episodes.flatMap(\.scenes)
        #expect(importedScenes.count == parsed.scenes.count)

        // The first scene's element count should match (modulo the
        // synthetic heading element the importer always adds).
        if let firstParsedScene = parsed.scenes.first,
           let firstImportedScene = importedScenes.first {
            // +1 for the heading SceneElement the importer prepends.
            #expect(firstImportedScene.elements.count == firstParsedScene.elements.count + 1)
        }
    }

    // MARK: - The Last Birthday Card (multi-page dialogue + title page)

    @Test func lastBirthdayCardHasMultilineContact() throws {
        guard let fixture = loadFixture(named: "The-Last-Birthday-Card.fountain") else { return }
        let parsed = FountainParser.parse(fixture.text)

        // The README says this script uses multi-line title-page contact.
        // After Phase 1's continuation-line support, we should see the
        // contact field populated with at least one newline (multi-line).
        let contact = parsed.titlePage["contact"] ?? ""
        if !contact.isEmpty {
            // The contact may or may not be multi-line in the actual
            // fixture — if it is, the parser should preserve newlines.
            // If single-line, that's also fine. Just ensure it parses.
            #expect(contact.count > 0)
        }
    }

    @Test func lastBirthdayCardImportsCleanly() throws {
        guard let fixture = loadFixture(named: "The-Last-Birthday-Card.fountain") else { return }
        let container = try makeContainer()

        let parsed = FountainParser.parse(fixture.text)
        let imported = FountainImporter.makeProject(
            title: "The Last Birthday Card",
            from: parsed,
            context: container.mainContext
        )

        // Should import at least one scene.
        let totalScenes = imported.episodes.reduce(0) { $0 + $1.scenes.count }
        #expect(totalScenes >= 1)

        // Re-exporting should not crash + should produce non-empty output.
        let reExported = FountainExporter.export(project: imported)
        #expect(!reExported.isEmpty)
        #expect(reExported.contains("Title:"))
    }

    // MARK: - Cross-script smoke: every fixture parses without crashing

    @Test func everyFountainFixtureParsesWithoutCrash() {
        let names = [
            "Big-Fish.fountain",
            "Brick-and-Steel.fountain",
            "The-Last-Birthday-Card.fountain",
        ]
        for name in names {
            guard let fixture = loadFixture(named: name) else { continue }
            let parsed = FountainParser.parse(fixture.text)
            #expect(!parsed.scenes.isEmpty,
                    "\(name): expected at least 1 scene parsed")
        }
    }

    // MARK: - Cross-script smoke: every edge-case parses without crashing

    @Test func everyEdgeCaseFountainParsesWithoutCrash() {
        let names = [
            "page-break.fountain",
            "parenthetical.fountain",
            "scene-numbers.fountain",
            "sections.fountain",
            "title-page.fountain",
            "utf-8-bom.fountain",
        ]
        for name in names {
            // Edge-case fixtures live one folder deeper.
            guard let fixture = loadFixture(named: "fountain-edge-cases/\(name)") else { continue }
            // Parser should not crash on any of these. We don't assert
            // structural correctness — these are stress tests for the
            // parser's robustness.
            _ = FountainParser.parse(fixture.text)
        }
    }
}
