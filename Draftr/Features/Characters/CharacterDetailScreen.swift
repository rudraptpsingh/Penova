//
//  CharacterDetailScreen.swift
//  Draftr
//
//  S15 — Character detail. Read-only view of name, role, age, occupation,
//  goal, conflict, traits, and notes. Edit button opens NewCharacterSheet
//  in edit mode. Delete routes through a confirm alert.
//

import SwiftUI
import SwiftData

struct CharacterDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var character: ScriptCharacter

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DraftrSpace.l) {
                headerBlock
                if let age = character.ageText, !age.isEmpty {
                    field(label: "Age", value: age)
                }
                if let occ = character.occupation, !occ.isEmpty {
                    field(label: "Occupation", value: occ)
                }
                if let goal = character.goal, !goal.isEmpty {
                    field(label: "Goal", value: goal)
                }
                if let conflict = character.conflict, !conflict.isEmpty {
                    field(label: "Conflict", value: conflict)
                }
                if !character.traits.isEmpty {
                    VStack(alignment: .leading, spacing: DraftrSpace.s) {
                        Text("Traits")
                            .font(DraftrFont.labelCaps)
                            .tracking(DraftrTracking.labelCaps)
                            .foregroundStyle(DraftrColor.snow3)
                        FlowLayout(spacing: DraftrSpace.s) {
                            ForEach(character.traits, id: \.self) { trait in
                                DraftrTag(text: trait)
                            }
                        }
                    }
                }
                if let notes = character.notes, !notes.isEmpty {
                    field(label: "Notes", value: notes)
                }
            }
            .padding(DraftrSpace.l)
        }
        .background(DraftrColor.ink0)
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    DraftrIconView(.more, size: 18, color: DraftrColor.snow)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let project = character.project {
                NewCharacterSheet(projects: [project], editing: character)
                    .presentationDetents([.large])
            }
        }
        .alert("Delete \(character.name)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This removes the character from the project. Their name will still appear in any dialogue already written.")
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: DraftrSpace.m) {
            Circle()
                .fill(DraftrColor.slate.opacity(0.3))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(String(character.name.prefix(1)))
                        .font(DraftrFont.hero)
                        .foregroundStyle(DraftrColor.snow)
                )
            VStack(alignment: .leading, spacing: DraftrSpace.xs) {
                Text(character.name)
                    .font(DraftrFont.title)
                    .foregroundStyle(DraftrColor.snow)
                DraftrTag(text: character.role.display)
            }
            Spacer()
        }
    }

    private func field(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DraftrSpace.xs) {
            Text(label.uppercased())
                .font(DraftrFont.labelCaps)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.snow3)
            Text(value)
                .font(DraftrFont.body)
                .foregroundStyle(DraftrColor.snow)
        }
    }

    private func delete() {
        context.delete(character)
        try? context.save()
        dismiss()
    }
}
