//
//  CharactersTabScreen.swift
//  Draftr
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
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
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
                            VStack(alignment: .leading, spacing: DraftrSpace.s) {
                                DraftrSectionHeader(title: group.project.title)
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: DraftrSpace.m
                                ) {
                                    ForEach(group.chars) { ch in
                                        NavigationLink(value: ch) {
                                            CharacterCard(character: ch)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(DraftrSpace.l)
                .padding(.bottom, DraftrSpace.xxl)
            }
            .background(DraftrColor.ink0)
            .navigationTitle(Copy.characters.title)
            .searchable(text: $search, prompt: "Search characters")
            .navigationDestination(for: ScriptCharacter.self) { ch in
                CharacterDetailScreen(character: ch)
            }

            if !activeProjects.isEmpty {
                DraftrFAB(icon: .plus) { showNewCharacter = true }
                    .padding(DraftrSpace.l)
            }
        }
        .sheet(isPresented: $showNewCharacter) {
            NewCharacterSheet(projects: activeProjects)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
