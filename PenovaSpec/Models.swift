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
//   - Project → ScriptCharacter cascade
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
    public var display: String { rawValue.capitalized }
}

public enum CharacterRole: String, Codable, CaseIterable {
    case protagonist, lead, antagonist, supporting, minor
    public var display: String { rawValue.capitalized }
}

// MARK: - Subscription (stored via UserDefaults, not SwiftData — single-row config)

public struct Subscription: Codable, Equatable {
    public enum Plan: String, Codable, CaseIterable { case free, pro }
    public var plan: Plan
    public var currentPeriodEnd: Date?
    public var cancelAtPeriodEnd: Bool

    public init(plan: Plan = .free, currentPeriodEnd: Date? = nil, cancelAtPeriodEnd: Bool = false) {
        self.plan = plan
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    public static let freeDefault = Subscription(plan: .free)
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

    @Relationship(deleteRule: .cascade, inverse: \Episode.project)
    public var episodes: [Episode] = []

    @Relationship(deleteRule: .cascade, inverse: \ScriptCharacter.project)
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
    public var project: Project?
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

// MARK: - Schema accessor

public enum PenovaSchema {
    public static let models: [any PersistentModel.Type] = [
        Project.self,
        Episode.self,
        ScriptScene.self,
        SceneElement.self,
        ScriptCharacter.self
    ]
}
