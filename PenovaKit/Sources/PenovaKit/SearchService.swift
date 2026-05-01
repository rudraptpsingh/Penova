//
//  SearchService.swift
//  PenovaKit
//
//  Pure-Swift, platform-agnostic search across the library. Returns
//  results grouped by kind (project / scene / location / dialogue /
//  character) so a UI can group them. Case-insensitive substring match
//  against project titles, scene headings, location names, dialogue
//  text and character names.
//
//  Lives in PenovaKit so the Mac search overlay and any future iOS
//  search redesign can share the same matcher and tests.
//

import Foundation

public enum SearchResultKind: String, CaseIterable, Sendable {
    case project, scene, location, dialogue, character
}

public struct SearchResult: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: SearchResultKind
    public let title: String
    public let subtitle: String
    /// Range of the matching characters in `title`, for highlighting.
    public let titleMatch: NSRange?

    /// Optional anchor IDs the UI can use to navigate.
    public let projectID: ID?
    public let episodeID: ID?
    public let sceneID: ID?
    public let elementID: ID?

    public init(
        id: String,
        kind: SearchResultKind,
        title: String,
        subtitle: String,
        titleMatch: NSRange? = nil,
        projectID: ID? = nil,
        episodeID: ID? = nil,
        sceneID: ID? = nil,
        elementID: ID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.titleMatch = titleMatch
        self.projectID = projectID
        self.episodeID = episodeID
        self.sceneID = sceneID
        self.elementID = elementID
    }
}

public enum SearchService {

    /// Run the search across `projects`. An empty query returns no
    /// results (callers can show a blank state or recents). Caps each
    /// kind at `perKindLimit` so a 5,000-line script doesn't dominate.
    public static func search(
        query: String,
        in projects: [Project],
        perKindLimit: Int = 8
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()

        var results: [SearchResult] = []

        // Projects
        var projectHits = 0
        for p in projects where projectHits < perKindLimit {
            if let range = match(p.title, q) {
                results.append(SearchResult(
                    id: "proj-\(p.id)",
                    kind: .project,
                    title: p.title,
                    subtitle: "\(p.totalSceneCount) scenes · \(p.activeEpisodesOrdered.count) episodes",
                    titleMatch: range,
                    projectID: p.id
                ))
                projectHits += 1
            }
        }

        // Scenes & locations
        var sceneHits = 0
        var locationHits = 0
        var seenLocations = Set<String>()
        for p in projects {
            for ep in p.activeEpisodesOrdered {
                for scene in ep.scenesOrdered {
                    if sceneHits < perKindLimit, let range = match(scene.heading, q) {
                        results.append(SearchResult(
                            id: "scene-\(scene.id)",
                            kind: .scene,
                            title: scene.heading,
                            subtitle: "Sc \(scene.order + 1) · \(ep.title) · \(p.title)",
                            titleMatch: range,
                            projectID: p.id, episodeID: ep.id, sceneID: scene.id
                        ))
                        sceneHits += 1
                    }
                    if locationHits < perKindLimit,
                       !seenLocations.contains(scene.locationName.uppercased()),
                       let range = match(scene.locationName, q) {
                        seenLocations.insert(scene.locationName.uppercased())
                        results.append(SearchResult(
                            id: "loc-\(scene.id)",
                            kind: .location,
                            title: scene.locationName,
                            subtitle: scene.location.display + " · " + scene.time.display,
                            titleMatch: range,
                            projectID: p.id, sceneID: scene.id
                        ))
                        locationHits += 1
                    }
                }
            }
        }

        // Dialogue
        var dialogueHits = 0
        for p in projects {
            for ep in p.activeEpisodesOrdered {
                for scene in ep.scenesOrdered {
                    for el in scene.elementsOrdered where el.kind == .dialogue {
                        guard dialogueHits < perKindLimit else { break }
                        if match(el.text, q) != nil {
                            let speaker = el.characterName ?? "—"
                            results.append(SearchResult(
                                id: "dlg-\(el.id)",
                                kind: .dialogue,
                                title: "\(speaker): \"\(el.text.prefix(120))\"",
                                subtitle: "\(scene.heading) · \(ep.title)",
                                projectID: p.id, episodeID: ep.id,
                                sceneID: scene.id, elementID: el.id
                            ))
                            dialogueHits += 1
                        }
                    }
                }
            }
        }

        // Characters
        var characterHits = 0
        var seenCharacters = Set<String>()
        for p in projects {
            for ch in p.characters where characterHits < perKindLimit {
                guard !seenCharacters.contains(ch.name.uppercased()) else { continue }
                if let range = match(ch.name, q) {
                    seenCharacters.insert(ch.name.uppercased())
                    results.append(SearchResult(
                        id: "char-\(ch.id)",
                        kind: .character,
                        title: ch.name,
                        subtitle: "\(ch.role.display) · \(p.title)",
                        titleMatch: range,
                        projectID: p.id
                    ))
                    characterHits += 1
                }
            }
        }

        return results
    }

    private static func match(_ haystack: String, _ q: String) -> NSRange? {
        guard let r = haystack.range(of: q, options: .caseInsensitive) else { return nil }
        return NSRange(r, in: haystack)
    }
}
