//
//  FeatureRequestsScreen.swift
//  Penova
//
//  "Suggest a feature" hub. Users post what they'd like to see, +1 the
//  ideas they want most, and watch their list move from "Submitted" to
//  "Planned" to "Shipped" as the maintainer triages.
//
//  Sort tabs:
//    Top     — live requests first, then by votes desc, then recency desc.
//    Recent  — pure recency, newest at the top, regardless of status.
//    Mine    — only requests this device submitted.
//

import SwiftUI
import SwiftData

struct FeatureRequestsScreen: View {
    enum SortTab: Hashable { case top, recent, mine }

    @Environment(\.modelContext) private var context
    @Query(sort: \FeatureRequest.createdAt, order: .reverse)
    private var requests: [FeatureRequest]

    @State private var tab: SortTab = .top
    @State private var showNewSheet = false

    private var filtered: [FeatureRequest] {
        switch tab {
        case .top:    return requests.rankedTop()
        case .recent: return requests   // already sorted by createdAt desc
        case .mine:   return requests.filter(\.submittedByThisDevice)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    Text(Copy.featureRequests.intro)
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow3)
                    tabRow
                    if filtered.isEmpty {
                        emptyState
                            .padding(.top, PenovaSpace.xl)
                    } else {
                        VStack(spacing: PenovaSpace.m) {
                            ForEach(filtered) { request in
                                NavigationLink(value: request) {
                                    FeatureRequestRow(request: request) {
                                        toggleVote(on: request)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, PenovaSpace.l)
                .padding(.vertical, PenovaSpace.m)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(Copy.featureRequests.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FeatureRequest.self) { request in
                FeatureRequestDetailScreen(request: request)
            }

            PenovaFAB(icon: .plus) { showNewSheet = true }
                .padding(PenovaSpace.l)
                .accessibilityLabel(Copy.featureRequests.newRequestCta)
        }
        .sheet(isPresented: $showNewSheet) {
            NewFeatureRequestSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var tabRow: some View {
        HStack(spacing: PenovaSpace.s) {
            PenovaChip(text: Copy.featureRequests.tabTop,    isSelected: tab == .top)    { tab = .top }
            PenovaChip(text: Copy.featureRequests.tabRecent, isSelected: tab == .recent) { tab = .recent }
            PenovaChip(text: Copy.featureRequests.tabMine,   isSelected: tab == .mine)   { tab = .mine }
            Spacer()
        }
    }

    private var emptyState: some View {
        let isMine = tab == .mine
        return EmptyState(
            icon: .bookmark,
            title: isMine ? Copy.featureRequests.emptyMineTitle : Copy.featureRequests.emptyTitle,
            message: isMine ? Copy.featureRequests.emptyMineBody : Copy.featureRequests.emptyBody,
            ctaTitle: isMine ? nil : Copy.featureRequests.newRequestCta,
            ctaAction: isMine ? nil : { showNewSheet = true }
        )
    }

    private func toggleVote(on request: FeatureRequest) {
        request.toggleVote()
        try? context.save()
    }
}

// MARK: - Row

struct FeatureRequestRow: View {
    @Bindable var request: FeatureRequest
    let onVote: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PenovaSpace.m) {
            voteColumn
            VStack(alignment: .leading, spacing: PenovaSpace.s) {
                HStack(spacing: PenovaSpace.s) {
                    PenovaTag(text: request.category.display)
                    statusTag
                    Spacer(minLength: 0)
                }
                Text(request.title)
                    .font(PenovaFont.bodyLarge)
                    .foregroundStyle(PenovaColor.snow)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if !request.detail.isEmpty {
                    Text(request.detail)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PenovaSpace.m)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private var voteColumn: some View {
        Button(action: onVote) {
            VStack(spacing: PenovaSpace.xs) {
                Image(systemName: request.hasVoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(request.hasVoted ? PenovaColor.amber : PenovaColor.snow3)
                Text("\(request.voteCount)")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(request.hasVoted ? PenovaColor.amber : PenovaColor.snow)
            }
            .frame(width: 40, height: 48)
            .background(request.hasVoted ? PenovaColor.amber.opacity(0.12) : PenovaColor.ink3)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: request.hasVoted)
        .accessibilityLabel(request.hasVoted ? Copy.featureRequests.votedCta : Copy.featureRequests.voteCta)
        .accessibilityValue(Copy.featureRequests.voteCountLabel(request.voteCount))
    }

    @ViewBuilder
    private var statusTag: some View {
        switch request.status {
        case .submitted, .underReview:
            PenovaTag(text: request.status.display.uppercased(),
                      tint: PenovaColor.slate.opacity(0.18),
                      fg: PenovaColor.slate)
        case .planned:
            PenovaTag(text: request.status.display.uppercased(),
                      tint: PenovaColor.amber.opacity(0.18),
                      fg: PenovaColor.amber)
        case .shipped:
            PenovaTag(text: request.status.display.uppercased(),
                      tint: PenovaColor.jade.opacity(0.18),
                      fg: PenovaColor.jade)
        case .declined:
            PenovaTag(text: request.status.display.uppercased(),
                      tint: PenovaColor.ember.opacity(0.18),
                      fg: PenovaColor.ember)
        }
    }
}
