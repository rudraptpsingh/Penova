//
//  LimitReachedSheet.swift
//  Penova
//
//  S22 — The polite wall. Free users see this when they hit a quantitative
//  limit (projects, scenes-per-project). Not a surprise — by the time this
//  appears, they've already seen the usage meter in Settings, a cap label
//  in the Scripts list, and a banner one scene short of the cap.
//
//  "Maybe later" closes. "Upgrade" pivots to the Paywall with the right
//  hero copy pre-selected.
//

import SwiftUI

struct LimitReachedContext: Identifiable {
    let id = UUID()
    let reason: FreemiumReason
    let limit: Int

    var title: String {
        switch reason {
        case .maxProjects: return "Finish your pilot first."
        case .maxScenes:   return "You've written a lot."
        case .exportFdx:   return "FDX export is a Pro feature."
        case .settings:    return "Penova Pro."
        }
    }

    var message: String {
        switch reason {
        case .maxProjects:
            return "Free gives you one project at a time — enough room for a whole feature or pilot. Finish your pilot. Then Penova Pro unlocks the rest."
        case .maxScenes:
            return "This project has hit the sanity ceiling. Pro removes it entirely — unlimited scenes, unlimited episodes."
        case .exportFdx:
            return "Hand a Final Draft file to your director. Pro unlocks FDX export."
        case .settings:
            return "Unlock parallel projects and FDX export. One scene away from unlimited."
        }
    }

    var paywallSource: PaywallSource {
        switch reason {
        case .maxProjects: return .projectLimit
        case .maxScenes:   return .sceneLimit
        case .exportFdx:   return .exportFdx
        case .settings:    return .settings
        }
    }
}

struct LimitReachedSheet: View {
    let context: LimitReachedContext
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: PenovaSpace.l) {
            Spacer()
            PenovaIconView(.focus, size: 56, color: PenovaColor.amber)
            Text(context.title)
                .font(PenovaFont.title)
                .foregroundStyle(PenovaColor.snow)
                .multilineTextAlignment(.center)
            Text(context.message)
                .font(PenovaFont.body)
                .foregroundStyle(PenovaColor.snow3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PenovaSpace.m)
            Spacer()
            PenovaButton(title: "Upgrade to Pro", variant: .primary) {
                showPaywall = true
            }
            PenovaButton(title: "Maybe later", variant: .ghost) {
                dismiss()
            }
        }
        .padding(PenovaSpace.l)
        .frame(maxWidth: .infinity)
        .background(PenovaColor.ink0)
        .sheet(isPresented: $showPaywall, onDismiss: { dismiss() }) {
            PaywallSheet(source: context.paywallSource)
                .presentationDetents([.large])
        }
    }
}
