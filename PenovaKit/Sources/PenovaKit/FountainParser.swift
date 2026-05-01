//
//  FountainParser.swift
//  Penova
//
//  Pragmatic subset of the Fountain screenplay plain-text format.
//  We only cover what users paste and what we emit — not the full spec.
//
//  Rules:
//    • Lines starting with INT./EXT./EST./INT./EXT. (case-insensitive,
//      allowing leading dots) → Scene heading.
//    • An ALL-CAPS line followed by a non-blank line → Character cue.
//    • A line wrapped in () → Parenthetical.
//    • An ALL-CAPS line ending in "TO:" → Transition.
//    • Everything else → Action.
//    • Blank lines separate elements.
//    • Lines beginning with "Title:" / "Author:" / "Credit:" etc. in the
//      opening title-page section are consumed into `titlePage` metadata
//      (stops at first blank line).
//
//  The parser operates on a plain string and produces a lightweight
//  in-memory model. `FountainImporter` lifts that into SwiftData.
//

import Foundation
import SwiftData

public enum FountainParser {

    public struct ParsedScene: Equatable {
        public var heading: String
        public var elements: [ParsedElement]

        public init(heading: String, elements: [ParsedElement] = []) {
            self.heading = heading
            self.elements = elements
        }
    }

    public struct ParsedElement: Equatable {
        public var kind: SceneElementKind
        public var text: String

        public init(kind: SceneElementKind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public struct ParsedDocument: Equatable {
        public var titlePage: [String: String] = [:]
        public var scenes: [ParsedScene] = []

        public init(titlePage: [String: String] = [:], scenes: [ParsedScene] = []) {
            self.titlePage = titlePage
            self.scenes = scenes
        }
    }

    // MARK: - Parse

    public static func parse(_ source: String) -> ParsedDocument {
        var doc = ParsedDocument()
        // Normalise line endings.
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let allLines = normalized.components(separatedBy: "\n")

        // Title page: at top of file, key: value pairs until a blank line.
        // Continuation lines (indented 3+ spaces or a tab) get appended
        // to the previous key's value, joined with newlines.
        var bodyStart = 0
        if let firstNonEmpty = allLines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           isTitlePageLine(allLines[firstNonEmpty]) {
            var i = firstNonEmpty
            var lastKey: String?
            while i < allLines.count {
                let line = allLines[i]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { bodyStart = i + 1; break }
                if isContinuationLine(line), let prevKey = lastKey {
                    let cont = line.trimmingCharacters(in: .whitespaces)
                    let prev = doc.titlePage[prevKey] ?? ""
                    doc.titlePage[prevKey] = prev.isEmpty ? cont : prev + "\n" + cont
                } else if let (k, v) = parseTitlePageLine(line) {
                    let lk = k.lowercased()
                    doc.titlePage[lk] = v
                    lastKey = lk
                }
                i += 1
                if i == allLines.count { bodyStart = i }
            }
        }

        let lines = Array(allLines[bodyStart...])

        var currentScene: ParsedScene?
        var pendingAction: [String] = []
        var lastElementKind: SceneElementKind?

        func flushActionInto(scene: inout ParsedScene?) {
            let joined = pendingAction.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            pendingAction.removeAll()
            guard !joined.isEmpty else { return }
            if scene == nil {
                // Action before any scene heading: synthesize a placeholder scene.
                scene = ParsedScene(heading: "INT. UNKNOWN - DAY", elements: [])
            }
            scene?.elements.append(ParsedElement(kind: .action, text: joined))
            lastElementKind = .action
        }

        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushActionInto(scene: &currentScene)
                i += 1
                continue
            }

            if isSceneHeading(trimmed) {
                flushActionInto(scene: &currentScene)
                if let s = currentScene { doc.scenes.append(s) }
                currentScene = ParsedScene(heading: normaliseHeading(trimmed), elements: [])
                lastElementKind = .heading
                i += 1
                continue
            }

            if isTransition(trimmed) {
                flushActionInto(scene: &currentScene)
                if currentScene == nil {
                    currentScene = ParsedScene(heading: "INT. UNKNOWN - DAY", elements: [])
                }
                currentScene?.elements.append(ParsedElement(kind: .transition, text: trimmed))
                lastElementKind = .transition
                i += 1
                continue
            }

            if isParenthetical(trimmed), lastElementKind == .character || lastElementKind == .dialogue {
                flushActionInto(scene: &currentScene)
                currentScene?.elements.append(ParsedElement(kind: .parenthetical, text: trimmed))
                lastElementKind = .parenthetical
                i += 1
                continue
            }

            // Character cue: all caps, next non-blank line is dialogue.
            if isCharacterCue(trimmed, next: i + 1 < lines.count ? lines[i + 1] : nil) {
                flushActionInto(scene: &currentScene)
                if currentScene == nil {
                    currentScene = ParsedScene(heading: "INT. UNKNOWN - DAY", elements: [])
                }
                currentScene?.elements.append(ParsedElement(kind: .character, text: characterName(trimmed)))
                lastElementKind = .character
                i += 1
                // Consume dialogue lines (and parentheticals) until blank.
                var dialogueBuf: [String] = []
                while i < lines.count {
                    let d = lines[i]
                    let dt = d.trimmingCharacters(in: .whitespaces)
                    if dt.isEmpty { break }
                    if isParenthetical(dt) {
                        if !dialogueBuf.isEmpty {
                            currentScene?.elements.append(
                                ParsedElement(kind: .dialogue,
                                              text: dialogueBuf.joined(separator: "\n"))
                            )
                            dialogueBuf.removeAll()
                        }
                        currentScene?.elements.append(ParsedElement(kind: .parenthetical, text: dt))
                        lastElementKind = .parenthetical
                        i += 1
                        continue
                    }
                    dialogueBuf.append(dt)
                    i += 1
                }
                if !dialogueBuf.isEmpty {
                    currentScene?.elements.append(
                        ParsedElement(kind: .dialogue,
                                      text: dialogueBuf.joined(separator: "\n"))
                    )
                    lastElementKind = .dialogue
                }
                continue
            }

            pendingAction.append(trimmed)
            i += 1
        }
        flushActionInto(scene: &currentScene)
        if let s = currentScene { doc.scenes.append(s) }

        return doc
    }

    // MARK: - Classifiers

    private static let sceneHeadingPrefixes: [String] = [
        "INT./EXT.", "INT/EXT.", "INT./EXT", "INT/EXT",
        "INT.", "EXT.", "EST.", "INT ", "EXT ", "EST "
    ]

    static func isSceneHeading(_ line: String) -> Bool {
        let upper = line.uppercased()
        // Fountain allows a leading "." to force a scene heading.
        if upper.hasPrefix(".") && !upper.hasPrefix("..") { return true }
        return sceneHeadingPrefixes.contains(where: { upper.hasPrefix($0) })
    }

    static func isTransition(_ line: String) -> Bool {
        let upper = line.uppercased()
        guard upper == line else { return false }            // must be all caps
        return upper.hasSuffix("TO:") || upper == "CUT TO:" || upper == "FADE OUT."
    }

    static func isParenthetical(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("(") && t.hasSuffix(")") && t.count >= 2
    }

    static func isCharacterCue(_ line: String, next: String?) -> Bool {
        guard !line.isEmpty else { return false }
        // Must contain at least one letter.
        guard line.rangeOfCharacter(from: .letters) != nil else { return false }
        // Must be fully upper-cased (ignoring digits/punctuation).
        let letters = line.filter { $0.isLetter }
        guard letters == letters.uppercased() else { return false }
        // Next non-blank line must exist and be non-blank.
        guard let next = next, !next.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        // Avoid false-matching a transition line.
        if isTransition(line) { return false }
        if isSceneHeading(line) { return false }
        // Fountain allows "@NAME" to force a character cue — strip the @
        // when classifying; characterName() will drop it too.
        return true
    }

    static func characterName(_ line: String) -> String {
        var s = line
        if s.hasPrefix("@") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func normaliseHeading(_ line: String) -> String {
        var s = line
        if s.hasPrefix(".") && !s.hasPrefix("..") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces).uppercased()
    }

    // MARK: - Title page

    private static func isTitlePageLine(_ line: String) -> Bool {
        // Minimally: "Key: value" with a recognised key.
        guard let colonIdx = line.firstIndex(of: ":") else { return false }
        let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
        let known: Set<String> = [
            "title", "credit", "author", "authors", "source", "draft date",
            "contact", "copyright", "notes"
        ]
        return known.contains(key)
    }

    private static func parseTitlePageLine(_ line: String) -> (String, String)? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// Per fountain.io: continuation lines for a multi-line title-page
    /// value start with a tab or three or more spaces.
    private static func isContinuationLine(_ line: String) -> Bool {
        if line.hasPrefix("\t") { return true }
        if line.hasPrefix("   ") { return true }
        return false
    }
}

// MARK: - TitlePage extraction

public extension FountainParser.ParsedDocument {
    /// Project-shaped TitlePage from the parsed key/value map. Keys
    /// the parser doesn't recognise are dropped silently.
    var titlePageStruct: TitlePage {
        TitlePage(
            title:     titlePage["title"]      ?? "",
            credit:    titlePage["credit"]     ?? "Written by",
            author:    titlePage["author"]     ?? titlePage["authors"] ?? "",
            source:    titlePage["source"]     ?? "",
            draftDate: titlePage["draft date"] ?? "",
            draftStage: "",
            contact:   titlePage["contact"]    ?? "",
            copyright: titlePage["copyright"]  ?? "",
            notes:     titlePage["notes"]      ?? ""
        )
    }
}

// MARK: - Heading → SceneLocation/locationName/time split

public enum FountainHeadingSplit {
    public struct Split {
        public var location: SceneLocation
        public var locationName: String
        public var time: SceneTimeOfDay
    }

    public static func split(_ heading: String) -> Split {
        let upper = heading.uppercased()
        var rest = upper
        let loc: SceneLocation
        if rest.hasPrefix("INT./EXT.") || rest.hasPrefix("INT/EXT.") || rest.hasPrefix("INT./EXT") || rest.hasPrefix("INT/EXT") {
            loc = .both
            rest = rest.drop(prefix: ["INT./EXT.", "INT/EXT.", "INT./EXT", "INT/EXT"])
        } else if rest.hasPrefix("INT.") || rest.hasPrefix("INT ") {
            loc = .interior
            rest = rest.drop(prefix: ["INT.", "INT "])
        } else if rest.hasPrefix("EXT.") || rest.hasPrefix("EXT ") {
            loc = .exterior
            rest = rest.drop(prefix: ["EXT.", "EXT "])
        } else if rest.hasPrefix("EST.") || rest.hasPrefix("EST ") {
            loc = .exterior
            rest = rest.drop(prefix: ["EST.", "EST "])
        } else {
            loc = .interior
        }
        rest = rest.trimmingCharacters(in: .whitespaces)

        // Optional "-" or "—" separating location from time.
        var name = rest
        var timeRaw = ""
        for sep in [" - ", " — ", " – "] {
            if let r = rest.range(of: sep) {
                name = String(rest[..<r.lowerBound])
                timeRaw = String(rest[r.upperBound...])
                break
            }
        }
        let time = SceneTimeOfDay(rawValue: timeRaw.trimmingCharacters(in: .whitespaces).uppercased()) ?? .day
        return Split(location: loc,
                     locationName: name.trimmingCharacters(in: .whitespaces),
                     time: time)
    }
}

private extension String {
    func drop(prefix candidates: [String]) -> String {
        for c in candidates where self.hasPrefix(c) {
            return String(self.dropFirst(c.count))
        }
        return self
    }
}

// MARK: - SwiftData importer

public enum FountainImporter {

    /// Build a full Project/Episode/Scene tree from a parsed Fountain document.
    /// Caller is responsible for inserting the returned Project into a context
    /// and saving — we just wire up the object graph.
    @MainActor
    public static func makeProject(
        title: String,
        from doc: FountainParser.ParsedDocument,
        context: ModelContext
    ) -> Project {
        let project = Project(title: title)
        // If the source carried a title-page block, hydrate it onto
        // the project. The setter syncs `project.title` and
        // `project.contactBlock` to keep legacy callers in sync.
        if !doc.titlePage.isEmpty {
            var tp = doc.titlePageStruct
            // Caller may have passed an explicit title — preserve it
            // when the parsed title is empty so we don't end up with
            // an "Untitled" project.
            if tp.title.isEmpty { tp.title = title }
            project.titlePage = tp
        }
        context.insert(project)

        let episode = Episode(title: "Pilot", order: 0)
        episode.project = project
        project.episodes.append(episode)
        context.insert(episode)

        for (idx, parsed) in doc.scenes.enumerated() {
            let split = FountainHeadingSplit.split(parsed.heading)
            let scene = ScriptScene(
                locationName: split.locationName.isEmpty ? "UNKNOWN" : split.locationName,
                location: split.location,
                time: split.time,
                order: idx
            )
            scene.episode = episode
            episode.scenes.append(scene)
            context.insert(scene)

            var order = 0
            let headingEl = SceneElement(kind: .heading, text: parsed.heading, order: order)
            headingEl.scene = scene
            scene.elements.append(headingEl)
            context.insert(headingEl)
            order += 1

            var lastCharacter: String?
            for el in parsed.elements {
                let e: SceneElement
                switch el.kind {
                case .character:
                    lastCharacter = el.text
                    e = SceneElement(kind: .character, text: el.text, order: order)
                case .dialogue:
                    e = SceneElement(kind: .dialogue, text: el.text, order: order,
                                     characterName: lastCharacter)
                case .parenthetical:
                    e = SceneElement(kind: .parenthetical, text: el.text, order: order,
                                     characterName: lastCharacter)
                default:
                    e = SceneElement(kind: el.kind, text: el.text, order: order)
                }
                e.scene = scene
                scene.elements.append(e)
                context.insert(e)
                order += 1
            }
        }
        return project
    }
}
