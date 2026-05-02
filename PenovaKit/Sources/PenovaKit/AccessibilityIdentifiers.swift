//
//  AccessibilityIdentifiers.swift
//  PenovaKit
//
//  Cross-platform `accessibilityIdentifier(_:)` constants used by both
//  Mac and iOS UI tests to find views reliably. Keeping them in
//  PenovaKit means both targets see the same set, and identifiers stay
//  consistent across platforms (e.g. `editor.scene-row` reads the
//  same in a Mac XCUITest and an iOS UI test).
//
//  This is the single source of truth; the Mac PenovaLog.swift
//  re-exports a subset for backwards-compatibility.
//
//  Convention:
//    - Top-level surfaces:   plain noun ("library-window", "settings")
//    - Containers / panes:   `pane.<name>` ("pane.editor")
//    - Toolbars:             `toolbar.<action>`
//    - Sheets/overlays:      `sheet.<name>`, `overlay.<name>`
//    - Per-element rows:     `<surface>.row.<id>` — caller fills the id
//

import Foundation

public enum A11yID {

    // MARK: Top-level shell

    public static let libraryWindow         = "library-window"
    public static let homeScreen            = "home"
    public static let scriptsTab            = "tab.scripts"
    public static let charactersTab         = "tab.characters"
    public static let settingsScreen        = "settings"

    // MARK: Toolbars / chrome

    public static let toolbarNewScene       = "toolbar.new-scene"
    public static let toolbarPrint          = "toolbar.print"
    public static let toolbarExport         = "toolbar.export"
    public static let toolbarFocus          = "toolbar.focus"
    public static let toolbarInspector      = "toolbar.inspector"
    public static let viewModePicker        = "view-mode.picker"
    public static let viewModeEditor        = "view-mode.editor"
    public static let viewModeCards         = "view-mode.cards"
    public static let viewModeOutline       = "view-mode.outline"

    // MARK: Sidebar (Mac)

    public static let sidebar               = "sidebar"
    public static let sidebarSearch         = "sidebar.search"
    public static let sidebarSmartAll       = "sidebar.smart.all-scenes"
    public static let sidebarSmartBookmarks = "sidebar.smart.bookmarks"
    public static let sidebarNewProject     = "sidebar.new-project"

    // MARK: Editor / center pane

    public static let editorPane            = "pane.editor"
    public static let cardsPane             = "pane.cards"
    public static let outlinePane           = "pane.outline"
    public static let scriptPage            = "script-page"
    /// Per-row identifier used in the iOS scene editor: append the
    /// scene-element id to disambiguate within a scene.
    public static func sceneElementRow(_ id: String) -> String {
        "scene-element.row.\(id)"
    }

    // MARK: Inspector

    public static let inspector             = "pane.inspector"
    public static let inspectorLocation     = "inspector.location"
    public static let inspectorBookmark     = "inspector.bookmark-toggle"

    // MARK: Status / overlays / sheets

    public static let statusBar             = "status-bar"
    public static let searchOverlay         = "overlay.search"
    public static let searchInput           = "overlay.search.input"
    public static let titlePageSheet        = "sheet.title-page"
    public static let exportSheet           = "sheet.export"
    public static let exportFormatPDF       = "export.format.pdf"
    public static let exportFormatFDX       = "export.format.fdx"
    public static let exportFormatFountain  = "export.format.fountain"

    // MARK: iOS — Project library + scene browse

    public static let projectListRow        = "project.row"
    public static let newProjectButton      = "project.new"
    public static let projectDetailScreen   = "project.detail"
    public static let sceneListRow          = "scene.row"
    public static let newSceneButton        = "scene.new"
    public static let sceneDetailScreen     = "scene.detail"
    public static let sceneHeading          = "scene.heading"

    // MARK: iOS — Settings sections

    public static let settingsAccount       = "settings.account"
    public static let settingsAppearance    = "settings.appearance"
    public static let settingsPrivacy       = "settings.privacy"
    public static let settingsAbout         = "settings.about"
    public static let settingsDangerZone    = "settings.danger-zone"
    public static let settingsSendFeedback  = "settings.send-feedback"

    // MARK: Reports + exports

    public static let reportsScreen         = "reports"
    public static let reportsSceneTab       = "reports.scenes"
    public static let reportsLocationTab    = "reports.locations"
    public static let reportsCastTab        = "reports.cast"
}
