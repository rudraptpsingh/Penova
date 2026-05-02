//
//  PenovaMigrationPlanTests.swift
//  PenovaTests
//
//  Pins the SwiftData schema migration scaffolding so the first time
//  a future release renames or removes a model property, the
//  migration plan is already wired up — no scrambling to declare a
//  VersionedSchema after a returning user has hit a launch crash.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
@Suite struct PenovaMigrationPlanTests {

    @Test func schemaV1HasEverySharedModel() {
        let names = PenovaSchema.SchemaV1.models.map { String(describing: $0) }
        // Every persisted model has to be in V1 — leaving one out of
        // the schema would mean SwiftData doesn't know to migrate it.
        #expect(names.contains("Project"))
        #expect(names.contains("Episode"))
        #expect(names.contains("ScriptScene"))
        #expect(names.contains("SceneElement"))
        #expect(names.contains("ScriptCharacter"))
        #expect(names.contains("WritingDay"))
        #expect(names.contains("Revision"))
    }

    @Test func schemaV1AndAggregateAreIdentical() {
        // PenovaSchema.models is the public alias; it must always
        // resolve to the latest VersionedSchema's models so callers
        // (App.init paths) always pick up new models without code
        // changes.
        let v1Names = Set(PenovaSchema.SchemaV1.models.map { String(describing: $0) })
        let aggNames = Set(PenovaSchema.models.map { String(describing: $0) })
        #expect(v1Names == aggNames)
    }

    @Test func versionIdentifierIsPinned() {
        // Renaming the version triggers SwiftData's migration logic.
        // We test the identifier is exactly 1.0.0 to catch accidental
        // bumps that would invalidate every existing user store.
        let id = PenovaSchema.SchemaV1.versionIdentifier
        #expect(id == Schema.Version(1, 0, 0))
    }

    @Test func migrationPlanContainsV1Schema() {
        let names = PenovaMigrationPlan.schemas.map { String(describing: $0) }
        #expect(names.contains("SchemaV1"))
    }

    @Test func migrationPlanHasNoStagesYet() {
        // We're at V1 with no historical migrations. The first time
        // we add a new VersionedSchema we'll add a MigrationStage to
        // this list, and this test will need to be updated to reflect
        // the new expected shape — flagging migration work explicitly.
        #expect(PenovaMigrationPlan.stages.isEmpty)
    }

    @Test func containerCreatesWithMigrationPlan() throws {
        // The real value of MigrationPlan is that ModelContainer
        // accepts it without throwing. This test pins the integration:
        // if a property is added and forgotten in the SchemaV1 list,
        // ModelContainer will fail to instantiate when it tries to
        // resolve the model graph.
        let schema = Schema(PenovaSchema.models)
        let config = ModelConfiguration(
            "PenovaMigrationPlanTests",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PenovaMigrationPlan.self,
            configurations: [config]
        )
        // Container is constructed; we can insert a Project without
        // a migration error.
        let ctx = ModelContext(container)
        let project = Project(title: "Migration Smoke")
        ctx.insert(project)
        try ctx.save()

        let count = try ctx.fetchCount(FetchDescriptor<Project>())
        #expect(count == 1)
    }
}
