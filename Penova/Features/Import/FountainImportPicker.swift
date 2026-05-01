//
//  FountainImportPicker.swift  (now: ScreenplayImportPicker)
//  Penova
//
//  Universal screenplay file picker. Accepts the three formats writers
//  actually have on hand:
//    - .pdf       — finished screenplay PDF (Final Draft, WriterDuet,
//                   Highland, Fade In, Fountain renderers, …)
//    - .fdx       — Final Draft XML
//    - .fountain  — plain-text Fountain markup
//    - .txt / .md — plain text containing Fountain
//
//  Picking a file fires `onPick` with the URL; the caller is responsible
//  for routing to the right parser via `ScreenplayImporter.dispatch`.
//
//  We keep the type alias `FountainImportPicker` so existing call sites
//  (ScriptsTabScreen) compile without changes; new code should refer to
//  ScreenplayImportPicker directly.
//

import SwiftUI
import UniformTypeIdentifiers
import PenovaKit

struct ScreenplayImportPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (URL) -> Void

    @State private var showing = true

    /// Content types we accept. `.fountain` and `.fdx` aren't in the
    /// system registry so we synthesize them from the extension.
    private var allowedTypes: [UTType] {
        var types: [UTType] = [.plainText, .pdf]
        if let ft = UTType(filenameExtension: "fountain") { types.append(ft) }
        if let fdx = UTType(filenameExtension: "fdx") { types.append(fdx) }
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

/// Backwards-compatible alias for the original Fountain-only picker.
typealias FountainImportPicker = ScreenplayImportPicker
