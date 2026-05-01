//
//  DesignSystemGallery.swift
//  Penova
//
//  DEBUG-only visual regression aid. Renders every design primitive on one
//  scrollable canvas so we can sanity-check colour/spacing/typography before
//  real screens land. Reachable via the `.paintbrush` toolbar button on
//  HomeScreen in DEBUG builds.
//

#if DEBUG
import SwiftUI
import PenovaKit

struct DesignSystemGallery: View {
    @State private var chipSelected = true
    @State private var fieldText = ""
    @State private var fieldError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                section("Typography") {
                    Text("Hero — Burning the midnight oil")
                        .font(PenovaFont.hero)
                        .foregroundStyle(PenovaColor.snow)
                    Text("Title — A screenplay in Penova")
                        .font(PenovaFont.title)
                        .foregroundStyle(PenovaColor.snow)
                    Text("Body Large — The protagonist stares at the empty page.")
                        .font(PenovaFont.bodyLarge)
                        .foregroundStyle(PenovaColor.snow)
                    Text("Body — Regular paragraph for descriptive UI copy.")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow3)
                    Text("Body Small — Metadata, secondary labels.")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                    Text("LABEL CAPS · SECTION")
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow4)
                    Text("INT. PLATFORM 7 — NIGHT")
                        .font(PenovaFont.monoScript)
                        .foregroundStyle(PenovaColor.snow)
                }

                section("Colours") {
                    swatchRow([
                        ("ink0", PenovaColor.ink0),
                        ("ink2", PenovaColor.ink2),
                        ("ink3", PenovaColor.ink3),
                        ("ink4", PenovaColor.ink4),
                        ("ink5", PenovaColor.ink5)
                    ])
                    swatchRow([
                        ("snow",  PenovaColor.snow),
                        ("snow2", PenovaColor.snow2),
                        ("snow3", PenovaColor.snow3),
                        ("snow4", PenovaColor.snow4)
                    ])
                    swatchRow([
                        ("amber", PenovaColor.amber),
                        ("jade",  PenovaColor.jade),
                        ("ember", PenovaColor.ember),
                        ("slate", PenovaColor.slate),
                        ("paper", PenovaColor.paper)
                    ])
                }

                section("Buttons") {
                    PenovaButton(title: "Primary", action: {})
                    PenovaButton(title: "Secondary", variant: .secondary, action: {})
                    PenovaButton(title: "Ghost", variant: .ghost, action: {})
                    PenovaButton(title: "Destructive", variant: .destructive, action: {})
                    PenovaButton(title: "Compact", size: .compact, action: {})
                    PenovaButton(title: "With Icon", icon: .plus, action: {})
                    PenovaButton(title: "Loading", isLoading: true, action: {})
                }

                section("Tags & Chips") {
                    HStack {
                        PenovaTag(text: "DRAMA")
                        PenovaTag(text: "THRILLER",
                                  tint: PenovaColor.amber.opacity(0.2),
                                  fg: PenovaColor.amber)
                        PenovaTag(text: "INCITING",
                                  tint: PenovaColor.slate.opacity(0.2),
                                  fg: PenovaColor.slate)
                    }
                    HStack {
                        PenovaChip(text: "Selected", isSelected: chipSelected) {
                            chipSelected.toggle()
                        }
                        PenovaChip(text: "Idle", isSelected: !chipSelected) {
                            chipSelected.toggle()
                        }
                    }
                }

                section("Text Field") {
                    PenovaTextField(
                        label: "Project title",
                        text: $fieldText,
                        placeholder: "The Last Train"
                    )
                    PenovaTextField(
                        label: "Logline",
                        text: $fieldError,
                        placeholder: "One sentence…",
                        error: fieldError.isEmpty ? nil : "Keep it under 140 characters."
                    )
                }

                section("Section Header") {
                    PenovaSectionHeader(title: "Active projects", action: {})
                    PenovaSectionHeader(title: "Recent scenes")
                }

                section("Icons") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: PenovaSpace.m
                    ) {
                        ForEach(PenovaIcon.allCases, id: \.self) { icon in
                            VStack(spacing: PenovaSpace.xs) {
                                PenovaIconView(icon, size: 24, color: PenovaColor.snow)
                                    .frame(height: 28)
                                Text(String(describing: icon))
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.snow4)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                section("Cards") {
                    ProjectCard(project: demoProject)
                    SceneItem(scene: demoScene)
                    CharacterCard(character: demoCharacter)
                        .frame(maxWidth: 180)
                }

                section("Empty State") {
                    EmptyState(
                        icon: .scripts,
                        title: "Your first story starts here.",
                        message: "Create a project. Penova will keep the formatting out of your way.",
                        ctaTitle: "Start your first project",
                        ctaAction: {}
                    )
                    .background(PenovaColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                }

                section("FAB") {
                    HStack {
                        Spacer()
                        PenovaFAB(action: {})
                    }
                }
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var demoProject: Project {
        Project(
            title: "The Last Train",
            logline: "A porter at Bombay Central waits for the 23:45 to Pune — which never comes.",
            genre: [.thriller, .drama]
        )
    }

    private var demoScene: ScriptScene {
        let s = ScriptScene(
            locationName: "Platform 7",
            location: .exterior,
            time: .night,
            order: 0,
            sceneDescription: "Rain. Steam. A porter waits for a train that refuses to come."
        )
        s.beatType = .inciting
        return s
    }

    private var demoCharacter: ScriptCharacter {
        ScriptCharacter(
            name: "Iqbal",
            role: .protagonist,
            ageText: "mid-40s",
            occupation: "Night porter"
        )
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.sm) {
            Text(title.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.amber)
            content()
        }
    }

    private func swatchRow(_ items: [(String, Color)]) -> some View {
        HStack(spacing: PenovaSpace.s) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: PenovaSpace.xs) {
                    RoundedRectangle(cornerRadius: PenovaRadius.sm)
                        .fill(color)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: PenovaRadius.sm)
                                .stroke(PenovaColor.ink4, lineWidth: 0.5)
                        )
                    Text(name)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DesignSystemGallery()
    }
    .preferredColorScheme(.dark)
}
#endif
