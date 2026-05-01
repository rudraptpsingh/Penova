//
//  RevisionPageTests.swift
//  PenovaTests
//
//  Verifies the per-page revision detection used by
//  ScreenplayPDFRenderer's stripe / slug / asterisk rendering. These
//  indicators should appear ONLY on pages where the active revision
//  actually changed something — clean pages stay clean.
//
//  Strategy: build a small project, lock it, attach a revision,
//  stamp `lastRevisedRevisionID` on a single element, then drive the
//  layout planner via `ScreenplayPDFRenderer.makeRevisionPlan(for:)`
//  to assert which pages are flagged as revision pages.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct RevisionPageTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self,
            SceneElement.self, ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    private func makeProject(ctx: ModelContext, locked: Bool) -> Project {
        let p = Project(title: "Revision Test"); ctx.insert(p)
        let ep = Episode(title: "Pilot", order: 0)
        ep.project = p; p.episodes.append(ep); ctx.insert(ep)

        // Two scenes — one short, one with enough text to fill a page
        // so we can verify per-page detection works across page breaks.
        let s1 = ScriptScene(locationName: "KITCHEN", location: .interior, time: .day, order: 0)
        s1.episode = ep; ep.scenes.append(s1); ctx.insert(s1)
        let s1a = SceneElement(kind: .action, text: "Quiet morning beat.", order: 0)
        s1a.scene = s1; s1.elements.append(s1a); ctx.insert(s1a)

        let s2 = ScriptScene(locationName: "ROOFTOP", location: .exterior, time: .night, order: 1)
        s2.episode = ep; ep.scenes.append(s2); ctx.insert(s2)
        let s2a = SceneElement(kind: .action, text: "Wind. Then a long stare.", order: 0)
        s2a.scene = s2; s2.elements.append(s2a); ctx.insert(s2a)

        if locked { p.lock() }
        return p
    }

    // MARK: - Plan correctness

    @Test func cleanProjectHasNoRevisionPages() throws {
        let container = try makeContainer()
        let p = makeProject(ctx: container.mainContext, locked: true)
        try container.mainContext.save()
        let plan = ScreenplayPDFRenderer.makeRevisionPlan(project: p)
        #expect(plan.revisionPages.isEmpty,
                "no revision = no flagged pages")
    }

    @Test func unstampedElementDoesNotFlagPage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = makeProject(ctx: ctx, locked: true)
        // Active revision exists but no element references it.
        let rev = Revision(label: "Blue", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 2, wordCountAtSave: 0,
                           color: .blue, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)
        try ctx.save()

        let plan = ScreenplayPDFRenderer.makeRevisionPlan(project: p)
        #expect(plan.revisionPages.isEmpty,
                "no element references the revision id")
        #expect(plan.activeRevisionID == rev.id)
    }

    @Test func stampedElementFlagsItsPage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = makeProject(ctx: ctx, locked: true)
        let rev = Revision(label: "Blue", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 2, wordCountAtSave: 0,
                           color: .blue, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)

        // Stamp the FIRST scene's only element.
        let target = p.activeEpisodesOrdered.first!.scenesOrdered.first!.elementsOrdered.first!
        target.lastRevisedRevisionID = rev.id
        try ctx.save()

        let plan = ScreenplayPDFRenderer.makeRevisionPlan(project: p)
        #expect(!plan.revisionPages.isEmpty,
                "stamped element should flag at least one page")
        let flaggedPage = plan.pageByElement[target.id]
        #expect(flaggedPage != nil, "planner should have placed the stamped element")
        if let page = flaggedPage {
            #expect(plan.revisionPages.contains(page),
                    "the page hosting the stamped element must be flagged")
        }
    }

    @Test func unlockedProjectSuppressesIndicators() throws {
        // Production conventions only apply to locked drafts. An
        // unlocked project with a stamped element must NOT flag any
        // page — Penova treats that as a draft revision and renders
        // clean pages.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = makeProject(ctx: ctx, locked: false)
        let rev = Revision(label: "Pink", fountainSnapshot: "",
                           authorName: "Test", sceneCountAtSave: 2, wordCountAtSave: 0,
                           color: .pink, roundNumber: 2)
        rev.project = p; p.revisions.append(rev); ctx.insert(rev)

        let target = p.activeEpisodesOrdered.first!.scenesOrdered.first!.elementsOrdered.first!
        target.lastRevisedRevisionID = rev.id
        try ctx.save()

        let plan = ScreenplayPDFRenderer.makeRevisionPlan(project: p)
        #expect(plan.revisionPages.isEmpty,
                "unlocked project should never flag revision pages")
    }

    @Test func staleRevisionStampDoesNotFlag() throws {
        // An element stamped with a PRIOR revision id (not the active
        // one) is part of the previous revision's diff, not this
        // round's — must not flag the current page.
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = makeProject(ctx: ctx, locked: true)

        let oldRev = Revision(label: "White", fountainSnapshot: "",
                              authorName: "Test", sceneCountAtSave: 2, wordCountAtSave: 0,
                              color: .white, roundNumber: 1)
        oldRev.project = p; oldRev.createdAt = Date().addingTimeInterval(-3600)
        p.revisions.append(oldRev); ctx.insert(oldRev)

        let activeRev = Revision(label: "Blue", fountainSnapshot: "",
                                 authorName: "Test", sceneCountAtSave: 2, wordCountAtSave: 0,
                                 color: .blue, roundNumber: 2)
        activeRev.project = p; activeRev.createdAt = Date()
        p.revisions.append(activeRev); ctx.insert(activeRev)

        let target = p.activeEpisodesOrdered.first!.scenesOrdered.first!.elementsOrdered.first!
        target.lastRevisedRevisionID = oldRev.id   // stale
        try ctx.save()

        let plan = ScreenplayPDFRenderer.makeRevisionPlan(project: p)
        #expect(plan.activeRevisionID == activeRev.id)
        #expect(plan.revisionPages.isEmpty,
                "stale stamp should not flag the page for the new revision")
    }
}
