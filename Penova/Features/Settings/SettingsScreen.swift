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
import UIKit
import PenovaKit

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthSession
    @ObservedObject private var prefs = PreferencesStore.shared

    @State private var showDeleteAll = false
    @State private var showSignOutConfirm = false
    @State private var showCopyFeedbackFallback = false
    @State private var showAnalyticsSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PenovaSpace.l) {
                accountBlock
                appearanceBlock
                privacyBlock
                analyticsBlock
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
        .sheet(isPresented: $showAnalyticsSent) {
            AnalyticsSentSheet()
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

    /// F5 — opt-in anonymous usage stats. OFF by default. The toggle is
    /// bound to `PreferencesStore.shared.analyticsEnabled`; flipping it
    /// either enables or disables a once-per-day POST to
    /// `https://penova.pages.dev/v1/ping`. Disclosure copy mirrors the
    /// Mac Settings scene (compressed for mobile).
    private var analyticsBlock: some View {
        VStack(alignment: .leading, spacing: PenovaSpace.s) {
            Text("Analytics")
                .font(PenovaFont.labelCaps)
                .tracking(PenovaTracking.labelCaps)
                .foregroundStyle(PenovaColor.snow3)
            VStack(alignment: .leading, spacing: PenovaSpace.s) {
                Toggle(isOn: $prefs.analyticsEnabled) {
                    Text("Help improve Penova by sharing anonymous usage data")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(PenovaColor.amber)

                Divider().overlay(PenovaColor.ink4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What we collect (only when this is on):")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow2)
                    Text("• App version, iOS version, locale\n• Aggregate counts: scripts opened, scripts created, exports run, reports viewed")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)

                    Text("What we never collect:")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow2)
                        .padding(.top, 4)
                    Text("• The contents of your scripts\n• Your name, email, IP, or any account identifier\n• Document filenames, paths, or metadata")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)

                    Text("Sent once per day, in a payload smaller than 1 KB. You can turn this off at any time.")
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow4)
                        .padding(.top, 4)
                }

                Divider().overlay(PenovaColor.ink4)

                Button(action: { showAnalyticsSent = true }) {
                    HStack {
                        Text("View what's been sent")
                            .font(PenovaFont.body)
                            .foregroundStyle(PenovaColor.snow)
                        Spacer()
                        PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                            .rotationEffect(.degrees(180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().overlay(PenovaColor.ink4)

                Button(action: openPrivacyDetails) {
                    HStack {
                        Text("Privacy details")
                            .font(PenovaFont.body)
                            .foregroundStyle(PenovaColor.snow)
                        Spacer()
                        PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                            .rotationEffect(.degrees(180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
    }

    private func openPrivacyDetails() {
        if let url = URL(string: "https://penova.pages.dev/privacy") {
            UIApplication.shared.open(url)
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
            VStack(spacing: 0) {
                HStack {
                    Text("Version")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow)
                    Spacer()
                    Text(FeedbackComposer.versionAndBuild())
                        .font(PenovaFont.monoScript)
                        .foregroundStyle(PenovaColor.snow3)
                }
                .padding(.vertical, PenovaSpace.xs)
                Divider().overlay(PenovaColor.ink4)
                Button(action: openFeedbackMail) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .font(PenovaFont.body)
                                .foregroundStyle(PenovaColor.snow)
                            Text("Built by one person — every email gets a reply.")
                                .font(PenovaFont.bodySmall)
                                .foregroundStyle(PenovaColor.snow3)
                        }
                        Spacer()
                        PenovaIconView(.back, size: 14, color: PenovaColor.snow4)
                            .rotationEffect(.degrees(180))
                    }
                    .padding(.vertical, PenovaSpace.xs)
                }
                .buttonStyle(.plain)
            }
            .padding(PenovaSpace.m)
            .background(PenovaColor.ink2)
            .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
        }
        .alert("Couldn't open Mail", isPresented: $showCopyFeedbackFallback) {
            Button("Copy diagnostic info") { copyFeedbackToClipboard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No mail client is configured. Copy the diagnostic info, then paste it into your browser or any other mail tool, and send to \(FeedbackComposer.recipient).")
        }
    }

    private func openFeedbackMail() {
        guard let url = FeedbackComposer.mailtoURL() else {
            showCopyFeedbackFallback = true
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url) { ok in
                if !ok { showCopyFeedbackFallback = true }
            }
        } else {
            showCopyFeedbackFallback = true
        }
    }

    private func copyFeedbackToClipboard() {
        UIPasteboard.general.string = FeedbackComposer.clipboardFallback()
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

// MARK: - Analytics "View what's been sent" sheet

/// Lets the user see exactly what payload would be sent right now if a
/// flush fired. Updates live as `pendingCounters` changes. The user can
/// copy the JSON to the clipboard for a totally transparent audit.
private struct AnalyticsSentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var analytics = AnalyticsService.shared
    @ObservedObject private var prefs = PreferencesStore.shared

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.m) {
                    Text(subtitle)
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)

                    Text(payloadJSON)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PenovaSpace.m)
                        .background(PenovaColor.ink2)
                        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))

                    Button(action: copy) {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy JSON to clipboard")
                        }
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.amber)
                    }
                    .buttonStyle(.plain)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("What's been sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var subtitle: String {
        if !prefs.analyticsEnabled {
            return "Analytics is off. Nothing is being sent."
        }
        if let last = prefs.analyticsLastSent {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return "Last successful send: \(f.string(from: last))"
        }
        return "Never sent."
    }

    private var payloadJSON: String {
        let payload = analytics.makePayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private func copy() {
        UIPasteboard.general.string = payloadJSON
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
