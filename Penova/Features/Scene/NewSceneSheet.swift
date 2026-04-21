//
//  NewSceneSheet.swift
//  Penova
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
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Heading preview")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        Text(previewHeading)
                            .font(PenovaFont.monoScript)
                            .foregroundStyle(PenovaColor.snow)
                            .padding(PenovaSpace.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PenovaColor.ink2)
                            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                    }

                    chipRow("Location", selection: $location, options: SceneLocation.allCases) { $0.rawValue }
                    PenovaTextField(
                        label: "Location name",
                        text: $locationName,
                        placeholder: "Platform 7"
                    )
                    chipRow("Time", selection: $time, options: SceneTimeOfDay.allCases) { $0.rawValue }
                    PenovaTextField(
                        label: "Description (optional)",
                        text: $description,
                        placeholder: "What happens here — one line."
                    )
                    PenovaButton(title: "Create scene", variant: .primary) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("New scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
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
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(label)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            FlowLayout(spacing: PenovaSpace.s) {
                ForEach(options, id: \.self) { option in
                    PenovaChip(
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
