//
//  AutocompleteService.swift
//  PenovaKit
//
//  Pure-Swift autocomplete suggestions for the screenplay editor:
//   • Locations — unique INT/EXT names already used in this project,
//     so the next scene can reuse "MUMBAI LOCAL TRAIN" without the
//     writer re-typing or risking case drift.
//   • Character cues — every distinct character name that appears in
//     a `.character` element across the project, plus all explicitly
//     created `ScriptCharacter` records. Catches characters the user
//     types directly into the editor without first registering them
//     in the Characters tab (Final Draft / Highland behaviour).
//
//  Both functions are pure: they take an in-memory snapshot and
//  return the sorted unique candidate list. The view layer pairs the
//  result with the user's current query via `EditorLogic.suggestions`
//  to filter case-insensitively.
//

import Foundation

@MainActor
public enum AutocompleteService {

    // MARK: - Locations

    /// Distinct, uppercased location names from every scene in this
    /// project. Sorted by recent-edit frequency descending so the
    /// writer's most-used locations float to the top.
    public static func locations(in project: Project) -> [String] {
        var counts: [String: Int] = [:]
        for ep in project.activeEpisodesOrdered {
            for s in ep.scenesOrdered {
                let name = s.locationName
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
                guard !name.isEmpty else { continue }
                counts[name, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }

    // MARK: - Character cues

    /// Every distinct character cue used in this project, including
    /// names typed directly into `.character` elements and not yet
    /// promoted to the Characters tab. Returns uppercased names sorted
    /// by usage frequency (most-frequent first).
    public static func characterCues(in project: Project) -> [String] {
        var counts: [String: Int] = [:]

        // Cues already typed in scene-element streams.
        for ep in project.activeEpisodesOrdered {
            for s in ep.scenesOrdered {
                for el in s.elementsOrdered where el.kind == .character {
                    let cleaned = stripCueSuffix(el.text)
                        .trimmingCharacters(in: .whitespaces)
                        .uppercased()
                    guard !cleaned.isEmpty else { continue }
                    counts[cleaned, default: 0] += 1
                }
            }
        }

        // Names registered in the Characters tab — count once, so a
        // brand-new project's character roster still autocompletes
        // even before any scene has been written.
        for ch in project.characters where !ch.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = ch.name.uppercased()
            counts[key, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }

    // MARK: - Helpers

    /// Strip "(CONT'D)", "(V.O.)", "(O.S.)" etc. from a character cue
    /// before counting it as a distinct cue. Otherwise the autocomplete
    /// would surface "ALICE" and "ALICE (CONT'D)" as separate names.
    static func stripCueSuffix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let idx = trimmed.firstIndex(of: "(") {
            return String(trimmed[..<idx])
                .trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}
