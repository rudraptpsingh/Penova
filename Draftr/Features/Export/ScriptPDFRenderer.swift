//
//  ScriptPDFRenderer.swift
//  Draftr
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
            kCGPDFContextCreator as String: "Draftr"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let url = temporaryURL(for: project)
        try? FileManager.default.removeItem(at: url)

        try renderer.writePDF(to: url) { ctx in
            var state = LayoutState(pageRect: pageRect)
            drawTitlePage(project: project, ctx: ctx, state: &state)
            for (epIndex, episode) in project.activeEpisodesOrdered.enumerated() {
                state.startScriptPage(ctx: ctx)
                if project.activeEpisodesOrdered.count > 1 {
                    drawEpisodeHeader(episode, index: epIndex, ctx: ctx, state: &state)
                }
                for scene in episode.scenesOrdered {
                    drawScene(scene, ctx: ctx, state: &state)
                }
            }
        }

        return url
    }

    // MARK: - Layout state

    private struct LayoutState {
        let pageRect: CGRect
        var y: CGFloat
        var scriptPageNumber: Int      // 1-based, excludes title page
        var onTitlePage: Bool

        init(pageRect: CGRect) {
            self.pageRect = pageRect
            self.y = Margins.top
            self.scriptPageNumber = 0
            self.onTitlePage = true
        }

        /// Begin the first (or next) numbered script page.
        mutating func startScriptPage(ctx: UIGraphicsPDFRendererContext) {
            ctx.beginPage()
            onTitlePage = false
            scriptPageNumber += 1
            y = Margins.top
            Self.drawPageNumber(page: scriptPageNumber, in: pageRect)
        }

        /// Continue to the next page mid-script (same numbering scheme).
        mutating func nextPage(ctx: UIGraphicsPDFRendererContext) {
            startScriptPage(ctx: ctx)
        }

        private static func drawPageNumber(page: Int, in pageRect: CGRect) {
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

    private static func drawTitlePage(project: Project, ctx: UIGraphicsPDFRendererContext, state: inout LayoutState) {
        ctx.beginPage()
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

        // Contact block, bottom-left, 1.5" from left & bottom.
        let contactY = state.pageRect.height - Margins.bottom - 3 * lineHeight
        let contactAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        let contact = NSAttributedString(
            string: "Drafted in Draftr\n\(dateString())",
            attributes: contactAttrs
        )
        contact.draw(with: CGRect(x: Margins.left, y: contactY,
                                  width: 200, height: 3 * lineHeight),
                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private static func authorName() -> String {
        let stored = UserDefaults.standard.string(forKey: "draftr.auth.fullName") ?? ""
        if !stored.trimmingCharacters(in: .whitespaces).isEmpty { return stored }
        return "The Writer"
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: Date())
    }

    // MARK: - Episode header (only when a project has >1 episode)

    private static func drawEpisodeHeader(_ episode: Episode, index: Int, ctx: UIGraphicsPDFRendererContext, state: inout LayoutState) {
        let title = "EPISODE \(episode.order + 1): \(episode.title.uppercased())"
        draw(
            text: title,
            x: Margins.left,
            width: BlockWidth.action,
            blankLinesAfter: 2,
            state: &state,
            ctx: ctx
        )
    }

    // MARK: - Scene

    private static func drawScene(_ scene: ScriptScene, ctx: UIGraphicsPDFRendererContext, state: inout LayoutState) {
        // 2 blank lines before a scene heading (but not if we just started a page).
        if state.y > Margins.top {
            state.y += 2 * blank
        }

        drawHeading(scene.heading.uppercased(), ctx: ctx, state: &state)

        let elements = scene.elementsOrdered.filter { $0.kind != .heading }
        if elements.isEmpty, let desc = scene.sceneDescription, !desc.isEmpty {
            state.y += blank
            draw(
                text: desc,
                x: Indent.action,
                width: BlockWidth.action,
                blankLinesAfter: 1,
                state: &state,
                ctx: ctx
            )
            return
        }

        var previousKind: SceneElementKind?
        for el in elements {
            drawElement(el, previousKind: previousKind, ctx: ctx, state: &state)
            previousKind = el.kind
        }
    }

    private static func drawHeading(_ text: String, ctx: UIGraphicsPDFRendererContext, state: inout LayoutState) {
        draw(
            text: text,
            x: Indent.action,
            width: BlockWidth.action,
            blankLinesAfter: 1,
            state: &state,
            ctx: ctx
        )
    }

    private static func drawElement(_ element: SceneElement,
                                    previousKind: SceneElementKind?,
                                    ctx: UIGraphicsPDFRendererContext,
                                    state: inout LayoutState) {
        switch element.kind {
        case .action:
            if previousKind != nil { state.y += blank }
            draw(text: element.text,
                 x: Indent.action, width: BlockWidth.action,
                 blankLinesAfter: 0, state: &state, ctx: ctx)

        case .character:
            // Character cue is preceded by a blank line.
            if previousKind != nil { state.y += blank }
            draw(text: element.text.uppercased(),
                 x: Indent.character, width: BlockWidth.action - (Indent.character - Indent.action),
                 blankLinesAfter: 0, state: &state, ctx: ctx)

        case .parenthetical:
            // Sits directly under character / between dialogue — no blank.
            draw(text: formatParenthetical(element.text),
                 x: Indent.parens, width: BlockWidth.parens,
                 blankLinesAfter: 0, state: &state, ctx: ctx)

        case .dialogue:
            // Sits directly under character or parenthetical — no blank.
            drawDialogueWithMoreContd(
                text: element.text,
                characterForContd: nearestCharacter(before: element),
                ctx: ctx,
                state: &state
            )

        case .transition:
            if previousKind != nil { state.y += blank }
            let text = formatTransition(element.text)
            drawRightAligned(text: text,
                             width: BlockWidth.transition,
                             state: &state, ctx: ctx)

        case .heading:
            break  // rendered via drawHeading at scene start only
        }
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
        ctx: UIGraphicsPDFRendererContext,
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

        state.nextPage(ctx: ctx)

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
        state: inout LayoutState,
        ctx: UIGraphicsPDFRendererContext
    ) -> CGFloat {
        let attributed = attributedString(text, alignment: .left)
        let height = measure(attributed, width: width)

        if state.y + height > state.pageRect.height - Margins.bottom {
            state.nextPage(ctx: ctx)
        }

        attributed.draw(
            with: CGRect(x: x, y: state.y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        state.y += height + CGFloat(blankLinesAfter) * blank
        return state.y
    }

    private static func drawRightAligned(
        text: String,
        width: CGFloat,
        state: inout LayoutState,
        ctx: UIGraphicsPDFRendererContext
    ) {
        let attributed = attributedString(text, alignment: .right)
        let height = measure(attributed, width: width)
        if state.y + height > state.pageRect.height - Margins.bottom {
            state.nextPage(ctx: ctx)
        }
        attributed.draw(
            with: CGRect(x: Margins.left, y: state.y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        state.y += height
    }

    private static func drawLine(_ text: String, x: CGFloat, width: CGFloat, state: inout LayoutState) {
        let attributed = attributedString(text, alignment: .left)
        attributed.draw(
            with: CGRect(x: x, y: state.y, width: width, height: lineHeight + 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
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
        let base = trimmed.isEmpty ? "Draftr-Script" : trimmed
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(base).pdf")
    }
}
