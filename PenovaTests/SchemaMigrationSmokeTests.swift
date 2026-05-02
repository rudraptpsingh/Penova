//
//  SchemaMigrationSmokeTests.swift
//  PenovaTests
//
//  Foundational tests for SwiftData schema evolution. v1.2.0 added
//  the `PenovaSchema.SchemaV1: VersionedSchema` + `PenovaMigrationPlan`
//  scaffolding; today the plan has zero stages because every property
//  shipped through 1.x has been an Optional-with-default that
//  SwiftData migrates lightweight automatically.
//
//  These tests pin THAT contract:
//    - Adding a new optional property to a model must not break
//      existing stores (tested by re-loading a v1-shaped store
//      with the live schema).
//    - The MigrationPlan stays empty until we add a v2 schema.
//    - The container can be built repeatedly against the same
//      on-disk store without losing data.
//
//  When v2 lands, this file gets a sibling `SchemaV1ToV2MigrationTests`
//  that tests the actual migration code.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
@Suite struct SchemaMigrationSmokeTests {

    /// **MigrationPlan stays empty at V1**
    /// We're at version 1.0.0. Until we ship a V2 with a renamed/
    /// removed property, the migration plan must be empty — adding
    /// a stage prematurely would cause SwiftData to think there's
    /// historical data to upgrade where there isn't.
    @Test func migrationPlanHasNoStagesAtV1() {
        #expect(PenovaMigrationPlan.stages.isEmpty)
        #expect(PenovaMigrationPlan.schemas.count == 1)
    }

    /// **Container restart preserves data** — the most basic
    /// migration-readiness check. Build a store with the live schema,
    /// write data, drop the container, rebuild against the same
    /// store with the same schema, verify the data is there.
    @Test func containerRestartPreservesAllData() throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Penova-MigrationSmoke-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let schema = Schema(PenovaSchema.models)

        // First container — write data.
        do {
            let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PenovaMigrationPlan.self,
                configurations: [config]
            )
            let project = Project(title: "Migration Smoke",
                                  logline: "Should survive restart.",
                                  genre: [.drama, .thriller])
            project.titlePage = TitlePage(
                title: "Migration Smoke",
                author: "Test",
                contact: "test@example.com"
            )
            container.mainContext.insert(project)

            let ep = Episode(title: "Pilot", order: 0)
            ep.project = project
            project.episodes.append(ep)
            container.mainContext.insert(ep)

            let scene = ScriptScene(locationName: "ROOM", order: 0)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)

            project.lock()
            try container.mainContext.save()
        }

        // Second container against the same store — verify everything.
        do {
            let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PenovaMigrationPlan.self,
                configurations: [config]
            )
            let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
            #expect(projects.count == 1)
            let p = projects.first
            #expect(p?.title == "Migration Smoke")
            #expect(p?.logline == "Should survive restart.")
            #expect(p?.genre == [.drama, .thriller])
            #expect(p?.locked == true)
            #expect(p?.titlePage.author == "Test")
            #expect(p?.titlePage.contact == "test@example.com")

            let scenes = try container.mainContext.fetch(FetchDescriptor<ScriptScene>())
            #expect(scenes.count == 1)
        }
    }

    /// **Multiple consecutive container builds don't corrupt the store**
    /// Open / close / open / close ten times. Final state must match
    /// what we wrote on the first iteration. This catches bugs where
    /// SwiftData would re-migrate or re-init unnecessarily and break
    /// data along the way.
    @Test func tenSuccessiveContainerOpensPreserveData() throws {
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Penova-Successive-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let schema = Schema(PenovaSchema.models)

        // First open: write.
        do {
            let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PenovaMigrationPlan.self,
                configurations: [config]
            )
            let p = Project(title: "Repeated Opens")
            container.mainContext.insert(p)
            try container.mainContext.save()
        }

        // Then 9 more opens — each must find the same project.
        for _ in 0..<9 {
            let config = ModelConfiguration("Penova", schema: schema, url: storeURL)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: PenovaMigrationPlan.self,
                configurations: [config]
            )
            let projects = try container.mainContext.fetch(FetchDescriptor<Project>())
            #expect(projects.count == 1)
            #expect(projects.first?.title == "Repeated Opens")
        }
    }

    /// **Schema list contains every shipped @Model**
    /// If a future @Model is added but not registered in
    /// `PenovaSchema.SchemaV1.models`, SwiftData won't know to
    /// persist it. This test enumerates the expected model names
    /// and pins them; adding a new model is a deliberate change.
    @Test func schemaContainsExpectedModels() {
        let actual = Set(PenovaSchema.models.map { String(describing: $0) })
        let expected: Set<String> = [
            "Project",
            "Episode",
            "ScriptScene",
            "SceneElement",
            "ScriptCharacter",
            "WritingDay",
            "Revision",
        ]
        #expect(actual == expected,
                "Schema models drifted from the pinned set. New @Models must also be registered in PenovaSchema.SchemaV1.")
    }

    /// **Schema version doesn't drift accidentally**
    /// Bumping the version triggers SwiftData's migration logic.
    /// Pin the current version so an accidental bump is caught.
    @Test func schemaVersionIsExactly1_0_0() {
        #expect(PenovaSchema.SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }
}
