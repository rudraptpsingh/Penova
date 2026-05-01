//
//  PDFKitLineSource.swift
//  Penova
//
//  Production adapter that turns a real `PDFDocument` into a stream of
//  `PDFLine`s. We let PDFKit do the line segmentation for us via
//  `PDFSelection.selectionsByLine()` — each returned selection is one
//  visual line whose `bounds(for: page)` gives us its rect in PDF
//  user space. This is robust to glyph ordering quirks that broke the
//  earlier index-arithmetic approach (where the running character offset
//  could fall out of sync with PDFKit's internal indexing for some
//  lines, returning `CGRect.null` and collapsing them all to y=pageHeight).
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

        let pageRect = page.bounds(for: .mediaBox)
        let pageHeight = pageRect.height

        // Build a selection over the entire page, then ask PDFKit to
        // split it into one selection per visual line.
        guard let pageString = page.string, !pageString.isEmpty else { return [] }
        let length = (pageString as NSString).length
        guard length > 0,
              let pageSelection = page.selection(for: NSRange(location: 0, length: length))
        else {
            return fallbackLines(on: page, pageHeight: pageHeight, pageIndex: index)
        }

        let lineSelections = pageSelection.selectionsByLine()
        if lineSelections.isEmpty {
            return fallbackLines(on: page, pageHeight: pageHeight, pageIndex: index)
        }

        var out: [PDFLine] = []
        out.reserveCapacity(lineSelections.count)
        for lineSel in lineSelections {
            let raw = lineSel.string ?? ""
            let trimmed = raw
                .replacingOccurrences(of: "[\\s]+$", with: "", options: .regularExpression)
            guard !trimmed.isEmpty else { continue }

            let bounds = lineSel.bounds(for: page)
            // Right-aligned text occasionally reports a null/empty rect.
            // Skip those lines rather than collapse them to a fake y —
            // the parser would otherwise merge them via mergeSameYLines
            // and lose them entirely.
            guard !bounds.isNull, !bounds.isEmpty else { continue }

            out.append(PDFLine(
                text: trimmed,
                x: bounds.origin.x,
                yTop: bounds.origin.y + bounds.height,
                pageHeight: pageHeight,
                pageIndex: index
            ))
        }

        // PDF origin is bottom-left, so larger y is higher on the page.
        // selectionsByLine() generally returns lines in reading order
        // already, but sort defensively in case of multi-column layouts.
        return out.sorted { $0.yTop > $1.yTop }
    }

    /// Last-resort path used when PDFKit refuses to return a page-wide
    /// selection (rare, but observed on PDFs with unusual content
    /// streams). Walks `page.string` line by line and asks for the
    /// bounds of each line's first non-whitespace character. Lines whose
    /// bounds come back null are dropped rather than placed at a
    /// fake y where the parser would merge them.
    private func fallbackLines(on page: PDFPage, pageHeight: CGFloat, pageIndex: Int) -> [PDFLine] {
        guard let pageString = page.string, !pageString.isEmpty else { return [] }
        let charCount = (pageString as NSString).length
        var out: [PDFLine] = []
        var offset = 0
        for line in pageString.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            let trimmedTrailing = lineText
                .replacingOccurrences(of: "[\\s]+$", with: "", options: .regularExpression)
            if trimmedTrailing.isEmpty {
                offset += (lineText as NSString).length + 1
                continue
            }
            var firstNonSpaceLocal = 0
            for (i, ch) in lineText.unicodeScalars.enumerated() {
                if !CharacterSet.whitespaces.contains(ch) {
                    firstNonSpaceLocal = i
                    break
                }
            }
            let firstIdx = min(offset + firstNonSpaceLocal, charCount - 1)
            let bounds = page.characterBounds(at: firstIdx)
            if !bounds.isNull, !bounds.isEmpty {
                out.append(PDFLine(
                    text: trimmedTrailing,
                    x: bounds.origin.x,
                    yTop: bounds.origin.y + bounds.height,
                    pageHeight: pageHeight,
                    pageIndex: pageIndex
                ))
            }
            offset += (lineText as NSString).length + 1
        }
        return out.sorted { $0.yTop > $1.yTop }
    }
}
