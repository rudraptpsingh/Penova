//
//  HabitTrackerTests.swift
//  PenovaTests
//
//  Covers the HabitTracker pipeline end-to-end:
//   - word counting,
//   - record() snapshot/delta semantics (first save seeds, subsequent
//     saves credit only the new words, deletions don't punish),
//   - currentStreak / longestStreak / last49Days against fabricated
//     WritingDay rows.
//

import Testing
import Foundation
import SwiftData
@testable import Penova

@MainActor
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Project.self,
        Episode.self,
        ScriptScene.self,
        SceneElement.self,
        ScriptCharacter.self,
        WritingDay.self,
        configurations: config
    )
}

/// A throwaway UserDefaults so the snapshot store doesn't leak between
/// tests or pollute the user's real defaults.
private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "penova.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

@MainActor
private func makeScene(text: String, in ctx: ModelContext) -> ScriptScene {
    let p = Project(title: "P"); ctx.insert(p)
    let ep = Episode(title: "E", order: 0); ep.project = p; p.episodes.append(ep); ctx.insert(ep)
    let s = ScriptScene(locationName: "ROOM", order: 0); s.episode = ep; ep.scenes.append(s); ctx.insert(s)
    let el = SceneElement(kind: .action, text: text, order: 0); el.scene = s; s.elements.append(el); ctx.insert(el)
    try? ctx.save()
    return s
}

@MainActor
private func appendWords(_ s: ScriptScene, text: String, in ctx: ModelContext) {
    let next = (s.elements.map(\.order).max() ?? -1) + 1
    let el = SceneElement(kind: .action, text: text, order: next)
    el.scene = s; s.elements.append(el); ctx.insert(el)
    try? ctx.save()
}

@MainActor
@Suite struct HabitTrackerTests {

    // MARK: - Word counting

    @Test func wordCountSplitsOnWhitespaceAndNewlines() {
        #expect(HabitTracker.wordCount(of: "") == 0)
        #expect(HabitTracker.wordCount(of: "   ") == 0)
        #expect(HabitTracker.wordCount(of: "one") == 1)
        #expect(HabitTracker.wordCount(of: "one two three") == 3)
        #expect(HabitTracker.wordCount(of: "one\ntwo\nthree") == 3)
        #expect(HabitTracker.wordCount(of: "  one   two  ") == 2)
    }

    // MARK: - Record: snapshot & delta

    @Test func firstRecordSeedsSnapshotWithoutCredit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeIsolatedDefaults()
        let now = Date()

        let scene = makeScene(text: "alpha beta gamma", in: ctx) // 3 words
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults)

        let day = try ctx.fetch(FetchDescriptor<WritingDay>()).first
        #expect(day != nil)
        // First save today seeds the snapshot — no words credited yet.
        #expect(day?.wordCount == 0)
        #expect(day?.sceneEditCount == 1)
    }

    @Test func subsequentRecordCreditsOnlyAddedWords() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeIsolatedDefaults()
        let now = Date()

        let scene = makeScene(text: "alpha beta gamma", in: ctx) // 3 words
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults)

        // Add four new words and record again.
        appendWords(scene, text: "delta epsilon zeta eta", in: ctx)
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults)

        let day = try ctx.fetch(FetchDescriptor<WritingDay>()).first
        #expect(day?.wordCount == 4)
        // Two saves total → two scene edits logged.
        #expect(day?.sceneEditCount == 2)
    }

    @Test func deletionsDoNotPunishStreak() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeIsolatedDefaults()
        let now = Date()

        let scene = makeScene(text: "one two three four five", in: ctx) // 5
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults) // seed

        appendWords(scene, text: "six seven", in: ctx) // total 7
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults) // +2

        // User deletes the original element entirely (now back to 2 words).
        if let toRemove = scene.elements.first(where: { $0.text.contains("one") }) {
            ctx.delete(toRemove)
            try ctx.save()
        }
        HabitTracker.record(scene: scene, in: ctx, now: now, defaults: defaults)

        let day = try ctx.fetch(FetchDescriptor<WritingDay>()).first
        // Day still has the +2 from earlier; deletion didn't subtract.
        #expect(day?.wordCount == 2)
    }

    @Test func crossDayResetsSnapshot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeIsolatedDefaults()

        let cal = Calendar(identifier: .gregorian)
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        let today = Date()

        let scene = makeScene(text: "a b c", in: ctx) // 3 words
        // Seed yesterday with 3-word snapshot.
        HabitTracker.record(scene: scene, in: ctx, now: yesterday, defaults: defaults)
        appendWords(scene, text: "d e", in: ctx) // 5 total
        HabitTracker.record(scene: scene, in: ctx, now: yesterday, defaults: defaults)
        // Yesterday's row got +2.

        // Today: even though the scene's word count is unchanged from
        // yesterday's end-state, the FIRST save today should seed a new
        // snapshot at 5 — so the writer doesn't get credit for words
        // they wrote yesterday.
        HabitTracker.record(scene: scene, in: ctx, now: today, defaults: defaults)

        let todayKey = WritingDay.dayKey(for: today, calendar: cal)
        let yKey = WritingDay.dayKey(for: yesterday, calendar: cal)
        let rows = try ctx.fetch(FetchDescriptor<WritingDay>())
        let yRow = rows.first(where: { $0.dateKey == yKey })
        let tRow = rows.first(where: { $0.dateKey == todayKey })

        #expect(yRow?.wordCount == 2)   // yesterday earned the +2
        #expect(tRow?.wordCount == 0)   // today seeded only, no credit
    }

    // MARK: - Streaks

    @Test func currentStreakCountsConsecutiveQualifyingDays() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let goal = 100

        // Build 4 consecutive days hitting the goal, ending today.
        let rows = (0..<4).map { offset -> WritingDay in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let r = WritingDay(dateKey: WritingDay.dayKey(for: d, calendar: cal), date: d)
            r.wordCount = goal
            return r
        }
        #expect(HabitTracker.currentStreak(rows: rows, goal: goal, today: today, calendar: cal) == 4)
    }

    @Test func currentStreakIgnoresTodayWhenNotYetHit() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let goal = 100

        // Yesterday and the day before: hit. Today: 0.
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!
        let rows: [WritingDay] = [
            { let r = WritingDay(dateKey: WritingDay.dayKey(for: yesterday, calendar: cal), date: yesterday); r.wordCount = goal; return r }(),
            { let r = WritingDay(dateKey: WritingDay.dayKey(for: twoDaysAgo, calendar: cal), date: twoDaysAgo); r.wordCount = goal; return r }()
        ]
        // Today not hit yet — streak should still be 2 (a fresh day
        // shouldn't break the writer's run before they've had a chance).
        #expect(HabitTracker.currentStreak(rows: rows, goal: goal, today: today, calendar: cal) == 2)
    }

    @Test func currentStreakBreaksOnGap() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let goal = 100

        // Today: hit. 1 day ago: hit. 2 days ago: miss. 3 days ago: hit.
        // Walking back: today (1) → yesterday (2) → 2 days ago (break).
        let dayN: (Int, Int) -> WritingDay = { offset, words in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let r = WritingDay(dateKey: WritingDay.dayKey(for: d, calendar: cal), date: d)
            r.wordCount = words
            return r
        }
        let rows = [dayN(0, goal), dayN(1, goal), dayN(2, 50), dayN(3, goal)]
        #expect(HabitTracker.currentStreak(rows: rows, goal: goal, today: today, calendar: cal) == 2)
    }

    @Test func currentStreakIsZeroWhenNoData() {
        #expect(HabitTracker.currentStreak(rows: [], goal: 100) == 0)
    }

    @Test func longestStreakFindsBestRun() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let goal = 100

        // Two runs: a 2-day run 10 days ago, and a 4-day run ending today.
        var rows: [WritingDay] = []
        for offset in [13, 12] {  // 2-day run
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let r = WritingDay(dateKey: WritingDay.dayKey(for: d, calendar: cal), date: d)
            r.wordCount = goal
            rows.append(r)
        }
        for offset in [3, 2, 1, 0] {  // 4-day run
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let r = WritingDay(dateKey: WritingDay.dayKey(for: d, calendar: cal), date: d)
            r.wordCount = goal
            rows.append(r)
        }

        #expect(HabitTracker.longestStreak(rows: rows, goal: goal, calendar: cal) == 4)
    }

    @Test func longestStreakIgnoresUnderGoalDays() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let goal = 100

        let rows = (0..<10).map { offset -> WritingDay in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let r = WritingDay(dateKey: WritingDay.dayKey(for: d, calendar: cal), date: d)
            r.wordCount = goal - 1   // never qualifies
            return r
        }
        #expect(HabitTracker.longestStreak(rows: rows, goal: goal, calendar: cal) == 0)
    }

    // MARK: - Heatmap

    @Test func last49DaysFillsZerosForMissingDays() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        let only = WritingDay(dateKey: WritingDay.dayKey(for: today, calendar: cal), date: today)
        only.wordCount = 200

        let cells = HabitTracker.last49Days(rows: [only], today: today, calendar: cal)
        #expect(cells.count == 49)
        #expect(cells.last?.wordCount == 200)            // today is the trailing cell
        #expect(cells.dropLast().allSatisfy { $0.wordCount == 0 })  // 48 empties before
    }

    // MARK: - Schema

    @Test func writingDayIsRegisteredInSchema() {
        let names = PenovaSchema.models.map { String(describing: $0) }
        #expect(names.contains("WritingDay"))
    }

    // MARK: - Goal default

    @Test func goalReturnsDefaultWhenUnset() {
        // dailyGoal property reads from .standard; just confirm the
        // default constant is sane.
        #expect(HabitTracker.defaultGoal == 250)
    }

    // MARK: - Date keys

    @Test func dayKeyIsStableISOFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 7
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: comps)!
        #expect(WritingDay.dayKey(for: date, calendar: cal) == "2026-03-07")
    }
}
