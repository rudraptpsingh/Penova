//
//  FountainImportPicker.swift
//  Penova
//
//  Thin SwiftUI wrapper around `.fileImporter` for picking Fountain /
//  plain-text / markdown files. Dismisses itself on selection/cancel.
//

import SwiftUI
import UniformTypeIdentifiers
import PenovaKit

struct FountainImportPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL) -> Void

    @State private var showing = true

    /// Content types we accept. `.fountain` isn't in the system registry so
    /// we synthesize it from the extension; also allow .txt and .md.
    private var allowedTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let ft = UTType(filenameExtension: "fountain") { types.append(ft) }
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }

    var body: some View {
        Color.clear
            .fileImporter(
                isPresented: $showing,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let u = urls.first { onPick(u) }
                case .failure:
                    break
                }
                dismiss()
            }
    }
}
