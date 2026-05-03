//
//  StructureOverlay.swift
//  PenovaKit
//
//  Story-structure scaffolds the Beat Board can lay over a writer's
//  scenes. Toggle overlays in the toolbar — the same scenes recolour
//  against a different framework. Structure is hypothesis, not religion.
//
//  Four overlays ship initially:
//
//    • Penova default (6 beats)   — Setup / Inciting / Turn /
//                                   Midpoint / Climax / Resolution.
//                                   This is the BeatType enum the
//                                   app already persists.
//
//    • Field 3-Act (3 beats)      — Syd Field's classic — Setup /
//                                   Confrontation / Resolution at
//                                   the 25% / 75% page anchors.
//
//    • Save the Cat! (15 beats)   — Blake Snyder's. Opening Image
//                                   through Final Image with the
//                                   Midpoint anchored centre-page.
//
//    • Hero's Journey (12 beats)  — Vogler's stages, Ordinary World
//                                   through Return with the Elixir.
//
//  Each beat carries a suggested page-range (as a fraction 0.0–1.0
//  of total page count) so the rail can position labels on a script
//  of any length. The Beat Board's UI consumes these directly.
//
//  Pure data + helpers. No platform deps.
//

import Foundation

// MARK: - Structure overlay enum

public enum StructureOverlay: String, Codable, CaseIterable, Sendable {
    case penova
    case fieldThreeAct = "field-three-act"
    case saveTheCat    = "save-the-cat"
    case herosJourney  = "heros-journey"

    public var display: String {
        switch self {
        case .penova:         return "Penova"
        case .fieldThreeAct:  return "Field 3-Act"
        case .saveTheCat:     return "Save the Cat"
        case .herosJourney:   return "Hero's Journey"
        }
    }

    /// Short label for the toolbar pill counter ("6", "3", "15", "12").
    public var beatCountLabel: String {
        "\(beats.count)"
    }

    public var beats: [StructureBeat] {
        switch self {
        case .penova:         return Self.penovaBeats
        case .fieldThreeAct:  return Self.fieldBeats
        case .saveTheCat:     return Self.saveTheCatBeats
        case .herosJourney:   return Self.herosJourneyBeats
        }
    }
}

// MARK: - Structure beat

public struct StructureBeat: Equatable, Hashable, Codable, Sendable {
    /// Stable id ("midpoint", "stc-fun-and-games", "hj-the-ordeal").
    /// Used as the key when persisting scene→beat assignments under
    /// a non-default overlay.
    public let id: String
    public let name: String
    public let description: String
    /// Suggested page anchor as a fraction of total page count.
    /// `start == end` means a point anchor (a single beat); a range
    /// represents a span (e.g. Save the Cat's "Fun & Games" 30%–55%).
    /// Both clamped to [0.0, 1.0].
    public let suggestedPageStart: Double
    public let suggestedPageEnd: Double
    /// True for the "Midpoint" beat in any overlay — surfaced for the
    /// rail's gold underline accent in the mockup.
    public let isMidpointAnchor: Bool

    public init(
        id: String,
        name: String,
        description: String,
        suggestedPageStart: Double,
        suggestedPageEnd: Double,
        isMidpointAnchor: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.suggestedPageStart = max(0, min(1, suggestedPageStart))
        self.suggestedPageEnd = max(0, min(1, suggestedPageEnd))
        self.isMidpointAnchor = isMidpointAnchor
    }

    /// Convert the suggested fraction to a 1-based page number given a
    /// total page count. Clamped to [1, totalPages].
    public func suggestedStartPage(in totalPages: Int) -> Int {
        guard totalPages > 0 else { return 1 }
        let raw = suggestedPageStart * Double(totalPages)
        return max(1, min(totalPages, Int(raw.rounded())))
    }

    public func suggestedEndPage(in totalPages: Int) -> Int {
        guard totalPages > 0 else { return 1 }
        let raw = suggestedPageEnd * Double(totalPages)
        return max(1, min(totalPages, Int(raw.rounded())))
    }
}

// MARK: - Penova default (6 beats — matches BeatType)

private extension StructureOverlay {

    static let penovaBeats: [StructureBeat] = [
        .init(
            id: "setup",
            name: "Setup",
            description: "World, character, ordinary life — the before.",
            suggestedPageStart: 0.00, suggestedPageEnd: 0.20
        ),
        .init(
            id: "inciting",
            name: "Inciting",
            description: "The thing that makes the story start.",
            suggestedPageStart: 0.10, suggestedPageEnd: 0.15
        ),
        .init(
            id: "turn",
            name: "Turn",
            description: "Crossing from ordinary world to the new path.",
            suggestedPageStart: 0.20, suggestedPageEnd: 0.30
        ),
        .init(
            id: "midpoint",
            name: "Midpoint",
            description: "The story flips. Stakes raise. No going back.",
            suggestedPageStart: 0.50, suggestedPageEnd: 0.50,
            isMidpointAnchor: true
        ),
        .init(
            id: "climax",
            name: "Climax",
            description: "The protagonist faces the hardest version of it.",
            suggestedPageStart: 0.75, suggestedPageEnd: 0.90
        ),
        .init(
            id: "resolution",
            name: "Resolution",
            description: "The new normal. The cost. The image we leave on.",
            suggestedPageStart: 0.90, suggestedPageEnd: 1.00
        )
    ]

    // MARK: - Field 3-Act

    static let fieldBeats: [StructureBeat] = [
        .init(
            id: "field-act-1",
            name: "Setup",
            description: "Introduce world, hero, dramatic premise.",
            suggestedPageStart: 0.00, suggestedPageEnd: 0.25
        ),
        .init(
            id: "field-act-2",
            name: "Confrontation",
            description: "Obstacles, complications, midpoint reversal.",
            suggestedPageStart: 0.25, suggestedPageEnd: 0.75,
            isMidpointAnchor: true
        ),
        .init(
            id: "field-act-3",
            name: "Resolution",
            description: "Climax + denouement.",
            suggestedPageStart: 0.75, suggestedPageEnd: 1.00
        )
    ]

    // MARK: - Save the Cat (15 beats)

    static let saveTheCatBeats: [StructureBeat] = [
        .init(
            id: "stc-opening-image",
            name: "Opening Image",
            description: "A snapshot of the before. Mood, theme, tone.",
            suggestedPageStart: 0.00, suggestedPageEnd: 0.01
        ),
        .init(
            id: "stc-theme-stated",
            name: "Theme Stated",
            description: "Someone says the lesson the hero will learn.",
            suggestedPageStart: 0.05, suggestedPageEnd: 0.05
        ),
        .init(
            id: "stc-setup",
            name: "Setup",
            description: "Hero in their flawed world. Stakes seeded.",
            suggestedPageStart: 0.00, suggestedPageEnd: 0.10
        ),
        .init(
            id: "stc-catalyst",
            name: "Catalyst",
            description: "The thing that makes the story start.",
            suggestedPageStart: 0.12, suggestedPageEnd: 0.12
        ),
        .init(
            id: "stc-debate",
            name: "Debate",
            description: "Should I? Can I? The hero hesitates.",
            suggestedPageStart: 0.12, suggestedPageEnd: 0.25
        ),
        .init(
            id: "stc-break-two",
            name: "Break Into Two",
            description: "Hero commits to the new world.",
            suggestedPageStart: 0.25, suggestedPageEnd: 0.25
        ),
        .init(
            id: "stc-b-story",
            name: "B Story",
            description: "Love story / mentor / the human counter-melody.",
            suggestedPageStart: 0.30, suggestedPageEnd: 0.30
        ),
        .init(
            id: "stc-fun-and-games",
            name: "Fun and Games",
            description: "The promise of the premise — the trailer set-pieces.",
            suggestedPageStart: 0.30, suggestedPageEnd: 0.55
        ),
        .init(
            id: "stc-midpoint",
            name: "Midpoint",
            description: "False victory or false defeat. Stakes raise.",
            suggestedPageStart: 0.50, suggestedPageEnd: 0.50,
            isMidpointAnchor: true
        ),
        .init(
            id: "stc-bad-guys",
            name: "Bad Guys Close In",
            description: "External + internal pressure mount.",
            suggestedPageStart: 0.55, suggestedPageEnd: 0.75
        ),
        .init(
            id: "stc-all-is-lost",
            name: "All Is Lost",
            description: "Whiff of death — the hero's lowest point.",
            suggestedPageStart: 0.75, suggestedPageEnd: 0.75
        ),
        .init(
            id: "stc-dark-night",
            name: "Dark Night of the Soul",
            description: "Wallowing in defeat. Lesson sinks in.",
            suggestedPageStart: 0.75, suggestedPageEnd: 0.85
        ),
        .init(
            id: "stc-break-three",
            name: "Break Into Three",
            description: "AHA — the new way to fight.",
            suggestedPageStart: 0.85, suggestedPageEnd: 0.85
        ),
        .init(
            id: "stc-finale",
            name: "Finale",
            description: "Storming the castle. Five-point convergence.",
            suggestedPageStart: 0.85, suggestedPageEnd: 1.00
        ),
        .init(
            id: "stc-final-image",
            name: "Final Image",
            description: "Mirror of the opening. The before/after image.",
            suggestedPageStart: 0.99, suggestedPageEnd: 1.00
        )
    ]

    // MARK: - Hero's Journey (12 beats — Vogler condensed)

    static let herosJourneyBeats: [StructureBeat] = [
        .init(
            id: "hj-ordinary-world",
            name: "Ordinary World",
            description: "Hero's status quo before the call.",
            suggestedPageStart: 0.00, suggestedPageEnd: 0.10
        ),
        .init(
            id: "hj-call",
            name: "Call to Adventure",
            description: "An invitation to leave the ordinary.",
            suggestedPageStart: 0.10, suggestedPageEnd: 0.15
        ),
        .init(
            id: "hj-refusal",
            name: "Refusal of the Call",
            description: "Fear, obligation, hesitation.",
            suggestedPageStart: 0.15, suggestedPageEnd: 0.20
        ),
        .init(
            id: "hj-mentor",
            name: "Meeting the Mentor",
            description: "Wisdom, gift, or training.",
            suggestedPageStart: 0.20, suggestedPageEnd: 0.25
        ),
        .init(
            id: "hj-threshold",
            name: "Crossing the Threshold",
            description: "Hero commits to the special world.",
            suggestedPageStart: 0.25, suggestedPageEnd: 0.30
        ),
        .init(
            id: "hj-tests",
            name: "Tests, Allies, Enemies",
            description: "New rules, new friends, new threats.",
            suggestedPageStart: 0.30, suggestedPageEnd: 0.50
        ),
        .init(
            id: "hj-approach",
            name: "Approach to the Inmost Cave",
            description: "Preparation for the central ordeal.",
            suggestedPageStart: 0.45, suggestedPageEnd: 0.55,
            isMidpointAnchor: true
        ),
        .init(
            id: "hj-ordeal",
            name: "The Ordeal",
            description: "Death and rebirth at the centre.",
            suggestedPageStart: 0.55, suggestedPageEnd: 0.65
        ),
        .init(
            id: "hj-reward",
            name: "Reward",
            description: "Seizing the prize the ordeal earned.",
            suggestedPageStart: 0.65, suggestedPageEnd: 0.75
        ),
        .init(
            id: "hj-road-back",
            name: "The Road Back",
            description: "Return journey begins; consequences chase.",
            suggestedPageStart: 0.75, suggestedPageEnd: 0.85
        ),
        .init(
            id: "hj-resurrection",
            name: "Resurrection",
            description: "Final test — proven transformed.",
            suggestedPageStart: 0.85, suggestedPageEnd: 0.95
        ),
        .init(
            id: "hj-return",
            name: "Return with the Elixir",
            description: "Hero returns home with what was won.",
            suggestedPageStart: 0.95, suggestedPageEnd: 1.00
        )
    ]
}

// MARK: - Mapping between overlays

/// Translates Penova's persisted BeatType (the only one the SwiftData
/// schema knows about today) into the corresponding beat ID under any
/// other overlay. Used by the Beat Board so toggling an overlay
/// reflects the writer's existing assignments — even though those
/// assignments were made against the 6-beat Penova default.
///
/// Best-fit, never lossy: the writer's BeatType assignments stay
/// intact in the model; the overlay just colours the cards differently
/// in the rail.
public enum StructureMapper {

    /// Best-fit equivalent beat ID for a Penova BeatType under the
    /// given target overlay. Falls back to the closest by page anchor
    /// when there's no semantic match.
    public static func equivalent(
        _ beat: BeatType,
        in overlay: StructureOverlay
    ) -> String? {
        switch overlay {
        case .penova:
            return beat.rawValue

        case .fieldThreeAct:
            switch beat {
            case .setup, .inciting:                  return "field-act-1"
            case .turn, .midpoint, .climax:          return "field-act-2"
            case .resolution:                        return "field-act-3"
            }

        case .saveTheCat:
            switch beat {
            case .setup:      return "stc-setup"
            case .inciting:   return "stc-catalyst"
            case .turn:       return "stc-break-two"
            case .midpoint:   return "stc-midpoint"
            case .climax:     return "stc-finale"
            case .resolution: return "stc-final-image"
            }

        case .herosJourney:
            switch beat {
            case .setup:      return "hj-ordinary-world"
            case .inciting:   return "hj-call"
            case .turn:       return "hj-threshold"
            case .midpoint:   return "hj-ordeal"
            case .climax:     return "hj-resurrection"
            case .resolution: return "hj-return"
            }
        }
    }

    /// Coverage report — given a list of beats the writer has actually
    /// assigned scenes to, return which beats in the target overlay
    /// are "covered" vs missing. Drives the rail's visual fill state.
    public static func coverage(
        assignedBeats: Set<BeatType>,
        overlay: StructureOverlay
    ) -> Coverage {
        let covered: Set<String> = Set(
            assignedBeats.compactMap { equivalent($0, in: overlay) }
        )
        let all = overlay.beats.map(\.id)
        let missing = all.filter { !covered.contains($0) }
        let percent = all.isEmpty
            ? 0.0
            : (Double(all.count - missing.count) / Double(all.count))
        return Coverage(
            overlay: overlay,
            coveredBeatIDs: covered,
            missingBeatIDs: missing,
            coveragePercent: percent
        )
    }

    public struct Coverage: Equatable, Sendable {
        public let overlay: StructureOverlay
        public let coveredBeatIDs: Set<String>
        public let missingBeatIDs: [String]
        /// 0.0 – 1.0 fraction of the overlay's beats that have at
        /// least one assigned scene mapping to them.
        public let coveragePercent: Double
    }
}
