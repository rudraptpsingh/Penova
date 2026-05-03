//
//  TableReadEngine.swift
//  PenovaKit
//
//  Turns a scene's elements into an ordered queue of read items —
//  (voiceID, text, kind) tuples the TTS pipeline plays back. Pure
//  logic; the actual AVSpeechSynthesizer / ElevenLabs driver lives
//  in the apps and consumes this queue.
//
//  Settings respected (matches the mockup's listen-options panel):
//    • readActionLines       — default true. False → skip action.
//    • readParentheticals    — default false. The mockup ships this
//                              off; it's a paragraph-of-static for
//                              most reads. Switchable.
//    • Headings, transitions, act-breaks, character cues are NEVER
//      read aloud — they're structural, not voiced.
//
//  Voice resolution:
//    • Speaking characters     → assigned voice, or auto-suggested
//                                from VoiceCatalogue.
//    • Action / narration      → catalogue's `narratorID`.
//    • Unknown character       → fall back to narrator (the engine
//                                won't crash on weird data).
//

import Foundation

@MainActor
public enum TableReadEngine {

    // MARK: - Settings

    public struct Settings: Equatable, Sendable {
        public var readActionLines: Bool
        public var readParentheticals: Bool
        public var sceneEndChime: Bool
        /// 0.7 – 1.5 nominal. Stored on the engine output so the TTS
        /// driver can apply it; the engine itself doesn't time playback.
        public var pace: Double

        public init(
            readActionLines: Bool = true,
            readParentheticals: Bool = false,
            sceneEndChime: Bool = false,
            pace: Double = 1.0
        ) {
            self.readActionLines = readActionLines
            self.readParentheticals = readParentheticals
            self.sceneEndChime = sceneEndChime
            self.pace = max(0.5, min(2.0, pace))
        }

        public static let `default` = Settings()
    }

    // MARK: - Read item

    public struct ReadItem: Equatable, Sendable {

        public enum Kind: String, Sendable {
            case action
            case dialogue
            case parenthetical
        }

        /// The SceneElement.id this item corresponds to. The UI uses
        /// this to highlight the "now playing" line as the queue
        /// advances.
        public let elementID: ID
        public let kind: Kind
        public let text: String
        public let voiceID: String
        /// nil for action/narration; uppercased character name for
        /// dialogue + parenthetical lines.
        public let characterName: String?

        public init(
            elementID: ID,
            kind: Kind,
            text: String,
            voiceID: String,
            characterName: String?
        ) {
            self.elementID = elementID
            self.kind = kind
            self.text = text
            self.voiceID = voiceID
            self.characterName = characterName
        }
    }

    // MARK: - Build queue

    /// Build the read queue for one scene. Pure: no side effects, no
    /// audio. Caller drives TTS using the returned items in order.
    public static func queue(
        for scene: ScriptScene,
        assignments: [String: VoiceAssignment],
        settings: Settings = .default,
        narratorVoiceID: String = VoiceCatalogue.narratorID
    ) -> [ReadItem] {

        var items: [ReadItem] = []
        items.reserveCapacity(scene.elementsOrdered.count)

        // Track the most recent character cue so we know who's speaking
        // for the dialogue/parenthetical lines that follow.
        var currentSpeaker: String?

        for el in scene.elementsOrdered {
            switch el.kind {
            case .heading, .transition, .actBreak:
                // Structural — never voiced. Reset the speaker so a
                // new scene doesn't inherit the previous cue.
                currentSpeaker = nil

            case .character:
                // Cue itself isn't voiced — it just sets the speaker.
                let name = el.characterName ?? el.text
                currentSpeaker = name.uppercased()

            case .dialogue:
                let speaker = (el.characterName ?? currentSpeaker)?.uppercased()
                let voice = voiceID(for: speaker, assignments: assignments)
                items.append(.init(
                    elementID: el.id,
                    kind: .dialogue,
                    text: el.text,
                    voiceID: voice,
                    characterName: speaker
                ))

            case .parenthetical:
                guard settings.readParentheticals else { continue }
                let speaker = (el.characterName ?? currentSpeaker)?.uppercased()
                let voice = voiceID(for: speaker, assignments: assignments)
                items.append(.init(
                    elementID: el.id,
                    kind: .parenthetical,
                    text: stripParentheses(el.text),
                    voiceID: voice,
                    characterName: speaker
                ))

            case .action:
                guard settings.readActionLines else { continue }
                items.append(.init(
                    elementID: el.id,
                    kind: .action,
                    text: el.text,
                    voiceID: narratorVoiceID,
                    characterName: nil
                ))
            }
        }

        return items
    }

    /// Build a queue for an entire episode (scene-by-scene, in order).
    /// Convenient for "read the whole thing" mode.
    public static func queue(
        for episode: Episode,
        assignments: [String: VoiceAssignment],
        settings: Settings = .default,
        narratorVoiceID: String = VoiceCatalogue.narratorID
    ) -> [ReadItem] {
        episode.scenesOrdered.flatMap {
            queue(
                for: $0,
                assignments: assignments,
                settings: settings,
                narratorVoiceID: narratorVoiceID
            )
        }
    }

    // MARK: - Helpers

    /// Resolve a character's voice. Order:
    ///   1. Explicit assignment in the project.
    ///   2. Auto-suggest from VoiceCatalogue.
    ///   3. Fall back to "Rohan" (catalogue's neutral mid-tone).
    /// Never returns nil — fail-safe so the read never stalls on weird
    /// data.
    static func voiceID(
        for speaker: String?,
        assignments: [String: VoiceAssignment]
    ) -> String {
        guard let speaker, !speaker.isEmpty else {
            return VoiceCatalogue.narratorID
        }
        if let row = assignments[speaker.uppercased()] {
            return row.voiceID
        }
        // No assignment — use a stable default so the same character
        // always gets the same voice across sessions even before
        // the user opens the voice panel.
        return VoiceCatalogue.suggest(
            gender: nil,
            approximateAge: nil,
            register: nil
        ).id
    }

    /// Trim outer parens from a parenthetical's stored text so the
    /// TTS pipeline doesn't say "open paren quietly close paren".
    /// Idempotent — text without parens passes through unchanged.
    static func stripParentheses(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("(") { t.removeFirst() }
        if t.hasSuffix(")") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
