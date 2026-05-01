//
//  IndexCardsPane.swift
//  Penova for Mac
//
//  Beat-board view: scenes laid out as cards, color-striped by beat
//  type. Click drills into the editor for that scene. Drag-to-reorder
//  arrives in a follow-up commit (uses EditorLogic.insertOrder once the
//  business-logic files are moved into PenovaKit).
//

import SwiftUI
import SwiftData
import PenovaKit

struct IndexCardsPane: View {
    let projects: [Project]
    @Binding var selectedScene: ScriptScene?

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let firstEp = projects.first?.activeEpisodesOrdered.first {
                    header(for: firstEp)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(allScenes, id: \.id) { scene in
                        SceneCard(scene: scene, isSelected: scene.id == selectedScene?.id)
                            .onTapGesture { selectedScene = scene }
                    }
                }
            }
            .padding(24)
        }
        .background(PenovaColor.ink0)
        .accessibilityIdentifier(A11yID.cardsPane)
    }

    private func header(for episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(episode.project?.title ?? "")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow4)
                .textCase(.uppercase)
            Text(episode.title)
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
        }
    }

    private var allScenes: [ScriptScene] {
        projects.flatMap(\.activeEpisodesOrdered).flatMap(\.scenesOrdered)
    }
}

private struct SceneCard: View {
    let scene: ScriptScene
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Beat color stripe
            Rectangle()
                .fill(beatColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SCENE \(scene.order + 1)")
                        .font(PenovaFont.labelTiny)
                        .tracking(0.6)
                        .foregroundStyle(PenovaColor.snow4)
                    Spacer()
                    if scene.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(PenovaColor.amber)
                    }
                }
                Text(scene.heading)
                    .font(.custom("RobotoMono-Medium", size: 13))
                    .foregroundStyle(PenovaColor.snow)
                    .textCase(.uppercase)
                    .lineLimit(2)
                if let desc = scene.sceneDescription, !desc.isEmpty {
                    Text(desc)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let beat = scene.beatType {
                        HStack(spacing: 4) {
                            Circle().fill(beatColor).frame(width: 6, height: 6)
                            Text(beat.display)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PenovaColor.snow4)
                        }
                    }
                    Spacer()
                    Text(pageEstimate)
                        .font(.custom("RobotoMono-Medium", size: 10))
                        .foregroundStyle(PenovaColor.snow4)
                }
            }
            .padding(16)
        }
        .frame(minHeight: 160, alignment: .topLeading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? PenovaColor.amber : PenovaColor.ink4,
                              lineWidth: isSelected ? 2 : 1)
        )
    }

    private var beatColor: Color {
        guard let b = scene.beatType else { return PenovaColor.snow4 }
        switch b {
        case .setup:      return PenovaColor.slate
        case .inciting:   return PenovaColor.ember
        case .turn:       return Color(red: 0.71, green: 0.54, blue: 0.29) // ochre
        case .midpoint:   return PenovaColor.jade
        case .climax:     return Color(red: 0.56, green: 0.23, blue: 0.23) // crimson
        case .resolution: return PenovaColor.snow4
        }
    }

    private var pageEstimate: String {
        let lines = scene.elements.reduce(0.0) { acc, el in
            switch el.kind {
            case .heading, .character: return acc + 1
            case .parenthetical: return acc + 0.6
            case .dialogue: return acc + Double(max(1, el.text.count / 35))
            case .action: return acc + Double(max(1, el.text.count / 60))
            case .transition, .actBreak: return acc + 1.5
            }
        }
        return String(format: "%.1f pp", lines / 55.0)
    }
}
