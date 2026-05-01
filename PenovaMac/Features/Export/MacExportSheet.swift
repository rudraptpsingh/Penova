//
//  MacExportSheet.swift
//  Penova for Mac
//
//  Three radio cards (PDF / FDX / Fountain) + scope picker + title-page
//  toggle. PDF route is wired to the Mac PDF adapter (in a follow-up
//  commit); for v0 we wire FDX and Fountain via the existing PenovaKit
//  writers and write to a user-chosen location.
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers
import PenovaKit

enum MacExportFormat: String, CaseIterable, Identifiable {
    case pdf, fdx, fountain
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf:      return "Production PDF"
        case .fdx:      return "Final Draft XML"
        case .fountain: return "Fountain plain text"
        }
    }
    var detail: String {
        switch self {
        case .pdf:      return "WGA-format, Courier 12pt, locked margins. The version you send to producers."
        case .fdx:      return "Round-trip with Final Draft 5+. Element types and scene structure preserved."
        case .fountain: return "Open standard. Diffable, scriptable, future-proof. Round-trips with Highland, Slugline, Fade In."
        }
    }
    var ext: String {
        switch self {
        case .pdf:      return "pdf"
        case .fdx:      return "fdx"
        case .fountain: return "fountain"
        }
    }
    var utType: UTType {
        switch self {
        case .pdf:      return .pdf
        case .fdx:      return UTType(filenameExtension: "fdx") ?? .xml
        case .fountain: return UTType(filenameExtension: "fountain") ?? .plainText
        }
    }
}

struct MacExportSheet: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    @State private var selected: MacExportFormat = .pdf
    @State private var includeTitlePage: Bool = true
    @State private var resultMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(PenovaColor.ink4)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    formatCards
                    Divider().background(PenovaColor.ink4)
                    optionsSection
                    if let resultMessage {
                        Text(resultMessage)
                            .font(PenovaFont.bodySmall)
                            .foregroundStyle(PenovaColor.jade)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            Divider().background(PenovaColor.ink4)
            footer
        }
        .background(PenovaColor.ink2)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export “\(episode.project?.title ?? "")” — \(episode.title)")
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(1)
                Text("\(episode.scenes.count) scenes · WGA-format ready")
                    .font(.system(size: 13))
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(8)
                    .background(PenovaColor.ink3)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var formatCards: some View {
        HStack(spacing: 12) {
            ForEach(MacExportFormat.allCases) { format in
                FormatCard(
                    format: format,
                    isSelected: format == selected,
                    onTap: { selected = format }
                )
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $includeTitlePage) {
                    Text("Include title page")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow2)
                }
                .toggleStyle(.switch)
                .tint(PenovaColor.amber)
                Spacer()
            }
            HStack {
                Text("Filename")
                    .font(.system(size: 13))
                    .foregroundStyle(PenovaColor.snow3)
                Spacer()
                Text(suggestedFilename)
                    .font(.custom("RobotoMono-Medium", size: 12))
                    .foregroundStyle(PenovaColor.snow)
            }
        }
    }

    private var suggestedFilename: String {
        let projectSlug = (episode.project?.title ?? "Untitled")
            .replacingOccurrences(of: " ", with: "")
        let epSlug = episode.title
            .replacingOccurrences(of: " ", with: "")
        let date = ISO8601DateFormatter()
            .string(from: .now)
            .prefix(10)
        return "\(projectSlug)-\(epSlug)-\(date).\(selected.ext)"
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(PenovaColor.snow3)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: doExport) {
                Text("Export \(selected.ext.uppercased())")
                    .font(PenovaFont.bodyMedium)
                    .foregroundStyle(PenovaColor.ink0)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(PenovaColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Export

    private func doExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [selected.utType]
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.title = "Export \(selected.displayName)"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            try writeContent(to: url)
            resultMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            resultMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func writeContent(to url: URL) throws {
        guard let project = episode.project else {
            throw NSError(domain: "PenovaExport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Episode has no project"])
        }
        switch selected {
        case .fountain:
            let text = FountainExporter.export(project: project)
            try text.write(to: url, atomically: true, encoding: .utf8)
        case .fdx:
            let xml = FinalDraftXMLWriter.xml(for: project)
            try xml.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            // Wire to the Mac PDF adapter once ScreenplayLayoutEngine is
            // extracted into PenovaKit. For v0, write a placeholder PDF
            // banner so users see something land on disk.
            let placeholder = "Penova — PDF export coming in v0.2.\nUse FDX or Fountain for now."
            try placeholder.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct FormatCard: View {
    let format: MacExportFormat
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(format.ext.uppercased())
                    .font(.custom("RobotoMono-Medium", size: 10))
                    .tracking(1)
                    .foregroundStyle(isSelected ? PenovaColor.amber : PenovaColor.snow4)
                Spacer()
                if isSelected && format == .pdf {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(PenovaColor.ink0)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PenovaColor.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(format.displayName)
                .font(PenovaFont.bodyLarge)
                .fontWeight(.semibold)
                .foregroundStyle(PenovaColor.snow)
            Text(format.detail)
                .font(.system(size: 12))
                .foregroundStyle(PenovaColor.snow3)
                .lineLimit(3)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(minHeight: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? PenovaColor.ink3 : PenovaColor.ink1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? PenovaColor.amber : PenovaColor.ink4, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
