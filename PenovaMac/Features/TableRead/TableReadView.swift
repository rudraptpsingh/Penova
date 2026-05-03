//
//  TableReadView.swift
//  Penova for Mac
//
//  The Voiced Table Read sheet. Renders the current scene as a cream
//  paper page with a "NOW" highlight on the line being spoken; an
//  anchored player at the bottom controls play / pause / skip and
//  shows the speaker's avatar, voice attribution, and elapsed-of-
//  total time.
//
//  Audio routes through TTSProvider — AVSpeechTTSProvider is the
//  day-one driver but the UI doesn't know that. Swap to ElevenLabs
//  later by changing one line in `init()`.
//

import SwiftUI
import SwiftData
import PenovaKit

struct TableReadView: View {

    let scene: ScriptScene
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @StateObject private var player: TableReadPlayer
    @State private var settings: TableReadEngine.Settings = .default
    @State private var assignments: [String: VoiceAssignment] = [:]
    @State private var queue: [TableReadEngine.ReadItem] = []

    init(scene: ScriptScene, project: Project) {
        self.scene = scene
        self.project = project
        _player = StateObject(
            wrappedValue: TableReadPlayer(provider: AVSpeechTTSProvider())
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(PenovaColor.ink4)
            HStack(spacing: 0) {
                paperPane
                Divider().background(PenovaColor.ink4)
                voicePanel
                    .frame(width: 320)
            }
            playerBar
                .padding(PenovaSpace.m)
                .background(PenovaColor.ink1)
        }
        .frame(width: 1100, height: 720)
        .background(PenovaColor.ink2)
        .onAppear { reload() }
        .onDisappear { player.stop() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voiced table read")
                    .font(PenovaFont.labelTiny)
                    .tracking(PenovaTracking.labelCaps)
                    .foregroundStyle(PenovaColor.amber)
                Text(scene.heading)
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(PenovaSpace.l)
    }

    // MARK: - Paper

    private var paperPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .center, spacing: 0) {
                    paperPage
                        .id("paper-page")
                        .padding(.vertical, PenovaSpace.l)
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: player.currentIndex) { _, _ in
                guard let id = player.current?.elementID else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("line-\(id)", anchor: .center)
                }
            }
        }
        .background(PenovaColor.ink0)
    }

    private var paperPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Page number
            HStack {
                Spacer()
                Text("1.")
                    .font(.custom("RobotoMono-Medium", size: 12))
                    .foregroundStyle(paperInk.opacity(0.45))
            }
            .padding(.bottom, 24)

            // Heading
            Text(scene.heading)
                .font(.custom("RobotoMono-Medium", size: 14))
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(paperInk)
                .padding(.bottom, 12)

            // Elements
            ForEach(scene.elementsOrdered) { el in
                paperRow(for: el)
                    .id("line-\(el.id)")
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 48)
        .frame(width: 580, alignment: .leading)
        .background(PenovaColor.paper)
        .foregroundStyle(paperInk)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(PenovaColor.paperLine, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 20)
    }

    private func paperRow(for el: SceneElement) -> some View {
        let isNow = isCurrentlyReading(el)
        return Group {
            switch el.kind {
            case .heading:
                Text(el.text)
                    .font(.custom("RobotoMono-Medium", size: 14))
                    .textCase(.uppercase)
                    .foregroundStyle(paperInk)
            case .action:
                Text(el.text)
                    .font(.custom("RobotoMono-Regular", size: 13))
                    .foregroundStyle(paperInk)
            case .character:
                Text(el.text.uppercased())
                    .font(.custom("RobotoMono-Medium", size: 13))
                    .foregroundStyle(paperInk)
                    .padding(.leading, 180)
                    .padding(.top, 8)
            case .parenthetical:
                Text(el.text)
                    .font(.custom("RobotoMono-Regular", size: 13))
                    .italic()
                    .foregroundStyle(paperInk.opacity(0.7))
                    .padding(.leading, 140)
            case .dialogue:
                Text(el.text)
                    .font(.custom("RobotoMono-Regular", size: 13))
                    .foregroundStyle(paperInk)
                    .padding(.horizontal, 80)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .transition:
                Text(el.text)
                    .font(.custom("RobotoMono-Medium", size: 13))
                    .textCase(.uppercase)
                    .foregroundStyle(paperInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 12)
            case .actBreak:
                Text(el.text)
                    .font(.custom("RobotoMono-Medium", size: 12))
                    .foregroundStyle(paperInk.opacity(0.6))
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isNow
            ? PenovaColor.amber.opacity(0.12)
            : Color.clear
        )
        .overlay(alignment: .leading) {
            if isNow {
                Rectangle()
                    .fill(PenovaColor.amber)
                    .frame(width: 2)
                    .padding(.leading, -8)
            }
        }
    }

    private func isCurrentlyReading(_ el: SceneElement) -> Bool {
        player.current?.elementID == el.id
    }

    private var paperInk: Color { Color(red: 0.13, green: 0.12, blue: 0.10) }

    // MARK: - Voice panel

    private var voicePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                vpHeader
                speakingSection
                listenSection
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink1)
    }

    private var vpHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cast & voices")
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
            Text("Penova matched each character to a voice by inferred age and register. Tap to swap.")
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
            // Voice quality hint — premium voices need a one-time
            // download from System Settings before they sound natural.
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(PenovaColor.amber)
                Text("Sounding robotic? Install premium voices in System Settings → Accessibility → Spoken Content → System voice. Penova picks the best installed quality automatically.")
                    .font(.custom("Inter-Regular", size: 11))
                    .foregroundStyle(PenovaColor.snow4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var speakingSection: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            sectionLabel("Speaking — this scene", count: speakingCharacters.count)
            ForEach(speakingCharacters, id: \.self) { name in
                voiceRow(for: name)
            }
            if speakingCharacters.isEmpty {
                Text("Nobody speaks in this scene yet.")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow4)
                    .italic()
            }
        }
    }

    private func voiceRow(for characterName: String) -> some View {
        let voiceID = assignments[characterName.uppercased()]?.voiceID
            ?? VoiceCatalogue.suggest().id
        let preset = VoiceCatalogue.preset(id: voiceID)
        return HStack(spacing: PenovaSpace.s) {
            Circle()
                .fill(PenovaColor.amber)
                .frame(width: 28, height: 28)
                .overlay(
                    Text(String(characterName.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PenovaColor.ink0)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(characterName.uppercased())
                    .font(.custom("RobotoMono-Medium", size: 11))
                    .foregroundStyle(PenovaColor.snow)
                Text(preset.map { "\($0.displayName) — \($0.descriptor)" } ?? "—")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var listenSection: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            sectionLabel("Listen", count: 3)
            listenRow(
                label: "Read action lines",
                isOn: Binding(
                    get: { settings.readActionLines },
                    set: { settings.readActionLines = $0; reload() }
                )
            )
            listenRow(
                label: "Read parentheticals",
                isOn: Binding(
                    get: { settings.readParentheticals },
                    set: { settings.readParentheticals = $0; reload() }
                )
            )
            listenRow(
                label: "Auto-scroll page",
                isOn: .constant(true)
            )
        }
    }

    private func listenRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow2)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(PenovaColor.amber)
        }
        .padding(.horizontal, PenovaSpace.sm).padding(.vertical, 4)
        .background(PenovaColor.ink3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionLabel(_ text: String, count: Int) -> some View {
        HStack {
            Text(text.uppercased())
                .font(PenovaFont.labelTiny)
                .tracking(PenovaTracking.labelTiny)
                .foregroundStyle(PenovaColor.snow4)
            Spacer()
            Text("\(count)")
                .font(.custom("RobotoMono-Regular", size: 10))
                .foregroundStyle(PenovaColor.snow4)
        }
    }

    // MARK: - Player bar

    private var playerBar: some View {
        HStack(spacing: PenovaSpace.m) {
            currentSpeakerInfo
            Spacer()
            Button {
                player.skipBackward()
            } label: { Image(systemName: "backward.fill") }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(queue.isEmpty)

            Button {
                if player.isPlaying {
                    player.pause()
                } else if !queue.isEmpty && player.queue.isEmpty {
                    player.play(queue: queue)
                } else {
                    player.resume()
                }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(PenovaColor.amber)
            .disabled(queue.isEmpty)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                player.skipForward()
            } label: { Image(systemName: "forward.fill") }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(queue.isEmpty)

            Spacer()
            progressLabel
        }
    }

    private var currentSpeakerInfo: some View {
        HStack(spacing: PenovaSpace.sm) {
            if let item = player.current, let speaker = item.characterName {
                Circle()
                    .fill(PenovaColor.amber)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(speaker.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(PenovaColor.ink0)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(speaker)
                        .font(.custom("RobotoMono-Medium", size: 11))
                        .foregroundStyle(PenovaColor.snow)
                    Text(VoiceCatalogue.preset(id: item.voiceID)?.displayName ?? "—")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                }
            } else {
                Text(queue.isEmpty ? "Nothing to read" : "Press space to play")
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow3)
            }
        }
    }

    private var progressLabel: some View {
        let total = queue.count
        let curr = total == 0 ? 0 : player.currentIndex + 1
        return Text("\(curr) / \(total) lines")
            .font(.custom("RobotoMono-Regular", size: 11))
            .foregroundStyle(PenovaColor.snow3)
    }

    // MARK: - Data

    private var speakingCharacters: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for el in scene.elementsOrdered where el.kind == .dialogue {
            if let name = el.characterName, !name.isEmpty, !seen.contains(name) {
                seen.insert(name)
                out.append(name)
            }
        }
        return out
    }

    private func reload() {
        // First time the sheet opens for a project, auto-assign distinct
        // voices to every speaking character so they don't all collapse
        // to the same default. This is the critical fix that turns
        // "everyone sounds like Vihaan" into "MARCUS sounds like Daniel,
        // PENNY sounds like Samantha, ZAINA sounds like Karen, …".
        // Idempotent: only assigns characters without an existing row.
        try? VoiceAssignmentService.autoAssignSpeakingCharacters(
            in: [scene],
            project: project,
            context: context
        )

        assignments = (try? VoiceAssignmentService.assignments(
            for: project, context: context
        )) ?? [:]

        queue = TableReadEngine.queue(
            for: scene,
            assignments: assignments,
            settings: settings
        )

        if !queue.isEmpty && player.queue != queue {
            player.stop()
        }
    }
}

// MARK: - Preview

#Preview("With Penny / Marcus dialogue") {
    let schema = Schema(PenovaSchema.models)
    let container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let p = Project(title: "Ek Raat Mumbai Mein", logline: "")
    ctx.insert(p)
    let ep = Episode(title: "Departure", order: 0); ep.project = p
    p.episodes.append(ep); ctx.insert(ep)
    let s = ScriptScene(
        locationName: "KITCHEN",
        location: .interior, time: .night, order: 0
    )
    s.episode = ep; ep.scenes.append(s); ctx.insert(s)

    let lines: [(SceneElementKind, String, String?)] = [
        (.action, "Penny stands at the sink. Water running.", nil),
        (.character, "MARCUS", nil),
        (.dialogue, "You didn't eat.", "MARCUS"),
        (.character, "PENNY", nil),
        (.parenthetical, "(without turning)", "PENNY"),
        (.dialogue, "I wasn't hungry.", "PENNY"),
        (.character, "MARCUS", nil),
        (.dialogue, "Penny.", "MARCUS"),
        (.action, "She turns off the water. Doesn't turn around.", nil),
        (.character, "PENNY", nil),
        (.dialogue, "I quit today.", "PENNY"),
    ]
    for (i, (k, t, n)) in lines.enumerated() {
        let el = SceneElement(kind: k, text: t, order: i, characterName: n)
        el.scene = s; s.elements.append(el); ctx.insert(el)
    }
    return TableReadView(scene: s, project: p)
        .modelContainer(container)
}
