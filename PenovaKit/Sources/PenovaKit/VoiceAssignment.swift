//
//  VoiceAssignment.swift
//  PenovaKit
//
//  Per-project mapping of character name → voice preset id. Persisted
//  via SwiftData so the writer's voice picks survive across launches.
//
//  Schema design choice: stored by `projectID: String` (FK to
//  Project.id) rather than as a SwiftData @Relationship. Two reasons:
//
//   1. Lets us add voice assignment without touching the Project @Model.
//      That model is part of CloudKit-syncable shapes; mutating its
//      relationship list mid-version is a bigger schema event.
//
//   2. Keeps the model standalone — VoiceAssignment can be queried,
//      serialized, and reasoned about without dragging Project's
//      object graph through the API.
//
//  Adding this @Model to PenovaSchema.models is an additive change.
//  SwiftData handles new tables transparently — no MigrationPlan
//  needed. Existing projects launch with zero assignments and the
//  TableReadEngine falls back to the default voice catalogue's
//  auto-suggestion.
//

import Foundation
import SwiftData

@Model
public final class VoiceAssignment {
    @Attribute(.unique) public var id: ID
    /// FK to Project.id. Stored as a plain string to keep the model
    /// independent of the Project relationship graph. Look up via the
    /// helper service below.
    public var projectID: String
    /// Character name in the screenplay — uppercased on init to match
    /// how SceneElement.characterName is stored.
    public var characterName: String
    /// Preset id from VoiceCatalogue.presets. The engine resolves this
    /// to a VoicePreset at read time.
    public var voiceID: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        projectID: String,
        characterName: String,
        voiceID: String,
        now: Date = .now
    ) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.characterName = characterName.uppercased()
        self.voiceID = voiceID
        self.createdAt = now
        self.updatedAt = now
    }
}

// MARK: - Service

@MainActor
public enum VoiceAssignmentService {

    /// Fetch all assignments for a project, indexed by uppercased
    /// character name for fast lookup during a table read.
    public static func assignments(
        for project: Project,
        context: ModelContext
    ) throws -> [String: VoiceAssignment] {
        let projectID = project.id
        let descriptor = FetchDescriptor<VoiceAssignment>(
            predicate: #Predicate { $0.projectID == projectID }
        )
        let rows = try context.fetch(descriptor)
        var byName: [String: VoiceAssignment] = [:]
        for row in rows {
            byName[row.characterName] = row
        }
        return byName
    }

    /// Set or update the voice for a character. Idempotent — calling
    /// twice with the same character + voice is a no-op write.
    @discardableResult
    public static func assign(
        voice voiceID: String,
        to characterName: String,
        in project: Project,
        context: ModelContext,
        now: Date = .now
    ) throws -> VoiceAssignment {
        let upper = characterName.uppercased()
        let existing = try assignments(for: project, context: context)
        if let row = existing[upper] {
            if row.voiceID != voiceID {
                row.voiceID = voiceID
                row.updatedAt = now
                try context.save()
            }
            return row
        }
        let row = VoiceAssignment(
            projectID: project.id,
            characterName: upper,
            voiceID: voiceID,
            now: now
        )
        context.insert(row)
        try context.save()
        return row
    }

    /// Remove an assignment. No-op if it doesn't exist.
    public static func remove(
        characterName: String,
        in project: Project,
        context: ModelContext
    ) throws {
        let upper = characterName.uppercased()
        let existing = try assignments(for: project, context: context)
        guard let row = existing[upper] else { return }
        context.delete(row)
        try context.save()
    }

    /// Best-fit voice id for a ScriptCharacter who hasn't been
    /// explicitly assigned. Uses the character's role + ageText to
    /// drive the catalogue heuristic.
    public static func suggest(for character: ScriptCharacter) -> String {
        let inferredAge: Int? = parseAge(character.ageText)
        // Crude name-based gender hint — not a primary signal, but
        // better than nothing for the first-pass auto-assign.
        let inferredGender: VoiceGender? = inferGender(from: character.name)
        let preset = VoiceCatalogue.suggest(
            gender: inferredGender,
            approximateAge: inferredAge,
            register: nil
        )
        return preset.id
    }

    /// Auto-assign every speaking character in the project that
    /// doesn't yet have a row. Returns the number of new assignments
    /// created. Pass-through to the catalogue's heuristic.
    @discardableResult
    public static func autoAssignMissing(
        in project: Project,
        context: ModelContext
    ) throws -> Int {
        let existing = try assignments(for: project, context: context)
        var added = 0
        for character in project.characters {
            guard existing[character.name.uppercased()] == nil else { continue }
            let voiceID = suggest(for: character)
            _ = try assign(
                voice: voiceID,
                to: character.name,
                in: project,
                context: context
            )
            added += 1
        }
        return added
    }

    // MARK: - Helpers

    /// Parse free-form age text ("38", "mid-30s", "early forties") to a
    /// rough integer. Best-effort — returns nil when nothing usable.
    static func parseAge(_ text: String?) -> Int? {
        guard let text else { return nil }
        // First try a literal integer.
        let lower = text.lowercased()
        if let n = Int(lower.trimmingCharacters(in: .whitespaces)) {
            return n
        }
        // Pull the first run of digits ("mid-30s" → 30, "early 40s" → 40).
        var digits = ""
        for ch in lower {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    /// Toy gender inference from the first letter / common suffixes —
    /// good enough to nudge the auto-assignment heuristic, never used
    /// for any persisted decision.
    static func inferGender(from name: String) -> VoiceGender? {
        let n = name.lowercased()
        if n.hasSuffix("a") || n.hasSuffix("i")  // Aanya, Zaina, Meera, Tulsi
            || n.hasSuffix("y")  // Penny, Sally
        {
            return .female
        }
        return nil
    }
}
