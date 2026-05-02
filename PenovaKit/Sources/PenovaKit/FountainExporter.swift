//
//  FountainExporter.swift
//  Penova
//
//  Serializes a Project back to Fountain plain-text. Inverse of
//  FountainParser — whatever the parser recognises, this emits in
//  a form it can round-trip.
//
//  As of v1.2 the exporter implements the Penova Fountain dialect:
//  the standard fountain.io spec plus Penova-namespaced extensions
//  for fields the standard doesn't cover (genre, status, locked
//  metadata, scene beats, episode boundaries). All extensions use
//  syntax forms the standard already permits — `Penova-` title-page
//  keys, `[[Penova: ...]]` element notes, `/* Penova-Episode: ... */`
//  boneyard delimiters — so non-Penova readers (Highland, Slugline,
//  Beat) treat our files as valid Fountain and just ignore the
//  extension data.
//
//  See `docs/spec/penova-fountain.md` for the full spec.
//

import Foundation

public enum FountainExporter {

    /// Produce a Fountain string for the given project.
    ///
    /// The output is intentionally the input to `FountainParser.parse(_:)`
    /// — round-trip is enforced by `FountainRoundTripTests` and
    /// `PenovaFountainDialectTests`.
    public static func export(project: Project) -> String {
        var out = ""

        // ---------------- Title page ----------------
        //
        // Emit all 6 documented Fountain keys (Title, Credit, Author,
        // Source, Draft date, Contact) when present. Empty values are
        // skipped. Multi-line values get 3-space continuation indents
        // per the fountain.io spec.
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

        // ---------- Penova-namespaced extensions ----------
        //
        // See docs/spec/penova-fountain.md §1. These keys carry data
        // the standard fountain.io spec doesn't model. Every standard
        // Fountain reader (Highland, Slugline, Beat) treats them as
        // unknown keys and silently drops them per the spec — so our
        // files remain valid Fountain.

        if !project.genre.isEmpty {
            let csv = project.genre.map(\.rawValue).joined(separator: ", ")
            out += "Penova-Genre: \(csv)\n"
        }
        if project.status != .active {
            out += "Penova-Status: \(project.status.rawValue)\n"
        }
        if !tp.draftStage.isEmpty {
            out += "Penova-Draft-Stage: \(tp.draftStage)\n"
        }
        if !tp.copyright.isEmpty {
            out += "Penova-Copyright: \(tp.copyright)\n"
        }
        if !tp.notes.isEmpty {
            out += emitKey("Penova-Notes", value: tp.notes)
        }
        if project.locked {
            out += "Penova-Locked: true\n"
            if let lockedAt = project.lockedAt {
                out += "Penova-Locked-At: \(iso8601(lockedAt))\n"
            }
            if let map = project.lockedSceneNumbers, !map.isEmpty {
                if let json = encodeJSON(map) {
                    out += "Penova-Locked-Numbers: \(json)\n"
                }
            }
        }

        out += "\n"  // blank line ends the title page

        // ---------------- Body ----------------

        let multiEpisode = project.activeEpisodesOrdered.count > 1

        for episode in project.activeEpisodesOrdered {
            if multiEpisode {
                // Penova-Episode boneyard delimiter — see spec §3.
                let etitle = episode.title.replacingOccurrences(of: "*/", with: "*\\/")
                out += "/* Penova-Episode: \(episode.order) — \(etitle) — status=\(episode.status.rawValue) */\n\n"
            }

            for scene in episode.scenesOrdered {
                // Scene heading
                out += scene.heading.uppercased() + "\n"

                // Scene-level Penova notes — emitted on a single line right
                // after the heading. Each note is a full `[[Penova: key=value]]`.
                var sceneNotes: [String] = []
                if let beat = scene.beatType {
                    sceneNotes.append("[[Penova: beat=\(beat.rawValue)]]")
                }
                if let actNumber = scene.actNumber {
                    sceneNotes.append("[[Penova: actNumber=\(actNumber)]]")
                }
                if scene.bookmarked {
                    sceneNotes.append("[[Penova: bookmarked=true]]")
                }
                if !sceneNotes.isEmpty {
                    out += sceneNotes.joined(separator: " ") + "\n"
                }
                out += "\n"

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

    // MARK: - Helpers

    /// Emit a Fountain title-page key with multi-line continuation
    /// support. The first line follows the colon; subsequent lines
    /// are indented 3 spaces (per fountain.io spec) so the parser
    /// can tell them apart from a fresh key line.
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

    static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }
}
