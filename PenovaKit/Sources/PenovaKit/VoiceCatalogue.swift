//
//  VoiceCatalogue.swift
//  PenovaKit
//
//  Built-in voice presets for the Voiced Table Read feature. Curated
//  for the Indian-context default project — the mockup pairs ARJUN
//  with "Vihaan", ZAINA with "Aanya", and so on. Each preset carries
//  enough metadata to drive the auto-assignment heuristic
//  (gender / age / register / locale) and to render the row in the
//  voice panel ("Vihaan — low, weathered, 30s").
//
//  Eight presets ship by default — enough to cover protagonist,
//  antagonist, and a handful of supporting roles. Premium voices
//  (ElevenLabs etc.) are added later behind a Pro tier; this file
//  ships only the system-AV-speech-synth-compatible defaults.
//

import Foundation

// MARK: - Preset

public struct VoicePreset: Equatable, Hashable, Codable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    /// Free-form descriptor surfaced in the UI ("low, weathered, mid-40s").
    public let descriptor: String
    public let gender: VoiceGender
    /// Approximate age in years used by the auto-assignment heuristic.
    /// 30 = mid-30s; 60 = 60s. Inclusive on both ends.
    public let ageRangeStart: Int
    public let ageRangeEnd: Int
    public let register: VoiceRegister
    /// BCP-47 locale hint for the TTS provider ("en-IN", "en-US").
    public let localeHint: String
    /// Provider abstraction — `system` is AVSpeechSynthesizer; `elevenLabs`
    /// flags Pro voices that need a network call. The engine consumes
    /// presets the same way; the provider routing happens later.
    public let provider: VoiceProvider

    public init(
        id: String,
        displayName: String,
        descriptor: String,
        gender: VoiceGender,
        ageRangeStart: Int,
        ageRangeEnd: Int,
        register: VoiceRegister,
        localeHint: String = "en-IN",
        provider: VoiceProvider = .system
    ) {
        self.id = id
        self.displayName = displayName
        self.descriptor = descriptor
        self.gender = gender
        self.ageRangeStart = ageRangeStart
        self.ageRangeEnd = ageRangeEnd
        self.register = register
        self.localeHint = localeHint
        self.provider = provider
    }

    public func contains(age: Int) -> Bool {
        age >= ageRangeStart && age <= ageRangeEnd
    }
}

// MARK: - Enums

public enum VoiceGender: String, Codable, CaseIterable, Sendable {
    case male, female, neutral
}

public enum VoiceRegister: String, Codable, CaseIterable, Sendable {
    case warm        // Aanya, June
    case low         // Vihaan, Marcus
    case clipped     // Saraswati
    case bright      // Kai
    case neutral     // Narrator
    case gravel      // older male
}

public enum VoiceProvider: String, Codable, CaseIterable, Sendable {
    case system      // AVSpeechSynthesizer — ships day-one, free
    case elevenLabs  // Premium, behind Pro tier in v1.5
}

// MARK: - Catalogue

public enum VoiceCatalogue {

    public static let narratorID = "system-narrator"

    /// Eight system presets. Order is the default UI order in the
    /// "Change voice" picker.
    public static let presets: [VoicePreset] = [
        .init(
            id: "system-vihaan",
            displayName: "Vihaan",
            descriptor: "low, weathered, mid-30s",
            gender: .male,
            ageRangeStart: 28, ageRangeEnd: 42,
            register: .low
        ),
        .init(
            id: "system-aanya",
            displayName: "Aanya",
            descriptor: "warm, measured, late-20s",
            gender: .female,
            ageRangeStart: 22, ageRangeEnd: 35,
            register: .warm
        ),
        .init(
            id: "system-saraswati",
            displayName: "Saraswati",
            descriptor: "clipped, regional, 60s",
            gender: .female,
            ageRangeStart: 55, ageRangeEnd: 75,
            register: .clipped
        ),
        .init(
            id: "system-kabir",
            displayName: "Kabir",
            descriptor: "gravel, older man, 60s",
            gender: .male,
            ageRangeStart: 55, ageRangeEnd: 80,
            register: .gravel
        ),
        .init(
            id: "system-meera",
            displayName: "Meera",
            descriptor: "bright, young woman, 20s",
            gender: .female,
            ageRangeStart: 18, ageRangeEnd: 28,
            register: .bright
        ),
        .init(
            id: "system-kai",
            displayName: "Kai",
            descriptor: "light, slightly nasal, 20s",
            gender: .male,
            ageRangeStart: 18, ageRangeEnd: 28,
            register: .bright
        ),
        .init(
            id: "system-rohan",
            displayName: "Rohan",
            descriptor: "neutral, mid-tone, 30s—40s",
            gender: .male,
            ageRangeStart: 30, ageRangeEnd: 50,
            register: .neutral
        ),
        .init(
            id: narratorID,
            displayName: "Narrator",
            descriptor: "Penova default — neutral action voice",
            gender: .neutral,
            ageRangeStart: 0, ageRangeEnd: 200,
            register: .neutral
        )
    ]

    public static func preset(id: String) -> VoicePreset? {
        presets.first(where: { $0.id == id })
    }

    /// Best-fit preset for a character given a few hints. Used by the
    /// auto-assignment pass when the writer first opens the table read.
    /// Falls back to `Rohan` (a neutral mid-tone male) when nothing
    /// else matches — never returns the narrator preset for a
    /// speaking character.
    public static func suggest(
        gender: VoiceGender? = nil,
        approximateAge: Int? = nil,
        register: VoiceRegister? = nil
    ) -> VoicePreset {
        let speaking = presets.filter { $0.id != narratorID }
        // Score each preset by how many hints it satisfies.
        let scored = speaking.map { preset -> (VoicePreset, Int) in
            var score = 0
            if let gender, preset.gender == gender { score += 3 }
            if let register, preset.register == register { score += 2 }
            if let approximateAge, preset.contains(age: approximateAge) {
                score += 2
            }
            return (preset, score)
        }
        let best = scored.max(by: { $0.1 < $1.1 })
        return best?.0 ?? speaking.first(where: { $0.id == "system-rohan" })!
    }
}
