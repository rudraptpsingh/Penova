//
//  MacReportsSheet.swift
//  PenovaMac
//
//  Mac-flavoured Reports view: scene / location / cast tables fed
//  from PenovaKit's ProductionReports. Three tabs in a fixed-width
//  sheet so the writer can scan the breakdown without leaving the
//  three-pane shell.
//

import SwiftUI
import PenovaKit

struct MacReportsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: Project
    @State private var selection: Tab = .scenes

    private enum Tab: String, CaseIterable, Identifiable {
        case scenes, locations, cast
        var id: String { rawValue }
        var label: String {
            switch self {
            case .scenes:    return "Scenes"
            case .locations: return "Locations"
            case .cast:      return "Cast"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .scenes:    sceneTable
                    case .locations: locationTable
                    case .cast:      castTable
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 720, height: 560)
        .background(PenovaColor.ink0)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reports")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PenovaColor.snow)
                Text(project.title)
                    .font(.system(size: 12))
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
            if project.locked {
                lockedPill
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var lockedPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("Locked")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(PenovaColor.amber)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(PenovaColor.ink2)
        .clipShape(Capsule())
        .padding(.trailing, 8)
    }

    // MARK: - Scenes

    private struct SceneCols {
        static let number:   CGFloat = 44
        static let intExt:   CGFloat = 70
        static let location: CGFloat = 240
        static let time:     CGFloat = 110
        static let cues:     CGFloat = 60
        static let words:    CGFloat = 70
    }

    private var sceneTable: some View {
        let rows = ProductionReports.sceneReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No scenes yet.")
            } else {
                tableHeader([
                    ("#",        SceneCols.number),
                    ("INT/EXT",  SceneCols.intExt),
                    ("LOCATION", SceneCols.location),
                    ("TIME",     SceneCols.time),
                    ("CUES",     SceneCols.cues),
                    ("WORDS",    SceneCols.words),
                ])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell("\(row.sceneNumber).",       width: SceneCols.number,   color: PenovaColor.amber)
                        cell(row.intExt,                  width: SceneCols.intExt)
                        cell(row.location,                width: SceneCols.location).lineLimit(1)
                        cell(row.time,                    width: SceneCols.time)
                        cell("\(row.cueCount)",           width: SceneCols.cues)
                        cell("\(row.totalWordCount)",     width: SceneCols.words)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider().background(PenovaColor.ink2)
                }
            }
        }
    }

    // MARK: - Locations

    private struct LocationCols {
        static let intExt:   CGFloat = 70
        static let location: CGFloat = 280
        static let scenes:   CGFloat = 70
        static let cast:     CGFloat = 60
        static let words:    CGFloat = 70
    }

    private var locationTable: some View {
        let rows = ProductionReports.locationReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No locations yet.")
            } else {
                tableHeader([
                    ("INT/EXT",  LocationCols.intExt),
                    ("LOCATION", LocationCols.location),
                    ("SCENES",   LocationCols.scenes),
                    ("CAST",     LocationCols.cast),
                    ("WORDS",    LocationCols.words),
                ])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell(row.intExt,                  width: LocationCols.intExt,   color: PenovaColor.amber)
                        cell(row.location,                width: LocationCols.location).lineLimit(1)
                        cell("\(row.sceneCount)",         width: LocationCols.scenes)
                        cell("\(row.distinctCues)",       width: LocationCols.cast)
                        cell("\(row.totalWordCount)",     width: LocationCols.words)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider().background(PenovaColor.ink2)
                }
            }
        }
    }

    // MARK: - Cast

    private struct CastCols {
        static let name:   CGFloat = 280
        static let lines:  CGFloat = 70
        static let words:  CGFloat = 70
        static let scenes: CGFloat = 70
    }

    private var castTable: some View {
        let rows = ProductionReports.castReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No character cues yet.")
            } else {
                tableHeader([
                    ("CHARACTER", CastCols.name),
                    ("LINES",     CastCols.lines),
                    ("WORDS",     CastCols.words),
                    ("SCENES",    CastCols.scenes),
                ])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell(row.name,                       width: CastCols.name,   color: PenovaColor.amber).lineLimit(1)
                        cell("\(row.dialogueBlockCount)",    width: CastCols.lines)
                        cell("\(row.dialogueWordCount)",     width: CastCols.words)
                        cell("\(row.sceneAppearances)",      width: CastCols.scenes)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider().background(PenovaColor.ink2)
                }
            }
        }
    }

    // MARK: - Shared chrome

    /// Header row that pins each column to the same width as the data
    /// rows so they align perfectly. The earlier `HStack` of natural-
    /// width text views drifted under the data columns when any column
    /// was wider than the header label.
    private func tableHeader(_ columns: [(title: String, width: CGFloat)]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                Text(col.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PenovaColor.snow4)
                    .frame(width: col.width, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func cell(_ text: String, width: CGFloat, color: Color = PenovaColor.snow) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: width, alignment: .leading)
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(PenovaColor.snow3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}
