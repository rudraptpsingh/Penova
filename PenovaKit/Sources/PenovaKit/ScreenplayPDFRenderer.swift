//
//  ScreenplayPDFRenderer.swift
//  PenovaKit
//
//  Cross-platform WGA-format screenplay PDF renderer. Pure CGContext
//  + Core Text — no UIKit, no AppKit text APIs — so the same source
//  compiles on iOS and macOS. Layout constants come from
//  ScreenplayLayoutSpec.
//
//  Coordinate convention: the layout walker tracks `y` as a distance
//  from the TOP of the page (1.0" margin = y 72). When we hand text
//  to Core Text we convert to CG's native bottom-up system at the
//  draw site — no global CTM flip — so text renders with its natural
//  baseline orientation and PDFKit's text extraction works.
//

import Foundation
import CoreGraphics
import CoreText

public enum ScreenplayPDFRenderer {

    /// Render `project` to `url` and return the URL on success.
    @discardableResult
    public static func render(project: Project, to url: URL) throws -> URL {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw NSError(domain: "ScreenplayPDFRenderer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF data consumer"])
        }
        var mediaBox = ScreenplayLayoutSpec.pageRect
        let info: [CFString: Any] = [
            kCGPDFContextTitle: project.title,
            kCGPDFContextCreator: "Penova",
        ]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            throw NSError(domain: "ScreenplayPDFRenderer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
        }

        // First pass: plan element-to-page assignment so the draw
        // pass can decorate revision pages (stripe + slug + asterisks)
        // up-front, before the page's text is laid down.
        let plan = makeRevisionPlan(project: project)
        var state = LayoutState(mode: .draw(ctx), plan: plan, project: project)
        layout(project: project, state: &state)
        ctx.closePDF()
        return url
    }

    /// Page count (excluding the unnumbered title page) the project
    /// would produce. Matches `render` byte-for-byte on layout decisions.
    public static func measurePageCount(project: Project) -> Int {
        var state = LayoutState(mode: .measure)
        layout(project: project, state: &state)
        if state.onTitlePage { return 0 }
        if !state.drewAnyContent { return 0 }
        return state.scriptPageNumber
    }

    // MARK: - Revision plan (test seam)

    /// Mapping each `SceneElement.id` to the 1-based script-page index
    /// it lands on, plus the set of pages flagged as revision pages
    /// (i.e. containing at least one element stamped with the project's
    /// active revision id). Computed by replaying layout in a planning
    /// mode that records placements without touching a CG context.
    public struct RevisionPlan: Equatable {
        public var pageByElement: [String: Int]
        public var revisionPages: Set<Int>
        public var activeRevisionID: String?

        public init(
            pageByElement: [String: Int] = [:],
            revisionPages: Set<Int> = [],
            activeRevisionID: String? = nil
        ) {
            self.pageByElement = pageByElement
            self.revisionPages = revisionPages
            self.activeRevisionID = activeRevisionID
        }
    }

    /// Walk layout in plan mode and return per-element page mappings
    /// + the set of pages that should render revision indicators
    /// (stripe + slug + asterisks). Indicators are suppressed when the
    /// project has no active revision or isn't `locked` — those are
    /// production conventions, not draft conventions.
    public static func makeRevisionPlan(project: Project) -> RevisionPlan {
        let activeID = project.activeRevision?.id
        var planMap: [String: Int] = [:]
        var state = LayoutState(mode: .plan(captureID: { id, page in
            planMap[id] = page
        }))
        layout(project: project, state: &state)
        var revisionPages: Set<Int> = []
        if project.locked, let activeID {
            for episode in project.activeEpisodesOrdered {
                for scene in episode.scenesOrdered {
                    for el in scene.elementsOrdered {
                        if el.lastRevisedRevisionID == activeID,
                           let page = planMap[el.id] {
                            revisionPages.insert(page)
                        }
                    }
                }
            }
        }
        return RevisionPlan(
            pageByElement: planMap,
            revisionPages: revisionPages,
            activeRevisionID: activeID
        )
    }

    // MARK: - Layout walker

    enum RenderMode {
        case draw(CGContext)
        case measure
        /// Plan pass: walk layout without touching a CG context, calling
        /// `captureID` each time an element is placed so the caller can
        /// build a per-element page map.
        case plan(captureID: (String, Int) -> Void)
    }

    struct LayoutState {
        let mode: RenderMode
        var y: CGFloat
        var scriptPageNumber: Int
        var onTitlePage: Bool
        var drewAnyContent: Bool
        var hasOpenPage: Bool
        /// Pre-computed page-to-revision mapping. Only populated in
        /// `.draw` mode — the plan/measure passes don't need it.
        let plan: RevisionPlan?
        /// Project reference so page-start hooks can pull title /
        /// active revision metadata for the slug + stripe.
        let project: Project?

        init(mode: RenderMode, plan: RevisionPlan? = nil, project: Project? = nil) {
            self.mode = mode
            self.y = ScreenplayLayoutSpec.Margins.top
            self.scriptPageNumber = 0
            self.onTitlePage = true
            self.drewAnyContent = false
            self.hasOpenPage = false
            self.plan = plan
            self.project = project
        }

        var isDrawing: Bool {
            if case .draw = mode { return true }
            return false
        }

        mutating func startScriptPage() {
            // Close the previous page first if one's open
            if hasOpenPage, case .draw(let ctx) = mode {
                ctx.endPDFPage()
                hasOpenPage = false
            }
            if case .draw(let ctx) = mode {
                ctx.beginPDFPage(nil)
                hasOpenPage = true
            }
            onTitlePage = false
            scriptPageNumber += 1
            y = ScreenplayLayoutSpec.Margins.top
            if case .draw(let ctx) = mode {
                if scriptPageNumber >= 2 {
                    ScreenplayPDFRenderer.drawPageNumber(scriptPageNumber, in: ctx)
                }
                // Revision indicators (stripe + header slug) — drawn at
                // page start so subsequent text overlays them. Asterisks
                // are stamped per-element inside drawElement / drawScene.
                if let plan, plan.revisionPages.contains(scriptPageNumber),
                   let project, let rev = project.activeRevision {
                    ScreenplayPDFRenderer.drawRevisionStripe(rev: rev, in: ctx)
                    ScreenplayPDFRenderer.drawRevisionSlug(project: project, rev: rev, in: ctx)
                }
            }
        }

        mutating func nextPage() {
            startScriptPage()
        }

        mutating func endPageIfOpen() {
            if hasOpenPage, case .draw(let ctx) = mode {
                ctx.endPDFPage()
                hasOpenPage = false
            }
        }
    }

    private static func drawPageNumber(_ page: Int, in ctx: CGContext) {
        let str = "\(page)."
        drawSingleLine(
            ctx: ctx,
            text: str,
            topLeftX: ScreenplayLayoutSpec.pageWidth - ScreenplayLayoutSpec.Margins.right - 36,
            topLeftY: 36,
            width: 30,
            alignment: .right
        )
    }

    // MARK: - Revision indicators

    /// Width of the right-margin colored stripe drawn on revision
    /// pages. ~6pt — enough to be unmissable when the page is held
    /// next to a clean one, narrow enough not to crowd the page-number
    /// column.
    private static let revisionStripeWidth: CGFloat = 6
    /// X origin of the right-margin asterisk gutter — sits between
    /// the script's text column and the colored stripe on its right.
    private static let revisionAsteriskX: CGFloat =
        ScreenplayLayoutSpec.pageWidth - ScreenplayLayoutSpec.Margins.right + 12

    /// Right-margin color stripe — full page height, ~6pt wide,
    /// painted in the active revision's `marginRGB`. Drawn at page
    /// start so subsequent text overlays cleanly on top.
    fileprivate static func drawRevisionStripe(rev: Revision, in ctx: CGContext) {
        let rgb = rev.color.marginRGB
        ctx.saveGState()
        ctx.setFillColor(red: CGFloat(rgb.r), green: CGFloat(rgb.g),
                         blue: CGFloat(rgb.b), alpha: 1.0)
        let stripeX = ScreenplayLayoutSpec.pageWidth - revisionStripeWidth
        ctx.fill(CGRect(x: stripeX, y: 0,
                        width: revisionStripeWidth,
                        height: ScreenplayLayoutSpec.pageHeight))
        ctx.restoreGState()
    }

    /// Header slug rendered at the top of every revision page,
    /// vertically aligned with the page number, right-aligned, italic
    /// 8pt. Format: "Blue Revision — 12 Mar 2026 — PROJECT TITLE".
    fileprivate static func drawRevisionSlug(project: Project, rev: Revision, in ctx: CGContext) {
        let df = DateFormatter()
        df.dateFormat = "dd MMM yyyy"
        let slug = "\(rev.color.display) Revision \u{2014} \(df.string(from: rev.createdAt)) \u{2014} \(project.title.uppercased())"
        // Box stretches across most of the page width but right-aligns,
        // sitting at y=36 (same row as the page number) but to the
        // LEFT of it so they don't collide.
        let boxWidth: CGFloat = 360
        let boxX = ScreenplayLayoutSpec.pageWidth - ScreenplayLayoutSpec.Margins.right - 40 - boxWidth
        drawItalicLine(
            ctx: ctx,
            text: slug,
            topLeftX: boxX,
            topLeftY: 36,
            width: boxWidth,
            alignment: .right,
            fontSize: 8
        )
    }

    /// Stamp a single `*` in the right margin at the given Y. Sits in
    /// the gutter between the text column's right edge and the colored
    /// stripe so it's visually obvious without overlapping either.
    fileprivate static func drawAsterisk(in ctx: CGContext, topLeftY: CGFloat) {
        drawSingleLine(
            ctx: ctx,
            text: "*",
            topLeftX: revisionAsteriskX,
            topLeftY: topLeftY,
            width: 12,
            alignment: .left,
            fontSize: ScreenplayLayoutSpec.bodyFontSize,
            bold: true
        )
    }

    /// Italic single-line draw — used for the header slug. Mirrors
    /// `drawSingleLine` but resolves a Courier-Oblique font.
    private static func drawItalicLine(
        ctx: CGContext,
        text: String,
        topLeftX: CGFloat,
        topLeftY: CGFloat,
        width: CGFloat,
        alignment: HAlign,
        fontSize: CGFloat
    ) {
        let font = CTFontCreateWithName("Courier-Oblique" as CFString, fontSize, nil)
        var alignVal: CTTextAlignment = {
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            }
        }()
        var settings = [CTParagraphStyleSetting]()
        withUnsafeMutablePointer(to: &alignVal) { alignPtr in
            settings.append(CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: alignPtr
            ))
        }
        let style = settings.withUnsafeBufferPointer { buffer in
            CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            .paragraphStyle: style,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs) as CFAttributedString
        let height = ceil(fontSize * 1.4) + 2
        let cgY = ScreenplayLayoutSpec.pageHeight - topLeftY - height
        let path = CGPath(rect: CGRect(x: topLeftX, y: cgY, width: width, height: height), transform: nil)
        let attrLen = CFAttributedStringGetLength(attr)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrLen), path, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    private static func layout(project: Project, state: inout LayoutState) {
        drawTitlePage(project: project, state: &state)
        let resetPerEpisode = project.activeEpisodesOrdered.count > 1
        var liveNumber = 1
        for (epIndex, episode) in project.activeEpisodesOrdered.enumerated() {
            state.startScriptPage()
            if project.activeEpisodesOrdered.count > 1 {
                drawEpisodeHeader(episode: episode, index: epIndex, state: &state)
            }
            if resetPerEpisode { liveNumber = 1 }
            for scene in episode.scenesOrdered {
                // Honour `Project.locked` — frozen scene numbers come
                // from `lockedSceneNumbers`, live counter otherwise.
                let renderNumber = project.renderSceneNumber(for: scene, live: liveNumber)
                drawScene(scene, number: renderNumber, state: &state)
                liveNumber += 1
            }
        }
        state.endPageIfOpen()
    }

    // MARK: - Title page

    private static func drawTitlePage(project: Project, state: inout LayoutState) {
        guard case .draw(let ctx) = state.mode else { return }
        ctx.beginPDFPage(nil)
        state.hasOpenPage = true

        let tp = project.titlePage
        let pageW = ScreenplayLayoutSpec.pageWidth
        let pageH = ScreenplayLayoutSpec.pageHeight

        // Title block — centered horizontally at ~1/3 down the page.
        let centerY = pageH / 3
        drawSingleLine(
            ctx: ctx,
            text: tp.title.uppercased(),
            topLeftX: 0,
            topLeftY: centerY,
            width: pageW,
            alignment: .center,
            fontSize: 14,
            bold: true
        )
        let credit = tp.credit.isEmpty ? "Written by" : tp.credit
        drawSingleLine(
            ctx: ctx,
            text: credit,
            topLeftX: 0,
            topLeftY: centerY + 48,
            width: pageW,
            alignment: .center,
            fontSize: 11
        )
        if !tp.author.isEmpty {
            drawSingleLine(
                ctx: ctx,
                text: tp.author,
                topLeftX: 0,
                topLeftY: centerY + 64,
                width: pageW,
                alignment: .center,
                fontSize: 11,
                bold: true
            )
        }
        if !tp.source.isEmpty {
            drawWrapped(
                ctx: ctx,
                text: tp.source,
                topLeftX: 72,
                topLeftY: centerY + 100,
                width: pageW - 144,
                alignment: .center
            )
        }

        // Bottom-left contact block.
        let contact = tp.contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if !contact.isEmpty {
            drawWrapped(
                ctx: ctx,
                text: contact,
                topLeftX: ScreenplayLayoutSpec.Margins.left,
                topLeftY: pageH - 180,
                width: 240
            )
        }

        // Bottom-right draft stage / date — production drafts only,
        // i.e. when the project is locked. Spec scripts get a clean
        // footer.
        if project.locked {
            var footerY: CGFloat = pageH - 180
            if !tp.draftStage.isEmpty {
                drawSingleLine(
                    ctx: ctx,
                    text: tp.draftStage,
                    topLeftX: pageW - ScreenplayLayoutSpec.Margins.right - 240,
                    topLeftY: footerY,
                    width: 240,
                    alignment: .right,
                    fontSize: 9
                )
                footerY += 14
            }
            if !tp.draftDate.isEmpty {
                drawSingleLine(
                    ctx: ctx,
                    text: tp.draftDate,
                    topLeftX: pageW - ScreenplayLayoutSpec.Margins.right - 240,
                    topLeftY: footerY,
                    width: 240,
                    alignment: .right,
                    fontSize: 9
                )
            }

            // Revision history stack (above the contact block) — only
            // emitted on locked production drafts. Each row is
            // "<LABEL>          <date>" right-padded so the dates form
            // a flush right column.
            let entries = project.revisionHistoryEntries
            if !entries.isEmpty {
                let df = DateFormatter()
                df.dateFormat = "d MMM yyyy"
                let labelWidth: CGFloat = 200
                let dateWidth: CGFloat = 96
                var rowY = pageH - 180 - CGFloat(entries.count) * 14 - 20
                for entry in entries {
                    drawSingleLine(
                        ctx: ctx,
                        text: entry.label,
                        topLeftX: ScreenplayLayoutSpec.Margins.left,
                        topLeftY: rowY,
                        width: labelWidth,
                        alignment: .left,
                        fontSize: 9
                    )
                    drawSingleLine(
                        ctx: ctx,
                        text: df.string(from: entry.date),
                        topLeftX: ScreenplayLayoutSpec.Margins.left + labelWidth,
                        topLeftY: rowY,
                        width: dateWidth,
                        alignment: .right,
                        fontSize: 9
                    )
                    rowY += 14
                }
            }
        }

        // Copyright bottom-center, dim small type.
        if !tp.copyright.isEmpty {
            drawSingleLine(
                ctx: ctx,
                text: tp.copyright,
                topLeftX: 0,
                topLeftY: pageH - 48,
                width: pageW,
                alignment: .center,
                fontSize: 8
            )
        }

        ctx.endPDFPage()
        state.hasOpenPage = false
    }

    // MARK: - Episode header

    private static func drawEpisodeHeader(episode: Episode, index: Int, state: inout LayoutState) {
        guard case .draw(let ctx) = state.mode else { return }
        let title = "EPISODE \(index + 1) — \(episode.title.uppercased())"
        drawSingleLine(
            ctx: ctx,
            text: title,
            topLeftX: 0,
            topLeftY: state.y,
            width: ScreenplayLayoutSpec.pageWidth,
            alignment: .center,
            fontSize: 14,
            bold: true
        )
        state.y += 36
        state.drewAnyContent = true
    }

    // MARK: - Scene

    private static func drawScene(_ scene: ScriptScene, number: Int, state: inout LayoutState) {
        if state.scriptPageNumber > 0 && state.y > ScreenplayLayoutSpec.Margins.top {
            state.y += ScreenplayLayoutSpec.line * 2
        }
        if state.y + ScreenplayLayoutSpec.line * 3 >
           ScreenplayLayoutSpec.pageHeight - ScreenplayLayoutSpec.Margins.bottom {
            state.nextPage()
        }

        if case .draw(let ctx) = state.mode {
            drawSingleLine(
                ctx: ctx,
                text: "\(number)",
                topLeftX: ScreenplayLayoutSpec.Margins.left - 36,
                topLeftY: state.y,
                width: 24,
                alignment: .right
            )
            drawSingleLine(
                ctx: ctx,
                text: "\(number)",
                topLeftX: ScreenplayLayoutSpec.transitionRight,
                topLeftY: state.y,
                width: 24,
                alignment: .left
            )
            let height = drawWrapped(
                ctx: ctx,
                text: scene.heading,
                topLeftX: ScreenplayLayoutSpec.Indent.action,
                topLeftY: state.y,
                width: ScreenplayLayoutSpec.BlockWidth.action
            )
            state.y += height
        } else {
            state.y += measureHeight(text: scene.heading,
                                     width: ScreenplayLayoutSpec.BlockWidth.action)
        }
        state.y += ScreenplayLayoutSpec.line
        state.drewAnyContent = true

        // Build a consolidation map: per-element flag for whether to
        // SUPPRESS its own asterisk because it's covered by a single
        // mark above the speaker cue.  WGA convention: when a single
        // dialogue block (CHARACTER + PARENTHETICAL/DIALOGUE rows) has
        // 3+ consecutive starred rows, draw one asterisk by the cue
        // and skip per-row marks for the rest of the block.
        let suppressed = consolidationSuppressionMap(
            scene: scene,
            activeRevisionID: state.plan?.activeRevisionID
        )

        for el in scene.elementsOrdered {
            drawElement(el, state: &state, suppressOwnAsterisk: suppressed.contains(el.id))
        }
    }

    /// Test-only seam onto `consolidationSuppressionMap`. Lets unit
    /// tests assert the WGA "3+ starred lines collapse to a single
    /// cue-level mark" rule without standing up a full PDF render.
    public static func testSuppressionMap(
        scene: ScriptScene,
        activeRevisionID: String?
    ) -> Set<String> {
        consolidationSuppressionMap(scene: scene, activeRevisionID: activeRevisionID)
    }

    /// Walk a scene's element list and find any character-led dialogue
    /// blocks where 3+ consecutive elements are starred against the
    /// active revision. Returns the set of element IDs whose own
    /// asterisks should be suppressed because the leading CHARACTER
    /// cue carries one for the whole block. Empty set when there's no
    /// active revision or no qualifying block.
    private static func consolidationSuppressionMap(
        scene: ScriptScene,
        activeRevisionID: String?
    ) -> Set<String> {
        guard let activeRevisionID else { return [] }
        var suppress: Set<String> = []
        let elements = scene.elementsOrdered
        var i = 0
        while i < elements.count {
            let el = elements[i]
            if el.kind == .character {
                // Walk forward over the contiguous dialogue block.
                var j = i
                var blockEnd = i
                while j < elements.count {
                    let k = elements[j].kind
                    if j == i, k == .character {
                        blockEnd = j
                        j += 1; continue
                    }
                    if k == .parenthetical || k == .dialogue {
                        blockEnd = j
                        j += 1
                    } else {
                        break
                    }
                }
                let block = Array(elements[i...blockEnd])
                let starred = block.filter { $0.lastRevisedRevisionID == activeRevisionID }
                if starred.count >= 3 {
                    // Suppress the per-row asterisks for every element
                    // EXCEPT the leading character cue (which keeps its
                    // single mark to flag the whole block).
                    for el in block where el.kind != .character {
                        suppress.insert(el.id)
                    }
                }
                i = blockEnd + 1
            } else {
                i += 1
            }
        }
        return suppress
    }

    private static func drawElement(_ el: SceneElement,
                                    state: inout LayoutState,
                                    suppressOwnAsterisk: Bool = false) {
        let indent: CGFloat
        let width: CGFloat
        switch el.kind {
        case .heading, .action, .actBreak:
            indent = ScreenplayLayoutSpec.Indent.action
            width  = ScreenplayLayoutSpec.BlockWidth.action
        case .character:
            indent = ScreenplayLayoutSpec.Indent.character
            width  = ScreenplayLayoutSpec.BlockWidth.character
        case .dialogue:
            indent = ScreenplayLayoutSpec.Indent.dialogue
            width  = ScreenplayLayoutSpec.BlockWidth.dialogue
        case .parenthetical:
            indent = ScreenplayLayoutSpec.Indent.parenthetical
            width  = ScreenplayLayoutSpec.BlockWidth.parenthetical
        case .transition:
            indent = ScreenplayLayoutSpec.transitionRight - 144
            width  = 144
        }

        let needed = measureHeight(text: el.text, width: width)
        if state.y + needed >
           ScreenplayLayoutSpec.pageHeight - ScreenplayLayoutSpec.Margins.bottom {
            state.nextPage()
        }

        // Plan mode: capture which page this element ended up on.
        if case .plan(let capture) = state.mode {
            capture(el.id, state.scriptPageNumber)
        }

        let elementTopY = state.y
        if case .draw(let ctx) = state.mode {
            let height = drawWrapped(
                ctx: ctx,
                text: el.text,
                topLeftX: indent,
                topLeftY: state.y,
                width: width,
                alignment: el.kind == .transition ? .right : .left
            )
            // Per-element asterisk: stamp ONE `*` next to the first
            // visual line if this element was edited during the active
            // revision, the page is a revision page, and the
            // consolidation rule isn't suppressing this row's mark.
            if !suppressOwnAsterisk,
               let plan = state.plan,
               let activeID = plan.activeRevisionID,
               el.lastRevisedRevisionID == activeID,
               plan.revisionPages.contains(state.scriptPageNumber) {
                drawAsterisk(in: ctx, topLeftY: elementTopY)
            }
            state.y += height
        } else {
            state.y += needed
        }

        let isContinuingDialogue: Bool = {
            switch el.kind {
            case .character, .parenthetical: return true
            default: return false
            }
        }()
        if !isContinuingDialogue {
            state.y += ScreenplayLayoutSpec.line
        }
        state.drewAnyContent = true
    }

    // MARK: - Text drawing primitives (CG bottom-up; we receive top-down y)

    enum HAlign { case left, center, right }

    /// Draw a single non-wrapping line. `topLeftY` is distance from the
    /// TOP of the page (matches the layout walker's `y`).
    private static func drawSingleLine(
        ctx: CGContext,
        text: String,
        topLeftX: CGFloat,
        topLeftY: CGFloat,
        width: CGFloat,
        alignment: HAlign = .left,
        fontSize: CGFloat = ScreenplayLayoutSpec.bodyFontSize,
        bold: Bool = false
    ) {
        let attr = attributedString(text, fontSize: fontSize, alignment: alignment, bold: bold)
        let height = ceil(fontSize * 1.4) + 2
        // Convert to CG bottom-up: visual top = pageHeight - topLeftY,
        // and the rect's y origin is its lower edge in CG terms.
        let cgY = ScreenplayLayoutSpec.pageHeight - topLeftY - height
        let path = CGPath(rect: CGRect(x: topLeftX, y: cgY, width: width, height: height), transform: nil)
        let attrLen = CFAttributedStringGetLength(attr)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrLen), path, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    /// Draw a wrapped text block. Returns height consumed (top-down).
    @discardableResult
    private static func drawWrapped(
        ctx: CGContext,
        text: String,
        topLeftX: CGFloat,
        topLeftY: CGFloat,
        width: CGFloat,
        alignment: HAlign = .left
    ) -> CGFloat {
        let attr = attributedString(text, alignment: alignment)
        let height = measureHeight(text: text, width: width)
        let cgY = ScreenplayLayoutSpec.pageHeight - topLeftY - height
        let path = CGPath(rect: CGRect(x: topLeftX, y: cgY, width: width, height: height), transform: nil)
        let attrLen = CFAttributedStringGetLength(attr)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrLen), path, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
        return height
    }

    private static func measureHeight(text: String, width: CGFloat) -> CGFloat {
        let attr = attributedString(text)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        var fitRange = CFRange(location: 0, length: 0)
        let attrLen = CFAttributedStringGetLength(attr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attrLen),
            nil,
            constraint,
            &fitRange
        )
        return ceil(size.height) + 4
    }

    private static func attributedString(
        _ text: String,
        fontSize: CGFloat = ScreenplayLayoutSpec.bodyFontSize,
        alignment: HAlign = .left,
        bold: Bool = false
    ) -> CFAttributedString {
        let baseFontName = bold ? "Courier-Bold" : ScreenplayLayoutSpec.bodyFontName
        let font = CTFontCreateWithName(baseFontName as CFString, fontSize, nil)
        var alignVal: CTTextAlignment = {
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            }
        }()
        var settings = [CTParagraphStyleSetting]()
        withUnsafeMutablePointer(to: &alignVal) { alignPtr in
            settings.append(CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: alignPtr
            ))
        }
        let style = settings.withUnsafeBufferPointer { buffer in
            CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            .paragraphStyle: style,
        ]
        return NSAttributedString(string: text, attributes: attrs) as CFAttributedString
    }
}
