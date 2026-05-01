//
//  TitlePageTests.swift
//  PenovaTests
//
//  Direct coverage of the TitlePage value type, the Project.titlePage
//  computed accessor's v1.0 → v1.1 hydration, and the
//  revisionHistoryEntries projection used by the production-draft
//  footer.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit
@testable import Penova

@MainActor
@Suite struct TitlePageTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Project.self, Episode.self, ScriptScene.self, SceneElement.self,
            ScriptCharacter.self, WritingDay.self, Revision.self,
            configurations: config
        )
    }

    // MARK: - Codable round-trip

    @Test func titlePageEncodesAndDecodes() throws {
        let tp = TitlePage(
            title: "The Last Train",
            credit: "Written by",
            author: "Jane Writer",
            source: "Based on the novel by R.K.",
            draftDate: "1 May 2026",
            draftStage: "Production Draft",
            contact: "jane@example.com\n+1 555 0100",
            copyright: "© 2026 Jane Writer",
            notes: "WGA Reg #12345"
        )
        let data = try JSONEncoder().encode(tp)
        let decoded = try JSONDecoder().decode(TitlePage.self, from: data)
        #expect(decoded == tp)
    }

    @Test func defaultsAreSensible() {
        let tp = TitlePage()
        #expect(tp.title == "")
        #expect(tp.credit == "Written by")
        #expect(tp.author == "")
        #expect(tp.source == "")
        #expect(tp.contact == "")
    }

    // MARK: - Lazy hydration from v1.0 fields

    @Test func lazyHydratesFromLegacyTitleAndContactBlock() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Legacy Title")
        p.contactBlock = "old@email.com\n+1 555 0100"
        ctx.insert(p)
        try ctx.save()

        // titlePageData was never set — the accessor should hydrate
        // from the legacy columns.
        #expect(p.titlePageData == nil)
        let tp = p.titlePage
        #expect(tp.title == "Legacy Title")
        #expect(tp.credit == "Written by")
        #expect(tp.contact == "old@email.com\n+1 555 0100")
    }

    @Test func setterPersistsAndKeepsLegacyFieldsInSync() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Old")
        ctx.insert(p)
        try ctx.save()

        p.titlePage = TitlePage(
            title: "New Title",
            credit: "Story by",
            author: "Ada",
            contact: "ada@example.com"
        )
        try ctx.save()

        #expect(p.titlePageData != nil)
        #expect(p.title == "New Title")           // legacy mirror
        #expect(p.contactBlock == "ada@example.com")
        // Reading back via the accessor returns stored value, not hydration
        let read = p.titlePage
        #expect(read.author == "Ada")
        #expect(read.credit == "Story by")
    }

    // MARK: - Revision history entries

    @Test func revisionHistoryEntriesSortedOldestFirst() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Series")
        ctx.insert(p)

        let r1 = Revision(label: "First",
                          fountainSnapshot: "",
                          authorName: "x",
                          sceneCountAtSave: 0,
                          wordCountAtSave: 0,
                          color: .white)
        r1.createdAt = Date(timeIntervalSince1970: 1_000_000)
        let r2 = Revision(label: "Second",
                          fountainSnapshot: "",
                          authorName: "x",
                          sceneCountAtSave: 0,
                          wordCountAtSave: 0,
                          color: .blue)
        r2.createdAt = Date(timeIntervalSince1970: 2_000_000)
        let r3 = Revision(label: "Third",
                          fountainSnapshot: "",
                          authorName: "x",
                          sceneCountAtSave: 0,
                          wordCountAtSave: 0,
                          color: .pink)
        r3.createdAt = Date(timeIntervalSince1970: 3_000_000)

        // Insert intentionally out of order — projection must sort.
        for r in [r3, r1, r2] {
            r.project = p
            p.revisions.append(r)
            ctx.insert(r)
        }
        try ctx.save()

        let entries = p.revisionHistoryEntries
        #expect(entries.count == 3)
        #expect(entries[0].label == "WHITE REVISION")
        #expect(entries[1].label == "BLUE REVISION")
        #expect(entries[2].label == "PINK REVISION")
        // Strictly oldest-first by date.
        #expect(entries[0].date < entries[1].date)
        #expect(entries[1].date < entries[2].date)
    }

    @Test func revisionHistoryEmptyWhenNoRevisions() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let p = Project(title: "Empty")
        ctx.insert(p)
        try ctx.save()
        #expect(p.revisionHistoryEntries.isEmpty)
    }
}
