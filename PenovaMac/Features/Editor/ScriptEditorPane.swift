//
//  ScriptEditorPane.swift
//  Penova for Mac
//
//  The cream-paper script editor. Renders SceneElements in proper
//  screenplay format (Courier-substitute Roboto Mono, WGA columns) on
//  the `paper` (#F5F0E6) surface that's the iOS app's signature look.
//
//  v1 scaffold: read-only display + an editable bottom row for adding
//  new elements. Real per-row inline editing with Tab/Return cycling
//  lands in the next commit.
//

import SwiftUI
import SwiftData
import PenovaKit

struct ScriptEditorPane: View {
    let scene: ScriptScene?
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 0) {
                if let scene {
                    PaperPage(scene: scene)
                        .padding(.vertical, 40)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(PenovaColor.ink0)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(PenovaColor.snow4)
            Text("Select a scene to edit")
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow3)
            Text("Pick one from the sidebar — or press ⌘⇧N for a new scene.")
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow4)
        }
        .padding(64)
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Paper page

struct PaperPage: View {
    let scene: ScriptScene

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Page number top-right
            HStack {
                Spacer()
                Text("1.")
                    .font(.custom("RobotoMono-Medium", size: 12))
                    .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.05).opacity(0.45))
            }
            .padding(.bottom, 24)

            // Scene heading
            Text(scene.heading)
                .font(.custom("RobotoMono-Medium", size: 14))
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .padding(.bottom, 12)

            // Elements
            ForEach(scene.elementsOrdered) { el in
                ElementRow(element: el)
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 48)
        .padding(.bottom, 80)
        .frame(width: 640, alignment: .leading)
        .background(PenovaColor.paper)
        .foregroundStyle(Color(red: 0.10, green: 0.08, blue: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(PenovaColor.paperLine, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 4)
    }
}

private struct ElementRow: View {
    let element: SceneElement

    private let pageWidth: CGFloat = 480 // 640 - 80*2 padding

    var body: some View {
        let mono = Font.custom("RobotoMono-Medium", size: 14)
        let leading: CGFloat = leadingIndent
        let trailing: CGFloat = element.kind == .dialogue ? pageWidth * 0.16 : 0
        let isUpper = [SceneElementKind.heading, .character, .transition].contains(element.kind)
        let italic = element.kind == .parenthetical
        let weight: Font.Weight = element.kind == .heading ? .semibold : .medium

        HStack(spacing: 0) {
            if element.kind == .transition {
                Spacer(minLength: 0)
                Text(element.text)
                    .font(mono)
                    .fontWeight(weight)
                    .textCase(.uppercase)
                    .padding(.vertical, paddingV)
            } else {
                Text(element.text)
                    .font(mono)
                    .fontWeight(weight)
                    .italic(italic)
                    .textCase(isUpper ? .uppercase : nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: pageWidth - leading - trailing, alignment: .leading)
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
                    .padding(.vertical, paddingV)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paddingV: CGFloat {
        switch element.kind {
        case .heading, .action, .actBreak, .transition: return 6
        case .character: return 4
        case .dialogue, .parenthetical: return 0
        }
    }

    private var leadingIndent: CGFloat {
        switch element.kind {
        case .heading, .action, .actBreak: return 0
        case .character:                   return pageWidth * 0.36
        case .parenthetical:               return pageWidth * 0.28
        case .dialogue:                    return pageWidth * 0.18
        case .transition:                  return 0
        }
    }
}
