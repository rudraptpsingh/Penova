//
//  FreemiumLimitsTests.swift
//  PenovaTests
//
//  Covers the 1.1 freemium model: one active project at a time on free,
//  unlimited on pro. Archiving a project frees up the slot.
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self, Episode.self, ScriptScene.self, SceneElement.self, ScriptCharacter.self,
        configurations: config
    )
}

@MainActor
@Suite struct FreemiumLimitsTests {

    @Test func freeUserCanCreateFirstProject() throws {
        let check = FreemiumCheck(plan: .free, projects: [])
        guard case .allowed = check.canCreateProject() else {
            Issue.record("Free user with zero projects should be allowed.")
            return
        }
    }

    @Test func freeUserBlockedOnSecondActiveProject() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p1 = Project(title: "One"); ctx.insert(p1)
        let check = FreemiumCheck(plan: .free, projects: [p1])
        if case .allowed = check.canCreateProject() {
            Issue.record("Free user with an active project should not be allowed a second.")
        }
    }

    @Test func freeUserCanCreateAfterArchivingFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p1 = Project(title: "One", status: .archived); ctx.insert(p1)
        let check = FreemiumCheck(plan: .free, projects: [p1])
        guard case .allowed = check.canCreateProject() else {
            Issue.record("Archiving the only project should free the slot on free tier.")
            return
        }
    }

    @Test func proUserHasNoActiveProjectCeiling() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let many = (0..<25).map { i -> Project in
            let p = Project(title: "P\(i)"); ctx.insert(p); return p
        }
        let check = FreemiumCheck(plan: .pro, projects: many)
        guard case .allowed = check.canCreateProject() else {
            Issue.record("Pro tier should have no active-project ceiling.")
            return
        }
    }

    @Test func sceneCapIsNowGenerous() throws {
        // 1.1 model: no tight scene cap. Feature screenplays fit.
        let limits = FreemiumLimitsTable.limits(for: .free)
        #expect(limits.maxScenesPerProject >= 100)
    }
}
