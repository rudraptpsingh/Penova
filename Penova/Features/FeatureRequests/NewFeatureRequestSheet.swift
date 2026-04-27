//
//  NewFeatureRequestSheet.swift
//  Penova
//
//  Compose a new FeatureRequest, or edit one this device authored.
//  Title is required; detail and category are optional (category
//  defaults to .other).
//

import SwiftUI
import SwiftData

struct NewFeatureRequestSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var editing: FeatureRequest? = nil

    @State private var title: String = ""
    @State private var detail: String = ""
    @State private var category: FeatureRequestCategory = .other

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    PenovaTextField(
                        label: Copy.featureRequests.titleField,
                        text: $title,
                        placeholder: Copy.featureRequests.titlePlaceholder
                    )
                    detailEditor
                    categoryPicker
                    PenovaButton(
                        title: editing == nil
                            ? Copy.featureRequests.submitCta
                            : Copy.featureRequests.saveChangesCta,
                        variant: .primary
                    ) {
                        save()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(editing == nil ? Copy.featureRequests.title : Copy.featureRequests.editCta)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.common.cancel) { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private var detailEditor: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(Copy.featureRequests.detailField)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            ZStack(alignment: .topLeading) {
                if detail.isEmpty {
                    Text(Copy.featureRequests.detailPlaceholder)
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow4)
                        .padding(.horizontal, PenovaSpace.m)
                        .padding(.vertical, PenovaSpace.s + 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $detail)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, PenovaSpace.s)
                    .padding(.vertical, PenovaSpace.xs)
                    .frame(minHeight: 120)
            }
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(Copy.featureRequests.categoryLabel)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            FlowLayout(spacing: PenovaSpace.s) {
                ForEach(FeatureRequestCategory.allCases) { option in
                    PenovaChip(text: option.display, isSelected: category == option) {
                        category = option
                    }
                }
            }
        }
    }

    private func hydrate() {
        guard let r = editing else { return }
        title = r.title
        detail = r.detail
        category = r.category
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = editing {
            r.title = trimmedTitle
            r.detail = trimmedDetail
            r.category = category
            r.updatedAt = .now
        } else {
            let request = FeatureRequest(
                title: trimmedTitle,
                detail: trimmedDetail,
                category: category
            )
            context.insert(request)
        }
        try? context.save()
        dismiss()
    }
}
