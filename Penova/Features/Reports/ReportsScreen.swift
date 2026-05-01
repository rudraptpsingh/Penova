//
//  ReportsScreen.swift
//  Penova
//
//  Pre-production breakdown reports surfaced from PenovaKit's
//  ProductionReports service. Three tabs: Scenes, Locations, Cast.
//  All data comes from in-memory project graph; no fetches here.
//

import SwiftUI
import PenovaKit

struct ReportsScreen: View {
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
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selection {
                    case .scenes:    sceneRows
                    case .locations: locationRows
                    case .cast:      castRows
                    }
                }
                .padding(PenovaSpace.l)
            }
        }
        .background(PenovaColor.ink0)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: PenovaSpace.xs) {
                        Text(tab.label)
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(selection == tab ? PenovaColor.snow : PenovaColor.snow3)
                        Rectangle()
                            .fill(selection == tab ? PenovaColor.amber : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.vertical, PenovaSpace.s)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .background(PenovaColor.ink0)
        .overlay(
            Rectangle()
                .fill(PenovaColor.ink2)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Scenes

    private var sceneRows: some View {
        let rows = ProductionReports.sceneReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No scenes yet.")
            } else {
                summaryCard("\(rows.count) scenes",
                            "across \(project.activeEpisodesOrdered.count) episode\(project.activeEpisodesOrdered.count == 1 ? "" : "s")")
                if project.locked {
                    lockedBanner
                }
                LazyVStack(spacing: PenovaSpace.s) {
                    ForEach(rows) { row in
                        sceneCard(row)
                    }
                }
            }
        }
    }

    private func sceneCard(_ row: ProductionReports.SceneRow) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            HStack {
                Text("\(row.sceneNumber).")
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.amber)
                    .frame(minWidth: 32, alignment: .leading)
                Text(row.heading)
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: PenovaSpace.s) {
                metaChip("\(row.cueCount) cue\(row.cueCount == 1 ? "" : "s")")
                metaChip("\(row.dialogueWordCount) dialogue word\(row.dialogueWordCount == 1 ? "" : "s")")
                metaChip("\(row.totalWordCount) total")
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Locations

    private var locationRows: some View {
        let rows = ProductionReports.locationReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No locations yet.")
            } else {
                summaryCard("\(rows.count) location\(rows.count == 1 ? "" : "s")",
                            "sorted by scene count")
                LazyVStack(spacing: PenovaSpace.s) {
                    ForEach(rows) { row in
                        locationCard(row)
                    }
                }
            }
        }
    }

    private func locationCard(_ row: ProductionReports.LocationRow) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            HStack {
                Text(row.intExt)
                    .font(PenovaFont.labelTiny)
                    .tracking(PenovaTracking.labelTiny)
                    .foregroundStyle(PenovaColor.amber)
                    .padding(.horizontal, PenovaSpace.xs)
                    .padding(.vertical, 2)
                    .background(PenovaColor.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                Text(row.location)
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow)
            }
            HStack(spacing: PenovaSpace.s) {
                metaChip("\(row.sceneCount) scene\(row.sceneCount == 1 ? "" : "s")")
                metaChip("\(row.distinctCues) cast")
                metaChip("\(row.totalWordCount) words")
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Cast

    private var castRows: some View {
        let rows = ProductionReports.castReport(for: project)
        return Group {
            if rows.isEmpty {
                emptyState("No character cues yet.")
            } else {
                summaryCard("\(rows.count) character\(rows.count == 1 ? "" : "s")",
                            "sorted by dialogue words")
                LazyVStack(spacing: PenovaSpace.s) {
                    ForEach(rows) { row in
                        castCard(row)
                    }
                }
            }
        }
    }

    private func castCard(_ row: ProductionReports.CastRow) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(row.name)
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
            HStack(spacing: PenovaSpace.s) {
                metaChip("\(row.dialogueBlockCount) line\(row.dialogueBlockCount == 1 ? "" : "s")")
                metaChip("\(row.dialogueWordCount) words")
                metaChip("\(row.sceneAppearances) scene\(row.sceneAppearances == 1 ? "" : "s")")
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Shared chrome

    private func summaryCard(_ headline: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(headline)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
            Text(sub)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink1)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        .padding(.bottom, PenovaSpace.m)
    }

    private var lockedBanner: some View {
        HStack(spacing: PenovaSpace.xs) {
            PenovaIconView(.bookmark, size: 14, color: PenovaColor.amber)
            Text("Scene numbers are locked.")
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.amber)
        }
        .padding(.horizontal, PenovaSpace.s)
        .padding(.vertical, PenovaSpace.xs)
        .background(PenovaColor.ink2)
        .clipShape(Capsule())
        .padding(.bottom, PenovaSpace.s)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(PenovaFont.labelTiny)
            .tracking(PenovaTracking.labelTiny)
            .foregroundStyle(PenovaColor.snow3)
            .padding(.horizontal, PenovaSpace.xs)
            .padding(.vertical, 2)
            .background(PenovaColor.ink3)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: PenovaSpace.s) {
            Text(message)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
        }
        .frame(maxWidth: .infinity)
        .padding(PenovaSpace.xl)
    }
}
