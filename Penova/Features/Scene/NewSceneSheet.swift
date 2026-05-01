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
import PenovaKit

struct NewSceneSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var episode: Episode
    var editing: ScriptScene? = nil

    @State private var locationName: String = ""
    @State private var location: SceneLocation = .interior
    @State private var time: SceneTimeOfDay = .day
    @State private var description: String = ""

    // Free-form heading entry. When true, the chip pickers collapse and the
    // user types the whole slug line directly. We parse on save.
    // TODO: hook into continuous editor when it lands
    @State private var freeFormMode: Bool = false
    @State private var freeFormHeading: String = ""

    private var canSave: Bool {
        if freeFormMode {
            return !freeFormHeading.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !locationName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var nextOrder: Int {
        (episode.scenes.map(\.order).max() ?? -1) + 1
    }

    private var previewHeading: String {
        if freeFormMode {
            let trimmed = freeFormHeading.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "INT. LOCATION - DAY" : trimmed.uppercased()
        }
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

                    Toggle(isOn: $freeFormMode) {
                        Text("Type heading directly")
                            .font(PenovaFont.body)
                            .foregroundStyle(PenovaColor.snow)
                    }
                    .tint(PenovaColor.amber)

                    if freeFormMode {
                        PenovaTextField(
                            label: "Heading",
                            text: $freeFormHeading,
                            placeholder: "INT. DINER - NIGHT"
                        )
                    } else {
                        chipRow("Location", selection: $location, options: SceneLocation.allCases) { $0.rawValue }
                        PenovaTextField(
                            label: "Location name",
                            text: $locationName,
                            placeholder: "Platform 7"
                        )
                        chipRow("Time", selection: $time, options: SceneTimeOfDay.allCases) { $0.rawValue }
                    }
                    PenovaTextField(
                        label: "Description (optional)",
                        text: $description,
                        placeholder: "What happens here — one line."
                    )
                    PenovaButton(title: editing == nil ? "Create scene" : "Save changes", variant: .primary) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(editing == nil ? "New scene" : "Edit scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard let s = editing else { return }
        locationName = s.locationName
        location = s.location
        time = s.time
        description = s.sceneDescription ?? ""
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
        // If the user chose free-form entry, parse it into the structured
        // fields before continuing. Parser never fails loudly — worst case
        // we stash the raw string into locationName.
        if freeFormMode {
            let parsed = SceneHeadingParser.parse(freeFormHeading)
            location = parsed.location ?? .interior
            locationName = parsed.locationName
            if let t = parsed.time { time = t }
        }
        if let s = editing {
            s.locationName = locationName.uppercased()
            s.location = location
            s.time = time
            s.sceneDescription = description.isEmpty ? nil : description
            s.rebuildHeading()
            s.updatedAt = .now
        } else {
            let scene = ScriptScene(
                locationName: locationName,
                location: location,
                time: time,
                order: nextOrder,
                sceneDescription: description.isEmpty ? nil : description
            )
            scene.episode = episode
            context.insert(scene)
        }
        episode.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
