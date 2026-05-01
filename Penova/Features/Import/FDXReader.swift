//
//  FDXReader.swift
//  Penova
//
//  Reads a Final Draft `.fdx` file (XML) into the same
//  `FountainParser.ParsedDocument` shape the Fountain parser produces,
//  so `FountainImporter.makeProject(...)` can lift either format into
//  SwiftData without forking.
//
//  Coverage:
//    - <Paragraph Type="Scene Heading|Action|Character|Dialogue|
//      Parenthetical|Transition|Shot|General">
//    - <TitlePage> → titlePage[k.lowercased()] = v for any text we can
//      pull out of <Title>, <Author>, <DraftDate>, etc.
//    - Dual-dialogue blocks are flattened to back-to-back single
//      dialogue blocks (the structure is preserved on a future model
//      bump).
//
//  Out of scope:
//    - Revision marks, change tracking, comments
//    - SmartType (auto-complete) lists
//    - Page layout / scene-numbering metadata
//

import Foundation
import PenovaKit

public enum FDXReader {

    public enum ReadError: Error {
        case invalidEncoding
        case malformedXML
    }

    public static func parse(_ data: Data) throws -> FountainParser.ParsedDocument {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        let ok = parser.parse()
        if !ok { throw ReadError.malformedXML }
        return delegate.assemble()
    }

    public static func parse(_ xml: String) throws -> FountainParser.ParsedDocument {
        guard let data = xml.data(using: .utf8) else {
            throw ReadError.invalidEncoding
        }
        return try parse(data)
    }

    // MARK: - Delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        var titlePage: [String: String] = [:]
        var scenes: [FountainParser.ParsedScene] = []
        var currentScene: FountainParser.ParsedScene?

        // Active <Paragraph> state.
        private var paragraphType: String?
        private var paragraphText: String = ""
        private var inParagraph = false

        // Active <TitlePage>/<Paragraph> state — same paragraph machinery
        // but accumulating into titlePage instead of scene elements.
        private var inTitlePage = false
        private var titlePageBuffer: [String] = []
        // <HeaderAndFooter> sub-context: title-block lines flow into
        // header (centered) and contact/footer lines into footer (left).
        // Tracking the section lets us route accumulated paragraphs into
        // the right title-page key without inferring from text alone.
        private var inHeader = false
        private var inFooter = false
        private var headerLines: [String] = []
        private var footerLines: [String] = []

        // MARK: parser callbacks

        func parser(_ parser: XMLParser,
                    didStartElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?,
                    attributes attributeDict: [String : String] = [:]) {
            switch elementName {
            case "TitlePage":
                inTitlePage = true
            case "Header":
                inHeader = true
            case "Footer":
                inFooter = true
            case "Paragraph":
                paragraphType = attributeDict["Type"]
                paragraphText = ""
                inParagraph = true
            case "Text", "DynamicLabel":
                // Reset accumulator? No — we append in `foundCharacters`,
                // which the parser delivers across <Text> child elements.
                break
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inParagraph {
                paragraphText += string
            }
        }

        func parser(_ parser: XMLParser,
                    didEndElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?) {
            switch elementName {
            case "Paragraph":
                let text = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
                let type = paragraphType ?? "Action"
                paragraphType = nil
                paragraphText = ""
                inParagraph = false

                if inTitlePage {
                    if !text.isEmpty {
                        if inHeader {
                            headerLines.append(text)
                        } else if inFooter {
                            footerLines.append(text)
                        } else {
                            titlePageBuffer.append(text)
                        }
                    }
                    return
                }
                if text.isEmpty { return }

                let kind = mapKind(type)
                if kind == .heading {
                    // Close the previous scene; start a fresh one with
                    // this heading.
                    if let scene = currentScene { scenes.append(scene) }
                    currentScene = FountainParser.ParsedScene(heading: text, elements: [])
                } else {
                    // FDX may contain dialogue/action before any scene
                    // heading (e.g. an opening title card). Park them in
                    // a synthetic prologue scene.
                    if currentScene == nil {
                        currentScene = FountainParser.ParsedScene(
                            heading: "INT. PROLOGUE - DAY",
                            elements: []
                        )
                    }
                    currentScene?.elements.append(
                        FountainParser.ParsedElement(kind: kind, text: text)
                    )
                }
            case "Header":
                inHeader = false
            case "Footer":
                inFooter = false
            case "TitlePage":
                inTitlePage = false
                // Heuristic mapping: each "Key: Value" buffered line goes
                // into titlePage; lines without a colon (centered title
                // text) fall back to "title" / "author" / "extra".
                applyTitlePage()
                applyHeaderFooter()
            default:
                break
            }
        }

        private func applyTitlePage() {
            for raw in titlePageBuffer {
                if let colon = raw.firstIndex(of: ":") {
                    let k = raw[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let v = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !k.isEmpty { titlePage[k] = v }
                } else {
                    if titlePage["title"] == nil {
                        titlePage["title"] = raw
                    } else if titlePage["author"] == nil,
                              raw.lowercased().hasPrefix("by ") || raw.lowercased().hasPrefix("written by") {
                        let v = raw
                            .replacingOccurrences(of: "(?i)^by\\s+", with: "", options: .regularExpression)
                            .replacingOccurrences(of: "(?i)^written\\s+by\\s+", with: "", options: .regularExpression)
                        titlePage["author"] = v.trimmingCharacters(in: .whitespaces)
                    } else if titlePage["author"] == nil {
                        titlePage["author"] = raw
                    } else {
                        // Append to a free-form contact bucket.
                        titlePage["contact"] = (titlePage["contact"].map { $0 + "\n" } ?? "") + raw
                    }
                }
            }
            titlePageBuffer.removeAll()
        }

        /// Map a Final Draft `<HeaderAndFooter>` block's accumulated
        /// header lines onto title/credit/author/source, and footer
        /// lines onto contact. Header convention (matching what
        /// FinalDraftXMLWriter emits): line 0 is title, line 1 is the
        /// credit ("Written by"), line 2 is author, the rest are
        /// source. Footer is straight-through to contact.
        private func applyHeaderFooter() {
            if !headerLines.isEmpty {
                if titlePage["title"] == nil { titlePage["title"] = headerLines[0] }
                if headerLines.count > 1, titlePage["credit"] == nil {
                    titlePage["credit"] = headerLines[1]
                }
                if headerLines.count > 2, titlePage["author"] == nil {
                    titlePage["author"] = headerLines[2]
                }
                if headerLines.count > 3, titlePage["source"] == nil {
                    titlePage["source"] = headerLines.dropFirst(3).joined(separator: "\n")
                }
            }
            if !footerLines.isEmpty, titlePage["contact"] == nil {
                titlePage["contact"] = footerLines.joined(separator: "\n")
            }
            headerLines.removeAll()
            footerLines.removeAll()
        }

        private func mapKind(_ type: String) -> SceneElementKind {
            switch type {
            case "Scene Heading":   return .heading
            case "Action":          return .action
            case "Character":       return .character
            case "Dialogue":        return .dialogue
            case "Parenthetical":   return .parenthetical
            case "Transition":      return .transition
            case "Shot":            return .action   // collapse to action
            case "General":         return .action
            default:                return .action
            }
        }

        // MARK: assemble

        func assemble() -> FountainParser.ParsedDocument {
            if let scene = currentScene { scenes.append(scene) }
            currentScene = nil
            var doc = FountainParser.ParsedDocument()
            doc.titlePage = titlePage
            doc.scenes = scenes
            return doc
        }
    }
}
