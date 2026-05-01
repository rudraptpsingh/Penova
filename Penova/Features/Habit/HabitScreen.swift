//
//  HabitScreen.swift
//  Penova
//
//  Writing-habit dashboard. Shows today's progress against the daily
//  goal, current and best streak, and a 7×7 heatmap of the last 49
//  days. Goal is editable. History can be reset.
//

import SwiftUI
import SwiftData

struct HabitScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WritingDay.date, order: .reverse) private var days: [WritingDay]

    @AppStorage(HabitTracker.goalDefaultsKey) private var dailyGoal: Int = HabitTracker.defaultGoal
    @State private var showGoalSheet = false
    @State private var showResetConfirm = false

    private var today: WritingDay? {
        let key = WritingDay.dayKey(for: .now)
        return days.first(where: { $0.dateKey == key })
    }

    private var todayWords: Int { today?.wordCount ?? 0 }
    private var goal: Int { max(1, dailyGoal) }
    private var goalHit: Bool { todayWords >= goal }
    private var progress: Double { min(1.0, Double(todayWords) / Double(goal)) }

    private var currentStreak: Int {
        HabitTracker.currentStreak(rows: days, goal: goal)
    }

    private var bestStreak: Int {
        HabitTracker.longestStreak(rows: days, goal: goal)
    }

    private var heatmap: [(date: Date, dateKey: String, wordCount: Int)] {
        HabitTracker.last49Days(rows: days)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                todayCard
                streakRow
                heatmapSection
                resetRow
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle(Copy.habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(Copy.habit.editGoalCta) { showGoalSheet = true }
                    .foregroundStyle(PenovaColor.amber)
            }
        }
        .sheet(isPresented: $showGoalSheet) {
            GoalEditorSheet(goal: $dailyGoal)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert(Copy.habit.resetPrompt, isPresented: $showResetConfirm) {
            Button(Copy.common.cancel, role: .cancel) {}
            Button(Copy.common.delete, role: .destructive) {
                HabitTracker.resetHistory(in: context)
            }
        } message: {
            Text(Copy.habit.resetBody)
        }
    }

    // MARK: - Today card

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.sm) {
            HStack {
                Text(Copy.habit.todayLabel)
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.snow3)
                Spacer()
                Text(Copy.habit.goalHitToday(goalHit))
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(goalHit ? PenovaColor.jade : PenovaColor.snow3)
            }
            Text(Copy.habit.wordsOfGoal(words: todayWords, goal: goal))
                .font(PenovaFont.hero)
                .foregroundStyle(PenovaColor.snow)
            ProgressBar(progress: progress, hit: goalHit)
                .frame(height: 8)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Streak row

    private var streakRow: some View {
        HStack(spacing: PenovaSpace.m) {
            statTile(
                label: Copy.habit.streakLabel.uppercased(),
                value: "\(currentStreak)",
                trail: Copy.habit.streakDaysLabel(currentStreak),
                accent: currentStreak > 0 ? PenovaColor.amber : PenovaColor.snow3
            )
            statTile(
                label: Copy.habit.bestStreakLabel.uppercased(),
                value: "\(bestStreak)",
                trail: Copy.habit.streakDaysLabel(bestStreak),
                accent: PenovaColor.jade
            )
        }
    }

    private func statTile(label: String, value: String, trail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(label)
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Text(value)
                .font(PenovaFont.title)
                .foregroundStyle(accent)
            Text(trail)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(Copy.habit.lastFortyNine.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            HeatmapGrid(cells: heatmap, goal: goal)
                .padding(PenovaSpace.m)
                .frame(maxWidth: .infinity)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    // MARK: - Reset

    private var resetRow: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            PenovaButton(title: Copy.habit.resetCta, variant: .ghost, size: .compact) {
                showResetConfirm = true
            }
        }
    }
}

// MARK: - Progress bar

private struct ProgressBar: View {
    let progress: Double
    let hit: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(PenovaColor.ink3)
                RoundedRectangle(cornerRadius: 4)
                    .fill(hit ? PenovaColor.jade : PenovaColor.amber)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))))
            }
        }
    }
}

// MARK: - Heatmap

private struct HeatmapGrid: View {
    let cells: [(date: Date, dateKey: String, wordCount: Int)]
    let goal: Int

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4), count: 7
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(cells, id: \.dateKey) { cell in
                cellView(words: cell.wordCount)
                    .accessibilityLabel(label(for: cell))
            }
        }
    }

    private func cellView(words: Int) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color(for: words))
            .aspectRatio(1, contentMode: .fit)
    }

    /// Five buckets — empty, low, mid, high, hit. The "hit" tier kicks in
    /// at the daily goal; the lower three are linear fractions of it.
    private func color(for words: Int) -> Color {
        guard words > 0 else { return PenovaColor.ink3 }
        if words >= goal { return PenovaColor.jade }
        let frac = Double(words) / Double(max(1, goal))
        if frac >= 0.66 { return PenovaColor.amber.opacity(0.85) }
        if frac >= 0.33 { return PenovaColor.amber.opacity(0.55) }
        return PenovaColor.amber.opacity(0.28)
    }

    private func label(for cell: (date: Date, dateKey: String, wordCount: Int)) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let dateStr = f.string(from: cell.date)
        return "\(dateStr): \(Copy.habit.wordsLabel(cell.wordCount))"
    }
}

// MARK: - Goal editor

private struct GoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goal: Int
    @State private var working: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                Text(Copy.habit.goalSheetBody)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
                VStack(alignment: .leading, spacing: PenovaSpace.xs) {
                    Text(Copy.habit.goalLabel.uppercased())
                        .font(PenovaFont.labelCaps)
                        .tracking(PenovaTracking.labelCaps)
                        .foregroundStyle(PenovaColor.snow3)
                    TextField("250", text: $working)
                        .keyboardType(.numberPad)
                        .font(PenovaFont.bodyLarge)
                        .foregroundStyle(PenovaColor.snow)
                        .padding(PenovaSpace.sm)
                        .background(PenovaColor.ink2)
                        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                }
                PenovaButton(title: Copy.habit.saveGoalCta, variant: .primary) {
                    if let n = Int(working.trimmingCharacters(in: .whitespaces)), n > 0 {
                        goal = min(50_000, n)
                    }
                    dismiss()
                }
                Spacer()
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle(Copy.habit.goalSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.common.cancel) { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
            .onAppear { working = "\(goal)" }
        }
    }
}
