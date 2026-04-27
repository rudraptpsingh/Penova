//
//  FeatureRequestTests.swift
//  PenovaTests
//
//  Covers the FeatureRequest SwiftData model: creation defaults, vote
//  toggling, deletion isolation, and the `rankedTop()` ordering used by
//  the "Top" tab on the FeatureRequestsScreen.
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self,
        Episode.self,
        ScriptScene.self,
        SceneElement.self,
        ScriptCharacter.self,
        FeatureRequest.self,
        configurations: config
    )
}

@MainActor
@Suite struct FeatureRequestTests {

    // MARK: - Creation

    @Test func newRequestAutoVotesAndIsOwned() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let r = FeatureRequest(title: "Index cards on iPad", category: .scenes)
        ctx.insert(r)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Index cards on iPad")
        #expect(fetched.first?.category == .scenes)
        #expect(fetched.first?.status == .submitted)
        // Author auto-votes for their own request.
        #expect(fetched.first?.voteCount == 1)
        #expect(fetched.first?.hasVoted == true)
        #expect(fetched.first?.submittedByThisDevice == true)
        // No maintainer reply yet.
        #expect(fetched.first?.maintainerNote.isEmpty == true)
    }

    @Test func nonOwnedRequestStartsAtZeroVotes() {
        let r = FeatureRequest(title: "Imported", submittedByThisDevice: false)
        #expect(r.voteCount == 0)
        #expect(r.hasVoted == false)
        #expect(r.submittedByThisDevice == false)
    }

    // MARK: - Voting

    @Test func toggleVoteRemovesAuthorOwnVote() {
        let r = FeatureRequest(title: "FDX import")
        // Starts at 1 / hasVoted = true (author auto-vote).
        r.toggleVote()
        #expect(r.voteCount == 0)
        #expect(r.hasVoted == false)
        // Toggle back on.
        r.toggleVote()
        #expect(r.voteCount == 1)
        #expect(r.hasVoted == true)
    }

    @Test func toggleVoteOnNonOwnedAddsAndRemoves() {
        let r = FeatureRequest(title: "Cloud sync", submittedByThisDevice: false)
        #expect(r.voteCount == 0)
        r.toggleVote()
        #expect(r.voteCount == 1)
        #expect(r.hasVoted == true)
        r.toggleVote()
        #expect(r.voteCount == 0)
        #expect(r.hasVoted == false)
    }

    @Test func voteCountClampsAtZero() {
        let r = FeatureRequest(title: "Edge case", submittedByThisDevice: false)
        // Force a desync — caller mutates voteCount but hasVoted is true,
        // simulating a corrupt-on-load row. Toggling off should clamp at 0
        // rather than going negative.
        r.hasVoted = true
        r.voteCount = 0
        r.toggleVote()
        #expect(r.voteCount == 0)
        #expect(r.hasVoted == false)
    }

    // MARK: - Persistence

    @Test func persistedToggleSurvivesRefetch() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let r = FeatureRequest(title: "Sticky note in scene")
        ctx.insert(r)
        try ctx.save()

        // Author un-votes their own request.
        r.toggleVote()
        try ctx.save()

        let again = try ctx.fetch(FetchDescriptor<FeatureRequest>()).first
        #expect(again?.hasVoted == false)
        #expect(again?.voteCount == 0)
        // Ownership is preserved.
        #expect(again?.submittedByThisDevice == true)
    }

    @Test func deletingRequestDoesNotTouchOthers() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let keep = FeatureRequest(title: "Keep", category: .editor)
        let drop = FeatureRequest(title: "Drop", category: .voice)
        ctx.insert(keep)
        ctx.insert(drop)
        try ctx.save()

        ctx.delete(drop)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<FeatureRequest>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Keep")
    }

    @Test func deletingProjectDoesNotTouchFeatureRequests() throws {
        // FeatureRequest lives in a separate root from Project — deleting
        // a project must not cascade into the feature-requests list.
        let container = try makeContainer()
        let ctx = container.mainContext

        let p = Project(title: "Some project")
        ctx.insert(p)
        let r = FeatureRequest(title: "Independent")
        ctx.insert(r)
        try ctx.save()

        ctx.delete(p)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<FeatureRequest>()).count == 1)
    }

    // MARK: - Ranking

    /// Live (.submitted, .underReview) outrank .planned, which outrank
    /// .shipped, which outrank .declined — regardless of vote count.
    @Test func rankedTopOrdersByStatusBucketFirst() {
        let live    = FeatureRequest(title: "Live",    status: .submitted)
        live.voteCount = 1
        let planned = FeatureRequest(title: "Planned", status: .planned)
        planned.voteCount = 999
        let shipped = FeatureRequest(title: "Shipped", status: .shipped)
        shipped.voteCount = 999
        let declined = FeatureRequest(title: "Declined", status: .declined)
        declined.voteCount = 999

        let ordered = [shipped, declined, planned, live].rankedTop()
        #expect(ordered.map(\.title) == ["Live", "Planned", "Shipped", "Declined"])
    }

    /// Within a status bucket: votes desc wins, then recency desc.
    @Test func rankedTopOrdersWithinBucketByVotesThenRecency() {
        let now = Date()
        let highOlder    = FeatureRequest(title: "high-old", status: .submitted)
        highOlder.voteCount = 10
        highOlder.createdAt = now.addingTimeInterval(-60)
        let highNewer    = FeatureRequest(title: "high-new", status: .submitted)
        highNewer.voteCount = 10
        highNewer.createdAt = now
        let low          = FeatureRequest(title: "low",      status: .submitted)
        low.voteCount = 1
        low.createdAt = now.addingTimeInterval(60)

        let ordered = [low, highOlder, highNewer].rankedTop()
        // Same vote count — newer first. Then the lower-vote row last.
        #expect(ordered.map(\.title) == ["high-new", "high-old", "low"])
    }

    @Test func rankedTopHandlesEmptyAndSingle() {
        let empty: [FeatureRequest] = []
        #expect(empty.rankedTop().isEmpty)
        let r = FeatureRequest(title: "Solo")
        #expect([r].rankedTop().map(\.title) == ["Solo"])
    }

    // MARK: - Schema

    @Test func featureRequestIsRegisteredInSchema() {
        let names = PenovaSchema.models.map { String(describing: $0) }
        #expect(names.contains("FeatureRequest"))
    }
}
