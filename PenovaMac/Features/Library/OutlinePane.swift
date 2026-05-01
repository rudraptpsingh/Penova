//
//  OutlinePane.swift
//  Penova for Mac
//
//  Dense sortable list — every scene at a glance, the way pros scan.
//  Columns: Scene #, Heading, Location, Time, Beat, Pages, Characters.
//  v1: sort by scene order. Sortable column headers in v1.1.
//

import SwiftUI
import PenovaKit

struct OutlinePane: View {
    let projects: [Project]
    @Binding var selectedScene: ScriptScene?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let firstEp = projects.first?.activeEpisodesOrdered.first {
                    header(for: firstEp)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }

                tableHeader
                    .padding(.horizontal, 24)

                ForEach(allScenes, id: \.id) { scene in
                    row(for: scene)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 24)
        }
        .background(PenovaColor.ink0)
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

    private var tableHeader: some View {
        HStack(spacing: 0) {
            cell("#",         width: 40)
            cell("Heading",   width: nil)
            cell("Location",  width: 200)
            cell("Time",      width: 90)
            cell("Beat",      width: 110)
            cell("Pages",     width: 70, alignment: .trailing)
        }
        .font(PenovaFont.labelTiny)
        .tracking(PenovaTracking.labelTiny)
        .foregroundStyle(PenovaColor.snow4)
        .textCase(.uppercase)
        .padding(.vertical, 8)
        .background(
            Rectangle().fill(PenovaColor.ink4).frame(height: 1),
            alignment: .bottom
        )
    }

    private func row(for scene: ScriptScene) -> some View {
        let isSelected = scene.id == selectedScene?.id
        return HStack(spacing: 0) {
            cell("\(scene.order + 1)", width: 40,
                 font: .custom("RobotoMono-Medium", size: 11),
                 color: PenovaColor.snow4)
            cell(scene.heading, width: nil,
                 font: .custom("RobotoMono-Medium", size: 12),
                 color: PenovaColor.snow,
                 transform: .uppercase)
            cell(scene.locationName, width: 200,
                 font: PenovaFont.body,
                 color: PenovaColor.snow2)
            cell(scene.time.display, width: 90,
                 font: .custom("RobotoMono-Medium", size: 11),
                 color: PenovaColor.snow3)
            beatCell(scene.beatType, width: 110)
            cell(pageEstimate(for: scene), width: 70,
                 font: .custom("RobotoMono-Medium", size: 11),
                 color: PenovaColor.snow3,
                 alignment: .trailing)
        }
        .padding(.vertical, 12)
        .background(
            (isSelected ? PenovaColor.ink3 : Color.clear)
        )
        .background(
            Rectangle().fill(PenovaColor.ink4).frame(height: 0.5),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedScene = scene }
    }

    private func cell(
        _ text: String,
        width: CGFloat?,
        font: Font = PenovaFont.body,
        color: Color = PenovaColor.snow2,
        transform: Text.Case? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        HStack {
            if alignment == .trailing { Spacer() }
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .textCase(transform)
                .lineLimit(1)
            if alignment == .leading { Spacer() }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        .padding(.horizontal, 8)
    }

    private func beatCell(_ beat: BeatType?, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let beat {
                Circle().fill(beatColor(beat)).frame(width: 8, height: 8)
                Text(beat.display)
                    .font(PenovaFont.labelTiny)
                    .tracking(0.6)
                    .foregroundStyle(PenovaColor.snow2)
                    .textCase(.uppercase)
            } else {
                Text("—")
                    .foregroundStyle(PenovaColor.snow4)
            }
            Spacer()
        }
        .frame(width: width)
        .padding(.horizontal, 8)
    }

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

    private var allScenes: [ScriptScene] {
        projects.flatMap(\.activeEpisodesOrdered).flatMap(\.scenesOrdered)
    }

    private func pageEstimate(for scene: ScriptScene) -> String {
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
}
