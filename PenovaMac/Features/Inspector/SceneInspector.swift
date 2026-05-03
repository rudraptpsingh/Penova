//
//  SceneInspector.swift
//  Penova for Mac
//
//  Right pane: contextual scene metadata. Heading editor (INT/EXT,
//  location, time-of-day), beat picker chips, bookmarked toggle, page
//  estimate, speaking-character report. Mirrors the iOS scene-detail
//  inspector, adapted for Mac density.
//

import SwiftUI
import SwiftData
import PenovaKit

struct SceneInspector: View {
    let scene: ScriptScene?
    /// Bubbles up the user's intent to delete the inspected scene
    /// to the parent (LibraryWindowView), which owns the confirm
    /// alert + selectedScene binding so we can snap to a sibling.
    var onRequestDelete: (ScriptScene) -> Void = { _ in }
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let scene {
                    headingSection(scene: scene)
                    beatSection(scene: scene)
                    pageSection(scene: scene)
                    charactersSection(scene: scene)
                    styleSection(scene: scene)
                    Divider()
                        .background(PenovaColor.ink4)
                    deleteSection(scene: scene)
                } else {
                    Text("No scene selected")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PenovaColor.ink2)
        .accessibilityIdentifier(A11yID.inspector)
    }

    /// Destructive zone — anchored at the bottom of the inspector so
    /// it doesn't crowd the editing controls but is always reachable.
    /// Calls back into the parent so the parent can present the
    /// confirm alert and select a sibling scene afterwards.
    private func deleteSection(scene: ScriptScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Danger zone")
            Button(role: .destructive) {
                onRequestDelete(scene)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete scene")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(PenovaColor.ember)
            .help("Remove this scene and its contents (⌫)")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(PenovaFont.labelTiny)
            .tracking(PenovaTracking.labelTiny)
            .foregroundStyle(PenovaColor.snow4)
            .textCase(.uppercase)
    }

    // MARK: - Heading

    private func headingSection(scene: ScriptScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Heading")

            // INT / EXT / INT/EXT segmented
            HStack(spacing: 2) {
                ForEach(SceneLocation.allCases, id: \.self) { loc in
                    locationChip(loc, isSelected: scene.location == loc) {
                        scene.location = loc
                        scene.rebuildHeading()
                        try? context.save()
                    }
                }
            }
            .padding(2)
            .background(PenovaColor.ink3)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Location field
            TextField("Location", text: Binding(
                get: { scene.locationName },
                set: {
                    scene.locationName = $0.uppercased()
                    scene.rebuildHeading()
                }
            ))
            .textFieldStyle(.plain)
            .font(PenovaFont.body)
            .foregroundStyle(PenovaColor.snow)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(PenovaColor.ink3)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onSubmit { try? context.save() }

            // Time-of-day chips
            FlowChips(
                items: SceneTimeOfDay.allCases.map(\.display),
                selectedIndex: SceneTimeOfDay.allCases.firstIndex(of: scene.time) ?? 0
            ) { idx in
                scene.time = SceneTimeOfDay.allCases[idx]
                scene.rebuildHeading()
                try? context.save()
            }
        }
    }

    private func locationChip(_ loc: SceneLocation, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(loc.display)
                .font(PenovaFont.labelCaps)
                .tracking(0.5)
                .foregroundStyle(isSelected ? PenovaColor.snow : PenovaColor.snow3)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isSelected ? PenovaColor.ink4 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Beat

    private func beatSection(scene: ScriptScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Beat")
            FlowChips(
                items: BeatType.allCases.map(\.display),
                selectedIndex: scene.beatType.flatMap { BeatType.allCases.firstIndex(of: $0) } ?? -1,
                swatches: BeatType.allCases.map(beatColor)
            ) { idx in
                scene.beatType = BeatType.allCases[idx]
                try? context.save()
            }

            HStack {
                Text("Bookmarked")
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow2)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { scene.bookmarked },
                    set: {
                        scene.bookmarked = $0
                        try? context.save()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(PenovaColor.amber)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Page estimate

    private func pageSection(scene: ScriptScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Page Estimate")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(estimate(for: scene))
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(PenovaColor.snow)
                Text("pp · \(scene.elements.count) elements")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow4)
            }
        }
    }

    // MARK: - Characters

    private func charactersSection(scene: ScriptScene) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Speaking")
            ForEach(speakingCharacters(in: scene), id: \.name) { entry in
                HStack {
                    Text(entry.name)
                        .font(PenovaFont.bodyMedium)
                        .foregroundStyle(PenovaColor.snow)
                    Spacer()
                    bar(for: entry)
                    Text("\(entry.count)")
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(PenovaColor.snow4)
                        .frame(minWidth: 22, alignment: .trailing)
                }
                .padding(.vertical, 4)
            }
            if speakingCharacters(in: scene).isEmpty {
                Text("Nobody speaks in this scene yet.")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow4)
                    .italic()
            }
        }
    }

    private func bar(for entry: SpeakingEntry) -> some View {
        let max = entry.maxInScene
        let frac = max == 0 ? 0 : CGFloat(entry.count) / CGFloat(max)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(PenovaColor.ink3).frame(height: 3)
                Rectangle().fill(PenovaColor.snow4).frame(width: geo.size.width * frac, height: 3)
            }
        }
        .frame(width: 60, height: 3)
    }

    // MARK: - Style check

    /// Quiet, opinionated style hints over action lines + parentheticals
    /// in this scene. Surfaces every `StyleMark` produced by
    /// `StyleCheckService.marks(for:)` as a small card with the matched
    /// excerpt — the matched span is emphasised in the semantic colour.
    /// Hidden when the scene has zero marks so a clean scene shows a
    /// clean inspector.
    @ViewBuilder
    private func styleSection(scene: ScriptScene) -> some View {
        let summary = StyleCheckService.marks(for: scene)
        let total = summary.reduce(0) { $0 + $1.marks.count }
        if total > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionLabel("Style")
                    Spacer()
                    Text("\(total) " + (total == 1 ? "mark" : "marks"))
                        .font(.custom("RobotoMono-Medium", size: 10))
                        .foregroundStyle(PenovaColor.snow4)
                }
                ForEach(Array(summary.enumerated()), id: \.offset) { _, entry in
                    ForEach(Array(entry.marks.enumerated()), id: \.offset) { _, mark in
                        styleMarkCard(mark: mark, source: entry.element.text)
                    }
                }
            }
        }
    }

    private func styleMarkCard(mark: StyleMark, source: String) -> some View {
        let colour = styleMarkColour(mark.kind)
        return VStack(alignment: .leading, spacing: 4) {
            Text(mark.kind.display.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(colour)
            Text(styleMarkExcerpt(mark: mark, source: source))
                .font(.custom("RobotoMono-Regular", size: 11.5))
                .foregroundStyle(PenovaColor.snow2)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(colour)
                .frame(width: 2)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 8,
                        bottomLeadingRadius: 8
                    )
                )
        }
    }

    /// Semantic colour per mark kind, drawn from PenovaColor:
    /// adverb + cliché use `ember` (the "fix this" red); passive uses
    /// `amber` (the gentler "consider this" tone).
    private func styleMarkColour(_ kind: StyleMarkKind) -> Color {
        switch kind {
        case .adverb, .cliche: return PenovaColor.ember
        case .passive:         return PenovaColor.amber
        }
    }

    /// Build an excerpt around the mark with the matched span emphasised.
    /// Falls back to the matched substring alone if the mark range can't
    /// be resolved against the source (shouldn't happen for marks
    /// produced by StyleCheckService, but we degrade gracefully).
    private func styleMarkExcerpt(mark: StyleMark, source: String) -> AttributedString {
        guard let range = mark.range(in: source) else {
            return AttributedString(mark.matched)
        }
        let leading  = source[source.startIndex..<range.lowerBound]
        let trailing = source[range.upperBound..<source.endIndex]

        // Trim the lead/tail to keep cards compact — show ~32 chars of
        // context on either side, ellipsised with a leading "…" if we
        // had to clip.
        let leadStr = String(leading)
        let tailStr = String(trailing)
        let leadDisplay: String = {
            if leadStr.count > 32 {
                let start = leadStr.index(leadStr.endIndex, offsetBy: -32)
                return "… " + String(leadStr[start...])
            }
            return leadStr
        }()
        let tailDisplay: String = {
            if tailStr.count > 48 {
                let end = tailStr.index(tailStr.startIndex, offsetBy: 48)
                return String(tailStr[..<end]) + " …"
            }
            return tailStr
        }()

        var attr = AttributedString(leadDisplay)

        var matched = AttributedString(mark.matched)
        matched.foregroundColor = PenovaColor.snow
        matched.backgroundColor = styleMarkColour(mark.kind).opacity(0.18)
        attr.append(matched)

        attr.append(AttributedString(tailDisplay))
        return attr
    }

    // MARK: - Beat colour

    private func beatColor(_ beat: BeatType) -> Color {
        switch beat {
        case .setup:      return PenovaColor.slate
        case .inciting:   return PenovaColor.ember
        case .turn:       return Color(red: 0.71, green: 0.54, blue: 0.29)
        case .midpoint:   return PenovaColor.jade
        case .climax:     return Color(red: 0.56, green: 0.23, blue: 0.23)
        case .resolution: return PenovaColor.snow4
        }
    }

    // MARK: - Page estimate

    private func estimate(for scene: ScriptScene) -> String {
        let lines = scene.elements.reduce(0.0) { acc, el in
            switch el.kind {
            case .heading, .character: return acc + 1
            case .parenthetical: return acc + 0.6
            case .dialogue: return acc + Double(max(1, el.text.count / 35))
            case .action: return acc + Double(max(1, el.text.count / 60))
            case .transition, .actBreak: return acc + 1.5
            }
        }
        return String(format: "%.1f", lines / 55.0)
    }

    // MARK: - Speaking characters

    private struct SpeakingEntry { let name: String; let count: Int; let maxInScene: Int }

    private func speakingCharacters(in scene: ScriptScene) -> [SpeakingEntry] {
        var counts: [String: Int] = [:]
        for el in scene.elements where el.kind == .dialogue {
            if let name = el.characterName, !name.isEmpty {
                counts[name, default: 0] += 1
            }
        }
        let max = counts.values.max() ?? 0
        return counts
            .map { SpeakingEntry(name: $0.key, count: $0.value, maxInScene: max) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Flow chips (wraps onto multiple lines)

struct FlowChips: View {
    let items: [String]
    /// Single-selection index. If `multiSelectIndices` is set this is ignored.
    let selectedIndex: Int
    var swatches: [Color]? = nil
    /// Optional multi-selection set. When non-nil, every index in this set
    /// renders as selected.
    var multiSelectIndices: Set<Int>? = nil
    let onTap: (Int) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                chip(idx: idx, label: item)
            }
        }
    }

    private func chip(idx: Int, label: String) -> some View {
        let isSelected: Bool = {
            if let multi = multiSelectIndices { return multi.contains(idx) }
            return idx == selectedIndex
        }()
        return Button(action: { onTap(idx) }) {
            HStack(spacing: 6) {
                if let swatches, idx < swatches.count {
                    Circle().fill(swatches[idx]).frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? PenovaColor.snow : PenovaColor.snow2)
                    .textCase(.lowercase)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isSelected ? PenovaColor.ink4 : PenovaColor.ink3)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? PenovaColor.snow4 : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow layout (wraps chips onto multiple lines)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Preview
//
// Open this file in Xcode and the canvas-side preview will render the
// inspector populated with a Mumbai-set scene whose action lines trip
// every style-check rule. Use this to visually verify the "Style"
// section renders correctly when iterating on its layout — the live
// app surface is harder to reach without seeded data.

#Preview("With style marks") {
    let schema = Schema(PenovaSchema.models)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let project = Project(title: "Ek Raat Mumbai Mein", logline: "")
    context.insert(project)
    let episode = Episode(title: "Arrival", order: 0)
    episode.project = project
    project.episodes.append(episode)
    context.insert(episode)

    let scene = ScriptScene(
        locationName: "MUMBAI LOCAL TRAIN",
        location: .interior,
        time: .night,
        order: 0
    )
    scene.episode = episode
    episode.scenes.append(scene)
    scene.beatType = .midpoint
    scene.bookmarked = true
    context.insert(scene)

    // Lines that trip every rule:
    //   • action #1: "the kind of tired that sleep doesn't fix" → cliché
    //                "is being careful" → passive
    //   • action #2: "begins to" → cliché
    //                "quietly" inside parenthetical (separate element)
    //   • parenthetical: "(quietly)" → adverb
    //   • dialogue (skipped): proves the section ignores spoken lines
    let elements: [(SceneElementKind, String, String?)] = [
        (.action,
         "Arjun has the kind of tired that sleep doesn't fix. He is being careful with the satchel.",
         nil),
        (.action,
         "The train begins to slow. Outside, headlights cut through the rain.",
         nil),
        (.character,     "ZAINA", nil),
        (.parenthetical, "(quietly)", "ZAINA"),
        (.dialogue,
         "You said you wouldn't come back, but here you are quickly disembarking.",
         "ZAINA"),
    ]
    for (i, (kind, text, name)) in elements.enumerated() {
        let el = SceneElement(kind: kind, text: text, order: i, characterName: name)
        el.scene = scene
        scene.elements.append(el)
        context.insert(el)
    }

    return SceneInspector(scene: scene)
        .frame(width: 320, height: 800)
        .modelContainer(container)
}

#Preview("Clean scene — section hidden") {
    let schema = Schema(PenovaSchema.models)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    let project = Project(title: "Demo", logline: "")
    context.insert(project)
    let ep = Episode(title: "Pilot", order: 0); ep.project = project
    project.episodes.append(ep); context.insert(ep)
    let scene = ScriptScene(
        locationName: "ROOFTOP",
        location: .exterior,
        time: .dawn,
        order: 0
    )
    scene.episode = ep; ep.scenes.append(scene); context.insert(scene)
    let el = SceneElement(
        kind: .action,
        text: "She watches the city wake. Birds. A vendor. A dog.",
        order: 0
    )
    el.scene = scene; scene.elements.append(el); context.insert(el)

    return SceneInspector(scene: scene)
        .frame(width: 320, height: 800)
        .modelContainer(container)
}
