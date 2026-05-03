//
//  CommandRegistry.swift
//  PenovaKit
//
//  Central registry for everything that can be invoked from the
//  command palette (⌘K). The palette stays oblivious to specific
//  app actions — it just queries the registry and dispatches by id.
//
//  Two layers:
//
//   • PenovaCommand        — pure descriptor (title, group, shortcut,
//                            search keywords). Hashable, Sendable —
//                            safe to ship into a SwiftUI view diff.
//
//   • CommandRegistry      — @MainActor class that owns the runtime
//                            handler closures and exposes a
//                            search(query:) method backed by
//                            FuzzyMatcher. Apps register their actions
//                            once at launch; the palette consumes the
//                            registry as an @ObservedObject.
//
//  Search ranks against three fields:
//
//   • title      (full weight)            — "Rename character…"
//   • aliases    (½ weight, fallback)     — ["Rename"]
//   • keywords   (⅓ weight, fallback)     — ["change", "edit"]
//
//  Matched character indices are reported on the title only so the
//  palette can highlight the literal letters the user typed.
//

import Foundation
import Combine

// MARK: - Group

public enum PenovaCommandGroup: String, Codable, CaseIterable, Sendable {
    case suggested
    case navigation
    case views
    case editing
    case production
    case settings

    public var display: String {
        switch self {
        case .suggested:  return "Suggested"
        case .navigation: return "Navigation"
        case .views:      return "Views"
        case .editing:    return "Editing"
        case .production: return "Production"
        case .settings:   return "Settings"
        }
    }

    /// Stable order in the palette UI — Suggested first, settings last.
    /// Numeric so callers can sort with a single integer key.
    public var sortOrder: Int {
        switch self {
        case .suggested:  return 0
        case .navigation: return 1
        case .views:      return 2
        case .editing:    return 3
        case .production: return 4
        case .settings:   return 5
        }
    }
}

// MARK: - Shortcut

public struct PenovaCommandShortcut: Equatable, Hashable, Codable, Sendable {

    public enum Modifier: String, Codable, Hashable, Sendable {
        case command, shift, option, control

        /// Apple-keyboard symbol used on Mac (⌘ ⇧ ⌥ ⌃) — same string
        /// fits the iPad hardware-keyboard hint surface too.
        public var symbol: String {
            switch self {
            case .command: return "⌘"
            case .shift:   return "⇧"
            case .option:  return "⌥"
            case .control: return "⌃"
            }
        }
    }

    public let modifiers: [Modifier]
    /// Single key as displayed (e.g. "K", "Return", "↑"). Already
    /// upper-cased / titled by the caller — no transformation here.
    public let key: String

    public init(_ modifiers: [Modifier], _ key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Joined display string ("⇧⌘R") suitable for a single-line label.
    public var displayString: String {
        modifiers.map(\.symbol).joined() + key
    }

    /// Per-glyph array — handy when the palette renders each modifier
    /// + key as a separate boxed token.
    public var displayTokens: [String] {
        modifiers.map(\.symbol) + [key]
    }
}

// MARK: - Command descriptor

public struct PenovaCommand: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let group: PenovaCommandGroup
    /// Alternative phrasings of the command title — lower-weight match
    /// targets so a user typing "rename" still finds "Change character
    /// name…".
    public let aliases: [String]
    /// Free-form search-only words (synonyms, related verbs). Lowest
    /// weight in the search score.
    public let keywords: [String]
    public let shortcut: PenovaCommandShortcut?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        group: PenovaCommandGroup,
        aliases: [String] = [],
        keywords: [String] = [],
        shortcut: PenovaCommandShortcut? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.aliases = aliases
        self.keywords = keywords
        self.shortcut = shortcut
    }
}

// MARK: - Search

public enum CommandSearch {

    public struct Result: Identifiable, Equatable, Hashable, Sendable {
        public let command: PenovaCommand
        public let score: Int
        /// Character indices in the title that were matched (for the
        /// caller to render as bold/coloured spans).
        public let matchedIndices: [Int]

        public var id: String { command.id }

        public init(command: PenovaCommand, score: Int, matchedIndices: [Int]) {
            self.command = command
            self.score = score
            self.matchedIndices = matchedIndices
        }
    }

    /// Score one command against the query.
    /// Returns nil if the query doesn't match any of the command's
    /// title / alias / keyword fields.
    public static func score(
        query: String,
        for command: PenovaCommand
    ) -> Result? {
        if query.isEmpty {
            return Result(command: command, score: 0, matchedIndices: [])
        }

        let titleMatch = FuzzyMatcher.match(query: query, target: command.title)
        let aliasMatch = command.aliases
            .compactMap { FuzzyMatcher.match(query: query, target: $0) }
            .max(by: { $0.score < $1.score })
        let keywordMatch = command.keywords
            .compactMap { FuzzyMatcher.match(query: query, target: $0) }
            .max(by: { $0.score < $1.score })

        let titleScore = titleMatch?.score ?? 0
        let aliasScore = (aliasMatch?.score ?? 0) / 2
        let keywordScore = (keywordMatch?.score ?? 0) / 3

        // Combine: title score is primary; alias/keyword serve as a
        // fallback boost so a command with no title hit can still
        // surface if its alias scores highly.
        let total = titleScore + max(aliasScore, keywordScore)
        guard total > 0 else { return nil }

        return Result(
            command: command,
            score: total,
            matchedIndices: titleMatch?.matchedIndices ?? []
        )
    }

    /// Return the top-scoring matches, descending. Stable on score
    /// ties — falls back to group sort order, then title.
    public static func results(
        query: String,
        in commands: [PenovaCommand],
        limit: Int = 30
    ) -> [Result] {
        let scored = commands.compactMap { score(query: query, for: $0) }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.command.group.sortOrder != rhs.command.group.sortOrder {
                return lhs.command.group.sortOrder < rhs.command.group.sortOrder
            }
            return lhs.command.title.localizedCompare(rhs.command.title)
                == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// Group results by their command's group, preserving the score-
    /// descending order within each group. Convenient for sectioning
    /// the palette without re-sorting in the view.
    public static func grouped(
        _ results: [Result]
    ) -> [(group: PenovaCommandGroup, items: [Result])] {
        var buckets: [PenovaCommandGroup: [Result]] = [:]
        for r in results {
            buckets[r.command.group, default: []].append(r)
        }
        return PenovaCommandGroup.allCases
            .compactMap { g -> (PenovaCommandGroup, [Result])? in
                guard let items = buckets[g], !items.isEmpty else { return nil }
                return (g, items)
            }
    }
}

// MARK: - Registry

@MainActor
public final class CommandRegistry: ObservableObject {

    @Published public private(set) var commands: [PenovaCommand] = []
    private var handlers: [String: () -> Void] = [:]

    public init() {}

    /// Register (or replace) a command with its handler. Stable on the
    /// command id — calling twice with the same id replaces the handler
    /// without duplicating the descriptor in `commands`.
    public func register(
        _ command: PenovaCommand,
        handler: @escaping () -> Void
    ) {
        if let idx = commands.firstIndex(where: { $0.id == command.id }) {
            commands[idx] = command
        } else {
            commands.append(command)
        }
        handlers[command.id] = handler
    }

    public func unregister(id: String) {
        commands.removeAll { $0.id == id }
        handlers[id] = nil
    }

    /// Drop everything. Useful in tests; apps shouldn't need this.
    public func reset() {
        commands.removeAll()
        handlers.removeAll()
    }

    /// Dispatch by id. No-op if the id is not registered — palette
    /// callers should never hit this path because they only see ids
    /// that came back from `search(_:)`.
    @discardableResult
    public func run(id: String) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler()
        return true
    }

    public func search(_ query: String, limit: Int = 30) -> [CommandSearch.Result] {
        CommandSearch.results(query: query, in: commands, limit: limit)
    }

    /// All registered commands grouped by their group, in stable group
    /// order. Used when the user opens the palette with an empty query.
    public func allGrouped() -> [(group: PenovaCommandGroup, items: [PenovaCommand])] {
        var buckets: [PenovaCommandGroup: [PenovaCommand]] = [:]
        for c in commands { buckets[c.group, default: []].append(c) }
        return PenovaCommandGroup.allCases
            .compactMap { g -> (PenovaCommandGroup, [PenovaCommand])? in
                guard let items = buckets[g], !items.isEmpty else { return nil }
                return (g, items.sorted {
                    $0.title.localizedCompare($1.title) == .orderedAscending
                })
            }
    }
}
