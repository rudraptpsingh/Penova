//
//  SaveRevisionService.swift
//  PenovaKit
//
//  Orchestrates "save the current draft as a coloured revision" — the
//  one-click action behind the WGA-flavoured progression panel in the
//  web mockups (White → Blue → Pink → Yellow → … → Double Cherry,
//  wrap).
//
//  What this service is responsible for:
//   1. Picking the next colour + round number off the project (or
//      accepting an explicit choice for "skip a colour" workflows).
//   2. Snapshotting the project as a Fountain string via
//      FountainExporter.
//   3. Creating a Revision @Model row with the snapshot, the chosen
//      colour, the chosen round number, and the author's display name.
//   4. Appending it to project.revisions and saving the context.
//
//  What this service is NOT responsible for:
//   • Per-line "edited since last revision" stamping — that's an
//     editor-side concern handled by `stampElementAsEdited(_:in:)`.
//     Each SceneElement carries `lastRevisedRevisionID` which the
//     editor sets at edit time so the renderer can draw margin
//     asterisks. Doing it at save time would require either an
//     `updatedAt` on SceneElement or a snapshot-diff against the
//     last revision's Fountain — both heavier than this PR.
//
//   • PDF watermarking per recipient — that lives in the renderer
//     and is a separate stacked PR.
//
//  Pure-logic friendly: the @MainActor save() entry takes a Project
//  + ModelContext + Input and is straightforward to unit-test against
//  an in-memory ModelContainer.
//

import Foundation
import SwiftData

@MainActor
public enum SaveRevisionService {

    // MARK: - Input / Output

    public struct Input: Sendable {
        /// Display label for the title-page footer ("BLUE REVISION",
        /// "PRODUCTION DRAFT"). Defaults to `"<Color> revision"` when
        /// `nil` is passed to `save(...)`.
        public let label: String?
        /// Optional note describing what changed. Stored on the
        /// Revision row; surfaced in the revisions list.
        public let note: String
        /// Override the auto-picked colour. Pass nil to take whatever
        /// `project.nextRevisionColor()` returns.
        public let color: RevisionColor?
        /// Override the round number. Nil → max + 1.
        public let roundNumber: Int?
        /// Author display name, snapshotted onto the row so a project
        /// that travels across sign-ins still shows who saved each
        /// revision.
        public let authorName: String

        public init(
            label: String? = nil,
            note: String = "",
            color: RevisionColor? = nil,
            roundNumber: Int? = nil,
            authorName: String
        ) {
            self.label = label
            self.note = note
            self.color = color
            self.roundNumber = roundNumber
            self.authorName = authorName
        }
    }

    public struct Output: Sendable {
        public let revision: Revision
        /// Length of the Fountain snapshot in UTF-8 bytes — useful for
        /// telemetry / "Saved 4.2 KB revision" UI affordances.
        public let snapshotBytes: Int

        public init(revision: Revision, snapshotBytes: Int) {
            self.revision = revision
            self.snapshotBytes = snapshotBytes
        }
    }

    // MARK: - Errors

    public enum Error: Swift.Error, Equatable, Sendable {
        /// `authorName` was blank — every revision must record an author
        /// or the title-page footer breaks. Callers should fall back to
        /// "The writer" before reaching the service.
        case blankAuthor
    }

    // MARK: - Save

    /// Snapshot the current project state into a new Revision row.
    /// Saves the context. Returns the row plus a few stats.
    @discardableResult
    public static func save(
        _ input: Input,
        project: Project,
        context: ModelContext,
        now: Date = .now
    ) throws -> Output {
        guard !input.authorName.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw Error.blankAuthor }

        let chosenColor = input.color ?? project.nextRevisionColor()
        let chosenRound = input.roundNumber ?? project.nextRevisionRoundNumber()
        let chosenLabel = input.label ?? defaultLabel(for: chosenColor)

        let snapshot = FountainExporter.export(project: project)
        let snapshotBytes = snapshot.utf8.count

        // Use the Project's snapshot-time scene/word counts so the
        // list view can render without loading the Fountain back.
        let sceneCount = project.totalSceneCount
        let wordCount = approximateWordCount(in: snapshot)

        let revision = Revision(
            label: chosenLabel,
            note: input.note,
            fountainSnapshot: snapshot,
            authorName: input.authorName,
            sceneCountAtSave: sceneCount,
            wordCountAtSave: wordCount,
            color: chosenColor,
            roundNumber: chosenRound
        )
        // The Revision init() above stamps createdAt = .now. For
        // deterministic tests we may want to override; do it after init.
        revision.createdAt = now
        revision.project = project
        project.revisions.append(revision)
        context.insert(revision)
        project.updatedAt = now

        try context.save()

        return Output(revision: revision, snapshotBytes: snapshotBytes)
    }

    // MARK: - Per-element stamping

    /// Stamp a single element as "edited during the current revision".
    /// No-op when the project has no revisions yet (i.e. nothing to
    /// stamp against). Idempotent — re-stamping with the same active
    /// revision is a write of the same value.
    ///
    /// Editor-side hook: call from the text-change path so the renderer
    /// can draw margin asterisks on changed lines per WGA convention.
    public static func stampElementAsEdited(
        _ element: SceneElement,
        in project: Project
    ) {
        guard let active = project.activeRevision else { return }
        element.lastRevisedRevisionID = active.id
    }

    // MARK: - Helpers

    /// Default label per colour — "Pink revision", "Production draft"
    /// for the first round on White, etc. Callers can override via
    /// `Input.label` for industry-specific phrasings.
    public static func defaultLabel(for color: RevisionColor) -> String {
        // First-round white: "Production draft" feels right;
        // every subsequent colour uses "<Colour> revision".
        return "\(color.display) revision"
    }

    /// Word count proxy — naive whitespace split. Good enough for the
    /// "Saved · ~4 200 words" affordance in the revisions list. Not
    /// used for any production-critical decision.
    public static func approximateWordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
