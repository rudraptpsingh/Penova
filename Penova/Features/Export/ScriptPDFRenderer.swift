//
//  ScriptPDFRenderer.swift
//  Penova
//
//  S15 — Renders a Project to an industry-standard screenplay PDF.
//
//  Paper / font:
//    - US Letter 8.5 × 11"
//    - Courier 12pt EXACTLY (every element). One character per 0.1". 55 lines/page.
//
//  Margins (WGA / industry convention):
//    - Top         1.0"
//    - Bottom      1.0"
//    - Left        1.5"   (binding)
//    - Right       1.0"
//
//  Element indents (from the LEFT page edge):
//    - Scene heading   1.5"   (flush with left margin, ALL CAPS, NOT bold)
//    - Action          1.5"   (flush with left margin)
//    - Character cue   3.7"   (ALL CAPS)
//    - Parenthetical   3.1"   (wrapped in parens, max ~2")
//    - Dialogue        2.5"   (max width 3.5")
//    - Transition      right-aligned to 7.5" (ALL CAPS, ends in colon)
//
//  Spacing (measured in exact Courier 12pt blank lines, 12pt each):
//    - 1 blank line between every block by default
//    - 2 blank lines BEFORE a scene heading
//    - Character → Parenthetical → Dialogue have NO blank lines between them
//
//  Page numbers:
//    - Top-right, 0.5" from top, "N." (period), starting page 2.
//    - The title page (page 1 of document) is unnumbered.
//
//  Dialogue page breaks:
//    - "(MORE)" at the bottom when dialogue continues
//    - "CHARACTER (CONT'D)" at the top of the new page
//

import Foundation
import UIKit

enum ScriptPDFRenderer {

    // MARK: - Public

    static func render(project: Project) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // 8.5 × 11"
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: project.title,
            kCGPDFContextCreator as String: "Penova"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let url = temporaryURL(for: project)
        try? FileManager.default.removeItem(at: url)

        try renderer.writePDF(to: url) { ctx in
            var state = LayoutState(pageRect: pageRect, mode: .draw(ctx))
            layout(project: project, state: &state)
        }

        return url
    }

    /// Measure how many numbered script pages the given project would produce
    /// if rendered. Uses the exact same layout math as `render(project:)`
    /// so the count agrees with the emitted PDF. Excludes the (unnumbered)
    /// title page. Returns 0 for a project with no renderable content.
    static func measurePageCount(project: Project) -> Int {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        var state = LayoutState(pageRect: pageRect, mode: .measure)
        layout(project: project, state: &state)
        // If we never advanced past the title page (empty project), nothing to count.
        if state.onTitlePage { return 0 }
        // A project with episodes but zero scenes still consumes one blank page
        // per episode (we beginPage before walking episode scenes); but nothing
        // was drawn — count that as 0.
        if !state.drewAnyContent { return 0 }
        return state.scriptPageNumber
    }

    // MARK: - Shared layout walker

    private static func layout(project: Project, state: inout LayoutState) {
        drawTitlePage(project: project, state: &state)
        let resetPerEpisode = project.activeEpisodesOrdered.count > 1
        var sceneNumber = 1
        for (epIndex, episode) in project.activeEpisodesOrdered.enumerated() {
            state.startScriptPage()
            if project.activeEpisodesOrdered.count > 1 {
                drawEpisodeHeader(episode, index: epIndex, state: &state)
            }
            if resetPerEpisode { sceneNumber = 1 }
            for scene in episode.scenesOrdered {
                drawScene(scene, number: sceneNumber, state: &state)
                sceneNumber += 1
            }
        }
    }

    // MARK: - Layout state

    /// How the layout walker handles page breaks and drawing primitives.
    /// `.draw` emits into a real PDF context; `.measure` walks the same
    /// flow without touching UIKit draw calls so we can return a page count.
    enum RenderMode {
        case draw(UIGraphicsPDFRendererContext)
        case measure
    }

    struct LayoutState {
        let pageRect: CGRect
        let mode: RenderMode
        var y: CGFloat
        var scriptPageNumber: Int      // 1-based, excludes title page
        var onTitlePage: Bool
        /// Set true the first time real content (not just a beginPage)
        /// is emitted on a script page. Lets `measurePageCount` distinguish
        /// "empty project" from "project with one rendered page".
        var drewAnyContent: Bool

        init(pageRect: CGRect, mode: RenderMode) {
            self.pageRect = pageRect
            self.mode = mode
            self.y = Margins.top
            self.scriptPageNumber = 0
            self.onTitlePage = true
            self.drewAnyContent = false
        }

        var isDrawing: Bool {
            if case .draw = mode { return true }
            return false
        }

        /// Begin the first (or next) numbered script page.
        mutating func startScriptPage() {
            if case .draw(let ctx) = mode { ctx.beginPage() }
            onTitlePage = false
            scriptPageNumber += 1
            y = Margins.top
            Self.drawPageNumber(page: scriptPageNumber, in: pageRect, mode: mode)
        }

        /// Continue to the next page mid-script (same numbering scheme).
        mutating func nextPage() {
            startScriptPage()
        }

        private static func drawPageNumber(page: Int, in pageRect: CGRect, mode: RenderMode) {
            guard case .draw = mode else { return }
            guard page >= 2 else { return }   // first script page unnumbered (industry convention)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: rightAligned()
            ]
            let str = NSAttributedString(string: "\(page).", attributes: attrs)
            str.draw(with: CGRect(x: 0,
                                  y: 36, // 0.5" from top
                                  width: pageRect.width - Margins.right,
                                  height: 14),
                     options: [.usesLineFragmentOrigin], context: nil)
        }
    }

    private enum Margins {
        static let top: CGFloat    = 72      // 1.0"
        static let bottom: CGFloat = 72      // 1.0"
        static let left: CGFloat   = 108     // 1.5"
        static let right: CGFloat  = 72      // 1.0"
    }

    private enum Indent {
        static let action: CGFloat     = 108  // 1.5"
        static let character: CGFloat  = 266  // 3.7"
        static let dialogue: CGFloat   = 180  // 2.5"
        static let parens: CGFloat     = 224  // 3.1"
    }

    private enum BlockWidth {
        static let action: CGFloat    = 432    // 6" (flush to 7.5")
        static let dialogue: CGFloat  = 252    // 3.5" (flush to 6.0")
        static let parens: CGFloat    = 144    // 2.0"
        static let transition: CGFloat = 432   // same as action; drawn right-aligned
    }

    /// Courier 12pt — ONE line = 12pt.
    private static let lineHeight: CGFloat = 12
    /// One blank Courier line.
    private static let blank: CGFloat = 12

    // MARK: - Title Page (industry standard)

    private static func drawTitlePage(project: Project, state: inout LayoutState) {
        if case .draw(let ctx) = state.mode { ctx.beginPage() } else { return }
        // Title centred at ~1/3 down the page.
        let centerX: CGFloat = 0
        let pageWidth = state.pageRect.width
        let titleY: CGFloat = state.pageRect.height * 0.38

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: centered()
        ]
        let title = NSAttributedString(string: project.title.uppercased(), attributes: titleAttrs)
        title.draw(with: CGRect(x: centerX, y: titleY, width: pageWidth, height: lineHeight + 4),
                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        let by = NSAttributedString(string: "Written by", attributes: titleAttrs)
        by.draw(with: CGRect(x: centerX, y: titleY + 4 * lineHeight, width: pageWidth, height: lineHeight + 4),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        let author = NSAttributedString(string: authorName(), attributes: titleAttrs)
        author.draw(with: CGRect(x: centerX, y: titleY + 6 * lineHeight, width: pageWidth, height: lineHeight + 4),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        // Optional contact block, bottom-left, 1" from left & bottom.
        // Only rendered when the project has one set — no hardcoded fallback.
        let contact = project.contactBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contact.isEmpty else { return }
        let contactLines = contact.components(separatedBy: .newlines).count
        let contactHeight = CGFloat(max(contactLines, 1)) * lineHeight + 4
        let contactY = state.pageRect.height - Margins.bottom - contactHeight
        let contactAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        let contactAttr = NSAttributedString(string: contact, attributes: contactAttrs)
        contactAttr.draw(with: CGRect(x: Margins.left, y: contactY,
                                      width: 260, height: contactHeight),
                         options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func authorName() -> String {
        let stored = UserDefaults.standard.string(forKey: "penova.auth.fullName") ?? ""
        if !stored.trimmingCharacters(in: .whitespaces).isEmpty { return stored }
        return "The Writer"
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }

    // MARK: - Episode header (only when a project has >1 episode)

    private static func drawEpisodeHeader(_ episode: Episode, index: Int, state: inout LayoutState) {
        let title = "EPISODE \(episode.order + 1): \(episode.title.uppercased())"
        draw(
            text: title,
            x: Margins.left,
            width: BlockWidth.action,
            blankLinesAfter: 2,
            state: &state
        )
    }

    // MARK: - Scene

    private static func drawScene(_ scene: ScriptScene, number: Int, state: inout LayoutState) {
        // 2 blank lines before a scene heading (but not if we just started a page).
        if state.y > Margins.top {
            state.y += 2 * blank
        }

        drawHeading(scene.heading.uppercased(), number: number, state: &state)

        let elements = scene.elementsOrdered.filter { $0.kind != .heading }
        if elements.isEmpty, let desc = scene.sceneDescription, !desc.isEmpty {
            state.y += blank
            draw(
                text: desc,
                x: Indent.action,
                width: BlockWidth.action,
                blankLinesAfter: 1,
                state: &state
            )
            return
        }

        var previousKind: SceneElementKind?
        for el in elements {
            drawElement(el, previousKind: previousKind, state: &state)
            previousKind = el.kind
        }
    }

    /// Draw the scene heading plus scene-number "gutter" markers in both the
    /// left and right margins (0.5" from each page edge, 12pt Courier).
    /// Markers sit on the same baseline as the heading and stay outside
    /// the heading text column.
    private static func drawHeading(_ text: String, number: Int, state: inout LayoutState) {
        // Stamp the gutter numbers at the heading's current y BEFORE `draw`
        // advances it — both gutters use the same baseline as the heading.
        let baselineY = state.y
        if case .draw = state.mode {
            let label = "\(number)."
            // Left gutter: 0.5" from left page edge.
            let leftAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.black
            ]
            NSAttributedString(string: label, attributes: leftAttrs).draw(
                with: CGRect(x: 36, y: baselineY,
                             width: Indent.action - 36 - 8,
                             height: lineHeight + 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
            // Right gutter: right-aligned so its right edge sits 0.5" from
            // the right page edge.
            let rightAttrs: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.black,
                .paragraphStyle: rightAligned()
            ]
            let rightWidth: CGFloat = 72   // 1" wide box
            let rightX = state.pageRect.width - 36 - rightWidth
            NSAttributedString(string: label, attributes: rightAttrs).draw(
                with: CGRect(x: rightX, y: baselineY,
                             width: rightWidth, height: lineHeight + 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
        }
        draw(
            text: text,
            x: Indent.action,
            width: BlockWidth.action,
            blankLinesAfter: 1,
            state: &state
        )
    }

    private static func drawElement(_ element: SceneElement,
                                    previousKind: SceneElementKind?,
                                    state: inout LayoutState) {
        switch element.kind {
        case .action:
            if previousKind != nil { state.y += blank }
            draw(text: element.text,
                 x: Indent.action, width: BlockWidth.action,
                 blankLinesAfter: 0, state: &state)

        case .character:
            // Character cue is preceded by a blank line.
            if previousKind != nil { state.y += blank }
            draw(text: element.text.uppercased(),
                 x: Indent.character, width: BlockWidth.action - (Indent.character - Indent.action),
                 blankLinesAfter: 0, state: &state)

        case .parenthetical:
            // Sits directly under character / between dialogue — no blank.
            draw(text: formatParenthetical(element.text),
                 x: Indent.parens, width: BlockWidth.parens,
                 blankLinesAfter: 0, state: &state)

        case .dialogue:
            // Sits directly under character or parenthetical — no blank.
            drawDialogueWithMoreContd(
                text: element.text,
                characterForContd: nearestCharacter(before: element),
                state: &state
            )

        case .transition:
            if previousKind != nil { state.y += blank }
            let text = formatTransition(element.text)
            drawRightAligned(text: text,
                             width: BlockWidth.transition,
                             state: &state)

        case .heading:
            break  // rendered via drawHeading at scene start only

        case .actBreak:
            // Centered, underlined, ALL CAPS — "END OF ACT ONE" convention.
            // Writers type whatever label they want; we just style it.
            if previousKind != nil { state.y += 2 * blank }
            drawActBreak(text: element.text, state: &state)
            state.y += blank
        }
    }

    private static func drawActBreak(
        text: String,
        state: inout LayoutState
    ) {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attributed = NSAttributedString(string: label, attributes: [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraph
        ])
        let height = measure(attributed, width: BlockWidth.action)
        if state.y + height > state.pageRect.height - Margins.bottom {
            state.nextPage()
        }
        attributed.draw(
            with: CGRect(x: Margins.left, y: state.y, width: BlockWidth.action, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        state.y += height
    }

    /// Look back through the element chain to find the speaking CHARACTER
    /// for dialogue CONT'D. A rough walk — the caller already passed us the
    /// dialogue element so we climb the scene elements list.
    private static func nearestCharacter(before element: SceneElement) -> String? {
        guard let scene = element.scene else { return nil }
        let ordered = scene.elementsOrdered
        guard let idx = ordered.firstIndex(where: { $0.id == element.id }) else { return nil }
        for back in stride(from: idx - 1, through: 0, by: -1) {
            if ordered[back].kind == .character {
                return ordered[back].text.uppercased()
            }
        }
        return nil
    }

    private static func formatParenthetical(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return trimmed }
        return "(\(trimmed))"
    }

    private static func formatTransition(_ raw: String) -> String {
        var t = raw.uppercased().trimmingCharacters(in: .whitespaces)
        if !t.hasSuffix(":") { t += ":" }
        return t
    }

    // MARK: - Dialogue with MORE/CONT'D page-break handling

    private static func drawDialogueWithMoreContd(
        text: String,
        characterForContd: String?,
        state: inout LayoutState
    ) {
        let attributed = attributedString(text, alignment: .left)
        let width = BlockWidth.dialogue
        let linesForThisPage = wrap(attributed: attributed, to: width)

        let available = state.pageRect.height - Margins.bottom - state.y
        let linesFit = max(0, Int(floor(available / lineHeight)))

        if linesFit >= linesForThisPage.count {
            for line in linesForThisPage {
                drawLine(line, x: Indent.dialogue, width: width, state: &state)
            }
            return
        }

        // Split: keep at least 2 lines on this page and move remainder
        // (we need room for "(MORE)").
        let keep = max(0, min(linesForThisPage.count - 1, linesFit - 1))
        if keep > 0 {
            for i in 0..<keep {
                drawLine(linesForThisPage[i], x: Indent.dialogue, width: width, state: &state)
            }
            // (MORE)
            drawLine("(MORE)", x: Indent.parens, width: BlockWidth.parens, state: &state)
        }

        state.nextPage()

        // Character (CONT'D)
        if let name = characterForContd {
            drawLine("\(name) (CONT'D)", x: Indent.character, width: BlockWidth.action, state: &state)
        }

        let remaining = Array(linesForThisPage.dropFirst(keep))
        for line in remaining {
            drawLine(line, x: Indent.dialogue, width: width, state: &state)
        }
    }

    // MARK: - Drawing primitives

    static let bodyFont: UIFont = {
        UIFont(name: "Courier", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    }()

    @discardableResult
    private static func draw(
        text: String,
        x: CGFloat,
        width: CGFloat,
        blankLinesAfter: Int,
        state: inout LayoutState
    ) -> CGFloat {
        let attributed = attributedString(text, alignment: .left)
        let height = measure(attributed, width: width)

        if state.y + height > state.pageRect.height - Margins.bottom {
            state.nextPage()
        }

        if state.isDrawing {
            attributed.draw(
                with: CGRect(x: x, y: state.y, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        state.drewAnyContent = true
        state.y += height + CGFloat(blankLinesAfter) * blank
        return state.y
    }

    private static func drawRightAligned(
        text: String,
        width: CGFloat,
        state: inout LayoutState
    ) {
        let attributed = attributedString(text, alignment: .right)
        let height = measure(attributed, width: width)
        if state.y + height > state.pageRect.height - Margins.bottom {
            state.nextPage()
        }
        if state.isDrawing {
            attributed.draw(
                with: CGRect(x: Margins.left, y: state.y, width: width, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        state.drewAnyContent = true
        state.y += height
    }

    private static func drawLine(_ text: String, x: CGFloat, width: CGFloat, state: inout LayoutState) {
        if state.isDrawing {
            let attributed = attributedString(text, alignment: .left)
            attributed.draw(
                with: CGRect(x: x, y: state.y, width: width, height: lineHeight + 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        state.drewAnyContent = true
        state.y += lineHeight
    }

    private static func attributedString(_ text: String, alignment: NSTextAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 0
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return NSAttributedString(string: text, attributes: [
            .font: bodyFont,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ])
    }

    private static func measure(_ attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        let bounding = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounding.height)
    }

    /// Hard-wrap a Courier attributed string to the column width. We rely on
    /// CTFramesetter so we get the exact break positions UIKit would use.
    private static func wrap(attributed: NSAttributedString, to width: CGFloat) -> [String] {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        let full = attributed.string as NSString
        var out: [String] = []
        for line in lines {
            let range = CTLineGetStringRange(line)
            let substr = full.substring(with: NSRange(location: range.location, length: range.length))
            out.append(substr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    private static func centered() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        return p
    }

    private static func rightAligned() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .right
        return p
    }

    // MARK: - Files

    private static func temporaryURL(for project: Project) -> URL {
        let safe = project.title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        let trimmed = safe.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "Penova-Script" : trimmed
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(base).pdf")
    }
}
