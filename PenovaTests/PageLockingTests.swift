//
//  PageLockingTests.swift
//  PenovaTests
//
//  Once the writer locks a script for production, scene numbers must
//  STOP changing — even when scenes are added, removed, or reordered.
//  Final Draft / WriterDuet / Fade In all enforce this; pre-production
//  schedules and shooting boards reference the locked numbers, so
//  silent renumbering after lock breaks downstream trust.
//
//  Coverage:
//    • lock() snapshots the current numbering and flips the flag
//    • renderSceneNumber returns the frozen number for known scenes
//    • renderSceneNumber falls back to the live count for new (post-lock) scenes
//    • reordering after lock does NOT renumber existing scenes
//    • deleting after lock does NOT renumber survivors
//    • unlock() drops the snapshot and live numbering resumes
//    • re-lock refreshes the snapshot
//    • the production scene report and the PDF renderer both honour the lock
//

import Testing
import Foundation
import SwiftData
import PDFKit
@testable import Penova
@testable import PenovaKit

@MainActor
@Suite struct PageLockingTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self,
            configurations: config
        )
    }

    private func makeProjectWithScenes(_ count: Int, in ctx: ModelContext) throws -> (Project, Episode) {
        let p = Project(title: "Lockable"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0); ep.project = p
        p.episodes.append(ep); ctx.insert(ep)
        for i in 0..<count {
            let s = ScriptScene(locationName: "Loc\(i)", location: .interior, time: .day, order: i)
            s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            let h = SceneElement(kind: .heading, text: s.heading, order: 0)
            h.scene = s; s.elements.append(h); ctx.insert(h)
        }
        try ctx.save()
        return (p, ep)
    }

    // MARK: - Snapshot & flag

    @Test func lockFlipsFlagAndSnapshotsNumbers() throws {
        let container = try makeContainer()
        let (p, _) = try makeProjectWithScenes(3, in: container.mainContext)
        #expect(p.locked == false)
        #expect(p.lockedSceneNumbers == nil)

        p.lock()

        #expect(p.locked == true)
        #expect(p.lockedSceneNumbers?.count == 3)
        #expect(p.lockedAt != nil)
    }

    @Test func unlockClearsSnapshot() throws {
        let container = try makeContainer()
        let (p, _) = try makeProjectWithScenes(2, in: container.mainContext)
        p.lock()
        p.unlock()

        #expect(p.locked == false)
        #expect(p.lockedSceneNumbers == nil)
        #expect(p.lockedAt == nil)
    }

    // MARK: - Number resolution

    @Test func renderSceneNumberReturnsFrozenWhenLocked() throws {
        let container = try makeContainer()
        let (p, ep) = try makeProjectWithScenes(3, in: container.mainContext)
        p.lock()
        let scenes = ep.scenesOrdered
        // Snapshot says scene 0 → 1, scene 1 → 2, scene 2 → 3.
        #expect(p.renderSceneNumber(for: scenes[0], live: 99) == 1)
        #expect(p.renderSceneNumber(for: scenes[1], live: 99) == 2)
        #expect(p.renderSceneNumber(for: scenes[2], live: 99) == 3)
    }

    @Test func renderSceneNumberFallsBackToLiveWhenUnlocked() throws {
        let container = try makeContainer()
        let (p, ep) = try makeProjectWithScenes(2, in: container.mainContext)
        let s = ep.scenesOrdered[0]
        // Unlocked: returns whatever live counter was passed in.
        #expect(p.renderSceneNumber(for: s, live: 42) == 42)
    }

    @Test func renderSceneNumberFallsBackToLiveForNewScenesAfterLock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(2, in: ctx)
        p.lock()
        // Add a brand-new scene after lock.
        let s3 = ScriptScene(locationName: "Loc3", location: .interior, time: .day, order: 2)
        s3.episode = ep; ep.scenes.append(s3); ctx.insert(s3)
        try ctx.save()
        // Snapshot has no entry for s3 — falls through to the live
        // counter the caller is tracking.
        #expect(p.renderSceneNumber(for: s3, live: 3) == 3)
        #expect(p.renderSceneNumber(for: s3, live: 99) == 99)
    }

    // MARK: - Reordering / deletion safety

    @Test func reorderingAfterLockDoesNotRenumber() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(3, in: ctx)
        p.lock()
        // Swap orders of scene 0 and scene 2.
        let scenes = ep.scenesOrdered
        let s0 = scenes[0], s2 = scenes[2]
        s0.order = 99; s2.order = -1
        try ctx.save()

        // Locked numbers are still 1-2-3 keyed by ID, regardless of
        // current `.order`.
        #expect(p.renderSceneNumber(for: s0, live: 1) == 1)
        #expect(p.renderSceneNumber(for: s2, live: 3) == 3)
    }

    @Test func deletingAfterLockKeepsSurvivorNumbers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(3, in: ctx)
        p.lock()

        let scenes = ep.scenesOrdered
        let s0 = scenes[0], s1 = scenes[1], s2 = scenes[2]
        // Delete the middle scene.
        ctx.delete(s1)
        try ctx.save()

        // Survivors keep their original locked numbers (1, 3) — there
        // is no scene 2 anymore but s2 still renders as "3" not "2".
        #expect(p.renderSceneNumber(for: s0, live: 1) == 1)
        #expect(p.renderSceneNumber(for: s2, live: 2) == 3,
                "deletion silently renumbered the survivor — locked number ignored")
    }

    // MARK: - Re-lock idempotency

    @Test func reLockingRefreshesSnapshot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(2, in: ctx)
        p.lock()
        // Add a scene, re-lock — the new scene gets a number now.
        let s3 = ScriptScene(locationName: "Loc3", location: .interior, time: .day, order: 2)
        s3.episode = ep; ep.scenes.append(s3); ctx.insert(s3)
        try ctx.save()
        p.lock()  // re-lock

        #expect(p.lockedSceneNumbers?.count == 3)
        #expect(p.renderSceneNumber(for: s3, live: 99) == 3)
    }

    // MARK: - Multi-episode locking

    @Test func multiEpisodeLockResetsPerEpisode() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Two-Episode"); ctx.insert(p)
        for i in 0..<2 {
            let ep = Episode(title: "E\(i)", order: i); ep.project = p
            p.episodes.append(ep); ctx.insert(ep)
            for j in 0..<2 {
                let s = ScriptScene(locationName: "E\(i)L\(j)",
                                    location: .interior, time: .day, order: j)
                s.episode = ep; ep.scenes.append(s); ctx.insert(s)
            }
        }
        try ctx.save()
        p.lock()

        let ep0 = p.activeEpisodesOrdered[0]
        let ep1 = p.activeEpisodesOrdered[1]
        // Each episode resets to 1.
        #expect(p.renderSceneNumber(for: ep0.scenesOrdered[0], live: 99) == 1)
        #expect(p.renderSceneNumber(for: ep0.scenesOrdered[1], live: 99) == 2)
        #expect(p.renderSceneNumber(for: ep1.scenesOrdered[0], live: 99) == 1)
        #expect(p.renderSceneNumber(for: ep1.scenesOrdered[1], live: 99) == 2)
    }

    // MARK: - Scene report honours lock

    @Test func sceneReportUsesLockedNumbersWhenLocked() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(3, in: ctx)
        p.lock()
        // Delete the middle scene; the survivors keep their original
        // numbers in the production scene report.
        ctx.delete(ep.scenesOrdered[1])
        try ctx.save()
        let rows = ProductionReports.sceneReport(for: p)
        #expect(rows.count == 2)
        #expect(rows.map(\.sceneNumber) == [1, 3],
                "expected locked numbers [1,3] preserved; got \(rows.map(\.sceneNumber))")
    }

    @Test func sceneReportUsesLiveNumbersWhenUnlocked() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(3, in: ctx)
        ctx.delete(ep.scenesOrdered[1])
        try ctx.save()
        let rows = ProductionReports.sceneReport(for: p)
        #expect(rows.map(\.sceneNumber) == [1, 2],
                "unlocked: live numbers compact after delete")
    }

    // MARK: - PDF render honours lock

    @Test func renderedPDFContainsLockedSceneNumbers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let (p, ep) = try makeProjectWithScenes(3, in: ctx)
        // Add real headings + actions so the renderer emits scene
        // gutters (PDFKit needs body content).
        for s in ep.scenesOrdered {
            let a = SceneElement(kind: .action, text: "Beat.", order: 1)
            a.scene = s; s.elements.append(a); ctx.insert(a)
        }
        try ctx.save()

        p.lock()
        ctx.delete(ep.scenesOrdered[1])  // remove middle scene
        try ctx.save()

        let url = try ScriptPDFRenderer.render(project: p)
        defer { try? FileManager.default.removeItem(at: url) }
        guard let doc = PDFDocument(url: url) else {
            Issue.record("PDF unreadable"); return
        }
        // Scene 3 must still appear as "3." in the gutter — not "2."
        #expect(!doc.findString("3.", withOptions: .literal).isEmpty,
                "locked scene number 3 missing from rendered PDF")
    }
}
