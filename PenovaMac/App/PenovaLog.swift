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

/// Accessibility identifiers used by the XCUITest harness to find views
/// reliably. Keep these in sync with the .accessibilityIdentifier(...)
/// calls inside the Mac feature views.
public enum A11yID {
    // Top-level shell
    public static let libraryWindow      = "library-window"
    public static let toolbarNewScene    = "toolbar.new-scene"
    public static let toolbarPrint       = "toolbar.print"
    public static let toolbarExport      = "toolbar.export"
    public static let toolbarFocus       = "toolbar.focus"
    public static let toolbarInspector   = "toolbar.inspector"
    public static let viewModePicker     = "view-mode.picker"
    public static let viewModeEditor     = "view-mode.editor"
    public static let viewModeCards      = "view-mode.cards"
    public static let viewModeOutline    = "view-mode.outline"

    // Sidebar
    public static let sidebar            = "sidebar"
    public static let sidebarSearch      = "sidebar.search"
    public static let sidebarSmartAll    = "sidebar.smart.all-scenes"
    public static let sidebarSmartBookmarks = "sidebar.smart.bookmarks"
    public static let sidebarNewProject  = "sidebar.new-project"

    // Editor / center pane
    public static let editorPane         = "pane.editor"
    public static let cardsPane          = "pane.cards"
    public static let outlinePane        = "pane.outline"
    public static let scriptPage         = "script-page"

    // Inspector
    public static let inspector          = "pane.inspector"
    public static let inspectorLocation  = "inspector.location"
    public static let inspectorBookmark  = "inspector.bookmark-toggle"

    // Status / overlays
    public static let statusBar          = "status-bar"
    public static let searchOverlay      = "overlay.search"
    public static let searchInput        = "overlay.search.input"
    public static let titlePageSheet     = "sheet.title-page"
    public static let exportSheet        = "sheet.export"
    public static let exportFormatPDF    = "export.format.pdf"
    public static let exportFormatFDX    = "export.format.fdx"
    public static let exportFormatFountain = "export.format.fountain"
}
