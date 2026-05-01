//
//  HabitTracker.swift
//  Penova
//
//  Service that records writing activity into per-day WritingDay rows
//  and computes streak / heatmap derivatives for the HabitScreen.
//
//  How counting works:
//   - On every editor save, the editor calls `record(scene:in:)`.
//   - We compute the scene's current word count and compare it to a
//     per-(scene,day) snapshot stored in UserDefaults. The snapshot is
//     "the word count this scene had the first time we saw it today".
//   - delta = current - snapshot. We add max(delta, 0) to today's row
//     so that deletions don't punish a writer who is revising. After a
//     positive delta, we move the snapshot up to current so the next
//     save only counts NEW words.
//   - If snapshot is absent (first save of this scene today), we seed
//     it without crediting any words. The user gets credit for what
//     they ADD today, not for what was already there.
//
//  Snapshots are best-effort. They live in UserDefaults under the
//  prefix `penova.habit.snapshot.` and are pruned to today + yesterday
//  on every record() call (so they don't accumulate forever).
//

import Foundation
import SwiftData

public enum HabitTracker {

    // MARK: - Storage keys

    /// Daily-goal default (words). User can change in Settings → Writing.
    public static let defaultGoal: Int = 250
    public static let goalDefaultsKey = "penova.habit.dailyGoal"

    private static let snapshotPrefix = "penova.habit.snapshot."

    // MARK: - Goal

    public static var dailyGoal: Int {
        let stored = UserDefaults.standard.integer(forKey: goalDefaultsKey)
        return stored > 0 ? stored : defaultGoal
    }

    public static func setDailyGoal(_ value: Int) {
        let clamped = max(1, min(value, 50_000))
        UserDefaults.standard.set(clamped, forKey: goalDefaultsKey)
    }

    // MARK: - Recording

    /// Word-count function used for both bookkeeping and the UI label.
    /// Splits on whitespace + newlines, ignores empty tokens. Mirrors a
    /// spreadsheet's WORDCOUNT semantics, not a typographer's.
    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count
    }

    public static func wordCount(of scene: ScriptScene) -> Int {
        scene.elementsOrdered
            .map { $0.text }
            .reduce(0) { $0 + wordCount(of: $1) }
    }

    /// Hook called from the editor's save path. Idempotent within a save:
    /// repeated calls without new words are no-ops. Errors are swallowed —
    /// the habit tracker must never block writing.
    public static func record(
        scene: ScriptScene,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let key = WritingDay.dayKey(for: now, calendar: calendar)
        let current = wordCount(of: scene)
        let snapKey = snapshotKey(sceneID: scene.id, dayKey: key)

        let snap = defaults.object(forKey: snapKey) as? Int

        // First save of this scene today — seed snapshot, give no credit.
        guard let snapshot = snap else {
            defaults.set(current, forKey: snapKey)
            // Still record a "touch" so the row exists if the user only
            // edited (no new words yet).
            bump(dayKey: key, now: now, deltaWords: 0, didEditScene: true, in: context)
            pruneSnapshots(keeping: key, calendar: calendar, defaults: defaults)
            return
        }

        let delta = current - snapshot
        if delta > 0 {
            defaults.set(current, forKey: snapKey)
            bump(dayKey: key, now: now, deltaWords: delta, didEditScene: true, in: context)
        } else if delta < 0 {
            // The user shrunk the scene. Don't subtract — but rebase the
            // snapshot so adding the same words back doesn't double-count.
            defaults.set(current, forKey: snapKey)
            bump(dayKey: key, now: now, deltaWords: 0, didEditScene: true, in: context)
        } else {
            // No word delta. Still bump the touch so lastWriteAt updates.
            bump(dayKey: key, now: now, deltaWords: 0, didEditScene: false, in: context)
        }
    }

    // MARK: - Streaks

    /// Number of consecutive days, ending today, on which the writer hit
    /// `goal`. A day with `wordCount >= goal` counts. Today not yet hit
    /// is OK — we still count yesterday's streak forward, so the writer
    /// doesn't see "0" the moment a new day starts.
    public static func currentStreak(
        rows: [WritingDay],
        goal: Int,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.dateKey, $0) })

        // Walk backwards from today. If today is missing OR below goal,
        // start the walk from yesterday — a new day shouldn't break a
        // streak the writer hasn't had a chance to maintain yet.
        let todayKey = WritingDay.dayKey(for: today, calendar: calendar)
        var cursor = today
        if (map[todayKey]?.wordCount ?? 0) < goal {
            guard let y = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = y
        }

        var streak = 0
        while true {
            let key = WritingDay.dayKey(for: cursor, calendar: calendar)
            let words = map[key]?.wordCount ?? 0
            if words >= goal {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }
        return streak
    }

    /// Best run of `wordCount >= goal` days ever recorded. Single pass,
    /// ordered by date ascending, with calendar-day adjacency required.
    public static func longestStreak(
        rows: [WritingDay],
        goal: Int,
        calendar: Calendar = .current
    ) -> Int {
        let qualifying = rows
            .filter { $0.wordCount >= goal }
            .sorted { $0.date < $1.date }

        var best = 0
        var run = 0
        var prevDate: Date?
        for row in qualifying {
            if let prev = prevDate {
                let prevDay = calendar.startOfDay(for: prev)
                let thisDay = calendar.startOfDay(for: row.date)
                let gap = calendar.dateComponents([.day], from: prevDay, to: thisDay).day ?? 0
                if gap == 1 {
                    run += 1
                } else if gap == 0 {
                    // Same day twice (shouldn't happen given dateKey is unique,
                    // but be defensive).
                } else {
                    run = 1
                }
            } else {
                run = 1
            }
            best = max(best, run)
            prevDate = row.date
        }
        return best
    }

    /// Returns 49 cells (7 weeks × 7 days), oldest first, ending today.
    /// Each cell is the day's `wordCount` or 0 if no row exists.
    public static func last49Days(
        rows: [WritingDay],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [(date: Date, dateKey: String, wordCount: Int)] {
        let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.dateKey, $0) })
        var out: [(date: Date, dateKey: String, wordCount: Int)] = []
        out.reserveCapacity(49)
        for offset in stride(from: 48, through: 0, by: -1) {
            let d = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = WritingDay.dayKey(for: d, calendar: calendar)
            let words = map[key]?.wordCount ?? 0
            out.append((d, key, words))
        }
        return out
    }

    // MARK: - Reset / cleanup

    public static func clearAllSnapshots(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(snapshotPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// Wipe every WritingDay row + every snapshot. Used by the "Reset
    /// history" button. Scripts are untouched.
    public static func resetHistory(in context: ModelContext) {
        try? context.delete(model: WritingDay.self)
        try? context.save()
        clearAllSnapshots()
    }

    // MARK: - Private

    private static func snapshotKey(sceneID: ID, dayKey: String) -> String {
        "\(snapshotPrefix)\(sceneID).\(dayKey)"
    }

    private static func pruneSnapshots(
        keeping todayKey: String,
        calendar: Calendar,
        defaults: UserDefaults
    ) {
        // Keep today + yesterday so a save right around midnight still
        // diffs against a recent snapshot. Drop everything older.
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) else { return }
        let yKey = WritingDay.dayKey(for: yesterday, calendar: calendar)
        let allowed: Set<String> = [todayKey, yKey]
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(snapshotPrefix) {
            // Snapshot key shape: "<prefix><sceneID>.<dayKey>"
            // dayKey is the trailing 10 characters ("yyyy-MM-dd").
            let day = String(key.suffix(10))
            if !allowed.contains(day) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Find or create today's WritingDay row, accumulate the delta, and
    /// optionally bump the scene-edit count + lastWriteAt.
    private static func bump(
        dayKey: String,
        now: Date,
        deltaWords: Int,
        didEditScene: Bool,
        in context: ModelContext
    ) {
        let key = dayKey  // capture for the predicate
        let descriptor = FetchDescriptor<WritingDay>(
            predicate: #Predicate<WritingDay> { $0.dateKey == key }
        )
        let day: WritingDay
        if let existing = try? context.fetch(descriptor).first {
            day = existing
        } else {
            let new = WritingDay(dateKey: dayKey, date: now)
            context.insert(new)
            day = new
        }
        if deltaWords > 0 { day.wordCount += deltaWords }
        if didEditScene { day.sceneEditCount += 1 }
        day.lastWriteAt = now
        try? context.save()
    }
}
