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

    private var sceneTable: some View {
        let rows = ProductionReports.sceneReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No scenes yet.")
            } else {
                tableHeader(["#", "INT/EXT", "Location", "Time", "Cues", "Words"])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell("\(row.sceneNumber).", width: 40, mono: true, color: PenovaColor.amber)
                        cell(row.intExt, width: 60, mono: true)
                        cell(row.location, width: 240, mono: true).lineLimit(1)
                        cell(row.time, width: 80, mono: true)
                        cell("\(row.cueCount)", width: 50, mono: true)
                        cell("\(row.totalWordCount)", width: 60, mono: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    // MARK: - Locations

    private var locationTable: some View {
        let rows = ProductionReports.locationReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No locations yet.")
            } else {
                tableHeader(["INT/EXT", "Location", "Scenes", "Cast", "Words"])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell(row.intExt, width: 60, mono: true, color: PenovaColor.amber)
                        cell(row.location, width: 280, mono: true).lineLimit(1)
                        cell("\(row.sceneCount)", width: 60, mono: true)
                        cell("\(row.distinctCues)", width: 50, mono: true)
                        cell("\(row.totalWordCount)", width: 60, mono: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    // MARK: - Cast

    private var castTable: some View {
        let rows = ProductionReports.castReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No character cues yet.")
            } else {
                tableHeader(["Character", "Lines", "Words", "Scenes"])
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        cell(row.name, width: 240, mono: true, color: PenovaColor.amber).lineLimit(1)
                        cell("\(row.dialogueBlockCount)", width: 60, mono: true)
                        cell("\(row.dialogueWordCount)", width: 60, mono: true)
                        cell("\(row.sceneAppearances)", width: 60, mono: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func tableHeader(_ titles: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(titles.enumerated()), id: \.offset) { _, t in
                Text(t.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(PenovaColor.snow4)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    private func cell(_ text: String, width: CGFloat, mono: Bool = false, color: Color = PenovaColor.snow) -> some View {
        Text(text)
            .font(.system(size: mono ? 12 : 13, design: mono ? .monospaced : .default))
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
