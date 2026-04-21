//
//  ExportShareSheet.swift
//  Draftr
//
//  Tiny sheet that hosts the native share sheet for a freshly-rendered
//  export file (PDF today, FDX after Pro ships). Separated from the
//  renderer so the caller only needs to hand it a URL.
//

import SwiftUI

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
    let format: ExportFormat
}

struct ExportShareSheet: View {
    let file: ExportFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: DraftrSpace.l) {
                Spacer()
                DraftrIconView(.export, size: 48, color: DraftrColor.amber)
                Text("Ready to share")
                    .font(DraftrFont.title)
                    .foregroundStyle(DraftrColor.snow)
                Text(file.url.lastPathComponent)
                    .font(DraftrFont.monoScript)
                    .foregroundStyle(DraftrColor.snow3)
                    .multilineTextAlignment(.center)
                Spacer()
                ShareLink(item: file.url) {
                    HStack {
                        DraftrIconView(.export, size: 18, color: DraftrColor.ink0)
                        Text("Share \(file.format.rawValue.uppercased())")
                            .font(DraftrFont.bodyLarge)
                            .foregroundStyle(DraftrColor.ink0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DraftrSpace.m)
                    .background(DraftrColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: DraftrRadius.md))
                }
                DraftrButton(title: "Done", variant: .ghost) { dismiss() }
            }
            .padding(DraftrSpace.l)
            .background(DraftrColor.ink0)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
