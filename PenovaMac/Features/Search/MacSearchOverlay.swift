//
//  MacSearchOverlay.swift
//  Penova for Mac
//
//  ⌘F overlay: translucent backdrop, a single search field, results
//  grouped by kind (project, scene, location, dialogue, character).
//  Up/Down to navigate, Return to open, Esc to dismiss.
//

import SwiftUI
import SwiftData
import PenovaKit

struct MacSearchOverlay: View {
    @Binding var isVisible: Bool
    let projects: [Project]
    let onSelectScene: (ScriptScene) -> Void

    @State private var query: String = ""
    @State private var activeIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private var results: [SearchResult] {
        SearchService.search(query: query, in: projects)
    }

    var body: some View {
        ZStack {
            // Dim backdrop
            Rectangle()
                .fill(.black.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack {
                Spacer().frame(height: 80)
                overlay
                Spacer()
            }
        }
        .accessibilityIdentifier(A11yID.searchOverlay)
        .onAppear {
            fieldFocused = true
            activeIndex = 0
        }
    }

    private var overlay: some View {
        VStack(spacing: 0) {
            inputRow
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(PenovaColor.ink2)
                .overlay(Rectangle().fill(PenovaColor.ink4).frame(height: 1), alignment: .bottom)

            if !results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.kind) { group in
                            sectionHeader(group.kind)
                            ForEach(group.results) { result in
                                ResultRow(
                                    result: result,
                                    isActive: results.firstIndex(where: { $0.id == result.id }) == activeIndex
                                )
                                .onTapGesture { open(result) }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 480)
                footerRow
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(PenovaColor.snow4)
                    Text("No matches in this library.")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow4)
                }
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
                .background(PenovaColor.ink2)
            } else {
                emptyHint
            }
        }
        .frame(width: 640)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PenovaColor.ink5, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 20)
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PenovaColor.snow3)
                .font(.system(size: 16))
            TextField("Search projects, scenes, locations, dialogue…", text: $query)
                .accessibilityIdentifier(A11yID.searchInput)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundStyle(PenovaColor.snow)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in activeIndex = 0 }
                .onKeyPress(.upArrow) {
                    activeIndex = max(0, activeIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    activeIndex = min(max(0, results.count - 1), activeIndex + 1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if results.indices.contains(activeIndex) {
                        open(results[activeIndex])
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            Text("⎋")
                .font(.custom("RobotoMono-Medium", size: 11))
                .foregroundStyle(PenovaColor.snow4)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func sectionHeader(_ kind: SearchResultKind) -> some View {
        HStack {
            Text(kind.rawValue.capitalized + "s")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
    }

    private var footerRow: some View {
        HStack(spacing: 16) {
            footerHint(label: "Navigate", keys: ["↑", "↓"])
            footerHint(label: "Open", keys: ["⏎"])
            footerHint(label: "Dismiss", keys: ["⎋"])
            Spacer()
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(PenovaColor.ink1)
        .overlay(Rectangle().fill(PenovaColor.ink4).frame(height: 1), alignment: .top)
    }

    private func footerHint(label: String, keys: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { k in
                Text(k)
                    .font(.custom("RobotoMono-Medium", size: 10))
                    .foregroundStyle(PenovaColor.snow3)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(PenovaColor.ink3)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PenovaColor.snow4)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 16) {
            Text("Search anything in your library")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
            HStack(spacing: 16) {
                hintChip("Project titles", icon: "folder")
                hintChip("Scene headings", icon: "doc.text")
                hintChip("Dialogue", icon: "quote.bubble")
                hintChip("Characters", icon: "person.2")
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(PenovaColor.ink2)
    }

    private func hintChip(_ label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label)
                .font(PenovaFont.bodySmall)
        }
        .foregroundStyle(PenovaColor.snow4)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(PenovaColor.ink3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func open(_ result: SearchResult) {
        if let sceneID = result.sceneID,
           let scene = projects
            .flatMap(\.activeEpisodesOrdered)
            .flatMap(\.scenesOrdered)
            .first(where: { $0.id == sceneID })
        {
            onSelectScene(scene)
        }
        dismiss()
    }

    private func dismiss() {
        isVisible = false
        query = ""
    }

    // MARK: - Grouping

    private struct Group: Identifiable {
        let kind: SearchResultKind
        let results: [SearchResult]
        var id: SearchResultKind { kind }
    }

    private var grouped: [Group] {
        let bucket = Dictionary(grouping: results, by: \.kind)
        return SearchResultKind.allCases.compactMap { kind in
            guard let r = bucket[kind], !r.isEmpty else { return nil }
            return Group(kind: kind, results: r)
        }
    }
}

// MARK: - Result row

private struct ResultRow: View {
    let result: SearchResult
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? PenovaColor.amber : PenovaColor.snow3)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                styledTitle
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(PenovaColor.snow4)
                    .lineLimit(1)
            }
            Spacer()
            Text(result.kind.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(PenovaColor.snow4)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isActive ? PenovaColor.ink3 : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? PenovaColor.amber : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 4)
    }

    private var icon: String {
        switch result.kind {
        case .project:   return "folder"
        case .scene:     return "doc.text"
        case .location:  return "mappin.and.ellipse"
        case .dialogue:  return "quote.bubble"
        case .character: return "person"
        }
    }

    @ViewBuilder
    private var styledTitle: some View {
        if let range = result.titleMatch,
           let r = Range(range, in: result.title) {
            let pre  = String(result.title[result.title.startIndex..<r.lowerBound])
            let mid  = String(result.title[r])
            let post = String(result.title[r.upperBound..<result.title.endIndex])
            (Text(pre).foregroundStyle(PenovaColor.snow)
             + Text(mid).foregroundStyle(PenovaColor.amber)
             + Text(post).foregroundStyle(PenovaColor.snow))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        } else {
            Text(result.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PenovaColor.snow)
                .lineLimit(1)
        }
    }
}
