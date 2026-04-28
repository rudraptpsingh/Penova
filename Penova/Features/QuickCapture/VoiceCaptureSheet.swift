//
//  VoiceCaptureSheet.swift
//  Penova
//
//  Quick Capture. Tap mic, dictate, save. The transcript is committed
//  as a single SceneElement (kind: .action) appended to an auto-managed
//  "Quick Capture" project so ideas never get lost between real screens.
//
//  Production polish (1.0):
//   - Live waveform driven by AVAudioEngine RMS taps (24 rolling bars).
//   - Partial-result smoothing throttles SFSpeechRecognizer updates so
//     the transcript doesn't flicker as recognition revises words.
//   - Locale picker (en-IN, en-US, en-GB, hi-IN) — reset before each
//     start() so changing language while recording is impossible.
//   - "Offline only" toggle that pins recognition to on-device.
//     Disabled when the chosen locale doesn't support on-device.
//

import SwiftUI
import SwiftData
import AVFoundation
import Speech

struct VoiceCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @State private var permissionDenied = false
    @State private var selectedLocale: VoiceRecorder.LocaleChoice = .enIN
    @State private var requiresOnDevice: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: PenovaSpace.l) {
                localeRow
                transcriptCard
                offlineToggle
                if permissionDenied {
                    Text(Copy.quickCapture.permissionDenied)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.ember)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                waveform
                micButton
                Spacer(minLength: 0)
                actionRow
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle(Copy.quickCapture.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.quickCapture.closeCta) {
                        recorder.stop()
                        dismiss()
                    }
                    .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onDisappear { recorder.stop() }
            .onChange(of: selectedLocale) { _, _ in
                // Locale change while recording is destructive — stop
                // and let the user re-tap if they want a new session.
                if recorder.isRecording { recorder.stop() }
            }
        }
    }

    // MARK: - Locale row

    private var localeRow: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(Copy.quickCapture.localeLabel.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PenovaSpace.s) {
                    ForEach(VoiceRecorder.LocaleChoice.allCases, id: \.self) { choice in
                        PenovaChip(
                            text: choice.display,
                            isSelected: choice == selectedLocale
                        ) {
                            selectedLocale = choice
                        }
                    }
                }
            }
        }
    }

    private var transcriptCard: some View {
        Text(displayText)
            .font(recorder.transcript.isEmpty ? PenovaFont.body : PenovaFont.bodyLarge)
            .foregroundStyle(recorder.transcript.isEmpty ? PenovaColor.snow3 : PenovaColor.snow)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PenovaSpace.l)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private var displayText: String {
        if !recorder.transcript.isEmpty { return recorder.transcript }
        return recorder.isRecording ? Copy.quickCapture.listening : Copy.quickCapture.tapToStart
    }

    // MARK: - Offline toggle

    private var offlineToggle: some View {
        let supportsOnDevice = selectedLocale.supportsOnDeviceRecognition
        return VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Toggle(isOn: Binding(
                get: { requiresOnDevice && supportsOnDevice },
                set: { requiresOnDevice = $0 }
            )) {
                Text(Copy.quickCapture.onDeviceLabel)
                    .font(PenovaFont.bodyMedium)
                    .foregroundStyle(PenovaColor.snow)
            }
            .tint(PenovaColor.amber)
            .disabled(!supportsOnDevice || recorder.isRecording)
            Text(supportsOnDevice
                 ? Copy.quickCapture.onDeviceHint
                 : Copy.quickCapture.onDeviceUnavailable)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(supportsOnDevice ? PenovaColor.snow3 : PenovaColor.ember)
        }
    }

    // MARK: - Waveform

    private var waveform: some View {
        WaveformView(
            levels: recorder.levels,
            isActive: recorder.isRecording,
            tint: recorder.isRecording ? PenovaColor.ember : PenovaColor.snow4
        )
        .frame(height: 36)
        .padding(.horizontal, PenovaSpace.l)
        .accessibilityLabel(recorder.isRecording ? "Recording" : "Idle")
    }

    private var micButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(recorder.isRecording ? PenovaColor.ember : PenovaColor.amber)
                    .frame(width: 88, height: 88)
                PenovaIconView(.voice, size: 36, color: PenovaColor.ink0)
            }
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: recorder.isRecording)
        .disabled(permissionDenied)
    }

    private var actionRow: some View {
        HStack(spacing: PenovaSpace.m) {
            PenovaButton(title: Copy.quickCapture.clearCta, variant: .ghost, size: .compact) {
                recorder.reset()
            }
            PenovaButton(title: Copy.quickCapture.saveCta, size: .compact) { save() }
                .disabled(recorder.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(recorder.transcript.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.requestAuthorization { authorized in
                if authorized {
                    recorder.start(
                        locale: selectedLocale,
                        requiresOnDevice: requiresOnDevice
                            && selectedLocale.supportsOnDeviceRecognition
                    )
                } else {
                    permissionDenied = true
                }
            }
        }
    }

    private func save() {
        let text = recorder.transcript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        recorder.stop()

        let inbox = ensureInbox()
        let episode = inbox.activeEpisodesOrdered.first ?? {
            let ep = Episode(title: "Captures", order: 0)
            ep.project = inbox
            context.insert(ep)
            return ep
        }()

        let nextOrder = (episode.scenes.map(\.order).max() ?? -1) + 1
        let scene = ScriptScene(
            locationName: "CAPTURE",
            location: .interior,
            time: .continuous,
            order: nextOrder,
            sceneDescription: text
        )
        scene.episode = episode
        context.insert(scene)

        let element = SceneElement(kind: .action, text: text, order: 0)
        element.scene = scene
        context.insert(element)

        inbox.updatedAt = .now
        try? context.save()
        dismiss()
    }

    private func ensureInbox() -> Project {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.title == "Quick Capture" }
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let p = Project(title: "Quick Capture",
                        logline: "Raw ideas. Promote the good ones.",
                        genre: [.drama])
        context.insert(p)
        return p
    }
}

// MARK: - Waveform

private struct WaveformView: View {
    let levels: [Float]
    let isActive: Bool
    let tint: Color

    private let barCount = 24

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = levelAt(i)
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: max(1, (geo.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)),
                            height: max(2, geo.size.height * CGFloat(level))
                        )
                        .animation(.linear(duration: 0.08), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(isActive ? 1 : 0.4)
        }
    }

    /// Map bar index `i` into the rolling levels buffer. The rightmost
    /// bar always shows the newest sample, so visually the waveform
    /// scrolls right-to-left as we record.
    private func levelAt(_ i: Int) -> Float {
        guard !levels.isEmpty else { return 0.05 }
        // i=0 → oldest, i=barCount-1 → newest. Map i across `levels`.
        let frac = Double(i) / Double(max(1, barCount - 1))
        let pos = frac * Double(levels.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(levels.count - 1, lo + 1)
        let t = Float(pos - Double(lo))
        let interp = levels[lo] * (1 - t) + levels[hi] * t
        // Clamp to a visible floor so even silence draws a tiny tick.
        return max(0.05, min(1, interp))
    }
}

// MARK: - Recorder

@MainActor
final class VoiceRecorder: ObservableObject {

    /// Languages we expose in the Quick-Capture locale chip row. Kept
    /// short on purpose — every entry has been smoke-tested against
    /// SFSpeechRecognizer's coverage matrix on iOS 17+.
    enum LocaleChoice: String, CaseIterable {
        case enIN = "en-IN"
        case enUS = "en-US"
        case enGB = "en-GB"
        case hiIN = "hi-IN"

        var locale: Locale { Locale(identifier: rawValue) }
        var display: String {
            switch self {
            case .enIN: return "English (India)"
            case .enUS: return "English (US)"
            case .enGB: return "English (UK)"
            case .hiIN: return "हिन्दी"
            }
        }
        var supportsOnDeviceRecognition: Bool {
            SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
        }
    }

    @Published private(set) var transcript: String = ""
    @Published private(set) var isRecording: Bool = false
    /// Rolling RMS-power samples, oldest-first. The waveform view maps
    /// these straight onto vertical bars. Kept short (24) so it stays
    /// snappy and predictable on any device.
    @Published private(set) var levels: [Float] = Array(repeating: 0.05, count: 24)

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Latest in-flight transcription text held off the @Published
    /// transcript so partial-result revisions don't strobe the UI. The
    /// throttle timer commits this to `transcript` at most once per
    /// `transcriptCommitInterval`.
    private var pendingTranscript: String = ""
    private var transcriptTimer: Timer?
    private let transcriptCommitInterval: TimeInterval = 0.15

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    completion(speechStatus == .authorized && micGranted)
                }
            }
        }
    }

    func start(locale: LocaleChoice = .enIN, requiresOnDevice: Bool = false) {
        guard !isRecording else { return }
        recognizer = SFSpeechRecognizer(locale: locale.locale)
        guard let recognizer, recognizer.isAvailable else { return }
        reset()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if requiresOnDevice && recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    // Stash the latest reading; the timer will publish.
                    self.pendingTranscript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stop() }
            }
        }

        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Push the audio to recognition AND extract an RMS sample
            // for the waveform. Tap is on a high-priority audio thread,
            // so do the math here and hop to main only to publish.
            self?.request?.append(buffer)
            let level = Self.rmsLevel(buffer)
            Task { @MainActor in self?.pushLevel(level) }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            startTranscriptTimer()
        } catch {
            stop()
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        stopTranscriptTimer()
        // Flush the latest pending transcript so the user sees the
        // last word they said even if it arrived between timer ticks.
        if !pendingTranscript.isEmpty { transcript = pendingTranscript }
        // Decay the waveform so it visually quiets down.
        levels = Array(repeating: 0.05, count: levels.count)
        isRecording = false
    }

    func reset() {
        transcript = ""
        pendingTranscript = ""
        levels = Array(repeating: 0.05, count: levels.count)
    }

    // MARK: - Throttle timer

    private func startTranscriptTimer() {
        stopTranscriptTimer()
        transcriptTimer = Timer.scheduledTimer(
            withTimeInterval: transcriptCommitInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.pendingTranscript != self.transcript {
                    self.transcript = self.pendingTranscript
                }
            }
        }
    }

    private func stopTranscriptTimer() {
        transcriptTimer?.invalidate()
        transcriptTimer = nil
    }

    // MARK: - Level math

    private func pushLevel(_ value: Float) {
        var arr = levels
        arr.removeFirst()
        arr.append(value)
        levels = arr
    }

    /// Compute a normalised 0…1 level from a buffer. We square-root the
    /// mean of squares (RMS), then clamp + scale so quiet voices read
    /// visibly without screaming voices clipping the bars off-screen.
    static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.05 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0.05 }
        var sumSquares: Float = 0
        for i in 0..<frames {
            let v = channelData[i]
            sumSquares += v * v
        }
        let rms = sqrt(sumSquares / Float(frames))
        // RMS for typical speech: ~0.005…0.1. Map log-scaled into 0…1
        // so quiet audio is visible and loud audio doesn't saturate.
        let db = 20 * log10(max(0.0001, rms))         // -80 … 0 dBFS
        let normalised = (db + 60) / 60                // -60 dBFS → 0, 0 dBFS → 1
        return max(0.05, min(1, normalised))
    }
}
