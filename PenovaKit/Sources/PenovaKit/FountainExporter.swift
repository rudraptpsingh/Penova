//
//  FountainExporter.swift
//  Penova
//
//  Serializes a Project back to Fountain plain-text. Inverse of
//  FountainParser — whatever the parser recognises, this emits in
//  a form it can round-trip.
//

import Foundation

public enum FountainExporter {

    /// Produce a Fountain string for the given project.
    public static func export(project: Project) -> String {
        var out = ""
        // Title page — emit all 6 documented Fountain keys when
        // present (Title, Credit, Author, Source, Draft date, Contact).
        // Empty values are skipped. Multi-line values (Contact, Source,
        // Notes) get their continuation lines indented by 3 spaces per
        // the fountain.io spec.
        let tp = project.titlePage
        let storedAuthor = UserDefaults.standard.string(forKey: "penova.auth.fullName") ?? ""

        let title = trimmedOrEmpty(tp.title.isEmpty ? project.title : tp.title)
        let credit = trimmedOrEmpty(tp.credit)
        // Author: explicit field wins, fall back to the signed-in
        // identity so v1.0 projects without a stored author still
        // emit one.
        let author = trimmedOrEmpty(tp.author.isEmpty ? storedAuthor : tp.author)
        let source = trimmedOrEmpty(tp.source)
        let draftDate = trimmedOrEmpty(tp.draftDate)
        let contact = trimmedOrEmpty(tp.contact.isEmpty ? project.contactBlock : tp.contact)

        if !title.isEmpty       { out += emitKey("Title",      value: title) }
        if !credit.isEmpty      { out += emitKey("Credit",     value: credit) }
        if !author.isEmpty      { out += emitKey("Author",     value: author) }
        if !source.isEmpty      { out += emitKey("Source",     value: source) }
        if !draftDate.isEmpty   { out += emitKey("Draft date", value: draftDate) }
        if !contact.isEmpty     { out += emitKey("Contact",    value: contact) }
        if !project.logline.isEmpty {
            out += emitKey("Notes", value: project.logline)
        }
        out += "\n"  // blank line ends the title page

        for episode in project.activeEpisodesOrdered {
            if project.activeEpisodesOrdered.count > 1 {
                // Fountain has no episode concept; emit as section-like boneyard.
                out += "/* EPISODE \(episode.order + 1): \(episode.title) */\n\n"
            }
            for scene in episode.scenesOrdered {
                out += scene.heading.uppercased() + "\n\n"
                if let desc = scene.sceneDescription, !desc.isEmpty,
                   !scene.elements.contains(where: { $0.kind == .action }) {
                    out += desc + "\n\n"
                }
                for el in scene.elementsOrdered {
                    switch el.kind {
                    case .heading:
                        continue
                    case .action:
                        out += el.text + "\n\n"
                    case .character:
                        out += el.text.uppercased() + "\n"
                    case .parenthetical:
                        var t = el.text.trimmingCharacters(in: .whitespaces)
                        if !t.hasPrefix("(") { t = "(" + t }
                        if !t.hasSuffix(")") { t = t + ")" }
                        out += t + "\n"
                    case .dialogue:
                        out += el.text + "\n\n"
                    case .transition:
                        var t = el.text.uppercased().trimmingCharacters(in: .whitespaces)
                        if !t.hasSuffix(":") { t += ":" }
                        out += t + "\n\n"
                    case .actBreak:
                        // Fountain centered-text syntax: > TEXT <
                        let t = el.text.uppercased().trimmingCharacters(in: .whitespaces)
                        out += "> " + t + " <\n\n"
                    }
                }
            }
        }
        return out
    }

    /// Emit a Fountain title-page key with multi-line continuation
    /// support. The first line follows the colon; subsequent lines are
    /// indented 3 spaces (per fountain.io spec) so the parser can tell
    /// them apart from a fresh key line.
    private static func emitKey(_ key: String, value: String) -> String {
        let lines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        guard let first = lines.first else { return "" }
        var out = "\(key): \(first)\n"
        for cont in lines.dropFirst() {
            out += "   \(cont)\n"
        }
        return out
    }

    private static func trimmedOrEmpty(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Write a Fountain export to a temporary .fountain file and return the URL.
    public static func write(project: Project) throws -> URL {
        let text = export(project: project)
        let safe = project.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        let base = safe.isEmpty ? "Penova-Script" : safe
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(base).fountain")
        try? FileManager.default.removeItem(at: url)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
