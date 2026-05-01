//
//  FountainExporterTests.swift
//  PenovaTests
//
//  Title-page emission coverage for FountainExporter — every documented
//  Fountain key emits when present, is skipped when empty, and
//  multi-line values get the 3-space continuation-line indentation
//  per fountain.io spec.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct FountainExporterTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self,
            ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    @Test func emitsAllSixDocumentedKeysWhenSet() throws {
        // Avoid bleed-through from a prior signed-in session.
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")

        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "")
        p.titlePage = TitlePage(
            title: "The Last Train",
            credit: "Written by",
            author: "Jane Writer",
            source: "Based on the novel by R.K.",
            draftDate: "1 May 2026",
            draftStage: "",
            contact: "jane@example.com",
            copyright: "© 2026 Jane Writer",
            notes: ""
        )
        ctx.insert(p)
        try ctx.save()

        let out = FountainExporter.export(project: p)
        #expect(out.contains("Title: The Last Train"))
        #expect(out.contains("Credit: Written by"))
        #expect(out.contains("Author: Jane Writer"))
        #expect(out.contains("Source: Based on the novel by R.K."))
        #expect(out.contains("Draft date: 1 May 2026"))
        #expect(out.contains("Contact: jane@example.com"))
    }

    @Test func skipsEmptyKeys() throws {
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "")
        p.titlePage = TitlePage(title: "Just a Title", credit: "Written by")
        ctx.insert(p)
        try ctx.save()

        let out = FountainExporter.export(project: p)
        #expect(out.contains("Title: Just a Title"))
        // No Author/Source/Contact/Draft date keys (each starts a line).
        #expect(!out.contains("\nAuthor:"))
        #expect(!out.contains("\nSource:"))
        #expect(!out.contains("\nContact:"))
        #expect(!out.contains("\nDraft date:"))
        // Title at file head doesn't have a leading "\n", but neither
        // would Author at file head — so also assert these don't appear
        // anywhere with the key prefix.
        #expect(!out.hasPrefix("Author:"))
        #expect(!out.hasPrefix("Source:"))
        #expect(!out.hasPrefix("Contact:"))
    }

    @Test func multilineContactGetsIndentedContinuations() throws {
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "")
        p.titlePage = TitlePage(
            title: "X",
            contact: "name@email.com\n+1 555 0100\nAgent: WME"
        )
        ctx.insert(p)
        try ctx.save()

        let out = FountainExporter.export(project: p)
        #expect(out.contains("Contact: name@email.com"))
        // Continuation lines: 3 leading spaces (or tab), per spec.
        #expect(out.contains("\n   +1 555 0100"))
        #expect(out.contains("\n   Agent: WME"))
    }

    @Test func draftDateOmittedWhenEmpty() throws {
        UserDefaults.standard.removeObject(forKey: "penova.auth.fullName")
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "")
        p.titlePage = TitlePage(title: "X", draftDate: "")
        ctx.insert(p)
        try ctx.save()
        let out = FountainExporter.export(project: p)
        #expect(!out.contains("Draft date:"))
    }
}
