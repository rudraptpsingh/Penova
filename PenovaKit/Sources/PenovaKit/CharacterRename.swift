//
//  CharacterRename.swift
//  PenovaKit
//
//  Element-aware global character rename — the workflow Final Draft
//  surfaces as Document → Replace Character. Renames every cue that
//  matches the old bare name (ignoring (V.O.)/(O.S.)/(CONT'D)
//  suffixes) in every scene of every project the character belongs to,
//  and refreshes the dialogue/parenthetical row's stored
//  `characterName` so it stays in sync.
//
//  We deliberately do NOT touch dialogue body text, action lines, or
//  parenthetical text — only the structural "this row points at the
//  named speaker" fields. That avoids the classic Find/Replace bug
//  where renaming JANE → JEAN clobbers a "in a vase by Jane" sentence
//  in dialogue or a "Janet" character whose name happens to share a
//  prefix.
//

import Foundation

public enum CharacterRename {

    /// Result of a rename pass — surfaced so the caller can show the
    /// user "X cues + Y dialogue references updated."
    public struct Result: Equatable, Sendable {
        public var cuesUpdated: Int = 0
        public var dialogueRefsUpdated: Int = 0
        public var total: Int { cuesUpdated + dialogueRefsUpdated }
    }

    /// Rename `from` → `to` across a single scene. Returns the count
    /// of changes made. Bare-name match (suffix-stripping) so
    /// `JANE (V.O.)` and `JANE (CONT'D)` both update to `JEAN (V.O.)`
    /// and `JEAN (CONT'D)` respectively.
    ///
    /// Operates on `ScriptScene` directly. Caller is responsible for
    /// `context.save()` after running across every relevant scene.
    @discardableResult
    public static func renameInScene(
        _ scene: ScriptScene,
        from oldName: String,
        to newName: String
    ) -> Result {
        var result = Result()
        let oldBare = EditorLogic.bareCharacterName(oldName)
        let newBare = EditorLogic.bareCharacterName(newName)
        guard !oldBare.isEmpty, !newBare.isEmpty, oldBare != newBare else {
            return result
        }

        for el in scene.elements {
            switch el.kind {
            case .character:
                let bare = EditorLogic.bareCharacterName(el.text)
                if bare == oldBare {
                    // Preserve any trailing suffixes the writer typed
                    // ("JANE (V.O.) (CONT'D)" → "JEAN (V.O.) (CONT'D)").
                    let suffix = trailingSuffixGroups(of: el.text)
                    el.text = suffix.isEmpty
                        ? newBare
                        : "\(newBare) \(suffix)"
                    result.cuesUpdated += 1
                }
            case .dialogue, .parenthetical:
                if let ref = el.characterName,
                   EditorLogic.bareCharacterName(ref) == oldBare {
                    let suffix = trailingSuffixGroups(of: ref)
                    el.characterName = suffix.isEmpty
                        ? newBare
                        : "\(newBare) \(suffix)"
                    result.dialogueRefsUpdated += 1
                }
            default:
                break
            }
        }
        return result
    }

    /// Run the rename across every scene in every project the
    /// character belongs to. Returns the cumulative count.
    @discardableResult
    public static func renameAcrossProjects(
        in projects: [Project],
        from oldName: String,
        to newName: String
    ) -> Result {
        var total = Result()
        for project in projects {
            for episode in project.episodes {
                for scene in episode.scenes {
                    let r = renameInScene(scene, from: oldName, to: newName)
                    total.cuesUpdated += r.cuesUpdated
                    total.dialogueRefsUpdated += r.dialogueRefsUpdated
                }
            }
        }
        return total
    }

    // MARK: - Internals

    /// Returns every trailing `(...)` group in the cue text, joined
    /// with single spaces. Used to preserve `(V.O.)`, `(O.S.)`, and
    /// `(CONT'D)` suffixes when swapping the bare name.
    private static func trailingSuffixGroups(of cue: String) -> String {
        let trimmed = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        var rest = trimmed
        var groups: [String] = []
        while rest.hasSuffix(")") {
            guard let openIdx = rest.lastIndex(of: "(") else { break }
            let group = String(rest[openIdx...])
            groups.append(group)
            rest = String(rest[..<openIdx]).trimmingCharacters(in: .whitespaces)
        }
        return groups.reversed().joined(separator: " ")
    }
}
