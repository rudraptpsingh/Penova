//
//  PaywallSheet.swift
//  Penova
//
//  S20 stub — hero title varies by source. Real StoreKit 2 product load +
//  purchase flow lands in Task 14.
//
// STUB: PaywallSheet — wire StoreKit 2 product load, purchase, restore; real price strings. See STUBS.md.
//

import SwiftUI

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: PaywallSource

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PenovaSpace.l) {
                    Text(heroTitle)
                        .font(PenovaFont.hero)
                        .foregroundStyle(PenovaColor.snow)
                    Text("Unlimited projects. Unlimited scenes. FDX export. Offline forever.")
                        .font(PenovaFont.body)
                        .foregroundStyle(PenovaColor.snow3)

                    VStack(alignment: .leading, spacing: PenovaSpace.s) {
                        planRow("Free",
                                "1 project · 15 scenes · PDF only",
                                highlighted: false)
                        planRow("Pro — ₹399 / month",
                                "Everything. Cancel anytime.",
                                highlighted: true)
                    }

                    PenovaButton(title: "Start 7-day trial") {
                        // Temporary: flip the stored plan so the rest of the
                        // app reacts until StoreKit lands.
                        UserDefaults.standard.set(
                            Subscription.Plan.pro.rawValue,
                            forKey: "penova.subscription.plan"
                        )
                        dismiss()
                    }

                    Button("Restore purchases") { }
                        .font(PenovaFont.bodySmall)
                        .foregroundStyle(PenovaColor.snow3)
                        .frame(maxWidth: .infinity)
                }
                .padding(PenovaSpace.l)
            }
            .background(PenovaColor.ink0)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        PenovaIconView(.close, size: 18, color: PenovaColor.snow3)
                    }
                }
            }
        }
    }

    private var heroTitle: String {
        switch source {
        case .sceneLimit:   return "One scene away from unlimited."
        case .projectLimit: return "Room for every story you start."
        case .exportFdx:    return "FDX for your director."
        case .settings:     return "Penova Pro."
        }
    }

    private func planRow(_ title: String, _ subtitle: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: PenovaSpace.xs) {
            Text(title)
                .font(PenovaFont.bodyLarge)
                .foregroundStyle(highlighted ? PenovaColor.amber : PenovaColor.snow)
            Text(subtitle)
                .font(PenovaFont.bodySmall)
                .foregroundStyle(PenovaColor.snow3)
        }
        .padding(PenovaSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? PenovaColor.amber.opacity(0.12) : PenovaColor.ink2)
        .overlay(
            RoundedRectangle(cornerRadius: PenovaRadius.md)
                .stroke(highlighted ? PenovaColor.amber : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
    }
}
