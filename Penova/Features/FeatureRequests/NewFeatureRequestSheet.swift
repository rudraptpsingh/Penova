//
//  NewFeatureRequestSheet.swift
//  Penova
//
//  Sheet for submitting a new feature request. Title is required;
//  category and description are optional. Saved to SwiftData on submit.
//

import SwiftUI
import SwiftData

struct NewFeatureRequestSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var body = ""
    @State private var category: FeatureRequestCategory = .general
    @State private var showTitleError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    Text(Copy.featureRequests.subtitle)
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow3)

                    titleField
                    categoryPicker
                    descriptionField
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(Copy.featureRequests.newTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.common.cancel) { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.featureRequests.submitButton) { submit() }
                        .font(PenovaFont.bodyMedium)
                        .foregroundStyle(title.trimmingCharacters(in: .whitespaces).isEmpty
                            ? PenovaColor.snow4 : PenovaColor.amber)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(Copy.featureRequests.titleLabel)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            TextField(Copy.featureRequests.titlePlaceholder, text: $title)
                .font(PenovaFont.bodyLarge)
                .foregroundStyle(PenovaColor.snow)
                .padding(PenovaSpace.sm)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PenovaRadius.sm)
                        .stroke(showTitleError ? PenovaColor.ember : PenovaColor.ink4, lineWidth: 1)
                )
                .onChange(of: title) { _, _ in
                    if showTitleError && !title.trimmingCharacters(in: .whitespaces).isEmpty {
                        showTitleError = false
                    }
                }
            if showTitleError {
                Text(Copy.featureRequests.titleRequired)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.ember)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(Copy.featureRequests.categoryLabel)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PenovaSpace.s) {
                    ForEach(FeatureRequestCategory.allCases) { cat in
                        PenovaChip(
                            text: cat.display,
                            isSelected: category == cat
                        ) { category = cat }
                    }
                }
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(Copy.featureRequests.descriptionLabel)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            TextEditor(text: $body)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .scrollContentBackground(.hidden)
                .padding(PenovaSpace.sm)
                .frame(minHeight: 100)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PenovaRadius.sm)
                        .stroke(PenovaColor.ink4, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if body.isEmpty {
                        Text(Copy.featureRequests.descriptionPlaceholder)
                            .font(PenovaFont.body)
                            .foregroundStyle(PenovaColor.snow4)
                            .padding(PenovaSpace.sm + 4)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showTitleError = true
            return
        }
        let request = FeatureRequest(
            title: trimmed,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category
        )
        context.insert(request)
        try? context.save()
        dismiss()
    }
}
