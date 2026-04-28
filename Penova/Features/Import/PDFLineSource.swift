//
//  PDFLineSource.swift
//  Penova
//
//  Abstraction over "a screenplay PDF, broken into lines with x-indent
//  per line". Production callers wrap a `PDFDocument` via the PDFKit
//  adapter; tests use the in-memory mock so the parser logic is testable
//  without rendering anything.
//
//  Coordinate convention:
//    - PDF user space (origin lower-left, points). All x/y are points.
//    - `pageHeight` is supplied per-line so the parser can drop chrome
//      rows that sit too close to the top/bottom of the page (page
//      numbers, headers, footers).
//

import Foundation
import CoreGraphics

public struct PDFLine: Equatable {
    public let text: String
    /// Left edge of the line's content in PDF user space (points).
    public let x: CGFloat
    /// Top edge of the line in PDF user space (points). PDF origin is
    /// lower-left, so larger y = closer to the top of the page.
    public let yTop: CGFloat
    public let pageHeight: CGFloat
    public let pageIndex: Int

    public init(
        text: String,
        x: CGFloat,
        yTop: CGFloat,
        pageHeight: CGFloat,
        pageIndex: Int
    ) {
        self.text = text
        self.x = x
        self.yTop = yTop
        self.pageHeight = pageHeight
        self.pageIndex = pageIndex
    }
}

public protocol PDFLineSource {
    var pageCount: Int { get }
    /// Lines on the given page, in reading order (top-to-bottom).
    /// Implementations must drop trailing whitespace from each line and
    /// skip empty/whitespace-only lines.
    func lines(onPage index: Int) -> [PDFLine]
}
