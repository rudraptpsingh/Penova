//
//  SeedData.swift
//  Draftr
//
//  First-launch demo content. Seeds a fully-written example screenplay
//  so the Home, Scripts, Scenes, and Characters tabs all have real
//  material to render before the user creates their own project.
//
//  The script below is a purpose-written 2-episode drama — every scene
//  exercises a different combination of SceneElement kinds (heading,
//  action, character, dialogue, parenthetical, transition) so the UI
//  and the PDF renderer both get a representative stress test.
//

import Foundation
import SwiftData

enum SeedData {
    private static let didSeedKey = "draftr.didSeedDemo.v2"

    static func installIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: didSeedKey) { return }

        let existing = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        guard existing == 0 else {
            defaults.set(true, forKey: didSeedKey)
            return
        }

        let project = Project(
            title: "The Last Train",
            logline: "A night porter at Bombay Central discovers the 23:45 to Pune never actually arrives.",
            genre: [.thriller, .drama]
        )
        context.insert(project)

        let characters = seedCharacters(for: project, in: context)
        _ = seedPilot(in: project, characters: characters, context: context)
        _ = seedEpisodeTwo(in: project, characters: characters, context: context)

        do {
            try context.save()
            defaults.set(true, forKey: didSeedKey)
        } catch {
            #if DEBUG
            print("⚠️  Draftr seed failed: \(error)")
            #endif
        }
    }

    // MARK: - Characters

    private struct Cast {
        let iqbal, ravi, meena, sharma, conductor: ScriptCharacter
    }

    private static func seedCharacters(for project: Project, in context: ModelContext) -> Cast {
        let iqbal = ScriptCharacter(
            name: "Iqbal",
            role: .protagonist,
            ageText: "mid-40s",
            occupation: "Night porter, Bombay Central",
            traits: ["patient", "observant", "widower"]
        )
        iqbal.goal = "Find out what happened to the 23:45 train — and his missing son."
        iqbal.conflict = "The Railways insist the train never existed."
        iqbal.notes = "Carries his late wife's thermos everywhere. Never drinks from it."

        let ravi = ScriptCharacter(
            name: "Ravi",
            role: .lead,
            ageText: "early-30s",
            occupation: "Signal controller",
            traits: ["anxious", "loyal"]
        )
        ravi.goal = "Cover for Iqbal without losing his own job."
        ravi.conflict = "His wife is in her third trimester."

        let meena = ScriptCharacter(
            name: "Meena",
            role: .lead,
            ageText: "38",
            occupation: "Railways compliance officer",
            traits: ["methodical", "haunted"]
        )
        meena.goal = "Quietly document the anomaly before it reaches Delhi."
        meena.conflict = "Her older brother rode the 23:45 twelve years ago."

        let sharma = ScriptCharacter(
            name: "Sharma",
            role: .antagonist,
            ageText: "50s",
            occupation: "Deputy Station Master",
            traits: ["polished", "immovable"]
        )
        sharma.goal = "Keep the anomaly off every ledger until his transfer clears."
        sharma.conflict = "He signed something he can't take back, years ago."

        let conductor = ScriptCharacter(
            name: "Conductor",
            role: .supporting,
            ageText: "timeless",
            occupation: "Ticket-checker on a train that may not exist",
            traits: ["unhurried", "courteous"]
        )

        [iqbal, ravi, meena, sharma, conductor].forEach {
            $0.project = project
            context.insert($0)
        }

        return Cast(iqbal: iqbal, ravi: ravi, meena: meena, sharma: sharma, conductor: conductor)
    }

    // MARK: - Pilot

    private static func seedPilot(in project: Project, characters: Cast, context: ModelContext) -> Episode {
        let ep = Episode(title: "Pilot", order: 0, status: .act1Done)
        ep.project = project
        context.insert(ep)

        // Scene 1 — Platform 7, night.
        let s1 = ScriptScene(
            locationName: "Bombay Central — Platform 7",
            location: .exterior,
            time: .night,
            order: 0,
            sceneDescription: "The last train that was never announced."
        )
        s1.episode = ep
        s1.beatType = .inciting
        s1.actNumber = 1
        s1.bookmarked = true
        context.insert(s1)
        writeElements(into: s1, context: context, pairs: [
            (.action, "Rain hammers the metal roof. Platform 7 is empty except for a thermos, a lantern, and IQBAL (mid-40s) — night porter, back straight, shoes polished to a shine that only old habits produce."),
            (.action, "The station clock reads 23:44."),
            (.character, "IQBAL"),
            (.parenthetical, "to himself"),
            (.dialogue, "Not late. Not yet."),
            (.action, "A muffled RADIO hiss. Iqbal lifts a battered handset to his ear."),
            (.character, "RAVI (V.O.)"),
            (.dialogue, "Seven, do you copy? The twenty-three forty-five isn't on my board."),
            (.character, "IQBAL"),
            (.dialogue, "It's on mine."),
            (.action, "The clock ticks to 23:45. A long, low whistle slides out of the fog. Headlights approach — two warm pinpricks, too low to be a train."),
            (.transition, "CUT TO:")
        ])

        // Scene 2 — Control Room, same night.
        let s2 = ScriptScene(
            locationName: "Signal Control Room",
            location: .interior,
            time: .continuous,
            order: 1,
            sceneDescription: "Ravi stares at a screen that disagrees with reality."
        )
        s2.episode = ep
        s2.beatType = .setup
        s2.actNumber = 1
        context.insert(s2)
        writeElements(into: s2, context: context, pairs: [
            (.action, "Fluorescent light. RAVI (early-30s) flicks between two monitors. Board A is full. Board B — the official one — shows Platform 7 as DARK."),
            (.character, "RAVI"),
            (.parenthetical, "into radio"),
            (.dialogue, "Iqbal. Uncle. Step back from the edge, yeah?"),
            (.action, "The door opens. MEENA (38), compliance officer, coat wet, notebook already open."),
            (.character, "MEENA"),
            (.dialogue, "Whose shift was it the last time this happened?"),
            (.character, "RAVI"),
            (.dialogue, "The last time what happened?"),
            (.action, "Meena just looks at him. Ravi swallows."),
            (.transition, "SMASH CUT TO:")
        ])

        // Scene 3 — Onboard, 23:46.
        let s3 = ScriptScene(
            locationName: "Train Carriage — Third Class",
            location: .interior,
            time: .continuous,
            order: 2,
            sceneDescription: "The train that isn't supposed to exist."
        )
        s3.episode = ep
        s3.beatType = .turn
        s3.actNumber = 1
        context.insert(s3)
        writeElements(into: s3, context: context, pairs: [
            (.action, "The carriage is half-full and too quiet. Passengers sit upright, coats still buttoned, eyes not quite looking at anything."),
            (.action, "Iqbal walks the aisle, lantern still in hand. He stops at seat 42."),
            (.character, "CONDUCTOR (O.S.)"),
            (.dialogue, "Ticket, uncle?"),
            (.action, "Iqbal turns. The CONDUCTOR smiles — a clean, small, unhurried smile."),
            (.character, "IQBAL"),
            (.dialogue, "I work the platform. I just came to see."),
            (.character, "CONDUCTOR"),
            (.parenthetical, "softly"),
            (.dialogue, "Everybody does, eventually."),
            (.action, "The conductor extends a hand. In it: a photograph Iqbal has not seen in twelve years."),
            (.action, "On the platform behind them, through the window, we see Iqbal still standing with his lantern. Still waiting."),
            (.transition, "FADE OUT.")
        ])

        return ep
    }

    // MARK: - Episode 2

    private static func seedEpisodeTwo(in project: Project, characters: Cast, context: ModelContext) -> Episode {
        let ep = Episode(title: "The 23:45", order: 1, status: .draft)
        ep.project = project
        context.insert(ep)

        // Scene 1 — Morning after.
        let s1 = ScriptScene(
            locationName: "Station Master's Office",
            location: .interior,
            time: .morning,
            order: 0,
            sceneDescription: "Iqbal returns. Nobody asks where from."
        )
        s1.episode = ep
        s1.beatType = .setup
        s1.actNumber = 1
        context.insert(s1)
        writeElements(into: s1, context: context, pairs: [
            (.action, "Morning light through dusty blinds. SHARMA (50s), Deputy Station Master, signs ledgers with the rhythm of a man who has never been interrupted by a question that stuck."),
            (.action, "A knock. Iqbal enters. His uniform is damp. His lantern is gone."),
            (.character, "SHARMA"),
            (.parenthetical, "not looking up"),
            (.dialogue, "You are six hours past your relief, porter."),
            (.character, "IQBAL"),
            (.dialogue, "The train from last night. I need the manifest."),
            (.action, "Sharma's pen stops. He looks up for the first time."),
            (.character, "SHARMA"),
            (.dialogue, "There was no train, Iqbal."),
            (.character, "IQBAL"),
            (.parenthetical, "quietly"),
            (.dialogue, "Then how am I holding this?"),
            (.action, "Iqbal places the photograph on the desk. Sharma's face loses, very slowly, twelve years of practised calm."),
            (.transition, "CUT TO:")
        ])

        // Scene 2 — Meena's car.
        let s2 = ScriptScene(
            locationName: "Meena's Car — Parked",
            location: .interior,
            time: .day,
            order: 1,
            sceneDescription: "The first honest conversation in either of their lives."
        )
        s2.episode = ep
        s2.beatType = .turn
        s2.actNumber = 2
        context.insert(s2)
        writeElements(into: s2, context: context, pairs: [
            (.action, "Rain again, but gentler. Meena's car is parked where it can see Platform 7 without being seen from it. A thermos steams between them."),
            (.character, "MEENA"),
            (.dialogue, "My brother took the 23:45. Twelve years and four months ago."),
            (.character, "IQBAL"),
            (.dialogue, "My son, eleven and seven."),
            (.action, "Silence. Not awkward — the opposite."),
            (.character, "MEENA"),
            (.dialogue, "I've been on the inside, reading the files they pretend don't exist. You've been on the outside, watching a platform that pretends to be empty."),
            (.character, "IQBAL"),
            (.dialogue, "We should probably compare notes."),
            (.character, "MEENA"),
            (.parenthetical, "smiling, barely"),
            (.dialogue, "We should probably do it quickly."),
            (.action, "She hands him a key. On the fob: a tiny, tarnished platform ticket, punched once, a long time ago."),
            (.transition, "TO BE CONTINUED.")
        ])

        return ep
    }

    // MARK: - Helpers

    private static func writeElements(
        into scene: ScriptScene,
        context: ModelContext,
        pairs: [(SceneElementKind, String)]
    ) {
        for (index, pair) in pairs.enumerated() {
            let el = SceneElement(kind: pair.0, text: pair.1, order: index)
            el.scene = scene
            if pair.0 == .character || pair.0 == .dialogue || pair.0 == .parenthetical {
                el.characterName = nil
            }
            context.insert(el)
        }
    }
}
