//
//  ScreenplayLayoutSpec.swift
//  PenovaKit
//
//  WGA / industry-standard screenplay PDF layout constants. Shared
//  between the iOS renderer (UIGraphicsPDFRenderer) and the Mac
//  renderer (CGContext + Core Text). Whoever changes these numbers
//  must also rerun the PDF parity tests in both targets.
//
//  Page = US Letter 8.5 × 11" (612 × 792 pt). Courier 12pt. 55 lines/page.
//

import CoreGraphics

public enum ScreenplayLayoutSpec {

    public static let pageWidth: CGFloat  = 612 // 8.5"
    public static let pageHeight: CGFloat = 792 // 11"
    public static let pageRect: CGRect    = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    public enum Margins {
        public static let top: CGFloat    = 72  // 1.0"
        public static let bottom: CGFloat = 72  // 1.0"
        public static let left: CGFloat   = 108 // 1.5" — binding gutter
        public static let right: CGFloat  = 72  // 1.0"
    }

    /// Indents from the LEFT page edge for each element type.
    public enum Indent {
        public static let action: CGFloat        = 108 // 1.5"
        public static let character: CGFloat     = 266 // 3.7"
        public static let dialogue: CGFloat      = 180 // 2.5"
        public static let parenthetical: CGFloat = 224 // 3.1"
    }

    /// Maximum text width per element (after indent).
    public enum BlockWidth {
        public static let action: CGFloat        = 396 // 5.5"
        public static let character: CGFloat     = 240 // generous to fit (V.O.)/(O.S.)
        public static let dialogue: CGFloat      = 252 // 3.5"
        public static let parenthetical: CGFloat = 144 // 2.0"
    }

    /// Right edge transitions snap to (right-aligned).
    public static let transitionRight: CGFloat = 540 // 7.5"

    /// One Courier 12pt blank line.
    public static let line: CGFloat = 12
    /// Lines per page (industry standard).
    public static let linesPerPage: Int = 55
    /// Body font size.
    public static let bodyFontSize: CGFloat = 12
    /// Body font name (Courier — every screenwriting tool ships this).
    public static let bodyFontName: String = "Courier"
}
