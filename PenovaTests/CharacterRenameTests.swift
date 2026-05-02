//
//  CharacterRenameTests.swift
//  PenovaTests
//
//  Pins the global character-rename contract that v1.1.1 ships:
//  renaming a `ScriptCharacter` rewrites every cue + dialogue/
//  parenthetical reference across every scene of every project the
//  character belongs to, while leaving action lines, dialogue body
//  text, and unrelated character names alone.
//

import Testing
import Foundation
import SwiftData
@testable import PenovaKit

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(PenovaSchema.models)
    let config = ModelConfiguration(
        "CharacterRenameTests",
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func makeScene(in context: ModelContext) -> ScriptScene {
    let project = Project(title: "Rename Test")
    context.insert(project)
    let episode = Episode(title: "Pilot", order: 0)
    episode.project = project
    project.episodes.append(episode)
    context.insert(episode)
    let scene = ScriptScene(locationName: "OFFICE", order: 0)
    scene.episode = episode
    episode.scenes.append(scene)
    context.insert(scene)
    return scene
}

@MainActor
private func appendElement(
    _ kind: SceneElementKind,
    text: String,
    characterName: String? = nil,
    to scene: ScriptScene,
    in context: ModelContext
) -> SceneElement {
    let order = scene.elements.count
    let el = SceneElement(kind: kind, text: text, order: order, characterName: characterName)
    el.scene = scene
    scene.elements.append(el)
    context.insert(el)
    return el
}

@MainActor
@Suite struct CharacterRenameTests {

    @Test func renamesBareCharacterCue() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE", to: scene, in: container.mainContext)
        appendElement(.dialogue, text: "Hello there.", characterName: "JANE",
                      to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        #expect(result.cuesUpdated == 1)
        #expect(result.dialogueRefsUpdated == 1)
        let cues = scene.elements.filter { $0.kind == .character }.map(\.text)
        #expect(cues == ["JEAN"])
        let dialogue = scene.elements.first(where: { $0.kind == .dialogue })
        #expect(dialogue?.characterName == "JEAN")
    }

    @Test func preservesVOSuffixThroughRename() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE (V.O.)",
                      to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        #expect(result.cuesUpdated == 1)
        let cue = scene.elements.first(where: { $0.kind == .character })?.text
        #expect(cue == "JEAN (V.O.)")
    }

    @Test func preservesContdSuffixThroughRename() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE (CONT'D)",
                      to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        #expect(result.cuesUpdated == 1)
        let cue = scene.elements.first(where: { $0.kind == .character })?.text
        #expect(cue == "JEAN (CONT'D)")
    }

    @Test func preservesMultipleSuffixesThroughRename() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE (V.O.) (CONT'D)",
                      to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        #expect(result.cuesUpdated == 1)
        let cue = scene.elements.first(where: { $0.kind == .character })?.text
        #expect(cue == "JEAN (V.O.) (CONT'D)")
    }

    @Test func leavesDifferentCharacterAlone() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE", to: scene, in: container.mainContext)
        appendElement(.character, text: "BETH", to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        #expect(result.cuesUpdated == 1)
        let cues = scene.elements.filter { $0.kind == .character }.map(\.text).sorted()
        #expect(cues == ["BETH", "JEAN"])
    }

    @Test func leavesActionLinesUntouched() throws {
        // Critical: the classic Find/Replace bug is renaming JANE in
        // dialogue body text or action lines. Element-aware rename
        // must not touch them.
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.action, text: "JANE walks into the office.",
                      to: scene, in: container.mainContext)
        appendElement(.character, text: "JANE", to: scene, in: container.mainContext)
        appendElement(.dialogue, text: "Where's Jane today?",
                      characterName: "JANE",
                      to: scene, in: container.mainContext)

        CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        let action = scene.elements.first(where: { $0.kind == .action })?.text
        let dialogue = scene.elements.first(where: { $0.kind == .dialogue })?.text
        // Action body: untouched (the rename rewrote the cue + the
        // structural characterName ref, NOT the body string).
        #expect(action == "JANE walks into the office.")
        #expect(dialogue == "Where's Jane today?")
    }

    @Test func leavesPrefixedCharacterAlone() throws {
        // "JANET" must not match a rename of "JANE".
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANET", to: scene, in: container.mainContext)
        appendElement(.character, text: "JANE", to: scene, in: container.mainContext)

        CharacterRename.renameInScene(scene, from: "JANE", to: "JEAN")

        let cues = scene.elements.filter { $0.kind == .character }.map(\.text)
        #expect(cues.contains("JANET"))   // unchanged
        #expect(cues.contains("JEAN"))
    }

    @Test func renameAcrossProjectsCoversEveryScene() throws {
        let container = try makeContainer()
        let project = Project(title: "Multi")
        container.mainContext.insert(project)

        for i in 0..<3 {
            let ep = Episode(title: "Ep \(i)", order: i)
            ep.project = project
            project.episodes.append(ep)
            container.mainContext.insert(ep)

            let scene = ScriptScene(locationName: "ROOM \(i)", order: 0)
            scene.episode = ep
            ep.scenes.append(scene)
            container.mainContext.insert(scene)

            appendElement(.character, text: "JANE",
                          to: scene, in: container.mainContext)
        }

        let result = CharacterRename.renameAcrossProjects(
            in: [project], from: "JANE", to: "JEAN"
        )
        #expect(result.cuesUpdated == 3)

        for ep in project.episodes {
            for scene in ep.scenes {
                let cue = scene.elements.first(where: { $0.kind == .character })?.text
                #expect(cue == "JEAN")
            }
        }
    }

    @Test func noOpWhenNamesAreIdenticalAfterNormalisation() throws {
        let container = try makeContainer()
        let scene = makeScene(in: container.mainContext)
        appendElement(.character, text: "JANE", to: scene, in: container.mainContext)

        let result = CharacterRename.renameInScene(scene, from: "JANE", to: "  jane  ")
        #expect(result.total == 0)

        let cue = scene.elements.first(where: { $0.kind == .character })?.text
        #expect(cue == "JANE")  // unchanged
    }
}
