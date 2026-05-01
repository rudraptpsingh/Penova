//
//  SmartGroupPane.swift
//  Penova for Mac
//
//  Center pane shown when a sidebar smart group (All Scenes / Bookmarked /
//  Recently Edited) is active. Lists every matching scene as a card.
//  Click a card to drill into the editor — the parent clears the active
//  smart group when that happens.
//

import SwiftUI
import PenovaKit

struct SmartGroupPane: View {
    let group: SmartGroup
    let projects: [Project]
    let onSelectScene: (ScriptScene) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16),
    ]

    private var scenes: [ScriptScene] {
        SmartGroup.scenes(for: group, in: projects)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if scenes.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(scenes, id: \.id) { scene in
                            SmartSceneCard(scene: scene)
                                .onTapGesture { onSelectScene(scene) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(PenovaColor.ink0)
        .accessibilityIdentifier("pane.smart-group")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.label.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.amber)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headerTitle)
                    .font(PenovaFont.hero)
                    .foregroundStyle(PenovaColor.snow)
                Text("\(scenes.count) scene\(scenes.count == 1 ? "" : "s")")
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow4)
            }
        }
    }

    private var headerTitle: String {
        switch group {
        case .allScenes:      return "All Scenes"
        case .bookmarked:     return "Bookmarked"
        case .recentlyEdited: return "Recently Edited"
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyIcon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(PenovaColor.snow4)
            Text(emptyTitle)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow3)
            Text(emptyBody)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow4)
                .multilineTextAlignment(.center)
        }
        .padding(64)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var emptyIcon: String {
        switch group {
        case .bookmarked: return "bookmark"
        default: return "rectangle.stack"
        }
    }

    private var emptyTitle: String {
        switch group {
        case .bookmarked: return "Nothing bookmarked yet"
        case .recentlyEdited: return "Nothing edited recently"
        case .allScenes: return "No scenes yet"
        }
    }

    private var emptyBody: String {
        switch group {
        case .bookmarked: return "Toggle the Bookmarked switch in the inspector to mark a scene."
        case .recentlyEdited: return "Edit a scene and it'll appear here."
        case .allScenes: return "Create a scene from any episode."
        }
    }
}

private struct SmartSceneCard: View {
    let scene: ScriptScene

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(beatColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(scene.episode?.project?.title ?? "")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(PenovaColor.snow4)
                        .lineLimit(1)
                    Spacer()
                    if scene.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
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
                    Text(updatedString)
                        .font(.system(size: 10))
                        .foregroundStyle(PenovaColor.snow4)
                }
            }
            .padding(16)
        }
        .frame(minHeight: 160, alignment: .topLeading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PenovaColor.ink4, lineWidth: 1))
    }

    private var beatColor: Color {
        guard let b = scene.beatType else { return PenovaColor.snow4 }
        switch b {
        case .setup:      return PenovaColor.slate
        case .inciting:   return PenovaColor.ember
        case .turn:       return Color(red: 0.71, green: 0.54, blue: 0.29)
        case .midpoint:   return PenovaColor.jade
        case .climax:     return Color(red: 0.56, green: 0.23, blue: 0.23)
        case .resolution: return PenovaColor.snow4
        }
    }

    private var updatedString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: scene.updatedAt, relativeTo: .now)
    }
}
