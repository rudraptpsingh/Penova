//
//  ScreenplayPasteConverter.swift
//  PenovaKit
//
//  F4 — Smart paste conversion. Sits one layer above
//  `ScreenplayPasteDetector`: takes a string + the detector's verdict
//  and produces a flat list of typed blocks the editor can insert as
//  SceneElements.
//
//  Two paths:
//
//    • `.fountain` inputs route through the existing FountainParser
//      so we get title-page handling, dot-prefixed headings, @-forced
//      character cues, the works. The first parsed scene's elements
//      become our blocks; if the input has multiple scenes, each
//      scene's heading flattens into a `.heading` block followed by
//      its elements.
//
//    • Word/PDF/email-shaped text uses a lite parser. We split on
//      blank lines into "blocks", classify each block via the same
//      shape predicates the detector uses, and pair character cues
//      with the next block as Dialogue. Anything we can't classify
//      becomes Action — the user can always fix it with the existing
//      element-kind cycle (Tab on Mac, the chip strip on iOS).
//
//  This is deliberately separate from `FountainImporter`: that one
//  builds full Project/Episode/Scene trees, this one stays at the
//  element layer because smart-paste lands inside a single existing
//  scene at the cursor.
//

import Foundation

public enum ScreenplayPasteConverter {

    /// One typed block ready to become a SceneElement. Mirrors the
    /// fields on SceneElement that smart-paste cares about.
    public struct Block: Equatable, Sendable {
        public var kind: SceneElementKind
        public var text: String
        /// Set on dialogue + parenthetical blocks so the SceneElement
        /// inserter can wire them to the speaking character without
        /// having to re-walk the list.
        public var characterName: String?

        public init(
            kind: SceneElementKind,
            text: String,
            characterName: String? = nil
        ) {
            self.kind = kind
            self.text = text
            self.characterName = characterName
        }
    }

    /// Convert a pasted string into typed blocks. Empty / whitespace-
    /// only input returns `[]` (the caller decides whether to no-op
    /// or insert a single empty Action). For the `.plain` path we
    /// emit a single Action block so the caller can use the same
    /// insertion code path either way.
    public static func convert(_ source: String) -> [Block] {
        let verdict = ScreenplayPasteDetector.classify(source)
        return convert(source, verdict: verdict)
    }

    /// Convert with a pre-computed verdict. Useful when the editor has
    /// already classified the paste to decide whether to show a pill —
    /// passing the verdict back avoids classifying twice.
    public static func convert(
        _ source: String,
        verdict: ScreenplayPasteVerdict
    ) -> [Block] {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        switch verdict {
        case .fountain:
            return convertViaFountainParser(source)
        case .maybeScreenplay:
            return convertLite(source)
        case .plain:
            return [Block(kind: .action, text: collapsePlainProse(source))]
        }
    }

    // MARK: - Fountain path

    private static func convertViaFountainParser(_ source: String) -> [Block] {
        let doc = FountainParser.parse(source)
        var blocks: [Block] = []
        var lastCharacter: String?
        for scene in doc.scenes {
            // The placeholder "INT. UNKNOWN - DAY" is what the parser
            // synthesises when action arrives before any heading. We
            // don't want to inject that into the user's existing scene.
            if scene.heading != "INT. UNKNOWN - DAY" {
                blocks.append(Block(kind: .heading, text: scene.heading))
            }
            for el in scene.elements {
                switch el.kind {
                case .character:
                    lastCharacter = el.text
                    blocks.append(Block(kind: .character, text: el.text))
                case .dialogue:
                    blocks.append(Block(
                        kind: .dialogue,
                        text: el.text,
                        characterName: lastCharacter
                    ))
                case .parenthetical:
                    blocks.append(Block(
                        kind: .parenthetical,
                        text: el.text,
                        characterName: lastCharacter
                    ))
                default:
                    blocks.append(Block(kind: el.kind, text: el.text))
                }
            }
        }
        return blocks
    }

    // MARK: - Lite parser (Word/PDF/email)

    /// Block-level classification for non-Fountain screenplay-shaped
    /// text. Splits on blank lines, classifies each block via the
    /// shape predicates from `ScreenplayPasteDetector`, and pairs
    /// character cues with the next block as Dialogue.
    static func convertLite(_ source: String) -> [Block] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        // Group into blocks separated by one-or-more blank lines.
        // A block's text is the joined non-blank lines, trimmed.
        var rawBlocks: [String] = []
        var current: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if !current.isEmpty {
                    rawBlocks.append(current.joined(separator: "\n"))
                    current.removeAll()
                }
            } else {
                current.append(t)
            }
        }
        if !current.isEmpty {
            rawBlocks.append(current.joined(separator: "\n"))
        }

        var out: [Block] = []
        var lastCharacter: String?
        var i = 0
        while i < rawBlocks.count {
            let block = rawBlocks[i]
            let firstLine = block.components(separatedBy: "\n").first ?? block

            // Scene heading — easy, +2 in detector terms.
            if ScreenplayPasteDetector.isSceneHeading(firstLine) {
                out.append(Block(kind: .heading, text: cleaned(block).uppercased()))
                lastCharacter = nil
                i += 1
                continue
            }

            // Transition — ALL-CAPS, single-line shape.
            if block.components(separatedBy: "\n").count == 1,
               ScreenplayPasteDetector.isTransition(firstLine) {
                out.append(Block(kind: .transition, text: cleaned(block)))
                lastCharacter = nil
                i += 1
                continue
            }

            // Character cue: first line of the block is ALL-CAPS,
            // 1–38 chars. Remaining lines (if any) of THIS block are
            // parentheticals + dialogue. If this is a single-line
            // cue block, the *next* block is the dialogue.
            if ScreenplayPasteDetector.isCharacterCueShape(firstLine),
               !ScreenplayPasteDetector.isTransition(firstLine) {
                let blockLines = block.components(separatedBy: "\n")
                let cueText = cleaned(firstLine)
                lastCharacter = cueText
                out.append(Block(kind: .character, text: cueText))

                if blockLines.count > 1 {
                    // The remaining lines of this block are dialogue
                    // (with optional leading parentheticals). The cue
                    // block itself owns the dialogue — typical Word
                    // paste formatting joins them with no blank line
                    // between cue and first dialogue line.
                    let remaining = Array(blockLines.dropFirst())
                    appendDialogueLines(remaining, to: &out, character: lastCharacter)
                    i += 1
                    continue
                }

                // Single-line cue → dialogue lives in the next block.
                i += 1
                if i < rawBlocks.count {
                    let next = rawBlocks[i]
                    let nextLines = next.components(separatedBy: "\n")
                    let nextFirst = nextLines.first ?? next
                    let nextIsHeading = ScreenplayPasteDetector.isSceneHeading(nextFirst)
                    let nextIsCue = nextLines.count == 1
                        && ScreenplayPasteDetector.isCharacterCueShape(nextFirst)
                        && !ScreenplayPasteDetector.isTransition(nextFirst)
                    let nextIsTrans = nextLines.count == 1
                        && ScreenplayPasteDetector.isTransition(nextFirst)
                    if !(nextIsHeading || nextIsCue || nextIsTrans) {
                        appendDialogueLines(nextLines, to: &out, character: lastCharacter)
                        i += 1
                    }
                }
                continue
            }

            // Pure parenthetical block (shouldn't happen often once
            // we've absorbed them into the cue above, but safe to
            // handle).
            if block.components(separatedBy: "\n").count == 1,
               ScreenplayPasteDetector.isParenthetical(firstLine) {
                out.append(Block(
                    kind: .parenthetical,
                    text: cleaned(block),
                    characterName: lastCharacter
                ))
                i += 1
                continue
            }

            // Default — Action.
            out.append(Block(kind: .action, text: cleaned(block)))
            lastCharacter = nil
            i += 1
        }
        return out
    }

    /// Split a slice of lines into leading parentheticals followed by
    /// dialogue, append both to `out`. Used by the cue path so a Word
    /// paste like `MARY\n(beat)\nWhat?` produces three properly-typed
    /// blocks (character / parenthetical / dialogue).
    private static func appendDialogueLines(
        _ lines: [String],
        to out: inout [Block],
        character: String?
    ) {
        var parenLines: [String] = []
        var dialogueLines: [String] = []
        var sawNonParen = false
        for ln in lines {
            let t = ln.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if !sawNonParen, ScreenplayPasteDetector.isParenthetical(t) {
                parenLines.append(t)
            } else {
                sawNonParen = true
                dialogueLines.append(t)
            }
        }
        for p in parenLines {
            out.append(Block(
                kind: .parenthetical,
                text: p,
                characterName: character
            ))
        }
        let dialogueText = cleaned(dialogueLines.joined(separator: "\n"))
        if !dialogueText.isEmpty {
            out.append(Block(
                kind: .dialogue,
                text: dialogueText,
                characterName: character
            ))
        }
    }

    // MARK: - Text cleanup

    /// Strip leading/trailing whitespace from each line, drop empty
    /// trailing lines, collapse runs of internal whitespace to a
    /// single space within each line.
    private static func cleaned(_ raw: String) -> String {
        let lines = raw.components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Collapse multi-space runs (Word PDF copy often
                // smuggles in tabs / runs of spaces from indents).
                return trimmed
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// For the `.plain` path: collapse aggressive whitespace but keep
    /// paragraph breaks. The result becomes the body of a single
    /// Action element.
    private static func collapsePlainProse(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Split into paragraphs on blank lines, clean each, rejoin.
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { para -> String in
                para
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        return paragraphs.joined(separator: "\n\n")
    }
}
