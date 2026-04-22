//
//  CharacterDetailScreen.swift
//  Penova
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

    /// Computed character report — walks every SceneElement in every project
    /// this character belongs to and tallies lines + scene appearances.
    /// Plain struct (not a cached view model) because scene element counts
    /// change often and the tiles are cheap to redraw.
    private struct CharacterReport {
        let lineCount: Int
        let sceneCount: Int
        let firstSceneHeading: String?
        let lastSceneHeading: String?
    }

    private var report: CharacterReport {
        let upperName = character.name.uppercased()
        var lineCount = 0
        var sceneIDs = Set<ID>()
        var appearingScenes: [ScriptScene] = []

        for project in character.projects {
            for episode in project.episodes {
                for scene in episode.scenes {
                    var speaking = false
                    var currentSpeaker: String?
                    for el in scene.elementsOrdered {
                        switch el.kind {
                        case .character:
                            currentSpeaker = el.text.uppercased()
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if currentSpeaker == upperName { speaking = true }
                        case .dialogue:
                            if currentSpeaker == upperName { lineCount += 1 }
                        default:
                            break
                        }
                    }
                    if speaking, !sceneIDs.contains(scene.id) {
                        sceneIDs.insert(scene.id)
                        appearingScenes.append(scene)
                    }
                }
            }
        }

        let sorted = appearingScenes.sorted { $0.order < $1.order }
        return CharacterReport(
            lineCount: lineCount,
            sceneCount: sceneIDs.count,
            firstSceneHeading: sorted.first?.heading,
            lastSceneHeading: sorted.last?.heading
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                headerBlock
                reportBlock
                if !character.projects.isEmpty {
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Projects")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        FlowLayout(spacing: PenovaSpace.s) {
                            ForEach(character.projects, id: \.id) { p in
                                PenovaTag(text: p.title)
                            }
                        }
                    }
                }
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
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Traits")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        FlowLayout(spacing: PenovaSpace.s) {
                            ForEach(character.traits, id: \.self) { trait in
                                PenovaTag(text: trait)
                            }
                        }
                    }
                }
                if let notes = character.notes, !notes.isEmpty {
                    field(label: "Notes", value: notes)
                }
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    PenovaIconView(.more, size: 18, color: PenovaColor.snow)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NewCharacterSheet(projects: character.projects, editing: character)
                .presentationDetents([.large])
        }
        .alert("Delete \(character.name)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This removes the character from the project. Their name will still appear in any dialogue already written.")
        }
    }

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: PenovaSpace.m) {
            Circle()
                .fill(PenovaColor.slate.opacity(0.3))
                .frame(width: 56, height: 56)
                .overlay(
                    Text(String(character.name.prefix(1)))
                        .font(PenovaFont.hero)
                        .foregroundStyle(PenovaColor.snow)
                )
            VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                Text(character.name)
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
                PenovaTag(text: character.role.display)
            }
            Spacer()
        }
    }

    private var reportBlock: some View {
        let r = report
        return VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Report")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            HStack(spacing: PenovaSpace.s) {
                reportTile(value: "\(r.lineCount)", label: "Lines")
                reportTile(value: "\(r.sceneCount)", label: "Scenes")
                reportTile(
                    value: r.firstSceneHeading != nil ? "✓" : "—",
                    label: "Appears"
                )
            }
            if let first = r.firstSceneHeading {
                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    Text("First scene")
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow3)
                    Text(first)
                        .font(PenovaFont.monoScript)
                        .foregroundStyle(PenovaColor.snow)
                }
            }
            if let last = r.lastSceneHeading, last != r.firstSceneHeading {
                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    Text("Last scene")
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow3)
                    Text(last)
                        .font(PenovaFont.monoScript)
                        .foregroundStyle(PenovaColor.snow)
                }
            }
        }
    }

    private func reportTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(value)
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
            Text(label.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private func field(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(label.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Text(value)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
        }
    }

    private func delete() {
        context.delete(character)
        try? context.save()
        dismiss()
    }
}
