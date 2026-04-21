//
//  NewSceneSheet.swift
//  Draftr
//
//  S09 — Create a scene. Location chip (INT/EXT/INT-EXT), location name,
//  time-of-day chip, optional description. Heading auto-composes from the
//  three chip values.
//

import SwiftUI
import SwiftData

struct NewSceneSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var episode: Episode

    @State private var locationName: String = ""
    @State private var location: SceneLocation = .interior
    @State private var time: SceneTimeOfDay = .day
    @State private var description: String = ""

    private var canSave: Bool {
        !locationName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var nextOrder: Int {
        (episode.scenes.map(\.order).max() ?? -1) + 1
    }

    private var previewHeading: String {
        let name = locationName.isEmpty ? "LOCATION" : locationName.uppercased()
        return "\(location.rawValue). \(name) - \(time.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
                    VStack(alignment: .leading, spacing: DraftrSpace.s) {
                        Text("Heading preview")
                            .font(DraftrFont.labelCaps)
                            .tracking(DraftrTracking.labelCaps)
                            .foregroundStyle(DraftrColor.snow3)
                        Text(previewHeading)
                            .font(DraftrFont.monoScript)
                            .foregroundStyle(DraftrColor.snow)
                            .padding(DraftrSpace.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DraftrColor.ink2)
                            .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.sm))
                    }

                    chipRow("Location", selection: $location, options: SceneLocation.allCases) { $0.rawValue }
                    DraftrTextField(
                        label: "Location name",
                        text: $locationName,
                        placeholder: "Platform 7"
                    )
                    chipRow("Time", selection: $time, options: SceneTimeOfDay.allCases) { $0.rawValue }
                    DraftrTextField(
                        label: "Description (optional)",
                        text: $description,
                        placeholder: "What happens here — one line."
                    )
                    DraftrButton(title: "Create scene", variant: .primary) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(DraftrSpace.l)
            }
            .background(DraftrColor.ink0)
            .navigationTitle("New scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DraftrColor.snow3)
                }
            }
        }
    }

    @ViewBuilder
    private func chipRow<T: Hashable>(
        _ label: String,
        selection: Binding<T>,
        options: [T],
        title: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DraftrSpace.s) {
            Text(label)
                .font(DraftrFont.labelCaps)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.snow3)
            FlowLayout(spacing: DraftrSpace.s) {
                ForEach(options, id: \.self) { option in
                    DraftrChip(
                        text: title(option),
                        isSelected: selection.wrappedValue == option
                    ) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
    }

    private func save() {
        let scene = ScriptScene(
            locationName: locationName,
            location: location,
            time: time,
            order: nextOrder,
            sceneDescription: description.isEmpty ? nil : description
        )
        scene.episode = episode
        context.insert(scene)
        episode.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
