//
//  SettingsScreen.swift
//  Penova
//
//  S18 — Settings. Appearance, privacy permission status, about, and the
//  destructive "Delete all data" action (S21). Subscription / usage meter
//  are hidden until the paid-features milestone (see STUBS.md).
//

import SwiftUI
import SwiftData
import AVFoundation

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                appearanceBlock
                privacyBlock
                aboutBlock
                dangerBlock
            }
            .padding(PenovaSpace.l)
        }
        .background(PenovaColor.ink0)
        .navigationTitle(Copy.settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all data?", isPresented: $showDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { deleteAll() }
        } message: {
            Text("This erases every project, episode, scene, element, and character. There is no undo.")
        }
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Appearance")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            HStack {
                Text("Theme")
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                Spacer()
                Text("Dark")
                    .font(PenovaFont.bodySmall)
                    .foregroundStyle(PenovaColor.snow3)
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var privacyBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Privacy")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            VStack(spacing: 0) {
                permissionRow(title: "Microphone", status: microphoneStatus)
                Divider().overlay(PenovaColor.ink4)
                permissionRow(title: "Speech recognition", status: "Requested on first use")
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private func permissionRow(title: String, status: String) -> some View {
        HStack {
            Text(title)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow)
            Spacer()
            Text(status)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(.vertical, PenovaSpace.xs)
    }

    private var microphoneStatus: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:  return "Allowed"
        case .denied:   return "Denied"
        case .undetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("About")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            HStack {
                Text("Version")
                    .font(PenovaFont.body)
                    .foregroundStyle(PenovaColor.snow)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow3)
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private var dangerBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Danger zone")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.ember)
            PenovaButton(
                title: "Delete all data",
                variant: .destructive,
                size: .compact
            ) {
                showDeleteAll = true
            }
        }
    }

    private func deleteAll() {
        try? context.delete(model: SceneElement.self)
        try? context.delete(model: ScriptScene.self)
        try? context.delete(model: Episode.self)
        try? context.delete(model: ScriptCharacter.self)
        try? context.delete(model: Project.self)
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "penova.didSeedDemo.v2")
    }
}
