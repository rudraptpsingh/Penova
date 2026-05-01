//
//  ProductionReports.swift
//  PenovaKit
//
//  Pre-production breakdown reports: scene-by-scene, location, and
//  cast roll-ups that script supervisors / line producers / first ADs
//  pull off a "locked" script. Final Draft has these under Production
//  → Reports; Penova ships the same data shapes so the writer can
//  hand off the script without round-tripping through Final Draft.
//
//  All three reports are pure functions over the in-memory project
//  graph. No SwiftData fetches — caller passes the materialised
//  `Project`. Returns Codable rows so we can later emit JSON / CSV /
//  print-friendly PDFs from the same source.
//

import Foundation

@MainActor
public enum ProductionReports {

    // MARK: - Scene report

    /// One row per scene. Agnostic to whether the project has been
    /// "locked" — scene number is the writer's current 1-based count
    /// across the project (resets per episode if the project has
    /// >1 episode, matching ScriptPDFRenderer's gutter numbering).
    public struct SceneRow: Equatable, Codable, Identifiable {
        public var id: String { "\(episodeOrder)-\(sceneOrder)" }
        public let episodeOrder: Int
        public let episodeTitle: String
        /// 1-based per-episode scene number when the project has
        /// multiple episodes; otherwise 1-based across the project.
        public let sceneNumber: Int
        /// Underlying SwiftData `ScriptScene.order` so the UI can
        /// resolve back to the model object.
        public let sceneOrder: Int
        public let intExt: String       // "INT", "EXT", or "INT/EXT"
        public let location: String
        public let time: String
        public let heading: String
        public let cueCount: Int        // distinct character cues in this scene
        public let dialogueWordCount: Int
        public let totalWordCount: Int
    }

    public static func sceneReport(for project: Project) -> [SceneRow] {
        var rows: [SceneRow] = []
        let resetPerEpisode = project.activeEpisodesOrdered.count > 1
        for episode in project.activeEpisodesOrdered {
            var n = 1
            if !resetPerEpisode {
                // Continue numbering from the previous episode in
                // single-stream mode (project has only this one).
                n = (rows.last?.sceneNumber ?? 0) + 1
            }
            for scene in episode.scenesOrdered {
                // Mirror the renderer: when the project is locked,
                // emit the frozen scene number from the snapshot;
                // otherwise use the live 1-based counter.
                let renderNumber = project.renderSceneNumber(for: scene, live: n)
                let dialogueWords = scene.elementsOrdered
                    .filter { $0.kind == .dialogue }
                    .reduce(0) { $0 + wordCount(of: $1.text) }
                let totalWords = scene.elementsOrdered
                    .reduce(0) { $0 + wordCount(of: $1.text) }
                let cues = Set(scene.elementsOrdered
                    .filter { $0.kind == .character }
                    .map { stripCueSuffix($0.text).uppercased() }
                    .filter { !$0.isEmpty })
                rows.append(SceneRow(
                    episodeOrder: episode.order,
                    episodeTitle: episode.title,
                    sceneNumber: renderNumber,
                    sceneOrder: scene.order,
                    intExt: scene.location.rawValue,
                    location: scene.locationName,
                    time: scene.time.rawValue,
                    heading: scene.heading,
                    cueCount: cues.count,
                    dialogueWordCount: dialogueWords,
                    totalWordCount: totalWords
                ))
                n += 1
            }
        }
        return rows
    }

    // MARK: - Location report

    /// One row per distinct location. Counts every scene set there,
    /// rolled up by INT/EXT so the same location at different times
    /// of day still aggregates.
    public struct LocationRow: Equatable, Codable, Identifiable {
        public var id: String { "\(intExt)|\(location)" }
        public let location: String
        public let intExt: String
        public let sceneCount: Int
        /// Distinct character cues that appear in any scene at this
        /// location — useful for casting at one shooting unit.
        public let distinctCues: Int
        /// Total words across every scene at this location.
        public let totalWordCount: Int
    }

    public static func locationReport(for project: Project) -> [LocationRow] {
        struct Bucket {
            var sceneCount: Int = 0
            var cues: Set<String> = []
            var words: Int = 0
        }
        var buckets: [String: (location: String, intExt: String, b: Bucket)] = [:]
        for ep in project.activeEpisodesOrdered {
            for scene in ep.scenesOrdered {
                let location = scene.locationName.uppercased()
                guard !location.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let key = "\(scene.location.rawValue)|\(location)"
                var entry = buckets[key]
                    ?? (location: location, intExt: scene.location.rawValue, b: Bucket())
                entry.b.sceneCount += 1
                let cues = scene.elementsOrdered
                    .filter { $0.kind == .character }
                    .map { stripCueSuffix($0.text).uppercased() }
                    .filter { !$0.isEmpty }
                entry.b.cues.formUnion(cues)
                entry.b.words += scene.elementsOrdered
                    .reduce(0) { $0 + wordCount(of: $1.text) }
                buckets[key] = entry
            }
        }
        return buckets
            .map { _, v in
                LocationRow(
                    location: v.location,
                    intExt: v.intExt,
                    sceneCount: v.b.sceneCount,
                    distinctCues: v.b.cues.count,
                    totalWordCount: v.b.words
                )
            }
            .sorted {
                if $0.sceneCount != $1.sceneCount { return $0.sceneCount > $1.sceneCount }
                return $0.location < $1.location
            }
    }

    // MARK: - Cast report

    /// One row per distinct character cue. Counts all dialogue lines
    /// the cue speaks plus a word total. Useful for casting (the
    /// biggest roles float to the top).
    public struct CastRow: Equatable, Codable, Identifiable {
        public var id: String { name }
        public let name: String
        /// Number of `.dialogue` blocks attributed to this cue.
        public let dialogueBlockCount: Int
        /// Total words across all of this cue's dialogue blocks.
        public let dialogueWordCount: Int
        /// Distinct scenes this cue appears in.
        public let sceneAppearances: Int
    }

    public static func castReport(for project: Project) -> [CastRow] {
        struct Stats {
            var blocks = 0
            var words = 0
            var scenes: Set<String> = []
        }
        var byName: [String: Stats] = [:]
        for ep in project.activeEpisodesOrdered {
            for scene in ep.scenesOrdered {
                let elements = scene.elementsOrdered
                var lastCue: String?
                for el in elements {
                    if el.kind == .character {
                        lastCue = stripCueSuffix(el.text).uppercased()
                        if let cue = lastCue, !cue.isEmpty {
                            byName[cue, default: Stats()].scenes.insert("\(ep.order)-\(scene.order)")
                        }
                    } else if el.kind == .dialogue, let cue = lastCue, !cue.isEmpty {
                        var s = byName[cue, default: Stats()]
                        s.blocks += 1
                        s.words += wordCount(of: el.text)
                        byName[cue] = s
                    }
                }
            }
        }
        return byName
            .map { name, s in
                CastRow(
                    name: name,
                    dialogueBlockCount: s.blocks,
                    dialogueWordCount: s.words,
                    sceneAppearances: s.scenes.count
                )
            }
            .sorted {
                if $0.dialogueWordCount != $1.dialogueWordCount {
                    return $0.dialogueWordCount > $1.dialogueWordCount
                }
                return $0.name < $1.name
            }
    }

    // MARK: - Helpers

    /// Spreadsheet-style word count: split on whitespace + newlines,
    /// drop empty tokens. Mirrors `HabitTracker.wordCount` so the
    /// production cast-by-words report agrees with the daily writing
    /// goal numbers.
    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count
    }

    /// Strip trailing parenthetical from a character cue
    /// ("ALICE (CONT'D)" → "ALICE") so all of one character's
    /// dialogue rolls into a single cast row.
    static func stripCueSuffix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let idx = trimmed.firstIndex(of: "(") {
            return String(trimmed[..<idx])
                .trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
