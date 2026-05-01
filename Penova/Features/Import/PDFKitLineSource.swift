//
//  PDFKitLineSource.swift
//  Penova
//
//  Production adapter that turns a real `PDFDocument` into a stream of
//  `PDFLine`s. We use `PDFPage.string` for the line text, then ask
//  PDFKit for the bounding box of each character to recover the line's
//  left edge in PDF user space.
//
//  Why character-level bounds: the PDF spec doesn't carry "line"
//  semantics — text shows up as a stream of placed glyphs. PDFKit
//  reconstructs lines for us in `string`, but the only way to get
//  geometry back out is via `characterBounds(at:)`. We sample one or
//  two chars per line (first non-space + last non-space) and that's
//  enough to know where the line starts.
//

import Foundation
import CoreGraphics
import PDFKit

public struct PDFKitLineSource: PDFLineSource {
    private let document: PDFDocument

    public init(document: PDFDocument) {
        self.document = document
    }

    public var pageCount: Int { document.pageCount }

    public func lines(onPage index: Int) -> [PDFLine] {
        guard let page = document.page(at: index) else { return [] }
        guard let pageString = page.string, !pageString.isEmpty else { return [] }

        let pageRect = page.bounds(for: .mediaBox)
        let pageHeight = pageRect.height

        var out: [PDFLine] = []
        out.reserveCapacity(64)

        // Walk pageString line by line. For each non-empty line, ask
        // PDFKit for the left edge of its first non-space character and
        // its top y. PDFKit indexes chars across the whole page string
        // with newline characters counted in the index, so we can keep
        // a running offset.
        var offset = 0
        let scalars = pageString
        let lines = scalars.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let lineText = String(line)
            // Trim trailing whitespace; preserve leading because we
            // re-derive the indent from PDF coordinates anyway.
            let trimmedTrailing = lineText
                .replacingOccurrences(of: "[\\s]+$", with: "", options: .regularExpression)

            if trimmedTrailing.isEmpty {
                offset += lineText.utf16.count + 1   // +1 for the newline
                continue
            }

            // Find the offset of the first non-whitespace char on this line.
            var firstNonSpaceLocal = 0
            for (i, ch) in lineText.unicodeScalars.enumerated() {
                if !CharacterSet.whitespaces.contains(ch) {
                    firstNonSpaceLocal = i
                    break
                }
            }
            let firstIdx = offset + firstNonSpaceLocal

            // characterBounds(at:) is bounded; guard against off-by-one.
            let charCount = pageString.utf16.count
            let safeIdx = min(firstIdx, charCount - 1)
            let bounds = page.characterBounds(at: safeIdx)
            // PDFKit returns CGRect.null for empty/invalid ranges — fall
            // back to "use the whole page" bounds so x defaults to 0
            // rather than skipping the line entirely.
            let x = bounds.isNull || bounds.isEmpty ? 0 : bounds.origin.x
            let yTop = bounds.isNull || bounds.isEmpty
                ? pageHeight
                : bounds.origin.y + bounds.height

            out.append(PDFLine(
                text: trimmedTrailing,
                x: x,
                yTop: yTop,
                pageHeight: pageHeight,
                pageIndex: index
            ))

            offset += lineText.utf16.count + 1
        }

        // Sort by y descending (PDF origin is bottom-left, so larger y
        // is higher on the page). PDFKit usually returns lines already
        // in reading order, but we sort defensively.
        return out.sorted { $0.yTop > $1.yTop }
    }
}
