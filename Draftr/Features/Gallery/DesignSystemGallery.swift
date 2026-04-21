//
//  DesignSystemGallery.swift
//  Draftr
//
//  DEBUG-only visual regression aid. Renders every design primitive on one
//  scrollable canvas so we can sanity-check colour/spacing/typography before
//  real screens land. Reachable via the `.paintbrush` toolbar button on
//  HomeScreen in DEBUG builds.
//

#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    @State private var chipSelected = true
    @State private var fieldText = ""
    @State private var fieldError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DraftrSpace.l) {
                section("Typography") {
                    Text("Hero — Burning the midnight oil")
                        .font(DraftrFont.hero)
                        .foregroundStyle(DraftrColor.snow)
                    Text("Title — A screenplay in Draftr")
                        .font(DraftrFont.title)
                        .foregroundStyle(DraftrColor.snow)
                    Text("Body Large — The protagonist stares at the empty page.")
                        .font(DraftrFont.bodyLarge)
                        .foregroundStyle(DraftrColor.snow)
                    Text("Body — Regular paragraph for descriptive UI copy.")
                        .font(DraftrFont.body)
                        .foregroundStyle(DraftrColor.snow3)
                    Text("Body Small — Metadata, secondary labels.")
                        .font(DraftrFont.bodySmall)
                        .foregroundStyle(DraftrColor.snow3)
                    Text("LABEL CAPS · SECTION")
                        .font(DraftrFont.labelCaps)
                        .tracking(DraftrTracking.labelCaps)
                        .foregroundStyle(DraftrColor.snow4)
                    Text("INT. PLATFORM 7 — NIGHT")
                        .font(DraftrFont.monoScript)
                        .foregroundStyle(DraftrColor.snow)
                }

                section("Colours") {
                    swatchRow([
                        ("ink0", DraftrColor.ink0),
                        ("ink2", DraftrColor.ink2),
                        ("ink3", DraftrColor.ink3),
                        ("ink4", DraftrColor.ink4),
                        ("ink5", DraftrColor.ink5)
                    ])
                    swatchRow([
                        ("snow",  DraftrColor.snow),
                        ("snow2", DraftrColor.snow2),
                        ("snow3", DraftrColor.snow3),
                        ("snow4", DraftrColor.snow4)
                    ])
                    swatchRow([
                        ("amber", DraftrColor.amber),
                        ("jade",  DraftrColor.jade),
                        ("ember", DraftrColor.ember),
                        ("slate", DraftrColor.slate),
                        ("paper", DraftrColor.paper)
                    ])
                }

                section("Buttons") {
                    DraftrButton(title: "Primary", action: {})
                    DraftrButton(title: "Secondary", variant: .secondary, action: {})
                    DraftrButton(title: "Ghost", variant: .ghost, action: {})
                    DraftrButton(title: "Destructive", variant: .destructive, action: {})
                    DraftrButton(title: "Compact", size: .compact, action: {})
                    DraftrButton(title: "With Icon", icon: .plus, action: {})
                    DraftrButton(title: "Loading", isLoading: true, action: {})
                }

                section("Tags & Chips") {
                    HStack {
                        DraftrTag(text: "DRAMA")
                        DraftrTag(text: "THRILLER",
                                  tint: DraftrColor.amber.opacity(0.2),
                                  fg: DraftrColor.amber)
                        DraftrTag(text: "INCITING",
                                  tint: DraftrColor.slate.opacity(0.2),
                                  fg: DraftrColor.slate)
                    }
                    HStack {
                        DraftrChip(text: "Selected", isSelected: chipSelected) {
                            chipSelected.toggle()
                        }
                        DraftrChip(text: "Idle", isSelected: !chipSelected) {
                            chipSelected.toggle()
                        }
                    }
                }

                section("Text Field") {
                    DraftrTextField(
                        label: "Project title",
                        text: $fieldText,
                        placeholder: "The Last Train"
                    )
                    DraftrTextField(
                        label: "Logline",
                        text: $fieldError,
                        placeholder: "One sentence…",
                        error: fieldError.isEmpty ? nil : "Keep it under 140 characters."
                    )
                }

                section("Section Header") {
                    DraftrSectionHeader(title: "Active projects", action: {})
                    DraftrSectionHeader(title: "Recent scenes")
                }

                section("Icons") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: DraftrSpace.m
                    ) {
                        ForEach(DraftrIcon.allCases, id: \.self) { icon in
                            VStack(spacing: DraftrSpace.xs) {
                                DraftrIconView(icon, size: 24, color: DraftrColor.snow)
                                    .frame(height: 28)
                                Text(String(describing: icon))
                                    .font(DraftrFont.bodySmall)
                                    .foregroundStyle(DraftrColor.snow4)
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
                        message: "Create a project. Draftr will keep the formatting out of your way.",
                        ctaTitle: "Start your first project",
                        ctaAction: {}
                    )
                    .background(DraftrColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
                }

                section("FAB") {
                    HStack {
                        Spacer()
                        DraftrFAB(action: {})
                    }
                }
            }
            .padding(DraftrSpace.l)
        }
        .background(DraftrColor.ink0)
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
        VStack(alignment: .leading, spacing: DraftrSpace.sm) {
            Text(title.uppercased())
                .font(DraftrFont.labelCaps)
                .tracking(DraftrTracking.labelCaps)
                .foregroundStyle(DraftrColor.amber)
            content()
        }
    }

    private func swatchRow(_ items: [(String, Color)]) -> some View {
        HStack(spacing: DraftrSpace.s) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: DraftrSpace.xs) {
                    RoundedRectangle(cornerRadius: DraftrRadius.sm)
                        .fill(color)
                        .frame(height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: DraftrRadius.sm)
                                .stroke(DraftrColor.ink4, lineWidth: 0.5)
                        )
                    Text(name)
                        .font(DraftrFont.bodySmall)
                        .foregroundStyle(DraftrColor.snow3)
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
