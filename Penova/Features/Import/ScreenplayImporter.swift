//
//  ScreenplayImporter.swift
//  Penova
//
//  Single entry point that routes a picked file URL to the right parser
//  (PDF → PDFScreenplayParser, FDX → FDXReader, anything else →
//  FountainParser) and lifts the resulting ParsedDocument into a fresh
//  Project via FountainImporter.makeProject.
//

import Foundation
import PDFKit
import SwiftData

@MainActor
public enum ScreenplayImporter {

    public enum ImportError: LocalizedError {
        case unreadable
        case unrecognizedFormat(String)
        case pdfHasNoText        // image-only / scanned PDF
        case empty
        case underlying(Error)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Could not open that file."
            case .unrecognizedFormat(let ext):
                return "Penova doesn't recognise .\(ext) yet — try a .pdf, .fdx, .fountain, .txt, or .md file."
            case .pdfHasNoText:
                return "That PDF appears to be a scan — Penova can only import PDFs that contain selectable text."
            case .empty:
                return "Couldn't find any scenes in that file."
            case .underlying(let err):
                return err.localizedDescription
            }
        }
    }

    public struct Result {
        public var project: Project
        /// Diagnostic info from the parser. Present for PDF imports
        /// only; nil for Fountain/FDX paths.
        public var pdfDiagnostics: PDFScreenplayParser.Diagnostics?
    }

    public static func importFile(at url: URL, into context: ModelContext) throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let title = baseName.isEmpty ? "Untitled" : baseName

        switch ext {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
            let source = PDFKitLineSource(document: document)
            let result = PDFScreenplayParser.parse(source)
            if result.document.scenes.isEmpty && result.diagnostics.bodyLineCount == 0 {
                throw ImportError.pdfHasNoText
            }
            if result.document.scenes.isEmpty {
                throw ImportError.empty
            }
            let project = FountainImporter.makeProject(
                title: titleFromTitlePage(result.document.titlePage) ?? title,
                from: result.document,
                context: context
            )
            applyTitlePage(result.document.titlePage, to: project)
            try? context.save()
            return Result(project: project, pdfDiagnostics: result.diagnostics)

        case "fdx":
            do {
                let data = try Data(contentsOf: url)
                let doc = try FDXReader.parse(data)
                if doc.scenes.isEmpty { throw ImportError.empty }
                let project = FountainImporter.makeProject(
                    title: titleFromTitlePage(doc.titlePage) ?? title,
                    from: doc,
                    context: context
                )
                applyTitlePage(doc.titlePage, to: project)
                try? context.save()
                return Result(project: project, pdfDiagnostics: nil)
            } catch let err as ImportError {
                throw err
            } catch {
                throw ImportError.underlying(error)
            }

        case "fountain", "txt", "md", "":
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                    throw ImportError.unreadable
                }
                let doc = FountainParser.parse(text)
                if doc.scenes.isEmpty { throw ImportError.empty }
                let project = FountainImporter.makeProject(
                    title: titleFromTitlePage(doc.titlePage) ?? title,
                    from: doc,
                    context: context
                )
                applyTitlePage(doc.titlePage, to: project)
                try? context.save()
                return Result(project: project, pdfDiagnostics: nil)
            } catch let err as ImportError {
                throw err
            } catch {
                throw ImportError.underlying(error)
            }

        default:
            throw ImportError.unrecognizedFormat(ext)
        }
    }

    // MARK: - Title-page lift

    private static func titleFromTitlePage(_ tp: [String: String]) -> String? {
        let candidate = tp["title"] ?? tp["Title"]
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    /// Apply non-title fields from the title page block onto the new
    /// Project. Author + contact go into `contactBlock` so the title
    /// page round-trips through our PDF/FDX export.
    private static func applyTitlePage(_ tp: [String: String], to project: Project) {
        var lines: [String] = []
        if let author = (tp["author"] ?? tp["Author"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !author.isEmpty {
            lines.append(author)
        }
        for k in ["email", "phone", "agent", "contact"] {
            if let v = tp[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                lines.append(v)
            }
        }
        if !lines.isEmpty {
            project.contactBlock = lines.joined(separator: "\n")
            project.updatedAt = .now
        }
    }
}
