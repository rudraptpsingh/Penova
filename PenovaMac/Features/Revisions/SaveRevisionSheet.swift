//
//  SaveRevisionSheet.swift
//  Penova for Mac
//
//  The "Save <Color> Revision" sheet from the web mockups. Surfaces
//  SaveRevisionService.save(...) with an explicit confirm step so the
//  writer can see the next colour, add an optional note, and back out
//  without consequence. Replaces the inline save-on-shortcut path that
//  shipped in v1.2.
//

import SwiftUI
import SwiftData
import PenovaKit

struct SaveRevisionSheet: View {

    let project: Project
    var onSaved: (Revision) -> Void = { _ in }
    var onCancel: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var saving: Bool = false
    @State private var error: String?

    /// Auto-picked colour and round number — captured once at sheet
    /// open so the labels don't shift if the writer pauses long enough
    /// for another save to land elsewhere.
    @State private var nextColor: RevisionColor = .white
    @State private var roundNumber: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PenovaColor.ink4)
            progressionRail
            Divider().background(PenovaColor.ink4)
            statsBlock
            Divider().background(PenovaColor.ink4)
            noteField
            footer
        }
        .accessibilityIdentifier("sheet.save-revision")
        .background(PenovaColor.ink2)
        .frame(width: 640)
        .onAppear {
            nextColor = project.nextRevisionColor()
            roundNumber = project.nextRevisionRoundNumber()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text("Save revision · production")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.amber)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Save")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PenovaColor.snow)
                Text(nextColor.display)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PenovaColor.amber)
                Text("revision")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PenovaColor.snow)
            }

            Text(headerSubtitle)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(.horizontal, PenovaSpace.xl)
        .padding(.top, PenovaSpace.l)
        .padding(.bottom, PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerSubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let dateStr = formatter.string(from: .now)
        let priorColor = project.activeRevision?.color
        let sincePart = priorColor.map { " since \($0.display)" } ?? ""
        return "\(dateStr) · round #\(roundNumber)\(sincePart)"
    }

    // MARK: - Progression rail

    private var progressionRail: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Revision progression")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)

            HStack(spacing: 6) {
                ForEach(progressionSlots, id: \.color) { slot in
                    progressionSlot(slot)
                }
            }
        }
        .padding(.horizontal, PenovaSpace.xl)
        .padding(.vertical, PenovaSpace.m)
    }

    private struct ProgressionSlot {
        let color: RevisionColor
        let state: SlotState
        let label: String
    }
    private enum SlotState { case done, next, future }

    /// Eight visible slots: prior 2 done + the next + 5 future.
    private var progressionSlots: [ProgressionSlot] {
        let allCases = RevisionColor.allCases
        guard let nextIdx = allCases.firstIndex(of: nextColor) else { return [] }
        var slots: [ProgressionSlot] = []
        for offset in -2...5 {
            let idx = nextIdx + offset
            guard idx >= 0, idx < allCases.count else { continue }
            let c = allCases[idx]
            let state: SlotState = offset < 0 ? .done : (offset == 0 ? .next : .future)
            slots.append(.init(color: c, state: state, label: c.display))
        }
        return slots
    }

    private func progressionSlot(_ slot: ProgressionSlot) -> some View {
        let rgb = slot.color.marginRGB
        let baseColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let opacity: Double = {
            switch slot.state {
            case .done:   return 0.55
            case .next:   return 0.92
            case .future: return 0.10
            }
        }()
        return ZStack(alignment: .bottomLeading) {
            baseColor.opacity(opacity)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.label)
                    .font(.custom("RobotoMono-Medium", size: 9))
                    .foregroundStyle(slot.state == .future ? PenovaColor.snow4 : .black.opacity(0.85))
                if slot.state == .next {
                    Text("today")
                        .font(.custom("RobotoMono-Regular", size: 8))
                        .foregroundStyle(.black.opacity(0.7))
                }
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: PenovaRadius.sm)
                .stroke(slot.state == .next ? PenovaColor.amber : Color.clear, lineWidth: 2)
        )
        .shadow(
            color: slot.state == .next ? PenovaColor.amber.opacity(0.25) : .clear,
            radius: slot.state == .next ? 12 : 0
        )
    }

    // MARK: - Stats

    private var statsBlock: some View {
        HStack(spacing: 0) {
            statCell(
                label: "Scenes",
                big: "\(project.totalSceneCount)",
                detail: "in this snapshot"
            )
            Divider().background(PenovaColor.ink4)
            statCell(
                label: "Author",
                big: storedAuthorName.isEmpty ? "—" : storedAuthorName,
                detail: "stamped on the row"
            )
        }
    }

    private func statCell(label: String, big: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(label.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            Text(big)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(PenovaColor.snow)
            Text(detail)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PenovaSpace.xl)
        .padding(.vertical, PenovaSpace.m)
    }

    private var storedAuthorName: String {
        UserDefaults.standard.string(forKey: "penova.auth.fullName") ?? ""
    }

    // MARK: - Note

    private var noteField: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Note (optional)")
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            TextField("What changed", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(PenovaSpace.sm)
                .background(PenovaColor.ink3)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.sm))
                .foregroundStyle(PenovaColor.snow)
                .font(PenovaFont.body)
        }
        .padding(.horizontal, PenovaSpace.xl)
        .padding(.vertical, PenovaSpace.m)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: PenovaSpace.xs) {
            if let error {
                Text(error)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.ember)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PenovaSpace.xl)
            }
            HStack(spacing: PenovaSpace.s) {
                Text("Penova will snapshot the project as Fountain, advance the colour, and stamp the row with your author name.")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Button {
                    save()
                } label: {
                    Text("Save \(nextColor.display) revision")
                        .fontWeight(.semibold)
                        .frame(minWidth: 180)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(PenovaColor.amber)
                .controlSize(.large)
                .disabled(saving)
            }
            .padding(.horizontal, PenovaSpace.xl)
            .padding(.vertical, PenovaSpace.m)
            .background(PenovaColor.ink1)
        }
    }

    // MARK: - Save

    private func save() {
        saving = true
        error = nil
        do {
            let authorName = storedAuthorName.isEmpty ? "The writer" : storedAuthorName
            let out = try SaveRevisionService.save(
                .init(
                    label: nil,                  // SaveRevisionService default → "<Color> revision"
                    note: note,
                    color: nextColor,
                    roundNumber: roundNumber,
                    authorName: authorName
                ),
                project: project,
                context: context
            )
            PenovaLog.editor.info(
                "Saved \(nextColor.display, privacy: .public) revision #\(roundNumber, privacy: .public)"
            )
            onSaved(out.revision)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            self.saving = false
        }
    }
}

// MARK: - Preview

#Preview("Save Pink revision") {
    let schema = Schema(PenovaSchema.models)
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let p = Project(title: "Ek Raat Mumbai Mein", logline: "")
    ctx.insert(p)
    let ep = Episode(title: "Arrival", order: 0); ep.project = p
    p.episodes.append(ep); ctx.insert(ep)
    for i in 0..<14 {
        let s = ScriptScene(
            locationName: "SCENE \(i + 1)",
            location: .interior, time: .night, order: i
        )
        s.episode = ep; ep.scenes.append(s); ctx.insert(s)
    }
    // Two prior revisions so the sheet shows White → Blue → (Pink).
    let r1 = Revision(
        label: "White revision",
        fountainSnapshot: "TITLE",
        authorName: "Rudra",
        sceneCountAtSave: 14,
        wordCountAtSave: 100,
        color: .white,
        roundNumber: 1
    )
    r1.project = p; p.revisions.append(r1); ctx.insert(r1)
    let r2 = Revision(
        label: "Blue revision",
        fountainSnapshot: "TITLE",
        authorName: "Rudra",
        sceneCountAtSave: 14,
        wordCountAtSave: 200,
        color: .blue,
        roundNumber: 2
    )
    r2.project = p; p.revisions.append(r2); ctx.insert(r2)

    return SaveRevisionSheet(project: p)
        .modelContainer(container)
}

#Preview("First revision — White") {
    let schema = Schema(PenovaSchema.models)
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let p = Project(title: "Untitled", logline: "")
    ctx.insert(p)
    return SaveRevisionSheet(project: p)
        .modelContainer(container)
}
