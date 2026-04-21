//
//  PaywallSheet.swift
//  Draftr
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
                VStack(alignment: .leading, spacing: DraftrSpace.l) {
                    Text(heroTitle)
                        .font(DraftrFont.hero)
                        .foregroundStyle(DraftrColor.snow)
                    Text("Unlimited projects. Unlimited scenes. FDX export. Offline forever.")
                        .font(DraftrFont.body)
                        .foregroundStyle(DraftrColor.snow3)

                    VStack(alignment: .leading, spacing: DraftrSpace.s) {
                        planRow("Free",
                                "1 project · 15 scenes · PDF only",
                                highlighted: false)
                        planRow("Pro — ₹399 / month",
                                "Everything. Cancel anytime.",
                                highlighted: true)
                    }

                    DraftrButton(title: "Start 7-day trial") {
                        // Temporary: flip the stored plan so the rest of the
                        // app reacts until StoreKit lands.
                        UserDefaults.standard.set(
                            Subscription.Plan.pro.rawValue,
                            forKey: "draftr.subscription.plan"
                        )
                        dismiss()
                    }

                    Button("Restore purchases") { }
                        .font(DraftrFont.bodySmall)
                        .foregroundStyle(DraftrColor.snow3)
                        .frame(maxWidth: .infinity)
                }
                .padding(DraftrSpace.l)
            }
            .background(DraftrColor.ink0)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        DraftrIconView(.close, size: 18, color: DraftrColor.snow3)
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
        case .settings:     return "Draftr Pro."
        }
    }

    private func planRow(_ title: String, _ subtitle: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: DraftrSpace.xs) {
            Text(title)
                .font(DraftrFont.bodyLarge)
                .foregroundStyle(highlighted ? DraftrColor.amber : DraftrColor.snow)
            Text(subtitle)
                .font(DraftrFont.bodySmall)
                .foregroundStyle(DraftrColor.snow3)
        }
        .padding(DraftrSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? DraftrColor.amber.opacity(0.12) : DraftrColor.ink2)
        .overlay(
            RoundedRectangle(cornerRadius: DraftrRadius.md)
                .stroke(highlighted ? DraftrColor.amber : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
    }
}
