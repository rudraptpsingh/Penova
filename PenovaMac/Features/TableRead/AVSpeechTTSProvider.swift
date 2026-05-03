//
//  AVSpeechTTSProvider.swift
//  Penova for Mac
//
//  Day-one TTS provider — wraps AVSpeechSynthesizer. On-device,
//  network-free, ships in macOS 14+. Maps PenovaKit voice presets to
//  AVSpeechSynthesisVoice instances by locale + gender hint.
//
//  Future: ElevenLabs adapter behind a Pro tier. Same protocol; the
//  player won't notice.
//

import Foundation
import AVFoundation
import PenovaKit

@MainActor
final class AVSpeechTTSProvider: NSObject, TTSProvider {

    private let synth = AVSpeechSynthesizer()
    private var pendingFinish: (() -> Void)?
    private var rateMultiplier: Float = 1.0
    /// Number of chunk utterances still in flight for the current
    /// line. We fire `pendingFinish` (which advances the player) only
    /// when this hits zero — so a 3-chunk line doesn't advance 3
    /// times.
    private var pendingChunkCount: Int = 0

    var isSpeaking: Bool { synth.isSpeaking }

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Track previous voice so we know when the speaker changes —
    /// drop a longer silence between people, the way actors do in a
    /// real table read.
    private var lastVoiceID: String?

    func speak(
        _ item: TableReadEngine.ReadItem,
        onFinished: @escaping () -> Void
    ) {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { onFinished(); return }

        let resolved = resolveVoice(for: item.voiceID)
        let speakerChanged = (lastVoiceID != nil && lastVoiceID != item.voiceID)
        lastVoiceID = item.voiceID

        // Split the line into sub-utterances at human-pause punctuation
        // so the engine inserts real silence at em-dashes, ellipses,
        // semicolons, and question/exclamation marks — the places a
        // real reader breathes. AVSpeech default voices ignore these
        // markers prosodically; we make them audible by ending one
        // utterance and starting another with a silence in between.
        let chunks = Self.chunkForProsody(text)
        guard let lastIdx = chunks.indices.last else {
            onFinished()
            return
        }

        // Fire onFinished only after the LAST chunk's didFinish.
        // pendingChunkCount counts down as each chunk completes; the
        // didFinish delegate calls pendingFinish only when it reaches 0.
        pendingFinish = onFinished
        pendingChunkCount = chunks.count

        for (idx, chunk) in chunks.enumerated() {
            let isFirst = (idx == 0)
            let isLast = (idx == lastIdx)

            let u = AVSpeechUtterance(string: chunk.text)
            u.voice = resolved.voice

            // Rate: 0.92× default + ±5% per-utterance jitter so the
            // cadence doesn't sound metronome-flat. Bounded by
            // AVSpeech's hard min/max.
            let rateJitter = 1.0 + Float.random(in: -0.05...0.05)
            let baseRate = AVSpeechUtteranceDefaultSpeechRate * 0.92 * rateJitter
            u.rate = max(
                AVSpeechUtteranceMinimumSpeechRate,
                min(AVSpeechUtteranceMaximumSpeechRate, baseRate * rateMultiplier)
            )

            // Pitch: preset baseline + small per-utterance jitter so
            // consecutive lines from the same speaker don't drone
            // identically. Jitter is small enough that the speaker
            // remains recognisable.
            let pitchJitter = Float.random(in: -0.04...0.04)
            u.pitchMultiplier = max(
                0.5,
                min(2.0, resolved.pitchMultiplier + pitchJitter)
            )
            u.volume = 1.0

            // Pre-utterance pause: only on the first chunk of a line.
            // Bigger gap when the speaker changed (the "beat" between
            // people, like a real table read).
            u.preUtteranceDelay = isFirst
                ? (speakerChanged ? 0.55 : 0.20)
                : 0.0

            // Post-utterance pause: short between mid-line chunks
            // (the breath after an em-dash); longer at the end of the
            // whole line so the next speaker's pre-pause has room.
            u.postUtteranceDelay = isLast ? 0.35 : chunk.trailingPause

            synth.speak(u)
        }
    }

    // MARK: - Prosody chunking

    /// A piece of a line plus the silence that should follow it.
    /// Ellipses get the longest mid-line silence; commas the shortest.
    fileprivate struct ProsodyChunk {
        let text: String
        let trailingPause: TimeInterval
    }

    /// Split a sentence on the punctuation that signals a real human
    /// pause. AVSpeech default voices ignore em-dashes and ellipses
    /// audibly — we make them audible by ending one utterance and
    /// starting another with silence in between.
    fileprivate static func chunkForProsody(_ text: String) -> [ProsodyChunk] {
        // Markers and the silence each should produce mid-line.
        // Order matters within the loop only as a tie-breaker — we
        // find the EARLIEST occurrence regardless.
        let markers: [(String, TimeInterval, String?)] = [
            // text         pause   keep-with-chunk
            ("…",            0.55,   "…"),
            ("...",          0.55,   "..."),
            (" — ",          0.40,   nil),
            ("—",            0.40,   nil),
            ("? ",           0.45,   "?"),
            ("! ",           0.40,   "!"),
            ("; ",           0.30,   ";"),
            (": ",           0.25,   ":"),
            (", ",           0.18,   ",")
        ]

        var chunks: [ProsodyChunk] = []
        var remaining = text

        while !remaining.isEmpty {
            // Find the EARLIEST marker occurrence.
            var earliestRange: Range<String.Index>?
            var pause: TimeInterval = 0
            var keepChar: String?
            for (m, p, k) in markers {
                guard let r = remaining.range(of: m) else { continue }
                if earliestRange == nil || r.lowerBound < earliestRange!.lowerBound {
                    earliestRange = r
                    pause = p
                    keepChar = k
                }
            }
            guard let r = earliestRange else {
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chunks.append(.init(text: trimmed, trailingPause: 0))
                }
                break
            }
            var head = String(remaining[..<r.lowerBound])
            if let keepChar { head += keepChar }
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(.init(text: trimmed, trailingPause: pause))
            }
            remaining = String(remaining[r.upperBound...])
        }

        return chunks.isEmpty
            ? [.init(text: text, trailingPause: 0)]
            : chunks
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        pendingFinish = nil
        pendingChunkCount = 0
        lastVoiceID = nil  // Next utterance after stop is a fresh start.
    }

    func pause() {
        synth.pauseSpeaking(at: .immediate)
    }

    func resume() {
        synth.continueSpeaking()
    }

    func setRate(_ rate: Double) {
        rateMultiplier = Float(max(0.5, min(2.0, rate)))
    }

    // MARK: - Voice mapping

    /// Voice resolution result — a system voice + a pitch tweak. Pitch
    /// differentiation is how we get distinct timbres out of the same
    /// underlying engine when only default-tier voices are installed.
    struct ResolvedVoice {
        let voice: AVSpeechSynthesisVoice?
        let pitchMultiplier: Float
    }

    /// Curated map: each Penova catalogue preset → preferred system
    /// voice name (case-insensitive prefix match) + pitch multiplier.
    /// macOS ships these voices by default on every install, so the
    /// table read produces 4–6 distinguishable timbres without the user
    /// downloading anything.
    ///
    /// Order of names is preference; we walk the list and take the
    /// first installed match. Pitch multiplier shifts the same engine
    /// voice up or down so e.g. Vihaan and Kai (both male, both fall
    /// back to Rishi/Daniel on stock macOS) still sound different.
    private static let presetVoiceMap: [String: (names: [String], pitch: Float)] = [
        "system-vihaan":     (["Rishi", "Daniel", "Alex"],         0.92),  // mid-30s male, low
        "system-aanya":      (["Samantha", "Karen", "Moira"],      1.05),  // late-20s female, warm
        "system-saraswati":  (["Moira", "Tessa", "Karen"],         0.92),  // 60s female, clipped
        "system-kabir":      (["Daniel", "Rishi", "Alex"],         0.85),  // 60s male, gravel
        "system-meera":      (["Karen", "Samantha", "Tessa"],      1.15),  // 20s female, bright
        "system-kai":        (["Daniel", "Rishi", "Alex"],         1.10),  // 20s male, bright
        "system-rohan":      (["Rishi", "Daniel"],                 1.00),  // 30s—40s male, neutral
        "system-narrator":   (["Samantha", "Daniel", "Rishi"],     0.95)   // neutral narrator
    ]

    /// Map a PenovaKit voice id to a system voice + pitch.
    ///
    /// Resolution order:
    ///   1. Curated preset map → first installed name match. Walks
    ///      premium → enhanced → default tiers within the name.
    ///   2. If no curated match installed, falls back to gender heuristic
    ///      + locale match (existing behaviour).
    ///   3. Locale fallback to `AVSpeechSynthesisVoice(language:)`.
    private func resolveVoice(for voiceID: String) -> ResolvedVoice {
        guard let preset = VoiceCatalogue.preset(id: voiceID) else {
            return ResolvedVoice(
                voice: AVSpeechSynthesisVoice(language: "en-IN"),
                pitchMultiplier: 1.0
            )
        }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let curated = Self.presetVoiceMap[preset.id]
        let pitch: Float = curated?.pitch ?? 1.0

        // Curated path: walk preferred names, prefer higher quality.
        if let names = curated?.names {
            for name in names {
                let matches = allVoices.filter {
                    $0.name.lowercased().contains(name.lowercased())
                }
                for quality in [
                    AVSpeechSynthesisVoiceQuality.premium,
                    .enhanced,
                    .default
                ] {
                    if let v = matches.first(where: { $0.quality == quality }) {
                        return ResolvedVoice(voice: v, pitchMultiplier: pitch)
                    }
                }
            }
        }

        // Fallback: locale + gender heuristic, premium-first.
        let localeMatched = allVoices.filter {
            $0.language.hasPrefix(preset.localeHint.prefix(2))
        }
        let candidatePool = localeMatched.isEmpty
            ? allVoices.filter { $0.language.hasPrefix("en") }
            : localeMatched
        for quality in [
            AVSpeechSynthesisVoiceQuality.premium,
            .enhanced,
            .default
        ] {
            let tier = candidatePool.filter { $0.quality == quality }
            if let genderHit = tier.first(where: {
                isMatch(systemVoiceName: $0.name, gender: preset.gender)
            }) {
                return ResolvedVoice(voice: genderHit, pitchMultiplier: pitch)
            }
            if let any = tier.first {
                return ResolvedVoice(voice: any, pitchMultiplier: pitch)
            }
        }
        return ResolvedVoice(
            voice: AVSpeechSynthesisVoice(language: preset.localeHint),
            pitchMultiplier: pitch
        )
    }

    /// Backwards-compatible shim — older sites still call pickVoice.
    private func pickVoice(for voiceID: String) -> AVSpeechSynthesisVoice? {
        resolveVoice(for: voiceID).voice
    }

    /// Crude gender heuristic from system voice names. macOS exposes
    /// names like "Veena", "Rishi" — we match against well-known
    /// Indian-English voices first and fall back to generic.
    private func isMatch(systemVoiceName name: String, gender: VoiceGender) -> Bool {
        let lower = name.lowercased()
        switch gender {
        case .male:
            return ["rishi", "alex", "aaron", "fred", "daniel"].contains(where: lower.contains)
        case .female:
            return ["veena", "samantha", "victoria", "allison", "tessa"].contains(where: lower.contains)
        case .neutral:
            return true
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AVSpeechTTSProvider: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Decrement the per-line chunk counter. Only when ALL
            // chunks of the current line have finished do we fire
            // pendingFinish — which advances the player to the next
            // line. A line with 3 chunks fires didFinish 3 times but
            // only advances once.
            if self.pendingChunkCount > 0 {
                self.pendingChunkCount -= 1
            }
            if self.pendingChunkCount == 0 {
                let cb = self.pendingFinish
                self.pendingFinish = nil
                cb?()
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Cancelled — clear state. Don't fire pendingFinish; the
            // caller owns the stop() invocation already.
            self.pendingFinish = nil
            self.pendingChunkCount = 0
        }
    }
}
