//
//  IndexCardsPane.swift
//  Penova for Mac
//
//  Beat-board view: scenes laid out as cards, color-striped by beat
//  type. Click drills into the editor for that scene. Drag-to-reorder
//  uses SceneReorder.move() — math covered by 12 SceneReorderTests.
//

import SwiftUI
import SwiftData
import PenovaKit
import UniformTypeIdentifiers

struct IndexCardsPane: View {
    let projects: [Project]
    @Binding var selectedScene: ScriptScene?
    /// Called when the user double-clicks (or single-clicks, see below)
    /// a card to drill into the editor. The parent flips viewMode →
    /// .editor and selects the scene. Single-click still updates the
    /// inspector via selectedScene; the explicit drill-in is what
    /// actually navigates.
    var onOpenScene: ((ScriptScene) -> Void)? = nil
    /// Bubbles a "right-clicked Delete on a card" up to the parent so
    /// the parent owns the confirm alert + sibling-selection logic.
    var onRequestDelete: ((ScriptScene) -> Void)? = nil
    @Environment(\.modelContext) private var context

    @State private var draggingSceneID: String?
    @State private var overlay: StructureOverlay = .penova

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 0) {
            structureToolbar
            Divider().background(PenovaColor.ink4)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let firstEp = projects.first?.activeEpisodesOrdered.first {
                        header(for: firstEp)
                    }
                    ForEach(visibleBeats, id: \.id) { beat in
                        beatSection(beat: beat)
                    }
                    let unbeated = scenesByBeatID["__unassigned"] ?? []
                    if !unbeated.isEmpty {
                        unassignedSection(scenes: unbeated)
                    }
                }
                .padding(24)
            }
        }
        .background(PenovaColor.ink0)
        .accessibilityIdentifier(A11yID.cardsPane)
    }

    // MARK: - Structure toolbar

    /// Pill-style overlay toggle + coverage stat. Penova's beat enum
    /// stays the source of truth — switching overlays just relabels
    /// the rail and remaps cards via StructureMapper.
    private var structureToolbar: some View {
        HStack(spacing: 14) {
            Text("STRUCTURE")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)

            HStack(spacing: 2) {
                ForEach(StructureOverlay.allCases, id: \.self) { o in
                    overlayPill(o)
                }
            }
            .padding(2)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Coverage pill — % of overlay's beats that have any
            // assigned scene mapping to them.
            HStack(spacing: 6) {
                Text("COVERAGE")
                    .font(PenovaFont.labelTiny)
                    .tracking(PenovaTracking.labelTiny)
                    .foregroundStyle(PenovaColor.snow4)
                Text(coverageLabel)
                    .font(.custom("RobotoMono-Medium", size: 11))
                    .foregroundStyle(PenovaColor.amber)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(PenovaColor.ink1)
    }

    private func overlayPill(_ o: StructureOverlay) -> some View {
        let isActive = (overlay == o)
        return Button(action: { overlay = o }) {
            HStack(spacing: 5) {
                Text(o.display)
                    .font(.system(size: 12, weight: .medium))
                Text(o.beatCountLabel)
                    .font(.custom("RobotoMono-Regular", size: 9))
                    .foregroundStyle(isActive ? PenovaColor.amber.opacity(0.7) : PenovaColor.snow4)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? PenovaColor.ink3 : Color.clear)
            )
            .foregroundStyle(isActive ? PenovaColor.amber : PenovaColor.snow3)
        }
        .buttonStyle(.plain)
    }

    private var coverageLabel: String {
        let assigned = Set(allScenes.compactMap(\.beatType))
        let cov = StructureMapper.coverage(assignedBeats: assigned, overlay: overlay)
        return "\(Int(cov.coveragePercent * 100))%"
    }

    // MARK: - Beat sections

    private var visibleBeats: [StructureBeat] { overlay.beats }

    /// Map of overlay-beat-id → scenes that fall under it. Plus an
    /// "__unassigned" bucket for scenes with no beatType set.
    private var scenesByBeatID: [String: [ScriptScene]] {
        var buckets: [String: [ScriptScene]] = [:]
        for scene in allScenes {
            guard let beatType = scene.beatType else {
                buckets["__unassigned", default: []].append(scene)
                continue
            }
            let id = StructureMapper.equivalent(beatType, in: overlay)
                ?? "__unassigned"
            buckets[id, default: []].append(scene)
        }
        return buckets
    }

    @ViewBuilder
    private func beatSection(beat: StructureBeat) -> some View {
        let scenes = scenesByBeatID[beat.id] ?? []
        VStack(alignment: .leading, spacing: 12) {
            beatHeader(beat: beat, count: scenes.count)
            if scenes.isEmpty {
                emptyBeatPlaceholder(beat: beat)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(scenes, id: \.id) { scene in
                        cardButton(for: scene)
                    }
                }
            }
        }
    }

    private func beatHeader(beat: StructureBeat, count: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(beat.name.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(beat.isMidpointAnchor ? PenovaColor.amber : PenovaColor.snow2)
            Text(beatPageLabel(beat))
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow4)
            Text(beat.description)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow4)
                .italic()
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.custom("RobotoMono-Medium", size: 11))
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(beat.isMidpointAnchor ? PenovaColor.amber : PenovaColor.ink4)
                .frame(height: beat.isMidpointAnchor ? 2 : 1)
        }
    }

    private func beatPageLabel(_ beat: StructureBeat) -> String {
        let start = Int(beat.suggestedPageStart * 100)
        let end = Int(beat.suggestedPageEnd * 100)
        if start == end { return "p. \(start)%" }
        return "pp \(start)—\(end)%"
    }

    private func emptyBeatPlaceholder(beat: StructureBeat) -> some View {
        HStack {
            Text("No scenes here yet — drag a card or assign \(beat.name) in the inspector.")
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow4)
                .italic()
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(PenovaColor.ink4, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    private func unassignedSection(scenes: [ScriptScene]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("UNASSIGNED")
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.snow4)
                Text("Scenes without a beat — pick one in the inspector.")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow4)
                    .italic()
                Spacer()
                Text("\(scenes.count)")
                    .font(.custom("RobotoMono-Medium", size: 11))
                    .foregroundStyle(PenovaColor.snow4)
            }
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(PenovaColor.ink4).frame(height: 1)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(scenes, id: \.id) { scene in
                    cardButton(for: scene)
                }
            }
        }
    }

    @ViewBuilder
    private func cardButton(for scene: ScriptScene) -> some View {
        Button(action: {
            selectedScene = scene
            onOpenScene?(scene)
        }) {
            SceneCard(scene: scene, isSelected: scene.id == selectedScene?.id)
                .opacity(draggingSceneID == scene.id ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .onDrag {
            draggingSceneID = scene.id
            PenovaLog.editor.info("drag start: scene \(scene.id, privacy: .public)")
            return NSItemProvider(object: scene.id as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: SceneCardDropDelegate(
                targetScene: scene,
                draggingSceneID: $draggingSceneID,
                onMove: handleDrop
            )
        )
        .contextMenu {
            Button("Open in editor") {
                selectedScene = scene
                onOpenScene?(scene)
            }
            Divider()
            Button("Delete scene", role: .destructive) {
                onRequestDelete?(scene)
            }
        }
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

    /// Performs a drag-drop reorder within the same episode. Cross-
    /// episode moves arrive in v1.1.
    private func handleDrop(sourceID: String, targetScene: ScriptScene) {
        guard let sourceScene = allScenes.first(where: { $0.id == sourceID }),
              let episode = sourceScene.episode,
              episode.id == targetScene.episode?.id
        else { return }

        let scenes = episode.scenesOrdered
        guard let targetIndex = scenes.firstIndex(where: { $0.id == targetScene.id }),
              let sourceIndex = scenes.firstIndex(where: { $0.id == sourceID })
        else { return }
        guard sourceIndex != targetIndex else { return }

        let items = scenes.map { (id: $0.id, order: $0.order) }
        let reordered = SceneReorder.move(items, movingID: sourceID, to: targetIndex)
        let lookup = Dictionary(uniqueKeysWithValues: reordered.map { ($0.id, $0.order) })
        for s in scenes {
            if let newOrder = lookup[s.id] {
                s.order = newOrder
            }
        }
        episode.updatedAt = .now
        try? context.save()
        PenovaLog.editor.info("reorder applied: source=\(sourceID, privacy: .public) → index \(targetIndex)")
    }
}

private struct SceneCardDropDelegate: DropDelegate {
    let targetScene: ScriptScene
    @Binding var draggingSceneID: String?
    let onMove: (String, ScriptScene) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { (string, _) in
            DispatchQueue.main.async {
                if let id = string as? String {
                    onMove(id, targetScene)
                }
                draggingSceneID = nil
            }
        }
        return true
    }

    func dropExited(info: DropInfo) {
        // Visual reset handled by performDrop or onDrop end
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
