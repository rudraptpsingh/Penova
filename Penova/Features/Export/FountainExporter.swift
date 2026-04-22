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
        // Minimal title page.
        out += "Title: \(project.title)\n"
        if !project.logline.isEmpty {
            out += "Notes: \(project.logline)\n"
        }
        let author = UserDefaults.standard.string(forKey: "penova.auth.fullName") ?? ""
        if !author.trimmingCharacters(in: .whitespaces).isEmpty {
            out += "Author: \(author)\n"
        }
        let contact = project.contactBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty {
            out += "Contact: \(contact.replacingOccurrences(of: "\n", with: ", "))\n"
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
                    }
                }
            }
        }
        return out
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
