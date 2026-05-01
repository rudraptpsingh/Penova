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

        var state = LayoutState(mode: .draw(ctx))
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

    // MARK: - Layout walker

    enum RenderMode {
        case draw(CGContext)
        case measure
    }

    struct LayoutState {
        let mode: RenderMode
        var y: CGFloat
        var scriptPageNumber: Int
        var onTitlePage: Bool
        var drewAnyContent: Bool
        var hasOpenPage: Bool

        init(mode: RenderMode) {
            self.mode = mode
            self.y = ScreenplayLayoutSpec.Margins.top
            self.scriptPageNumber = 0
            self.onTitlePage = true
            self.drewAnyContent = false
            self.hasOpenPage = false
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
            if scriptPageNumber >= 2, case .draw(let ctx) = mode {
                ScreenplayPDFRenderer.drawPageNumber(scriptPageNumber, in: ctx)
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

        for el in scene.elementsOrdered {
            drawElement(el, state: &state)
        }
    }

    private static func drawElement(_ el: SceneElement, state: inout LayoutState) {
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

        if case .draw(let ctx) = state.mode {
            let height = drawWrapped(
                ctx: ctx,
                text: el.text,
                topLeftX: indent,
                topLeftY: state.y,
                width: width,
                alignment: el.kind == .transition ? .right : .left
            )
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
