//
//  FinalDraftXMLWriter.swift
//  Penova
//
//  Serialises a Project into Final Draft 8+ compatible XML (.fdx).
//  One <Paragraph Type="…"> per SceneElement, emitted in scene order
//  across every episode in the project. Text is XML-escaped.
//
//  Reference shape:
//    <?xml version="1.0" encoding="UTF-8"?>
//    <FinalDraft DocumentType="Script" Template="No" Version="5">
//      <Content>
//        <Paragraph Type="Scene Heading"><Text>INT. DINER - NIGHT</Text></Paragraph>
//        ...
//      </Content>
//    </FinalDraft>
//

import Foundation

public enum FinalDraftXMLWriter {

    // MARK: - Public

    /// Returns the .fdx XML document for the given project, as a String.
    public static func xml(for project: Project) -> String {
        var out = ""
        out.reserveCapacity(4096)
        out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">\n"
        out += "  <Content>\n"

        for episode in project.activeEpisodesOrdered {
            for scene in episode.scenesOrdered {
                // Scene heading comes from the scene itself so we always have
                // a slug line even if the user never added an explicit
                // `.heading` element. If the first element IS a heading, we
                // skip emitting the synthetic one to avoid duplicates.
                let ordered = scene.elementsOrdered
                let firstIsHeading = ordered.first?.kind == .heading

                if !firstIsHeading {
                    out += paragraph(type: "Scene Heading", text: scene.heading.uppercased())
                }

                for el in ordered {
                    out += paragraph(type: fdxType(el.kind), text: renderedText(for: el))
                }
            }
        }

        out += "  </Content>\n"
        out += "</FinalDraft>\n"
        return out
    }

    /// Writes the .fdx document to a temporary file and returns its URL.
    public static func write(project: Project) throws -> URL {
        let xmlString = xml(for: project)
        let url = temporaryURL(for: project)
        try? FileManager.default.removeItem(at: url)
        try xmlString.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Paragraph rendering

    private static func paragraph(type: String, text: String) -> String {
        "    <Paragraph Type=\"\(escape(type))\"><Text>\(escape(text))</Text></Paragraph>\n"
    }

    private static func fdxType(_ kind: SceneElementKind) -> String {
        switch kind {
        case .heading:       return "Scene Heading"
        case .action:        return "Action"
        case .character:     return "Character"
        case .dialogue:      return "Dialogue"
        case .parenthetical: return "Parenthetical"
        case .transition:    return "Transition"
        case .actBreak:      return "Action"
        }
    }

    private static func renderedText(for el: SceneElement) -> String {
        switch el.kind {
        case .heading:
            return el.text.uppercased()
        case .character:
            return el.text.uppercased()
        case .transition:
            return el.text.uppercased()
        case .parenthetical:
            let trimmed = el.text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return trimmed }
            return "(\(trimmed))"
        case .action, .dialogue:
            return el.text
        case .actBreak:
            return el.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
    }

    // MARK: - Escaping

    /// Escapes the five XML predefined entities: & < > " '
    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&apos;"
            default:   out.append(ch)
            }
        }
        return out
    }

    // MARK: - Files

    private static func temporaryURL(for project: Project) -> URL {
        let safe = project.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        let trimmed = safe.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "Penova-Script" : trimmed
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(base).fdx")
    }
}
