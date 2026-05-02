//
//  PenovaLog.swift
//  Penova for Mac
//
//  Centralised OSLog subsystem so the app emits consistent, filterable
//  log streams in Console.app. Categories let support and the
//  developer narrow down to the area they care about — `editor`,
//  `library`, `export`, `sync`, `automation`. Signpost intervals on
//  expensive operations (PDF render, library load) so we can profile
//  with Instruments without sprinkling code with bespoke timing logic.
//
//  Usage:
//      PenovaLog.editor.log("appended new dialogue row")
//      let id = PenovaLog.signpost.beginInterval("pdf-render", "render")
//      defer { PenovaLog.signpost.endInterval("pdf-render", id, "done") }
//

import Foundation
import OSLog

public enum PenovaLog {
    public static let subsystem = "com.rudrapratapsingh.penova.mac"

    public static let app        = Logger(subsystem: subsystem, category: "app")
    public static let library    = Logger(subsystem: subsystem, category: "library")
    public static let editor     = Logger(subsystem: subsystem, category: "editor")
    public static let export     = Logger(subsystem: subsystem, category: "export")
    public static let sync       = Logger(subsystem: subsystem, category: "sync")
    public static let search     = Logger(subsystem: subsystem, category: "search")
    public static let automation = Logger(subsystem: subsystem, category: "automation")

    public static let signpost = OSSignposter(subsystem: subsystem, category: "perf")
}

// Accessibility identifiers moved to
// `PenovaKit/Sources/PenovaKit/AccessibilityIdentifiers.swift` so iOS
// and Mac share one declaration. The Mac files that referenced
// `A11yID.foo` already import PenovaKit, so no call-site changes are
// required — the type just resolves through the kit module now.
