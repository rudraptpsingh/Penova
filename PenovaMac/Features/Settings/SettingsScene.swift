//
//  SettingsScene.swift
//  Penova for Mac
//
//  Standard `Settings { TabView { … } }` scene. Penova's Mac app didn't
//  have a Preferences window before v1.1; this is the first tab to ship,
//  built around the F5 opt-in analytics toggle. Future tabs (Editor,
//  Updates, Account) hang off the same TabView.
//
//  Copy clones Apple's "Share Mac Analytics" pattern in System Settings —
//  toggle, then a paragraph that lists exactly what's collected and what
//  isn't. Plus two affordances:
//
//    • Privacy details → opens https://penova.pages.dev/privacy
//    • View what's been sent → sheet with the current pending payload
//      pretty-printed as JSON, plus a "Copy" button.
//

import SwiftUI
import AppKit
import PenovaKit

struct SettingsScene: View {
    var body: some View {
        TabView {
            PrivacyAnalyticsTab()
                .tabItem {
                    Label("Privacy & Analytics", systemImage: "lock.shield")
                }
                .frame(width: 520, height: 480)
        }
    }
}

// MARK: - Privacy & Analytics tab

private struct PrivacyAnalyticsTab: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @ObservedObject private var analytics = AnalyticsService.shared

    @State private var showSentSheet = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.analyticsEnabled) {
                    Text("Help improve Penova by sharing anonymous usage data")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
            } footer: {
                EmptyView()
            }

            Section {
                disclosureBlock
            }

            Section {
                HStack {
                    Button("Privacy details…") { openPrivacy() }
                    Button("View what's been sent…") { showSentSheet = true }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .sheet(isPresented: $showSentSheet) {
            SentPayloadSheet()
                .frame(minWidth: 520, minHeight: 420)
        }
    }

    private var disclosureBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What we collect (only when this is on):")
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                bullet("App version, macOS version, locale (e.g. en-US)")
                bullet("Aggregate counts: scripts opened, scripts created, exports run, reports viewed")
            }
            .foregroundStyle(.secondary)

            Text("What we never collect:")
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                bullet("The contents of your scripts")
                bullet("Your name, email, IP address, or any account identifier")
                bullet("Document filenames, paths, or metadata")
            }
            .foregroundStyle(.secondary)

            Text("Sent once per day, in a payload smaller than 1 KB. You can turn this off at any time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .font(.system(size: 12))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openPrivacy() {
        if let url = URL(string: "https://penova.pages.dev/privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - "View what's been sent" sheet

private struct SentPayloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var analytics = AnalyticsService.shared
    @ObservedObject private var prefs = PreferencesStore.shared

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending payload")
                        .font(.headline)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payloadJSON, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
            ScrollView {
                Text(payloadJSON)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
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
}
