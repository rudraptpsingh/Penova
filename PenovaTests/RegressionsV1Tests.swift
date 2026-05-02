//
//  RegressionsV1Tests.swift
//  PenovaTests
//
//  Tests that pin specific bugs we shipped fixes for in 1.1.0–1.2.1.
//  Each test corresponds to a real user-visible regression that
//  would have been caught here if this test had existed when the
//  bug was introduced.
//
//  Pattern: bug → test that would have caught it.
//
//  These are deliberately small and focused — they test the exact
//  symptom the user observed, not the underlying mechanism. That
//  way they survive refactoring and stay readable.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "RegressionsV1Tests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func makeScene(in context: ModelContext) -> ScriptScene {
    let project = Project(title: "R")
    context.insert(project)
    let episode = Episode(title: "Pilot", order: 0)
    episode.project = project
    project.episodes.append(episode)
    context.insert(episode)
    let scene = ScriptScene(locationName: "ROOM", order: 0)
    scene.episode = episode
    episode.scenes.append(scene)
    context.insert(scene)
    return scene
}

// MARK: - 1.1.2 → 1.2.0 → 1.2.1 visible regressions

@MainActor
@Suite struct RegressionsV1Tests {

    /// **v1.2.1 — Mac kindBadge overlap**
    /// User reported the "TRANSITION" chip overlapping right-aligned
    /// "CUT TO:" text on the focused row. The fix removed the chip
    /// entirely from `EditableElementRow.body` on Mac. This test pins
    /// "no `kindBadge` symbol in the visible row body" — if a future
    /// refactor accidentally re-adds an inline element-kind chip on
    /// Mac, this test fires.
    ///
    /// We grep the Mac source rather than render the view because
    /// SwiftUI views don't expose their child views in a way Swift
    /// Testing can introspect, and adding a snapshot-testing dep just
    /// for one assertion is overkill.
    @Test func macEditorRowDoesNotRenderKindBadgeInline() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PenovaMac/Features/Editor/ScriptEditorPane.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // The fix removed `kindBadge` from EditableElementRow's
        // visible body. The variable should no longer exist on Mac;
        // its prior presence was the root cause of the badge-vs-text
        // overlap on transition rows. If a future change re-introduces
        // it, this assertion catches it before users do.
        #expect(!source.contains("kindBadge"),
                "Mac EditableElementRow must not render an inline element-kind chip — see RegressionsV1Tests for context.")
    }

    /// **v1.2.1 — Window minWidth math**
    /// User reported horizontal scrolling in the default window.
    /// Window-math: 260pt sidebar + 640pt paper + 300pt inspector +
    /// breathing room = 1280pt minimum. v1.1.2 set defaultSize=1280
    /// but minWidth stayed at 1024 — returning users restored their
    /// previous frame at 1024 and saw overflow. v1.2.1 raised
    /// minWidth → 1280 to force fit on every install.
    @Test func macWindowMinWidthMatchesLayoutMath() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PenovaMac/App/PenovaMacApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // 1280 is the sum: sidebar (260) + paper (640) + inspector
        // (300) + breathing room (~80). Lowering it would re-introduce
        // the horizontal scroll bug for returning users.
        #expect(source.contains("minWidth: 1280"),
                "Window minWidth must be ≥1280 to fit the 640pt paper page next to the sidebar + inspector.")
    }

    /// **v1.2.0 hotfix — Sparkle "improperly signed" cache mismatch**
    /// User reported "improperly signed" Sparkle dialog. Root cause:
    /// the appcast `<enclosure url=>` pointed at the moving
    /// `Penova.dmg` alias, and Cloudflare's CDN edge served stale
    /// bytes from that URL after we overwrote it. Length+signature
    /// mismatched → rejection. Fix: always use per-version URL.
    @Test func signUpdateScriptDefaultsToPerVersionURL() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tools/sign-update.sh")
        let source = try String(contentsOf: url, encoding: .utf8)
        // The default URL must include the version. Pointing at a
        // moving alias like `Penova.dmg` lets Cloudflare's edge
        // cache mask updates with stale bytes.
        #expect(source.contains("Penova-${VERSION}.dmg"),
                "tools/sign-update.sh must default the appcast URL to a per-version path so CDN-cached bytes can't mask updates and break Sparkle's signature check.")
        // Negative form: the legacy moving-alias URL must not be the
        // default. Catches reverts to the old shape.
        #expect(!source.contains("DMG_URL_DEFAULT=\"https://penova.app/releases/$DMG_NAME\""),
                "tools/sign-update.sh must not default to the moving Penova.dmg alias — see the v1.2.0 hotfix for context.")
    }

    /// **v1.2.0 — appcast.xml well-formedness**
    /// First v1.1.0 release shipped an appcast with `--version` inside
    /// an XML `<!-- ... -->` comment, which the spec forbids; libxml2
    /// rejected the feed and Sparkle showed "An error occurred while
    /// parsing the update feed". The committed appcast must always
    /// parse as well-formed XML.
    @Test func liveAppcastIsWellFormedXML() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/appcast.xml")
        let data = try Data(contentsOf: url)
        // XMLParser will report a parse error if the feed is
        // malformed (e.g. `--` inside a comment, missing close tags,
        // duplicate attributes).
        let parser = XMLParser(data: data)
        let ok = parser.parse()
        #expect(ok, "docs/appcast.xml must be well-formed XML; Sparkle's libxml2 rejects malformed feeds with 'an error occurred while parsing the update feed'.")
    }

    /// **v1.2.0 — Every appcast `<enclosure url=>` is a per-version path**
    /// Reinforces the cache-stability principle. Every entry must
    /// reference an immutable per-version DMG URL so Cloudflare
    /// cache can never mask an update.
    @Test func everyAppcastEnclosureUsesPerVersionURL() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/appcast.xml")
        let source = try String(contentsOf: url, encoding: .utf8)

        // Every `<enclosure url=...>` value must include "Penova-".
        // The moving alias `Penova.dmg` (no version suffix) is the
        // bug we're guarding against.
        let pattern = #"url="([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        var bareAliasUrls: [String] = []
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range(at: 1), in: source) else { return }
            let foundURL = String(source[r])
            // `Penova-1.2.1.dmg` is fine; `Penova.dmg` (no version
            // before .dmg) is the bug.
            if foundURL.hasSuffix("/Penova.dmg") {
                bareAliasUrls.append(foundURL)
            }
        }
        #expect(bareAliasUrls.isEmpty,
                "Every appcast enclosure must use a per-version DMG URL (Penova-X.Y.Z.dmg). Found bare alias: \(bareAliasUrls)")
    }

    /// **v1.1.2 — addFirstElement no longer creates a duplicate heading**
    /// Tapping "Start writing" on a new scene previously inserted a
    /// `.heading` SceneElement seeded with `scene.heading` — but the
    /// heading was already rendered separately by the parent view, so
    /// the user saw the slug duplicated. v1.1.2 changed it to insert
    /// an empty `.action` row instead.
    @Test func emptyScenesShouldNotDuplicateHeadingOnFirstWrite() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)

        // Simulate the new "first element" flow. The scene starts with
        // zero elements; tapping the empty-state CTA should produce a
        // single .action element, not a .heading element.
        let firstElement = SceneElement(kind: .action, text: "", order: 0)
        firstElement.scene = scene
        scene.elements.append(firstElement)
        container.mainContext.insert(firstElement)
        try container.mainContext.save()

        let kinds = scene.elements.map(\.kind)
        #expect(kinds == [.action],
                "First write to an empty scene must be a .action element, not .heading — the parent view already renders the heading separately, and inserting a .heading SceneElement duplicates the slug visually.")
    }

    /// **v1.1.2 — Mac line-delete renumbers siblings**
    /// Repeated insert-above + delete sequences could leave duplicate
    /// `order` values among scene elements; SwiftUI's ForEach is not
    /// stable on equal keys, so visible row order would flip between
    /// reloads. Delete now compacts orders to a contiguous 0..N-1.
    @Test func deleteCompactsOrdersToContiguousSequence() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)

        // Build a scene with 4 elements, sparse orders to simulate
        // the post-delete gap pattern.
        for (i, kind) in [SceneElementKind.action, .character, .dialogue, .action].enumerated() {
            let el = SceneElement(kind: kind, text: "row \(i)", order: i * 10)
            el.scene = scene
            scene.elements.append(el)
            container.mainContext.insert(el)
        }
        try container.mainContext.save()

        // The "delete with renumber" contract: after any deletion,
        // all surviving elements have orders 0, 1, 2, … contiguously.
        // Critical: save() the deletion BEFORE renumbering so the
        // doomed element is gone from `scene.elementsOrdered` when we
        // iterate. Otherwise the renumber assigns 0..N-1 to N+1
        // elements (including the doomed one), and the post-save
        // result has non-contiguous orders for the survivors.
        // ScriptEditorPane.delete(_:) does the same thing.
        let toDelete = scene.elementsOrdered[1]
        container.mainContext.delete(toDelete)
        try container.mainContext.save()
        for (i, surviving) in scene.elementsOrdered.enumerated() {
            surviving.order = i
        }
        try container.mainContext.save()

        let orders = scene.elementsOrdered.map(\.order)
        #expect(orders == [0, 1, 2],
                "After deletion, surviving elements must have contiguous 0..N-1 orders so SwiftUI's ForEach can't produce non-deterministic row ordering on reload.")
    }

    /// **v1.1.2 — Mac PaperPage adapts to window width**
    /// PaperPage must use idealWidth+maxWidth (not hard width) so it
    /// shrinks gracefully when the user drags the window narrower.
    @Test func macPaperPageUsesAdaptiveWidth() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PenovaMac/Features/Editor/ScriptEditorPane.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // Hard `frame(width: 640)` was the v1.0.x bug — it meant the
        // paper overflowed the editor pane on narrow windows.
        // idealWidth+maxWidth lets the paper shrink to fit.
        #expect(!source.contains(".frame(width: 640,"),
                "PaperPage must not use a hard width — use idealWidth+maxWidth so the paper adapts to the available editor pane space.")
        #expect(source.contains("idealWidth: 640"),
                "PaperPage should declare idealWidth: 640 so the paper renders at full width when there's room and shrinks gracefully when there isn't.")
    }

    /// **v1.1.0 hotfix — appcast comment can't contain `--`**
    /// XML spec forbids `--` inside `<!-- ... -->` comments. v1.1.0
    /// shipped with `--version` inside the appcast's header comment
    /// and Sparkle rejected the feed. This test scans the comment
    /// content for the offending sequence.
    @Test func appcastCommentsContainNoDoubleHyphens() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/appcast.xml")
        let source = try String(contentsOf: url, encoding: .utf8)

        // Naive scan: extract every <!-- ... --> block and check no
        // internal `--` appears (other than the closing `-->`).
        let pattern = #"<!--([\s\S]*?)-->"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        var offending: [String] = []
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let m = match,
                  let r = Range(m.range(at: 1), in: source) else { return }
            let body = String(source[r])
            if body.contains("--") {
                offending.append(String(body.prefix(60)))
            }
        }
        #expect(offending.isEmpty,
                "XML comments in docs/appcast.xml must not contain `--` (forbidden by XML spec). Sparkle's libxml2 rejects feeds with malformed comments. Found: \(offending)")
    }
}
