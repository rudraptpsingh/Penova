//
//  FeatureRequestsScreen.swift
//  Penova
//
//  S23 — Feature Requests. Displays all locally-stored feature requests
//  the user has submitted. Grouped by status (pending → planned → shipped).
//  FAB opens NewFeatureRequestSheet.
//

import SwiftUI
import SwiftData

struct FeatureRequestsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FeatureRequest.createdAt, order: .reverse) private var requests: [FeatureRequest]

    @State private var showNewRequest = false

    private var pending: [FeatureRequest] { requests.filter { $0.status == .pending } }
    private var planned: [FeatureRequest] { requests.filter { $0.status == .planned } }
    private var shipped: [FeatureRequest] { requests.filter { $0.status == .shipped } }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if requests.isEmpty {
                EmptyState(
                    icon: .progress,
                    title: Copy.featureRequests.emptyTitle,
                    message: Copy.featureRequests.emptyBody,
                    ctaTitle: Copy.featureRequests.emptyCta
                ) { showNewRequest = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PenovaColor.ink0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: PenovaSpace.l) {
                        if !pending.isEmpty {
                            statusSection(title: "Pending", requests: pending, status: .pending)
                        }
                        if !planned.isEmpty {
                            statusSection(title: "Planned", requests: planned, status: .planned)
                        }
                        if !shipped.isEmpty {
                            statusSection(title: "Shipped", requests: shipped, status: .shipped)
                        }
                    }
                    .padding(PenovaSpace.l)
                    .padding(.bottom, PenovaSpace.xxl)
                }
                .background(PenovaColor.ink0)
            }

            PenovaFAB(icon: .plus) { showNewRequest = true }
                .padding(PenovaSpace.l)
        }
        .navigationTitle(Copy.featureRequests.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewRequest) {
            NewFeatureRequestSheet()
        }
    }

    private func statusSection(title: String, requests: [FeatureRequest], status: FeatureRequestStatus) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(spacing: PenovaSpace.s) {
                Text(title)
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.snow3)
                statusDot(status)
            }
            VStack(spacing: PenovaSpace.s) {
                ForEach(requests) { request in
                    FeatureRequestCard(request: request) {
                        upvote(request)
                    }
                    .contextMenu {
                        Button(role: .destructive) { delete(request) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func statusDot(_ status: FeatureRequestStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 6, height: 6)
    }

    private func statusColor(_ status: FeatureRequestStatus) -> Color {
        switch status {
        case .pending: return PenovaColor.snow4
        case .planned: return PenovaColor.amber
        case .shipped: return PenovaColor.jade
        }
    }

    private func upvote(_ request: FeatureRequest) {
        request.upvotes += 1
        request.updatedAt = .now
        try? context.save()
    }

    private func delete(_ request: FeatureRequest) {
        context.delete(request)
        try? context.save()
    }
}

// MARK: - Feature Request Card

private struct FeatureRequestCard: View {
    let request: FeatureRequest
    let onUpvote: () -> Void

    @State private var upvoteTap = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(alignment: .top, spacing: PenovaSpace.s) {
                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    Text(request.title)
                        .font(PenovaFont.bodyMedium)
                        .foregroundStyle(PenovaColor.snow)
                        .fixedSize(horizontal: false, vertical: true)
                    PenovaTag(
                        text: request.category.display,
                        tint: PenovaColor.ink3,
                        fg: PenovaColor.snow3
                    )
                }
                Spacer()
                upvoteButton
            }
            if !request.body.isEmpty {
                Text(request.body)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(request.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private var upvoteButton: some View {
        Button {
            upvoteTap &+= 1
            onUpvote()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(request.upvotes)")
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
            }
            .foregroundStyle(PenovaColor.amber)
            .frame(minWidth: 36, minHeight: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: upvoteTap)
    }
}
