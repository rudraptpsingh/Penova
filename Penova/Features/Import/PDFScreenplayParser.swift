//
//  PDFScreenplayParser.swift
//  Penova
//
//  Onboarding for the universal screenplay format: a finished PDF.
//  Most writers share scripts as PDFs (Final Draft → PDF, WriterDuet →
//  PDF, Fountain renderers → PDF) so this is the format that actually
//  unblocks "open my existing screenplay in Penova."
//
//  How it works:
//    1. Per page, collect lines + their left x-edge from a PDFLineSource.
//    2. Drop chrome (page numbers, "MORE", "CONTINUED", scene numbers
//       in the left/right margins, top/bottom of page bands).
//    3. Cluster x-positions across the body to learn the columns this
//       particular template uses (action, character, parenthetical,
//       dialogue, transition). Industry templates are rigid in their
//       *relative* ordering even when the absolute pixel values vary.
//    4. Classify each line by (column bucket × content patterns).
//    5. Group lines into scenes on each `.heading`.
//    6. Stitch dialogue across page breaks where the next page opens
//       with `(CONT'D)` or `CHARACTER (CONT'D)` cues.
//    7. Page 1 is parsed as a title page (Title / Author / Contact)
//       *only* if it contains no scene headings — otherwise we treat
//       it as body content (some scripts skip the title page).
//
//  We do not try to be a full layout engine. We try to be right on the
//  ~90% of scripts that follow the WGA convention, and fail loudly
//  (return an empty doc) when text extraction is impossible (scanned
//  PDFs, image-only pages).
//

import Foundation
import CoreGraphics

public enum PDFScreenplayParser {

    // MARK: - Public

    public struct Result: Equatable {
        public var document: FountainParser.ParsedDocument
        /// Heuristics that fired during the parse. Useful for tests
        /// (so we can prove the x-clustering picked up specific roles)
        /// and a future "import preview" UI.
        public var diagnostics: Diagnostics
    }

    public struct Diagnostics: Equatable {
        public var pageCount: Int = 0
        public var bodyLineCount: Int = 0
        public var droppedChromeCount: Int = 0
        public var sceneCount: Int = 0
        /// Inferred indent (in points) for each role. Nil when the
        /// parser couldn't find enough samples for that role on this
        /// document and fell back to content-only classification.
        public var actionX: CGFloat?
        public var characterX: CGFloat?
        public var parentheticalX: CGFloat?
        public var dialogueX: CGFloat?
        public var transitionX: CGFloat?
        public var hadTitlePage: Bool = false
    }

    public static func parse(_ source: PDFLineSource) -> Result {
        var diag = Diagnostics()
        diag.pageCount = source.pageCount

        // Collect every line on every page, then merge any lines that
        // sit at the same y (within tolerance). Some PDF text-extraction
        // backends split visually-same-line content into separate line
        // records when there's a space + period adjacency
        // ("INT. KITCHEN" → "INT." + "KITCHEN"), which would otherwise
        // break scene-heading detection on real Hollywood scripts.
        var allLines: [PDFLine] = []
        for p in 0..<source.pageCount {
            allLines.append(contentsOf: mergeSameYLines(source.lines(onPage: p)))
        }

        // Drop chrome: page numbers, headers/footers, "(MORE)" markers,
        // top-of-page CONT'D markers we'll re-stitch later.
        var dropped = 0
        var bodyLines: [PDFLine] = []
        bodyLines.reserveCapacity(allLines.count)
        for line in allLines {
            if isChrome(line) {
                dropped += 1
                continue
            }
            bodyLines.append(line)
        }
        diag.droppedChromeCount = dropped

        // First pass: detect whether page 0 looks like a title page.
        // Heuristic: zero scene-heading-shaped lines AND has a Title-like
        // string OR is densely centered. We check the first heuristic
        // (no scene headings on page 0) here; centering is implied by
        // the title-page extractor.
        let page0Lines = bodyLines.filter { $0.pageIndex == 0 }
        let page0HasHeadings = page0Lines.contains(where: isSceneHeadingText)

        var doc = FountainParser.ParsedDocument()
        var scenesStartLine = 0

        if !page0HasHeadings, let titlePage = extractTitlePage(from: page0Lines) {
            doc.titlePage = titlePage
            diag.hadTitlePage = true
            // Skip page 0 lines for body parsing.
            scenesStartLine = bodyLines.firstIndex(where: { $0.pageIndex > 0 }) ?? bodyLines.count
        }

        let body = Array(bodyLines[scenesStartLine...])
        diag.bodyLineCount = body.count

        // X-cluster the body to find role columns, then validate each
        // labelled column against its expected content. Big Fish-style
        // scripts have non-WGA indents (dialogue at ~174 not 180), so
        // the positional inference can mislabel a real-dialogue column
        // as parenthetical. validateColumns demotes any column whose
        // contents don't match its label.
        var columns = inferColumns(body)
        columns = validateColumns(columns, against: body)
        diag.actionX = columns.action
        diag.characterX = columns.character
        diag.parentheticalX = columns.parenthetical
        diag.dialogueX = columns.dialogue
        diag.transitionX = columns.transition

        // Classify and group.
        var currentScene: FountainParser.ParsedScene?
        var pendingAction: [String] = []
        var pendingCharacter: String?

        func flushAction() {
            let joined = pendingAction.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            pendingAction.removeAll()
            guard !joined.isEmpty, currentScene != nil else { return }
            currentScene?.elements.append(.init(kind: .action, text: joined))
        }

        for line in body {
            let kind = classify(line, columns: columns)
            switch kind {
            case .heading:
                flushAction()
                if let scene = currentScene { doc.scenes.append(scene) }
                let cleanHeading = stripSceneNumberPrefix(
                    line.text.trimmingCharacters(in: .whitespaces)
                )
                currentScene = .init(heading: cleanHeading, elements: [])
                pendingCharacter = nil
            case .action:
                pendingAction.append(line.text.trimmingCharacters(in: .whitespaces))
            case .character:
                flushAction()
                let cleaned = stripCueSuffix(line.text.trimmingCharacters(in: .whitespaces))
                pendingCharacter = cleaned
                currentScene?.elements.append(.init(kind: .character, text: cleaned))
            case .parenthetical:
                flushAction()
                currentScene?.elements.append(.init(kind: .parenthetical,
                                                    text: line.text.trimmingCharacters(in: .whitespaces)))
            case .dialogue:
                flushAction()
                // Multi-line dialogue: if the previous emitted element was
                // a dialogue block from the same character, merge with a
                // space; otherwise append a fresh dialogue element.
                if var last = currentScene?.elements.last, last.kind == .dialogue {
                    last.text = (last.text + " " + line.text.trimmingCharacters(in: .whitespaces))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    currentScene?.elements[currentScene!.elements.count - 1] = last
                } else {
                    currentScene?.elements.append(.init(kind: .dialogue,
                                                        text: line.text.trimmingCharacters(in: .whitespaces)))
                }
            case .transition:
                flushAction()
                currentScene?.elements.append(.init(kind: .transition,
                                                    text: line.text.trimmingCharacters(in: .whitespaces)))
            }
        }
        flushAction()
        if let scene = currentScene { doc.scenes.append(scene) }

        diag.sceneCount = doc.scenes.count
        return Result(document: doc, diagnostics: diag)
    }

    // MARK: - Chrome

    /// Lines that carry no screenplay content: page numbers, "(MORE)",
    /// "(CONTINUED)", revision marks, top/bottom margin chrome.
    private static func isChrome(_ line: PDFLine) -> Bool {
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)

        // Standalone page number (e.g. "12.", "12", "iv.").
        let pageNumberRegex = #"^[0-9]{1,4}\.?$"#
        if matches(trimmed, pattern: pageNumberRegex) { return true }
        let romanRegex = #"^[ivxlcdm]{1,5}\.?$"#
        if matches(trimmed.lowercased(), pattern: romanRegex) && trimmed.count <= 5 { return true }

        // Continuation chrome.
        if trimmed.uppercased() == "(MORE)" { return true }
        if trimmed.uppercased() == "(CONTINUED)" { return true }
        if trimmed.uppercased() == "CONTINUED:" { return true }
        if trimmed.uppercased().hasSuffix("(CONT'D)") &&
            trimmed.uppercased().hasPrefix("(") && line.yTop > line.pageHeight - 90 {
            // A bare "(CONT'D)" near the page top is a continuation
            // marker, not a real character cue. Drop it.
            return true
        }

        // Top / bottom margin (within ~36pt = 0.5") with very short
        // numeric or all-caps content is almost always chrome.
        let nearTop = line.yTop > line.pageHeight - 54
        let nearBottom = line.yTop < 54
        if (nearTop || nearBottom) && trimmed.count <= 16 {
            // Page number-shaped or "REVISED 1/2/24"-shaped → chrome.
            if matches(trimmed, pattern: #"^[A-Z0-9 .,/\-:]+$"#) { return true }
        }

        return false
    }

    // MARK: - Title page

    private static func extractTitlePage(from lines: [PDFLine]) -> [String: String]? {
        guard !lines.isEmpty else { return nil }
        // Try Fountain-style "Title: Foo" lines first.
        var fields: [String: String] = [:]
        for line in lines {
            if let (k, v) = parseKeyValueLine(line.text), !k.isEmpty {
                fields[k.lowercased()] = v
            }
        }
        if !fields.isEmpty { return fields }

        // Fallback: first non-empty line = title; "by" / "Written by"
        // markers attribute the next non-empty centered line as the
        // author. Trailing centered lines fall into a free-form contact
        // bucket so contact info round-trips on export.
        let sorted = lines.sorted { $0.yTop > $1.yTop }
        let topish = sorted.prefix(12).map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let title = topish.first else { return nil }
        fields["title"] = title

        var i = 1
        while i < topish.count {
            let line = topish[i]
            if isAuthorLabel(line) {
                // Label-only line ("written by"). The author's actual
                // name is the next non-empty line. If we run off the
                // end, give up rather than capture the label as author.
                if i + 1 < topish.count {
                    fields["author"] = topish[i + 1]
                    i += 2
                    continue
                }
                // No name follows — drop the standalone label.
                i += 1
                continue
            }
            if isAuthorPrefix(line) {
                // "by John August" / "Written by John August" — strip
                // the prefix and capture what's left.
                let cleaned = line
                    .replacingOccurrences(of: "(?i)^written\\s+by\\s+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "(?i)^by\\s+", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { fields["author"] = cleaned }
                i += 1
                continue
            }
            i += 1
        }
        return fields
    }

    private static func isAuthorLabel(_ raw: String) -> Bool {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return lower == "by" || lower == "written by"
    }

    private static func isAuthorPrefix(_ raw: String) -> Bool {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.hasPrefix("by ") || lower.hasPrefix("written by ")
    }

    private static func parseKeyValueLine(_ raw: String) -> (String, String)? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        // A line with a colon is only a title-page field if the key
        // is short and word-like. "INT. ROOM - DAY" has a period not
        // a colon, but "TITLE: My Story" does.
        guard key.count > 0, key.count <= 32 else { return nil }
        let isWordy = key.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || $0 == " " }
        guard isWordy else { return nil }
        return (key, value)
    }

    // MARK: - X-clustering

    struct Columns: Equatable {
        var action: CGFloat?
        var character: CGFloat?
        var parenthetical: CGFloat?
        var dialogue: CGFloat?
        var transition: CGFloat?
    }

    /// Merge runs of lines whose top-y values are within `tolerance` of
    /// each other into a single line. PDF text-extraction can break
    /// visually-same-line text into multiple records (e.g. "INT.
    /// KITCHEN" gets cut at the period); this glues them back so the
    /// scene-heading and column-content checks see whole lines.
    static func mergeSameYLines(_ lines: [PDFLine], tolerance: CGFloat = 3) -> [PDFLine] {
        guard lines.count > 1 else { return lines }
        let sorted = lines.sorted { $0.yTop > $1.yTop }
        var out: [PDFLine] = []
        out.reserveCapacity(sorted.count)
        var current = sorted[0]
        var pieces: [(x: CGFloat, text: String)] = [(current.x, current.text)]
        for line in sorted.dropFirst() {
            if abs(line.yTop - current.yTop) <= tolerance {
                pieces.append((line.x, line.text))
                continue
            }
            out.append(flush(pieces, base: current))
            current = line
            pieces = [(line.x, line.text)]
        }
        out.append(flush(pieces, base: current))
        return out
    }

    private static func flush(_ pieces: [(x: CGFloat, text: String)], base: PDFLine) -> PDFLine {
        if pieces.count == 1 { return base }
        let sorted = pieces.sorted { $0.x < $1.x }
        let merged = sorted.map(\.text).joined(separator: " ")
        let leftmost = sorted.first?.x ?? base.x
        return PDFLine(
            text: merged,
            x: leftmost,
            yTop: base.yTop,
            pageHeight: base.pageHeight,
            pageIndex: base.pageIndex
        )
    }

    /// Sanity-check the inferred columns by sampling content at each
    /// column's x. Bad attributions (a "parenthetical" column whose
    /// lines mostly don't start with `(`, a "character" column whose
    /// lines mostly aren't ALL CAPS short) get demoted so the
    /// classifier can fall back to content-pattern routing.
    static func validateColumns(_ cols: Columns, against lines: [PDFLine]) -> Columns {
        var out = cols
        let tolerance: CGFloat = 6

        if let parenX = cols.parenthetical {
            let sample = lines.filter { abs($0.x - parenX) <= tolerance }
            if !sample.isEmpty {
                let parenStarts = sample.filter {
                    let t = $0.text.trimmingCharacters(in: .whitespaces)
                    return t.hasPrefix("(") && t.hasSuffix(")")
                }.count
                let ratio = Double(parenStarts) / Double(sample.count)
                // Require at least half of the lines in this column to
                // actually be parentheticals. Otherwise this column is
                // really dialogue (or something else); demote it.
                if ratio < 0.5 {
                    // If the demoted parenthetical column had more
                    // lines than whatever we labelled "dialogue", it
                    // WAS the real dialogue (Big Fish-style layout
                    // where dialogue sits at ~174pt instead of 180pt
                    // and the inferrer's positional rank misfired).
                    // Overwrite dialogue with the demoted column.
                    let dialogueCount = out.dialogue.map { dx in
                        lines.filter { abs($0.x - dx) <= tolerance }.count
                    } ?? 0
                    if sample.count > dialogueCount {
                        out.dialogue = parenX
                    } else if out.dialogue == nil {
                        out.dialogue = parenX
                    }
                    out.parenthetical = nil
                }
            }
        }

        if let charX = cols.character {
            let sample = lines.filter { abs($0.x - charX) <= tolerance }
            if !sample.isEmpty {
                let cueShaped = sample.filter {
                    let t = $0.text.trimmingCharacters(in: .whitespaces)
                    return isUppercaseLetters(t) && t.count >= 2 && t.count <= 32
                        && !t.contains(".") && !t.contains(",")
                }.count
                let ratio = Double(cueShaped) / Double(sample.count)
                if ratio < 0.4 {
                    out.character = nil
                }
            }
        }

        return out
    }

    /// Cluster x-positions into role columns. We don't trust the
    /// document to use industry-standard pixel values exactly, but the
    /// *ordering* (action < dialogue < parenthetical < character <
    /// transition) is reliable enough that we infer roles by rank.
    static func inferColumns(_ lines: [PDFLine]) -> Columns {
        guard !lines.isEmpty else { return Columns() }
        // Bucket x-positions to the nearest 6pt and count occurrences.
        var bucketCounts: [CGFloat: Int] = [:]
        for line in lines {
            let rounded = (line.x / 6).rounded() * 6
            bucketCounts[rounded, default: 0] += 1
        }
        // Keep buckets with at least 2 hits so a stray line doesn't
        // become a phantom column.
        let buckets = bucketCounts
            .filter { $0.value >= 2 }
            .sorted { $0.key < $1.key }
            .map { $0.key }

        var cols = Columns()
        guard !buckets.isEmpty else { return cols }

        // Heuristic mapping by index in the sorted bucket list:
        //   0  → action / heading
        //   1  → dialogue
        //   2  → parenthetical
        //   3  → character
        //   4+ → transition (rightmost)
        if buckets.count >= 1 { cols.action = buckets[0] }
        if buckets.count >= 2 { cols.dialogue = buckets[1] }
        if buckets.count >= 3 { cols.parenthetical = buckets[2] }
        if buckets.count >= 4 { cols.character = buckets[3] }
        if buckets.count >= 5 { cols.transition = buckets.last }
        // Two-bucket scripts: just action + dialogue. That's still useful.
        if buckets.count == 2 {
            cols.action = buckets[0]
            cols.dialogue = buckets[1]
        }
        return cols
    }

    // MARK: - Classification

    enum LineKind { case heading, action, character, parenthetical, dialogue, transition }

    static func classify(_ line: PDFLine, columns: Columns) -> LineKind {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        let isAllCaps = isUppercaseLetters(text)

        // 1. Scene heading: highest-confidence pattern match wins
        // regardless of column.
        if isSceneHeadingText(line) { return .heading }

        // 2. Transition: ALL CAPS ending in "TO:" or known terminal cues
        // OR sitting in the rightmost column.
        if isTransitionText(text) { return .transition }
        if let tx = columns.transition, line.x >= tx - 6 { return .transition }

        // 3. Parenthetical: line wrapped in parens.
        if text.hasPrefix("(") && text.hasSuffix(")") { return .parenthetical }

        // 4. Character cue at the inferred character column.
        if let charX = columns.character,
           abs(line.x - charX) <= 10, isAllCaps {
            return .character
        }

        // 5. Wonky-template fallback: when the document didn't yield a
        // character column at all (typical of single-indent / hand-typed
        // scripts), promote ALL CAPS short non-punctuated lines to
        // character cues BEFORE the action-column match would steal
        // them. This is what lets "BOB" sandwiched between flush-left
        // dialogue still become a cue.
        if columns.character == nil,
           isAllCaps,
           text.count >= 2, text.count <= 32,
           !text.contains("."), !text.contains(",") {
            return .character
        }

        // 6. Remaining column-based buckets.
        if let parenX = columns.parenthetical, abs(line.x - parenX) <= 10 {
            return .parenthetical
        }
        if let dlgX = columns.dialogue, abs(line.x - dlgX) <= 10 {
            return .dialogue
        }
        if let actX = columns.action, abs(line.x - actX) <= 10 {
            return .action
        }

        // 7. Final content fallback: bare ALL CAPS short line that
        // didn't match any column at all.
        if isAllCaps,
           text.count >= 2, text.count <= 32,
           !text.contains("."), !text.contains(",") {
            return .character
        }
        return .action
    }

    // MARK: - Patterns

    private static let sceneHeadingPrefixes: [String] = [
        "INT.", "EXT.", "EST.",
        "INT/EXT.", "INT./EXT.", "EXT/INT.", "EXT./INT.",
        "I/E.", "I./E."
    ]

    static func isSceneHeadingText(_ line: PDFLine) -> Bool {
        let raw = line.text.trimmingCharacters(in: .whitespaces)
        // Strip a leading scene number ("12   INT. KITCHEN ...   12").
        let stripped = stripSceneNumberPrefix(raw)
        let upper = stripped.uppercased()
        for prefix in sceneHeadingPrefixes {
            if upper.hasPrefix(prefix) || upper.hasPrefix(prefix + " ") {
                return true
            }
        }
        // Forced heading (Fountain ".INT" → still rendered "INT" in PDF
        // most of the time; this branch catches edge cases where the dot
        // survived).
        if upper.hasPrefix(".INT") || upper.hasPrefix(".EXT") {
            return true
        }
        return false
    }

    static func isTransitionText(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard isUppercaseLetters(text) else { return false }
        // "CUT TO:", "FADE OUT.", "SMASH CUT TO:" etc.
        if upper.hasSuffix("TO:") { return true }
        let knownTerminals: Set<String> = [
            "FADE OUT.", "FADE TO BLACK.", "FADE OUT", "FADE TO BLACK",
            "THE END", "THE END.", "TO BE CONTINUED.", "TO BE CONTINUED"
        ]
        if knownTerminals.contains(upper) { return true }
        return false
    }

    /// Strip "(O.S.)", "(V.O.)", "(CONT'D)", and any number of stacked
    /// suffixes like "RAVI (V.O.) (CONT'D)" from a character cue.
    static func stripCueSuffix(_ text: String) -> String {
        var out = text
        while true {
            let next = out.replacingOccurrences(
                of: #"\s*\([^)]*\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            if next == out { break }
            out = next
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// "12   INT. KITCHEN — DAY   12" → "INT. KITCHEN — DAY".
    /// Final Draft prints scene numbers in BOTH margins; depending on
    /// how the PDF text extractor groups columns, those numbers may
    /// arrive with multi-space gaps (typical pdftotext layout output)
    /// or with single-space gaps (after our same-y line merge collapses
    /// the row). The regex tolerates both.
    static func stripSceneNumberPrefix(_ text: String) -> String {
        var out = text
        // Leading "12 " / "A12  " / "12A   ".
        out = out.replacingOccurrences(
            of: #"^[A-Z]?[0-9]{1,4}[A-Z]?\s+"#,
            with: "",
            options: .regularExpression
        )
        // Trailing " 12" / "  A12" / "   12A".
        out = out.replacingOccurrences(
            of: #"\s+[A-Z]?[0-9]{1,4}[A-Z]?$"#,
            with: "",
            options: .regularExpression
        )
        return out
    }

    /// True when every cased character in `s` is uppercase. Returns true
    /// for strings that contain only digits, punctuation, or whitespace
    /// (we treat those as "not lowercase" rather than rejecting outright).
    static func isUppercaseLetters(_ s: String) -> Bool {
        var sawLetter = false
        for ch in s {
            if ch.isLetter {
                sawLetter = true
                if ch.isLowercase { return false }
            }
        }
        return sawLetter
    }

    private static func matches(_ s: String, pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }
}
