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
    @EnvironmentObject private var auth: AuthSession

    @State private var showDeleteAll = false
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                accountBlock
                appearanceBlock
                privacyBlock
                habitBlock
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
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { auth.signOut() }
        } message: {
            Text("Your scripts stay on this device. Signing back in restores your name and email on new exports.")
        }
    }

    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Account")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            VStack(alignment: .leading, spacing: PenovaSpace.s) {
                if auth.isSignedIn {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.displayName)
                                .font(PenovaFont.bodyLarge)
                                .foregroundStyle(PenovaColor.snow)
                            if !auth.email.isEmpty {
                                Text(auth.email)
                                    .font(PenovaFont.bodySmall)
                                    .foregroundStyle(PenovaColor.snow3)
                            }
                            Text("Signed in with Apple")
                                .font(PenovaFont.labelCaps)
                                .tracking(PenovaTracking.labelCaps)
                                .foregroundStyle(PenovaColor.jade)
                        }
                        Spacer()
                    }
                    .padding(PenovaSpace.m)
                    .background(PenovaColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                    PenovaButton(
                        title: "Sign out",
                        variant: .ghost,
                        size: .compact
                    ) {
                        showSignOutConfirm = true
                    }
                } else if auth.status == .revoked {
                    HStack {
                        Text("Apple sign-in was revoked. Tap to sign in again.")
                            .font(PenovaFont.bodySmall)
                            .foregroundStyle(PenovaColor.ember)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(PenovaSpace.m)
                    .background(PenovaColor.ember.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: PenovaRadius.md)
                            .stroke(PenovaColor.ember.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anonymous")
                                .font(PenovaFont.bodyLarge)
                                .foregroundStyle(PenovaColor.snow)
                            Text("Sign in with Apple to attach your name to exports and revisions.")
                                .font(PenovaFont.bodySmall)
                                .foregroundStyle(PenovaColor.snow3)
                        }
                        Spacer()
                    }
                    .padding(PenovaSpace.m)
                    .background(PenovaColor.ink2)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                }
            }
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

    private var habitBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Writing")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            NavigationLink {
                HabitScreen()
            } label: {
                HStack(spacing: PenovaSpace.m) {
                    PenovaIconView(.progress, size: 18, color: PenovaColor.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Copy.habit.settingsRow)
                            .font(PenovaFont.body)
                            .foregroundStyle(PenovaColor.snow)
                        Text(Copy.habit.settingsRowSubtitle)
                            .font(PenovaFont.bodySmall)
                            .foregroundStyle(PenovaColor.snow3)
                    }
                    Spacer()
                    PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                        .rotationEffect(.degrees(180))
                }
                .padding(PenovaSpace.m)
                .background(PenovaColor.ink2)
                .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.habit.settingsRow)
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
        try? context.delete(model: Revision.self)
        try? context.delete(model: SceneElement.self)
        try? context.delete(model: ScriptScene.self)
        try? context.delete(model: Episode.self)
        try? context.delete(model: ScriptCharacter.self)
        try? context.delete(model: Project.self)
        try? context.delete(model: WritingDay.self)
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "penova.didSeedDemo.v2")
        HabitTracker.clearAllSnapshots()
    }
}
