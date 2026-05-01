//
//  RevisionsListScreen.swift
//  Penova
//
//  Per-project revision history. The writer takes a snapshot any time
//  they want to mark "this is the draft I sent to the producer" /
//  "blue-pages revision" / etc. Each row records the label, optional
//  note, author name (snapshotted from AuthSession at save time),
//  scene count, word count, and the full project content as Fountain
//  text — so a future "restore this revision" feature can be added
//  without a schema bump.
//

import SwiftUI
import SwiftData
import PenovaKit

struct RevisionsListScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @Bindable var project: Project

    @State private var showSaveSheet = false
    @State private var pendingDelete: Revision?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    Text("Snapshots of this project at points you marked. Stored on this device — nothing is uploaded.")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow3)

                    if project.revisions.isEmpty {
                        EmptyState(
                            icon: .bookmark,
                            title: "No revisions yet.",
                            message: "Save the first one when you're happy with where the script is. You'll see who, what, and when later.",
                            ctaTitle: "Save first revision",
                            ctaAction: { showSaveSheet = true }
                        )
                        .padding(.top, PenovaSpace.l)
                    } else {
                        VStack(spacing: PenovaSpace.m) {
                            ForEach(project.revisionsByDate) { rev in
                                NavigationLink(value: rev) {
                                    RevisionRow(revision: rev)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = rev
                                    } label: {
                                        Label("Delete revision", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PenovaSpace.l)
                .padding(.bottom, PenovaSpace.xxl)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Revisions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Revision.self) { rev in
                RevisionDetailScreen(revision: rev)
            }

            if !project.revisions.isEmpty {
                PenovaFAB(icon: .plus) { showSaveSheet = true }
                    .padding(PenovaSpace.l)
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveRevisionSheet(project: project)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete revision?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { confirmDelete() }
        } message: {
            Text("This removes only the snapshot — your live script is untouched.")
        }
    }

    private func confirmDelete() {
        guard let rev = pendingDelete else { return }
        context.delete(rev)
        try? context.save()
        pendingDelete = nil
    }
}

// MARK: - Row

private struct RevisionRow: View {
    let revision: Revision

    var body: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(spacing: PenovaSpace.s) {
                colorDot
                Text(revision.label)
                    .font(PenovaFont.bodyLarge)
                    .foregroundStyle(PenovaColor.snow)
                Spacer(minLength: 0)
                Text(formattedDate)
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            HStack(spacing: PenovaSpace.s) {
                Text("\(revision.color.display) #\(revision.roundNumber)")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
                Text("·").font(PenovaFont.bodySmall).foregroundStyle(PenovaColor.snow4)
                if !revision.authorName.isEmpty {
                    Text(revision.authorName)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                    Text("·").font(PenovaFont.bodySmall).foregroundStyle(PenovaColor.snow4)
                }
                Text("\(revision.sceneCountAtSave) scenes")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
                Text("·").font(PenovaFont.bodySmall).foregroundStyle(PenovaColor.snow4)
                Text("\(revision.wordCountAtSave.formatted()) words")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            if !revision.note.isEmpty {
                Text(revision.note)
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                    .lineLimit(2)
            }
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PenovaColor.ink2)
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: revision.createdAt)
    }

    /// 12pt circular swatch in the row's actual WGA stock color, with
    /// a hairline border so White and Buff still register on the
    /// dark UI.
    private var colorDot: some View {
        let rgb = revision.color.marginRGB
        return Circle()
            .fill(Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1))
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(PenovaColor.ink4, lineWidth: 1))
            .accessibilityLabel("\(revision.color.display) revision")
    }
}

// MARK: - Save sheet

private struct SaveRevisionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    let project: Project

    @State private var label: String = ""
    @State private var note: String = ""
    /// Default-initialised lazily on first appearance so we read the
    /// up-to-date project state and don't pre-pick a stale color.
    @State private var color: RevisionColor?

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The color the user has chosen, or the project's WGA-next pick
    /// if they haven't yet touched the picker.
    private var resolvedColor: RevisionColor {
        color ?? project.nextRevisionColor()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    PenovaTextField(
                        label: "Label",
                        text: $label,
                        placeholder: nextDefaultLabel
                    )
                    colorPicker
                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        Text("Note (optional)")
                            .font(PenovaFont.labelCaps)
                            .tracking(PenovaTracking.labelCaps)
                            .foregroundStyle(PenovaColor.snow3)
                        ZStack(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("Tightened the third act. Cut the diner scene.")
                                    .font(PenovaFont.body)
                                    .foregroundStyle(PenovaColor.snow4)
                                    .padding(.horizontal, PenovaSpace.m)
                                    .padding(.vertical, PenovaSpace.s + 2)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $note)
                                .font(PenovaFont.body)
                                .foregroundStyle(PenovaColor.snow)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, PenovaSpace.s)
                                .padding(.vertical, PenovaSpace.xs)
                                .frame(minHeight: 96)
                        }
                        .background(PenovaColor.ink2)
                        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                    }
                    PenovaButton(title: "Save revision", variant: .primary) {
                        save()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("Save revision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PenovaColor.snow3)
                }
            }
        }
    }

    /// WGA color picker. Pre-selects the project's next color in the
    /// sequence; tapping any chip overrides. The chip ring uses each
    /// color's `marginRGB` so the user sees the actual stock color.
    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Revision color")
                    .font(PenovaFont.labelCaps)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.snow3)
                Spacer(minLength: 0)
                Text(resolvedColor.display.uppercased())
                    .font(PenovaFont.labelTiny)
                    .tracking(PenovaTracking.labelTiny)
                    .foregroundStyle(PenovaColor.snow3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PenovaSpace.s) {
                    ForEach(RevisionColor.allCases, id: \.self) { c in
                        colorChip(c)
                    }
                }
            }
            // Hint copy to make the WGA semantics obvious to first-time users.
            Text(colorHint)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow4)
        }
    }

    private func colorChip(_ c: RevisionColor) -> some View {
        let rgb = c.marginRGB
        let stockColor = Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
        let isSelected = c == resolvedColor
        return Button {
            color = c
        } label: {
            Circle()
                .fill(stockColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? PenovaColor.amber : PenovaColor.ink4,
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                .accessibilityLabel(c.display)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
    }

    private var colorHint: String {
        let next = project.nextRevisionColor()
        if next == .white {
            return "First revision is always White (the original draft)."
        }
        return "WGA convention: production is currently on \(next.display) pages."
    }

    private var nextDefaultLabel: String {
        let n = project.revisions.count + 1
        return "Revision \(n)"
    }

    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? nextDefaultLabel : trimmedLabel
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = FountainExporter.export(project: project)
        let wordCount = snapshot
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { !$0.isEmpty }
            .count

        let rev = Revision(
            label: finalLabel,
            note: trimmedNote,
            fountainSnapshot: snapshot,
            authorName: auth.isSignedIn ? auth.fullName : "",
            sceneCountAtSave: project.totalSceneCount,
            wordCountAtSave: wordCount,
            color: resolvedColor,
            roundNumber: project.nextRevisionRoundNumber()
        )
        rev.project = project
        project.revisions.append(rev)
        project.updatedAt = .now
        context.insert(rev)
        try? context.save()
        dismiss()
    }
}

// MARK: - Detail

private struct RevisionDetailScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var revision: Revision

    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                header
                if !revision.note.isEmpty {
                    section(title: "Note", body: revision.note)
                }
                snapshotSection
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle(revision.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: revision.fountainSnapshot,
                    preview: SharePreview(
                        revision.label,
                        image: Image(systemName: "doc.text")
                    )
                ) {
                    PenovaIconView(.export, size: 18, color: PenovaColor.snow)
                }
                .accessibilityLabel("Share revision")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            HStack(spacing: PenovaSpace.s) {
                if !revision.authorName.isEmpty {
                    PenovaTag(text: revision.authorName,
                              tint: PenovaColor.jade.opacity(0.18),
                              fg: PenovaColor.jade)
                }
                PenovaTag(text: "\(revision.sceneCountAtSave) scenes")
                PenovaTag(text: "\(revision.wordCountAtSave.formatted()) words")
            }
            Text(formattedDate)
                .font(PenovaFont.bodyMedium)
                .foregroundStyle(PenovaColor.snow3)
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: revision.createdAt)
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text(title.uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Text(body)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PenovaSpace.m)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Snapshot (Fountain)".uppercased())
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            Text(revision.fountainSnapshot)
                .font(PenovaFont.monoScript)
                .foregroundStyle(PenovaColor.snow)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PenovaSpace.m)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                .textSelection(.enabled)
        }
    }
}
