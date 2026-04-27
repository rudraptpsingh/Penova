//
//  FeatureRequestDetailScreen.swift
//  Penova
//
//  Read-mostly view for a single FeatureRequest. Shows title, category,
//  status, vote count, detail body, and any maintainer note. The user
//  can +1 from here too. Edit + Delete are only available when this
//  device authored the request.
//

import SwiftUI
import SwiftData

struct FeatureRequestDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var request: FeatureRequest

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                header
                voteBar
                if !request.detail.isEmpty {
                    section(title: Copy.featureRequests.detailLabel, body: request.detail)
                }
                if !request.maintainerNote.isEmpty {
                    maintainerSection
                }
                if request.submittedByThisDevice {
                    ownerActions
                }
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle(request.category.display)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditSheet) {
            NewFeatureRequestSheet(editing: request)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(Copy.featureRequests.deletePrompt, isPresented: $showDeleteConfirm) {
            Button(Copy.common.cancel, role: .cancel) {}
            Button(Copy.common.delete, role: .destructive) { delete() }
        } message: {
            Text(Copy.featureRequests.deleteBody)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(spacing: PenovaSpace.s) {
                PenovaTag(text: request.category.display)
                statusTag
                Spacer(minLength: 0)
            }
            Text(request.title)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
        }
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

    private var voteBar: some View {
        HStack(spacing: PenovaSpace.m) {
            Button(action: toggleVote) {
                HStack(spacing: PenovaSpace.s) {
                    Image(systemName: request.hasVoted ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text(request.hasVoted ? Copy.featureRequests.votedCta : Copy.featureRequests.voteCta)
                        .font(PenovaFont.bodyMedium)
                }
                .foregroundStyle(request.hasVoted ? PenovaColor.amber : PenovaColor.snow)
                .padding(.horizontal, PenovaSpace.m)
                .padding(.vertical, PenovaSpace.s)
                .background(request.hasVoted ? PenovaColor.amber.opacity(0.12) : PenovaColor.ink3)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: request.hasVoted)
            .accessibilityLabel(request.hasVoted ? Copy.featureRequests.votedCta : Copy.featureRequests.voteCta)

            Text(Copy.featureRequests.voteCountLabel(request.voteCount))
                .font(PenovaFont.bodyMedium)
                .foregroundStyle(PenovaColor.snow3)
            Spacer()
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(title)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Text(body)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PenovaSpace.m)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var maintainerSection: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(Copy.featureRequests.maintainerLabel)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.amber)
            Text(request.maintainerNote)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PenovaSpace.m)
                .background(PenovaColor.amber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: PenovaRadius.md)
                        .stroke(PenovaColor.amber.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var ownerActions: some View {
        VStack(spacing: PenovaSpace.s) {
            PenovaButton(title: Copy.featureRequests.editCta, icon: .edit, variant: .secondary, size: .compact) {
                showEditSheet = true
            }
            PenovaButton(title: Copy.featureRequests.deleteCta, variant: .destructive, size: .compact) {
                showDeleteConfirm = true
            }
        }
    }

    private func toggleVote() {
        request.toggleVote()
        try? context.save()
    }

    private func delete() {
        context.delete(request)
        try? context.save()
        dismiss()
    }
}
