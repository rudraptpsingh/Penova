//
//  VoiceCaptureSheet.swift
//  Penova
//
//  S19 — Quick Capture. Tap mic, dictate, save. The transcript is committed
//  as a single SceneElement (kind: .action) appended to an auto-managed
//  "Quick Capture" project so ideas never get lost between real screens.
//
// STUB: VoiceCaptureSheet — production polish: waveform, partial-result smoothing,
//       locale selection, offline-only mode toggle. See STUBS.md.
//

import SwiftUI
import SwiftData
import AVFoundation
import Speech
import PenovaKit

struct VoiceCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: PenovaSpace.l) {
                Spacer()
                Text(recorder.transcript.isEmpty
                     ? (recorder.isRecording ? "Listening…" : "Tap the mic to start.")
                     : recorder.transcript)
                    .font(recorder.transcript.isEmpty ? PenovaFont.body : PenovaFont.bodyLarge)
                    .foregroundStyle(recorder.transcript.isEmpty ? PenovaColor.snow3 : PenovaColor.snow)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, PenovaSpace.l)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
                    .padding(PenovaSpace.m)
                    .background(PenovaColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))

                if permissionDenied {
                    Text("Microphone or speech access denied. Enable in Settings to dictate.")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.ember)
                        .multilineTextAlignment(.center)
                }

                Spacer()

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

                Spacer()

                HStack(spacing: PenovaSpace.m) {
                    PenovaButton(title: "Clear", variant: .ghost, size: .compact) {
                        recorder.reset()
                    }
                    PenovaButton(title: "Save", size: .compact) { save() }
                        .disabled(recorder.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(recorder.transcript.isEmpty ? 0.5 : 1)
                }
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        recorder.stop()
                        dismiss()
                    }
                    .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onDisappear { recorder.stop() }
        }
            .preferredColorScheme(.dark)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.requestAuthorization { authorized in
                if authorized { recorder.start() } else { permissionDenied = true }
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
        let p = Project(title: "Quick Capture", logline: "Raw ideas. Promote the good ones.", genre: [.drama])
        context.insert(p)
        return p
    }
}

// MARK: - Recorder

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        ?? SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    completion(speechStatus == .authorized && micGranted)
                }
            }
        }
    }

    func start() {
        guard !isRecording, let recognizer, recognizer.isAvailable else { return }
        reset()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stop() }
            }
        }

        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
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
        isRecording = false
    }

    func reset() {
        transcript = ""
    }
}
