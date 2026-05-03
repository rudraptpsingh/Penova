//
//  TTSProvider.swift
//  PenovaKit
//
//  Provider protocol for the Voiced Table Read pipeline. Lives in
//  PenovaKit (zero AVFoundation dependency at the protocol level) so
//  both Mac and iOS shells can plug in their own concrete provider.
//
//  Day-one provider in PenovaMac: AVSpeechSynthesizer (free, on-device,
//  no network). Future: ElevenLabs / OpenAI TTS adapters behind a
//  Pro tier — same protocol, swap at runtime.
//

import Foundation

// MARK: - Provider

public protocol TTSProvider: AnyObject {
    /// True while the provider is actively rendering audio.
    var isSpeaking: Bool { get }

    /// Speak a single read item. Calls `onFinished()` once the utterance
    /// completes or is interrupted. Implementations should serialise
    /// utterances internally — callers just pass items in the order
    /// they want them spoken.
    func speak(_ item: TableReadEngine.ReadItem, onFinished: @escaping () -> Void)

    /// Stop the current utterance (if any) and clear the provider's
    /// queue. Idempotent.
    func stop()

    /// Pause the current utterance — resumable via `resume()`. No-op
    /// when not speaking.
    func pause()

    /// Resume a paused utterance.
    func resume()

    /// Set playback rate. 1.0 = the provider's natural pace; values
    /// in [0.5, 2.0] are typical. Implementations should clamp.
    func setRate(_ rate: Double)
}

// MARK: - Player

/// Drives a TTSProvider through a pre-built read queue. UI observes
/// `currentIndex` + `isPlaying` and reacts (current-line highlight,
/// progress bar, etc).
@MainActor
public final class TableReadPlayer: ObservableObject {

    @Published public private(set) var currentIndex: Int = 0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var queue: [TableReadEngine.ReadItem] = []

    private let provider: TTSProvider
    private var pendingItem: TableReadEngine.ReadItem?

    public init(provider: TTSProvider) {
        self.provider = provider
    }

    /// Load a queue and start playing from index 0.
    public func play(queue: [TableReadEngine.ReadItem]) {
        self.queue = queue
        self.currentIndex = 0
        guard !queue.isEmpty else { return }
        isPlaying = true
        speakCurrent()
    }

    /// Pause current playback. Resumable via `resume()`.
    public func pause() {
        guard isPlaying else { return }
        provider.pause()
        isPlaying = false
    }

    public func resume() {
        guard !isPlaying, !queue.isEmpty else { return }
        isPlaying = true
        provider.resume()
    }

    /// Stop and reset to the start. Caller can `play(queue:)` again.
    public func stop() {
        provider.stop()
        isPlaying = false
        currentIndex = 0
    }

    /// Skip to next item; loops back to the first item if at the end.
    public func skipForward() {
        guard !queue.isEmpty else { return }
        provider.stop()
        currentIndex = min(queue.count - 1, currentIndex + 1)
        if isPlaying { speakCurrent() }
    }

    public func skipBackward() {
        guard !queue.isEmpty else { return }
        provider.stop()
        currentIndex = max(0, currentIndex - 1)
        if isPlaying { speakCurrent() }
    }

    public func setRate(_ rate: Double) {
        provider.setRate(rate)
    }

    /// Jump to an arbitrary queue index (e.g. user clicks a line).
    public func jump(to index: Int) {
        guard index >= 0, index < queue.count else { return }
        provider.stop()
        currentIndex = index
        if isPlaying { speakCurrent() }
    }

    public var current: TableReadEngine.ReadItem? {
        guard !queue.isEmpty, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    // MARK: - Private

    private func speakCurrent() {
        guard let item = current else {
            isPlaying = false
            return
        }
        provider.speak(item) { [weak self] in
            Task { @MainActor in
                self?.advanceAfterUtterance()
            }
        }
    }

    private func advanceAfterUtterance() {
        guard isPlaying else { return }
        if currentIndex < queue.count - 1 {
            currentIndex += 1
            speakCurrent()
        } else {
            isPlaying = false
        }
    }
}
