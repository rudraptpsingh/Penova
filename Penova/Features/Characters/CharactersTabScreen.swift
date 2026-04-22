//
//  CharactersTabScreen.swift
//  Penova
//
//  S14 — Global characters tab. Groups characters by their parent project,
//  supports search by name, and offers a single FAB that routes through a
//  project picker → New Character flow.
//

import SwiftUI
import SwiftData

struct CharactersTabScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScriptCharacter.name) private var characters: [ScriptCharacter]
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var search: String = ""
    @State private var showNewCharacter = false
    @State private var editing: ScriptCharacter?
    @State private var pendingDelete: ScriptCharacter?

    private var activeProjects: [Project] {
        projects.filter { $0.status == .active }
    }

    private var filtered: [ScriptCharacter] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return characters }
        return characters.filter { $0.name.lowercased().contains(q) }
    }

    private var grouped: [(project: Project, chars: [ScriptCharacter])] {
        let byProject = Dictionary(grouping: filtered) { $0.project?.id ?? "" }
        return activeProjects.compactMap { project -> (Project, [ScriptCharacter])? in
            let chars = byProject[project.id] ?? []
            return chars.isEmpty ? nil : (project, chars)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    if characters.isEmpty {
                        EmptyState(
                            icon: .characters,
                            title: Copy.emptyStates.charactersTitle,
                            message: Copy.emptyStates.charactersBody,
                            ctaTitle: activeProjects.isEmpty ? nil : "New character",
                            ctaAction: activeProjects.isEmpty ? nil : { showNewCharacter = true }
                        )
                    } else {
                        ForEach(grouped, id: \.project.id) { group in
                            VStack(alignment: .leading, spacing: PenovaSpace.s) {
                                PenovaSectionHeader(title: group.project.title)
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: PenovaSpace.m
                                ) {
                                    ForEach(group.chars) { ch in
                                        NavigationLink(value: ch) {
                                            CharacterCard(character: ch)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button("Edit") { editing = ch }
                                            Button("Delete", role: .destructive) { pendingDelete = ch }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle(Copy.characters.title)
            .searchable(text: $search, prompt: "Search characters")
            .navigationDestination(for: ScriptCharacter.self) { ch in
                CharacterDetailScreen(character: ch)
            }

            if !activeProjects.isEmpty {
                PenovaFAB(icon: .plus) { showNewCharacter = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showNewCharacter) {
            NewCharacterSheet(projects: activeProjects)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $editing) { ch in
            NewCharacterSheet(projects: activeProjects, editing: ch)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete character?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text("Removes “\(pendingDelete?.name ?? "")” from the project. Names already in dialogue stay put.")
        }
    }

    private func confirmDelete() {
        guard let ch = pendingDelete else { return }
        context.delete(ch)
        try? context.save()
        pendingDelete = nil
    }
}
