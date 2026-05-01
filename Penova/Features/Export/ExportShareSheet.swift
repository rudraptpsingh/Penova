//
//  ExportShareSheet.swift
//  Penova
//
//  Tiny sheet that hosts the native share sheet for a freshly-rendered
//  export file (PDF today, FDX after Pro ships). Separated from the
//  renderer so the caller only needs to hand it a URL.
//

import SwiftUI
import PenovaKit

public enum ExportFormat: String, Codable, CaseIterable {
    case pdf, fdx, fountain
}

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
            VStack(spacing: PenovaSpace.l) {
                Spacer()
                PenovaIconView(.export, size: 48, color: PenovaColor.amber)
                Text("Ready to share")
                    .font(PenovaFont.title)
                    .foregroundStyle(PenovaColor.snow)
                Text(file.url.lastPathComponent)
                    .font(PenovaFont.monoScript)
                    .foregroundStyle(PenovaColor.snow3)
                    .multilineTextAlignment(.center)
                Spacer()
                ShareLink(item: file.url) {
                    HStack {
                        PenovaIconView(.export, size: 18, color: PenovaColor.ink0)
                        Text("Share \(file.format.rawValue.uppercased())")
                            .font(PenovaFont.bodyLarge)
                            .foregroundStyle(PenovaColor.ink0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PenovaSpace.m)
                    .background(PenovaColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: PenovaRadius.md))
                }
                PenovaButton(title: "Done", variant: .ghost) { dismiss() }
            }
            .padding(PenovaSpace.l)
            .background(PenovaColor.ink0)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
        }
            .preferredColorScheme(.dark)
    }
}
