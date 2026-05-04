//
//  SprintChip.swift
//  Penova for Mac
//
//  Toolbar pill that runs a focused-writing sprint. Click to start a
//  session with a default goal (1000 words / 25 minutes); the chip
//  shows live elapsed time + word delta vs the start. Click again to
//  stop and book the session against today's WritingDay.
//
//  Word-counting is delegated to whatever the parent feeds in (the
//  current project's total word count from StatusBar's existing
//  count). This keeps the chip pure-display + one closure away from
//  the data layer.
//

import SwiftUI
import Combine
import PenovaKit

/// Lightweight session model. Reset on stop.
@MainActor
final class SprintSession: ObservableObject {

    @Published var isActive: Bool = false
    @Published var elapsed: TimeInterval = 0
    @Published var startWordCount: Int = 0
    @Published var currentWordCount: Int = 0

    /// Default goal — 1000 words, sub-Pomodoro 25 minutes.
    var goalWords: Int = 1000
    var goalSeconds: TimeInterval = 25 * 60

    private var timer: AnyCancellable?
    private var startedAt: Date?

    func start(currentWords: Int) {
        guard !isActive else { return }
        isActive = true
        startWordCount = currentWords
        currentWordCount = currentWords
        elapsed = 0
        startedAt = .now
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let started = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isActive = false
        elapsed = 0
        startedAt = nil
    }

    /// Caller pushes the latest project word count so the chip can
    /// show the delta. Pure display — no SwiftData reads here.
    func update(currentWords: Int) {
        currentWordCount = currentWords
    }

    var wordsAdded: Int {
        max(0, currentWordCount - startWordCount)
    }

    var goalProgress: Double {
        guard goalWords > 0 else { return 0 }
        return min(1.0, Double(wordsAdded) / Double(goalWords))
    }
}

/// Toolbar chip view. Click toggles start/stop. Idle state shows
/// "Sprint" with a small dot; active shows "MM:SS · W / GOAL".
struct SprintChip: View {

    @ObservedObject var session: SprintSession
    /// Pulled when starting so the chip knows the baseline.
    var currentWordCount: () -> Int

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                pulseDot
                if session.isActive {
                    Text(elapsedLabel)
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(PenovaColor.amber)
                    Text("·")
                        .foregroundStyle(PenovaColor.snow4)
                    Text(wordsLabel)
                        .font(.custom("RobotoMono-Regular", size: 11))
                        .foregroundStyle(PenovaColor.snow2)
                } else {
                    Text("Sprint")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PenovaColor.snow2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(session.isActive
                        ? PenovaColor.amber.opacity(0.08)
                        : PenovaColor.ink3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                session.isActive
                                ? PenovaColor.amber.opacity(0.32)
                                : PenovaColor.ink4,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .help(session.isActive
            ? "Click to end the sprint."
            : "Start a 25-minute / 1000-word writing sprint.")
    }

    private var pulseDot: some View {
        Circle()
            .fill(session.isActive ? PenovaColor.amber : PenovaColor.snow4)
            .frame(width: 6, height: 6)
            .scaleEffect(session.isActive ? 1.0 + 0.15 * sin(session.elapsed * 2) : 1.0)
            .animation(.easeInOut(duration: 0.5), value: session.elapsed)
    }

    private var elapsedLabel: String {
        let total = Int(session.elapsed)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var wordsLabel: String {
        "\(session.wordsAdded) / \(session.goalWords)"
    }

    private func toggle() {
        if session.isActive {
            session.stop()
        } else {
            session.start(currentWords: currentWordCount())
        }
    }
}
