//
//  FeatureRequestTests.swift
//  PenovaTests
//
//  CRUD and business-logic tests for FeatureRequest + its enums.
//

import Testing
import SwiftData
@testable import Penova

@Suite("FeatureRequest")
struct FeatureRequestTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([FeatureRequest.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Init defaults

    @Test("Default status is pending and upvotes start at 1")
    func defaultValues() {
        let req = FeatureRequest(title: "Dark mode")
        #expect(req.status == .pending)
        #expect(req.upvotes == 1)
        #expect(req.body == "")
        #expect(req.category == .general)
    }

    @Test("ID is unique across instances")
    func uniqueIDs() {
        let a = FeatureRequest(title: "A")
        let b = FeatureRequest(title: "B")
        #expect(a.id != b.id)
    }

    // MARK: - CRUD

    @Test("Insert and fetch round-trip")
    func insertFetch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let req = FeatureRequest(title: "Voice search", category: .search)
        ctx.insert(req)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Voice search")
        #expect(fetched[0].category == .search)
    }

    @Test("Delete removes record")
    func deleteRecord() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let req = FeatureRequest(title: "Export to PDF")
        ctx.insert(req)
        try ctx.save()

        ctx.delete(req)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(fetched.isEmpty)
    }

    @Test("Upvote increments count")
    func upvote() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let req = FeatureRequest(title: "Collaboration")
        ctx.insert(req)
        try ctx.save()

        req.upvotes += 1
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(fetched[0].upvotes == 2)
    }

    @Test("Status transition persists")
    func statusTransition() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let req = FeatureRequest(title: "Cloud sync")
        ctx.insert(req)
        try ctx.save()

        req.status = .planned
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(fetched[0].status == .planned)
    }

    // MARK: - Enum display

    @Test("FeatureRequestCategory display strings")
    func categoryDisplay() {
        #expect(FeatureRequestCategory.editor.display == "Editor")
        #expect(FeatureRequestCategory.export.display == "Export & Share")
        #expect(FeatureRequestCategory.characters.display == "Characters")
        #expect(FeatureRequestCategory.search.display == "Search")
        #expect(FeatureRequestCategory.general.display == "General")
    }

    @Test("FeatureRequestStatus display strings")
    func statusDisplay() {
        #expect(FeatureRequestStatus.pending.display == "Pending")
        #expect(FeatureRequestStatus.planned.display == "Planned")
        #expect(FeatureRequestStatus.shipped.display == "Shipped")
    }

    // MARK: - Copy strings

    @Test("requestCount formats correctly")
    func requestCount() {
        #expect(Copy.featureRequests.requestCount(1) == "1 request")
        #expect(Copy.featureRequests.requestCount(0) == "0 requests")
        #expect(Copy.featureRequests.requestCount(5) == "5 requests")
    }
}
