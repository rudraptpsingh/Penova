//
//  SampleLibrary.swift
//  Penova for Mac
//
//  Seeds an empty store with a vivid example project so the Mac app
//  always has something visible on first launch. The scene used in the
//  mockups (Penny / Marcus, INT. KITCHEN — NIGHT) is the canonical
//  demo content.
//

import Foundation
import SwiftData
import PenovaKit

enum SampleLibrary {
    static func installIfNeeded(in context: ModelContext) {
        // Only seed when the store is empty.
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        guard existing.isEmpty else { return }

        let project = Project(
            title: "Ek Raat Mumbai Mein",
            logline: "On the night she means to leave him, the city refuses to let her go.",
            genre: [.drama]
        )
        project.contactBlock = "rudra@example.com\n+91 98XXX XXXXX"
        context.insert(project)

        let ep1 = Episode(title: "Arrival", order: 0, status: .complete)
        ep1.project = project
        context.insert(ep1)

        let ep2 = Episode(title: "Departure", order: 1, status: .draft)
        ep2.project = project
        context.insert(ep2)

        // Episode 2 — the showcase scene from the mockups
        let kitchen = ScriptScene(
            locationName: "KITCHEN",
            location: .interior,
            time: .night,
            order: 0,
            sceneDescription: "Penny tells Marcus she quit her job. The whole episode pivots on this scene."
        )
        kitchen.episode = ep2
        kitchen.beatType = .midpoint
        kitchen.bookmarked = true
        context.insert(kitchen)

        let lines: [(SceneElementKind, String, String?)] = [
            (.action,        "Penny stands at the sink, water running. She hasn't moved in some time. A glass of red wine sweats on the counter beside her.", nil),
            (.action,        "The front door opens. Marcus enters, his hair smelling of rain. He sets his keys down — slowly, as if a sound might break something.", nil),
            (.character,     "MARCUS", nil),
            (.dialogue,      "You didn't eat.", "MARCUS"),
            (.character,     "PENNY", nil),
            (.parenthetical, "(without turning)", "PENNY"),
            (.dialogue,      "I wasn't hungry.", "PENNY"),
            (.character,     "MARCUS", nil),
            (.dialogue,      "Penny.", "MARCUS"),
            (.action,        "She turns off the water. Doesn't turn around.", nil),
            (.character,     "PENNY", nil),
            (.dialogue,      "I quit today.", "PENNY"),
            (.action,        "A long beat. Marcus looks at the back of her head — at the wet ends of her hair, the small tremor in her shoulder.", nil),
            (.character,     "MARCUS", nil),
            (.dialogue,      "You quit.", "MARCUS"),
            (.character,     "PENNY", nil),
            (.dialogue,      "I quit.", "PENNY"),
            (.transition,    "CUT TO:", nil),
        ]
        for (i, (kind, text, name)) in lines.enumerated() {
            let el = SceneElement(kind: kind, text: text, order: i, characterName: name)
            el.scene = kitchen
            context.insert(el)
        }

        // A few more scenes so the sidebar has something to scroll
        let extras: [(String, SceneLocation, SceneTimeOfDay, BeatType?)] = [
            ("TRAIN STATION", .interior, .dawn, .setup),
            ("CHAI STALL", .exterior, .dawn, .setup),
            ("PLATFORM 4", .exterior, .day, .inciting),
            ("HIGHWAY", .exterior, .night, .turn),
            ("MARCUS' APT", .interior, .night, .turn),
            ("SEA WALL, BANDRA", .exterior, .night, .climax),
            ("PENNY'S CAR", .interior, .dawn, .resolution),
        ]
        for (i, (loc, where_, time, beat)) in extras.enumerated() {
            let scene = ScriptScene(
                locationName: loc,
                location: where_,
                time: time,
                order: i + 1
            )
            scene.episode = ep2
            scene.beatType = beat
            context.insert(scene)
        }

        // Two characters
        let penny = ScriptCharacter(
            name: "PENNY",
            role: .protagonist,
            ageText: "32",
            occupation: "Chef de partie",
            traits: ["determined", "guarded", "tender beneath"]
        )
        penny.projects = [project]
        context.insert(penny)

        let marcus = ScriptCharacter(
            name: "MARCUS",
            role: .lead,
            ageText: "38",
            occupation: "Architect",
            traits: ["patient", "watchful", "hard to surprise"]
        )
        marcus.projects = [project]
        context.insert(marcus)

        try? context.save()
    }
}
