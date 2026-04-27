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

public enum FeatureRequestCategory: String, Codable, CaseIterable, Identifiable {
    case editor          // writing surface, formatting, keyboard
    case characters      // character profiles, relationships
    case scenes          // scene list, board, beats
    case exportFormat    // PDF, FDX, Fountain
    case sync            // cloud sync, multi-device
    case voice           // dictation, voice capture
    case other
    public var id: String { rawValue }
    public var display: String {
        switch self {
        case .editor:       return "Editor"
        case .characters:   return "Characters"
        case .scenes:       return "Scenes"
        case .exportFormat: return "Export"
        case .sync:         return "Sync"
        case .voice:        return "Voice"
        case .other:        return "Other"
        }
    }
}

/// Lifecycle of a user-submitted feature request. The user can only create
/// rows in `submitted`; the rest are reserved for the maintainer flipping a
/// row's state when triaging the list (today via `SeedData` / a debug build
/// menu, eventually via a backend).
public enum FeatureRequestStatus: String, Codable, CaseIterable {
    case submitted   // user just sent it
    case underReview = "under-review"
    case planned
    case shipped
    case declined
    public var display: String {
        switch self {
        case .submitted:   return "Submitted"
        case .underReview: return "Under review"
        case .planned:     return "Planned"
        case .shipped:     return "Shipped"
        case .declined:    return "Declined"
        }
    }
}

// MARK: - Project

@Model
public final class Project {
    @Attribute(.unique) public var id: ID
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

    @Relationship(deleteRule: .cascade, inverse: \Episode.project)
    public var episodes: [Episode] = []

    // Many-to-many with ScriptCharacter. No explicit deleteRule: on a
    // to-many relationship the SwiftData default (nullify) is what we want —
    // deleting a Project detaches it from each character's `projects` array
    // without deleting the character rows themselves. `.cascade` would be
    // wrong because characters can be shared across projects.
    @Relationship(inverse: \ScriptCharacter.projects)
    public var characters: [ScriptCharacter] = []

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
}

// MARK: - Episode

@Model
public final class Episode {
    @Attribute(.unique) public var id: ID
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
    @Attribute(.unique) public var id: ID
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
    @Attribute(.unique) public var id: ID
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
    @Attribute(.unique) public var id: ID
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

// MARK: - FeatureRequest
//
// User-submitted suggestions for things they'd like to see Penova do. The
// app is offline-first and currently has no backend, so:
//
//   - A request lives only on the device that wrote it. Voting is local —
//     `voteCount` is bumped/decremented as the user toggles their +1.
//   - `submittedByThisDevice` is the toggle. If true, this device can edit
//     or delete the row; if false, the row is read-only on this device.
//     (A future backend sync will reconcile vote counts across devices and
//     attach a stable owner id.)
//
// Status transitions are intentionally not validated by code — the
// maintainer flips them. The UI treats `.submitted`/`.underReview` as
// "live", `.planned` as "queued", `.shipped`/`.declined` as terminal.

@Model
public final class FeatureRequest {
    @Attribute(.unique) public var id: ID
    public var title: String
    public var detail: String
    public var category: FeatureRequestCategory
    public var status: FeatureRequestStatus
    /// Local +1 count. Always >= 1 (the author auto-votes for their own).
    public var voteCount: Int
    /// Whether the local user has +1'd this row. Persisted so toggling
    /// across launches is consistent without a backend account.
    public var hasVoted: Bool
    /// True if this device is the one that submitted the request. Drives
    /// "edit" / "delete" affordances on the detail screen.
    public var submittedByThisDevice: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Optional maintainer reply. Shown under the description on the
    /// detail screen. Empty string means "no reply yet".
    public var maintainerNote: String

    public init(
        title: String,
        detail: String = "",
        category: FeatureRequestCategory = .other,
        status: FeatureRequestStatus = .submitted,
        submittedByThisDevice: Bool = true
    ) {
        self.id = UUID().uuidString
        self.title = title
        self.detail = detail
        self.category = category
        self.status = status
        self.voteCount = submittedByThisDevice ? 1 : 0
        self.hasVoted = submittedByThisDevice
        self.submittedByThisDevice = submittedByThisDevice
        self.createdAt = .now
        self.updatedAt = .now
        self.maintainerNote = ""
    }

    /// Toggle the local +1. Author votes (already counted at creation) can
    /// also be revoked — that's a feature, not a bug: if the user changed
    /// their mind they can pull their own +1 back to 0.
    public func toggleVote() {
        if hasVoted {
            hasVoted = false
            voteCount = max(0, voteCount - 1)
        } else {
            hasVoted = true
            voteCount += 1
        }
        updatedAt = .now
    }

    /// Sorting key for the "Top" tab: status weight first (live > planned >
    /// shipped > declined), then votes desc, then recency desc. Returned
    /// as a tuple so callers can use it with `sorted(by:)`.
    public var rankTuple: (Int, Int, Date) {
        let statusWeight: Int
        switch status {
        case .submitted, .underReview: statusWeight = 0
        case .planned:                 statusWeight = 1
        case .shipped:                 statusWeight = 2
        case .declined:                statusWeight = 3
        }
        // Sort ascending on status (live first), descending on votes &
        // recency. We invert votes/recency by negating in the comparison.
        return (statusWeight, voteCount, createdAt)
    }
}

public extension Sequence where Element == FeatureRequest {
    /// "Top" ordering: live first, then by votes desc, then recency desc.
    func rankedTop() -> [FeatureRequest] {
        sorted { lhs, rhs in
            let (ls, lv, lc) = lhs.rankTuple
            let (rs, rv, rc) = rhs.rankTuple
            if ls != rs { return ls < rs }
            if lv != rv { return lv > rv }
            return lc > rc
        }
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
        FeatureRequest.self
    ]
}
