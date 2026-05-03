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

    var isSpeaking: Bool { synth.isSpeaking }

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(
        _ item: TableReadEngine.ReadItem,
        onFinished: @escaping () -> Void
    ) {
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { onFinished(); return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = pickVoice(for: item.voiceID)
        // Rate. AVSpeechUtteranceDefaultSpeechRate is on the fast side
        // for a table read — the default cadence sounds rushed. 0.92×
        // default gives a slightly slower, more table-read-friendly
        // pace; the user can speed back up via the pace control.
        let baseRate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.rate = max(
            AVSpeechUtteranceMinimumSpeechRate,
            min(AVSpeechUtteranceMaximumSpeechRate, baseRate * rateMultiplier)
        )
        // Pitch: very slight detune so consecutive lines feel less
        // monotone. Default 1.0; preset-driven multiplier later.
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Slight pause between utterances so consecutive lines don't
        // run into each other.
        utterance.postUtteranceDelay = 0.10

        pendingFinish = onFinished
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        pendingFinish = nil
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

    /// Map a PenovaKit voice id to the best available AVSpeechSynthesisVoice.
    ///
    /// Quality preference: **premium → enhanced → default**. macOS ships
    /// premium / enhanced voices but only auto-installs the default
    /// (robotic-sounding) ones. The premium voices sound dramatically
    /// more natural — neural-trained — but need to be downloaded once
    /// from System Settings → Accessibility → Spoken Content. We pick
    /// the best installed quality so users who have done that download
    /// get the good voices automatically.
    ///
    /// Within a quality tier we prefer matches in the preset's locale
    /// (en-IN by default) and on the gender hint. Falls back gracefully
    /// when nothing better is installed.
    private func pickVoice(for voiceID: String) -> AVSpeechSynthesisVoice? {
        guard let preset = VoiceCatalogue.preset(id: voiceID) else {
            return AVSpeechSynthesisVoice(language: "en-IN")
        }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        // Locale-match first; English is a sensible fallback if the
        // preset's hint locale has no installed voice at all.
        let localeMatched = allVoices.filter {
            $0.language.hasPrefix(preset.localeHint.prefix(2))
        }
        let candidatePool = localeMatched.isEmpty
            ? allVoices.filter { $0.language.hasPrefix("en") }
            : localeMatched

        // Try each quality tier in descending order; within a tier prefer
        // gender match.
        for quality in [
            AVSpeechSynthesisVoiceQuality.premium,
            .enhanced,
            .default
        ] {
            let tier = candidatePool.filter { $0.quality == quality }
            if let genderHit = tier.first(where: {
                isMatch(systemVoiceName: $0.name, gender: preset.gender)
            }) {
                return genderHit
            }
            if let any = tier.first {
                return any
            }
        }
        return AVSpeechSynthesisVoice(language: preset.localeHint)
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
            self.pendingFinish?()
            self.pendingFinish = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Cancelled — also clear the callback. Don't fire it; the
            // caller owns a stop() invocation already.
            self.pendingFinish = nil
        }
    }
}
