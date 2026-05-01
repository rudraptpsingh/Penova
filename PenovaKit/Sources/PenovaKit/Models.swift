//
//  Models.swift
//  Penova
//
//  SwiftData `@Model` classes. Every mutation runs through a `ModelContext`
//  and autosaves on main thread.
//
//  Naming rules:
//   - `ScriptScene` and `ScriptCharacter` avoid collisions with
//     SwiftUI's `Scene` protocol and Swift's `Character` type.
//   - Timestamps are `Date` — SwiftData stores them natively.
//   - Enums conform to `Codable` + `RawRepresentable` so SwiftData can
//     persist them (and arrays of them) without custom transformers.
//
//  Deletion:
//   - Project → Episode → ScriptScene → SceneElement cascade
//   - Project ↔ ScriptCharacter is many-to-many: deleting a Project detaches
//     its characters (they may still belong to other projects) but does NOT
//     delete the ScriptCharacter rows. Deleting a character just removes it
//     from every project it was linked to.
//   - Scene → Character links are weak refs (we keep names), not SwiftData
//     relationships, so deleting a character doesn't wipe dialogue blocks.
//

import Foundation
import SwiftData

public typealias ID = String

// MARK: - Enums

public enum Genre: String, Codable, CaseIterable, Identifiable {
    case drama, thriller, romance, comedy, noir
    case sciFi = "sci-fi"
    case fantasy, historical
    public var id: String { rawValue }
    public var display: String {
        switch self {
        case .sciFi: return "Sci-Fi"
        default: return rawValue.capitalized
        }
    }
}

public enum ProjectStatus: String, Codable, CaseIterable {
    case active, archived, trashed
}

public enum EpisodeStatus: String, Codable, CaseIterable {
    case draft
    case act1Done = "act1-done"
    case act2Done = "act2-done"
    case complete
}

public enum SceneLocation: String, Codable, CaseIterable {
    case interior = "INT"
    case exterior = "EXT"
    case both = "INT/EXT"
    public var display: String { rawValue }
}

public enum SceneTimeOfDay: String, Codable, CaseIterable {
    case day = "DAY"
    case night = "NIGHT"
    case dawn = "DAWN"
    case dusk = "DUSK"
    case morning = "MORNING"
    case evening = "EVENING"
    case continuous = "CONTINUOUS"
    case later = "LATER"
    public var display: String { rawValue }
}

public enum BeatType: String, Codable, CaseIterable {
    case setup, inciting, turn, midpoint, climax, resolution
    public var display: String { rawValue.capitalized }
}

public enum SceneElementKind: String, Codable, CaseIterable {
    case heading, action, character, dialogue, parenthetical, transition
    case actBreak = "act-break"
    public var display: String {
        switch self {
        case .actBreak: return "Act break"
        default:        return rawValue.capitalized
        }
    }
}

public enum CharacterRole: String, Codable, CaseIterable {
    case protagonist, lead, antagonist, supporting, minor
    public var display: String { rawValue.capitalized }
}

// MARK: - Project

@Model
public final class Project {
    /// CloudKit-compatible: no @Attribute(.unique). Uniqueness is guaranteed
    /// by `init` generating a fresh UUID; CloudKit cannot enforce uniqueness
    /// across devices anyway, so the schema-level constraint was redundant
    /// and would have blocked enabling sync.
    public var id: ID
    public var title: String
    public var logline: String
    public var genre: [Genre]
    public var status: ProjectStatus
    public var trashedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    /// Optional contact block rendered on the title page bottom-left
    /// (name, email, phone, agent). Newline-separated plain text.
    /// Defaults to empty. Added in v1.1 — existing stores tolerate the
    /// new optional-with-default property without a migration.
    public var contactBlock: String = ""

    /// True once the writer has locked the script for production. The
    /// renderer freezes scene + page numbers off `lockedSceneNumbers`
    /// while this is set; toggling it back to false clears the
    /// snapshot. Added in v1.2 — existing stores tolerate the new
    /// default-false property without a migration.
    public var locked: Bool = false

    /// Timestamp of the most recent lock event. Surfaced in the UI
    /// as "Locked on Jan 12, 2026" and used to seed the FDX writer's
    /// `<HeaderAndFooter>` lock-date metadata in a future PR.
    public var lockedAt: Date?

    /// Frozen scene-number assignment captured at lock time. Keyed
    /// by `ScriptScene.id` so reordering scenes after lock doesn't
    /// renumber them — matches the Final Draft / WGA convention. New
    /// scenes inserted after lock are NOT in this map; the renderer
    /// numbers them off their predecessor (A-numbering will land in
    /// a follow-up). Stored as `[String: Int]` so SwiftData treats
    /// it as a Codable attribute.
    public var lockedSceneNumbers: [String: Int]?

    @Relationship(deleteRule: .cascade, inverse: \Episode.project)
    public var episodes: [Episode] = []

    // Many-to-many with ScriptCharacter. No explicit deleteRule: on a
    // to-many relationship the SwiftData default (nullify) is what we want —
    // deleting a Project detaches it from each character's `projects` array
    // without deleting the character rows themselves. `.cascade` would be
    // wrong because characters can be shared across projects.
    @Relationship(inverse: \ScriptCharacter.projects)
    public var characters: [ScriptCharacter] = []

    // Per-project revision history. Cascading delete: revisions outside
    // their parent project are meaningless.
    @Relationship(deleteRule: .cascade, inverse: \Revision.project)
    public var revisions: [Revision] = []

    public init(
        title: String,
        logline: String = "",
        genre: [Genre] = [.drama],
        status: ProjectStatus = .active
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.logline = logline
        self.genre = genre
        self.status = status
        self.trashedAt = nil
        self.createdAt = .now
        self.updatedAt = .now
    }

    public var activeEpisodesOrdered: [Episode] {
        episodes.sorted { $0.order < $1.order }
    }

    public var totalSceneCount: Int {
        episodes.reduce(0) { $0 + $1.scenes.count }
    }

    public var revisionsByDate: [Revision] {
        revisions.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Page locking

    /// Snapshot the current scene-number assignment and flip the lock
    /// flag. After this, scene numbers are frozen — reordering or
    /// deleting scenes does not renumber the survivors. Idempotent:
    /// re-locking refreshes the snapshot.
    public func lock(now: Date = .now) {
        var map: [String: Int] = [:]
        let resetPerEpisode = activeEpisodesOrdered.count > 1
        var n = 1
        for episode in activeEpisodesOrdered {
            if resetPerEpisode { n = 1 }
            for scene in episode.scenesOrdered {
                map[scene.id] = n
                n += 1
            }
        }
        lockedSceneNumbers = map
        locked = true
        lockedAt = now
        updatedAt = now
    }

    /// Release the lock. Scene numbering reverts to live 1-based
    /// order — useful when the writer is still iterating on a draft
    /// they accidentally locked.
    public func unlock(now: Date = .now) {
        locked = false
        lockedAt = nil
        lockedSceneNumbers = nil
        updatedAt = now
    }

    /// Resolve a scene's render-time number. Returns the locked
    /// number if the project is locked AND the scene has one in the
    /// snapshot; otherwise returns `liveNumber` so newly-inserted
    /// scenes still get a number (will be replaced by A-numbering
    /// in a future PR).
    public func renderSceneNumber(for scene: ScriptScene, live liveNumber: Int) -> Int {
        if locked, let map = lockedSceneNumbers, let n = map[scene.id] {
            return n
        }
        return liveNumber
    }
}

// MARK: - Episode

@Model
public final class Episode {
    public var id: ID
    public var project: Project?
    public var title: String
    public var order: Int
    public var status: EpisodeStatus
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ScriptScene.episode)
    public var scenes: [ScriptScene] = []

    public init(title: String, order: Int, status: EpisodeStatus = .draft) {
        self.id = UUID().uuidString
        self.title = title
        self.order = order
        self.status = status
        self.createdAt = .now
        self.updatedAt = .now
    }

    public var scenesOrdered: [ScriptScene] {
        scenes.sorted { $0.order < $1.order }
    }
}

// MARK: - ScriptScene

@Model
public final class ScriptScene {
    public var id: ID
    public var episode: Episode?
    public var heading: String
    public var location: SceneLocation
    public var locationName: String
    public var time: SceneTimeOfDay
    public var sceneDescription: String?
    public var order: Int
    public var beatType: BeatType?
    public var actNumber: Int?
    public var bookmarked: Bool
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SceneElement.scene)
    public var elements: [SceneElement] = []

    public init(
        locationName: String,
        location: SceneLocation = .interior,
        time: SceneTimeOfDay = .day,
        order: Int,
        sceneDescription: String? = nil
    ) {
        self.id = UUID().uuidString
        self.locationName = locationName.uppercased()
        self.location = location
        self.time = time
        self.heading = "\(location.rawValue). \(locationName.uppercased()) - \(time.rawValue)"
        self.sceneDescription = sceneDescription
        self.order = order
        self.bookmarked = false
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Rebuild heading from current location/locationName/time.
    public func rebuildHeading() {
        heading = "\(location.rawValue). \(locationName.uppercased()) - \(time.rawValue)"
    }

    public var elementsOrdered: [SceneElement] {
        elements.sorted { $0.order < $1.order }
    }
}

// MARK: - SceneElement

@Model
public final class SceneElement {
    public var id: ID
    public var scene: ScriptScene?
    public var kind: SceneElementKind
    public var text: String
    public var order: Int
    /// Name of the speaking character (for dialogue/parenthetical blocks).
    public var characterName: String?

    public init(kind: SceneElementKind, text: String, order: Int, characterName: String? = nil) {
        self.id = UUID().uuidString
        self.kind = kind
        self.text = text
        self.order = order
        self.characterName = characterName
    }
}

// MARK: - ScriptCharacter

@Model
public final class ScriptCharacter {
    public var id: ID
    /// Projects this character belongs to. Many-to-many: a single character
    /// can appear in multiple projects (e.g. shared across a series of films
    /// or a spin-off). Inverse is declared on `Project.characters`.
    public var projects: [Project] = []
    public var name: String
    public var role: CharacterRole
    /// Age expressed as text so we accept "38" or "mid-30s" equally.
    public var ageText: String?
    public var occupation: String?
    public var goal: String?
    public var conflict: String?
    public var traits: [String]
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        name: String,
        role: CharacterRole = .supporting,
        ageText: String? = nil,
        occupation: String? = nil,
        traits: [String] = []
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.role = role
        self.ageText = ageText
        self.occupation = occupation
        self.traits = traits
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Approximation — counted by scanning scene elements at query time.
    public var lineCountFallback: Int { 0 }
}

// MARK: - WritingDay
//
// One row per calendar day on which the writer touched their script.
// `dateKey` is the local "yyyy-MM-dd" so streak math is calendar-aware
// and timezone-stable (the user's calendar, not UTC). `wordCount` is
// monotonic within a day — we never subtract on deletion, otherwise
// the streak would punish revision.
//
// Lookups are by `dateKey` and rows are unique on it.

@Model
public final class WritingDay {
    @Attribute(.unique) public var dateKey: String
    public var date: Date
    public var wordCount: Int
    public var sceneEditCount: Int
    public var lastWriteAt: Date

    public init(dateKey: String, date: Date) {
        self.dateKey = dateKey
        self.date = date
        self.wordCount = 0
        self.sceneEditCount = 0
        self.lastWriteAt = date
    }
}

public extension WritingDay {
    /// Stable yyyy-MM-dd key for the writer's local calendar. Used as the
    /// unique primary key and as the bucket id for snapshot diffs.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year  ?? 0
        let m = comps.month ?? 0
        let d = comps.day   ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

// MARK: - Revision
//
// A point-in-time snapshot of a Project's content, captured by the
// writer when they decide a draft is worth preserving. Each revision
// stores:
//
//   - A label like "First draft" or "Blue revision" so the writer can
//     find it later.
//   - An optional note describing what changed.
//   - The author's name, snapshotted from the AuthSession at save
//     time. Lets a project that travels across sign-ins still show
//     who wrote each revision.
//   - The full project content as a Fountain string. Plain text is
//     compact, diff-able, and re-importable through FountainParser
//     if a future "restore this revision" feature ships.
//   - Word count + scene count at save, denormalised onto the row so
//     the list view can render without loading the whole snapshot.
//
// Cascade: deleting a Project deletes all its revisions. A revision
// without a project is meaningless, so the cascade is correct.

@Model
public final class Revision {
    @Attribute(.unique) public var id: ID
    public var project: Project?
    public var label: String
    public var note: String
    public var fountainSnapshot: String
    public var authorName: String
    public var sceneCountAtSave: Int
    public var wordCountAtSave: Int
    public var createdAt: Date

    public init(
        label: String,
        note: String = "",
        fountainSnapshot: String,
        authorName: String,
        sceneCountAtSave: Int,
        wordCountAtSave: Int
    ) {
        self.id = UUID().uuidString
        self.label = label
        self.note = note
        self.fountainSnapshot = fountainSnapshot
        self.authorName = authorName
        self.sceneCountAtSave = sceneCountAtSave
        self.wordCountAtSave = wordCountAtSave
        self.createdAt = .now
    }
}

// MARK: - Schema accessor

public enum PenovaSchema {
    public static let models: [any PersistentModel.Type] = [
        Project.self,
        Episode.self,
        ScriptScene.self,
        SceneElement.self,
        ScriptCharacter.self,
        WritingDay.self,
        Revision.self
    ]
}
