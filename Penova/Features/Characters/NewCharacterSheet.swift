//
//  NewCharacterSheet.swift
//  Penova
//
//  Create or edit a ScriptCharacter. When `editing` is nil, inserts a new
//  character into the chosen project. When `editing` is provided, mutates
//  that character in place.
//

import SwiftUI
import SwiftData
import PenovaKit

struct NewCharacterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let projects: [Project]
    var editing: ScriptCharacter? = nil

    @State private var selectedProjectId: String = ""
    @State private var name: String = ""
    @State private var role: CharacterRole = .supporting
    @State private var ageText: String = ""
    @State private var occupation: String = ""
    @State private var goal: String = ""
    @State private var conflict: String = ""
    @State private var traitsRaw: String = ""
    @State private var notes: String = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedProjectId.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    if editing == nil && projects.count > 1 {
                        projectPicker
                    }
                    PenovaTextField(label: "Name", text: $name, placeholder: "Iqbal")
                    chipRow("Role", selection: $role, options: CharacterRole.allCases) { $0.display }
                    PenovaTextField(label: "Age", text: $ageText, placeholder: "mid-40s or 42")
                    PenovaTextField(label: "Occupation", text: $occupation, placeholder: "Night porter")
                    PenovaTextField(label: "Goal", text: $goal, placeholder: "What they want.")
                    PenovaTextField(label: "Conflict", text: $conflict, placeholder: "What's in their way.")
                    PenovaTextField(label: "Traits", text: $traitsRaw, placeholder: "patient, observant, quiet")
                    PenovaTextField(label: "Notes", text: $notes, placeholder: "Anything else worth remembering.")
                    PenovaButton(title: editing == nil ? "Create character" : "Save changes", variant: .primary) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(editing == nil ? "New character" : "Edit character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear(perform: hydrate)
        }
            .preferredColorScheme(.dark)
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Project")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            FlowLayout(spacing: PenovaSpace.s) {
                ForEach(projects) { p in
                    PenovaChip(text: p.title, isSelected: p.id == selectedProjectId) {
                        selectedProjectId = p.id
                    }
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
                    PenovaChip(text: title(option), isSelected: selection.wrappedValue == option) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
    }

    private func hydrate() {
        if let c = editing {
            selectedProjectId = c.projects.first?.id ?? ""
            name = c.name
            role = c.role
            ageText = c.ageText ?? ""
            occupation = c.occupation ?? ""
            goal = c.goal ?? ""
            conflict = c.conflict ?? ""
            traitsRaw = c.traits.joined(separator: ", ")
            notes = c.notes ?? ""
        } else if let only = projects.first, projects.count == 1 {
            selectedProjectId = only.id
        }
    }

    private func parsedTraits() -> [String] {
        traitsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        if let c = editing {
            c.name = name.trimmingCharacters(in: .whitespaces)
            c.role = role
            c.ageText = ageText.isEmpty ? nil : ageText
            c.occupation = occupation.isEmpty ? nil : occupation
            c.goal = goal.isEmpty ? nil : goal
            c.conflict = conflict.isEmpty ? nil : conflict
            c.traits = parsedTraits()
            c.notes = notes.isEmpty ? nil : notes
            c.updatedAt = .now
        } else {
            guard let project = projects.first(where: { $0.id == selectedProjectId }) else {
                dismiss(); return
            }
            let c = ScriptCharacter(
                name: name.trimmingCharacters(in: .whitespaces),
                role: role,
                ageText: ageText.isEmpty ? nil : ageText,
                occupation: occupation.isEmpty ? nil : occupation,
                traits: parsedTraits()
            )
            c.goal = goal.isEmpty ? nil : goal
            c.conflict = conflict.isEmpty ? nil : conflict
            c.notes = notes.isEmpty ? nil : notes
            c.projects = [project]
            context.insert(c)
        }
        try? context.save()
        dismiss()
    }
}
