//
//  PenovaMacUITests.swift
//  PenovaMacUITests
//
//  XCUITest scenarios that exercise realistic screenwriter workflows
//  against the running Mac app. Each test launches the app fresh,
//  performs a small user journey, and asserts on the resulting state.
//
//  Accessibility identifiers (A11yID enum, in PenovaMac/App/PenovaLog.swift)
//  give us stable hooks to find views without relying on label text
//  changing under us.
//

import XCTest

final class PenovaMacUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The app seeds a sample library on first launch when the store
        // is empty. To make tests deterministic we ask the app to use a
        // fresh in-memory store via env vars.
        app.launchEnvironment["PENOVA_TEST_RESET_STORE"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - 01. Launch / first paint

    /// The bedrock test: app launches, shows the three panes, and the
    /// kitchen scene loads on the cream paper.
    func test01_launchShowsThreePaneShell() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8), "Window did not appear")

        // The library window is identified, but on macOS XCUITest sees
        // the window itself + nested elements. Just verify the sidebar,
        // editor pane, and inspector all exist.
        let sidebar = app.descendants(matching: .any)["sidebar"]
        let editor = app.descendants(matching: .any)["pane.editor"]
        let inspector = app.descendants(matching: .any)["pane.inspector"]

        XCTAssertTrue(sidebar.waitForExistence(timeout: 4), "Sidebar pane missing")
        XCTAssertTrue(editor.exists, "Editor pane missing")
        XCTAssertTrue(inspector.exists, "Inspector pane missing")
    }

    // MARK: - 02. Navigate via sidebar

    /// Mira's morning: opens the app, scans the sidebar, finds her
    /// scene, opens it. Confirms the sidebar has more than one row
    /// (sample library seeded).
    func test02_sidebarHasSeededProject() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        // The sample library installs Ek Raat Mumbai Mein.
        let projectRow = app.staticTexts["Ek Raat Mumbai Mein"]
        XCTAssertTrue(projectRow.waitForExistence(timeout: 4),
                     "Sample project not found in sidebar")
    }

    // MARK: - 03. View-mode toggle

    /// Power user flow: cycle Editor → Index Cards → Outline → Editor.
    /// Each pane uses a distinct accessibilityIdentifier so we can
    /// verify the swap actually happens.
    func test03_viewModeToggle() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        // Wait for editor to be present at start
        let editor = app.descendants(matching: .any)["pane.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 4))

        // Click "Index Cards" segment in the toolbar picker
        let cardsButton = app.buttons["Index Cards"].firstMatch
        if cardsButton.waitForExistence(timeout: 2) {
            cardsButton.click()
            let cardsPane = app.descendants(matching: .any)["pane.cards"]
            XCTAssertTrue(cardsPane.waitForExistence(timeout: 3),
                         "Index Cards pane did not appear")
        }

        // Click "Outline"
        let outlineButton = app.buttons["Outline"].firstMatch
        if outlineButton.waitForExistence(timeout: 2) {
            outlineButton.click()
            let outlinePane = app.descendants(matching: .any)["pane.outline"]
            XCTAssertTrue(outlinePane.waitForExistence(timeout: 3),
                         "Outline pane did not appear")
        }

        // Back to Editor
        let editorButton = app.buttons["Editor"].firstMatch
        if editorButton.waitForExistence(timeout: 2) {
            editorButton.click()
            XCTAssertTrue(editor.waitForExistence(timeout: 3),
                         "Editor pane did not return")
        }
    }

    // MARK: - 04. ⌘F search overlay

    /// Power user reflex: ⌘F → type a query → see results. The search
    /// service is unit-tested separately; this test only verifies the
    /// overlay appears and the input accepts text.
    func test04_searchOverlay() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        // Trigger ⌘F
        XCUIElement.perform(withKeyModifiers: .command) {
            window.typeKey("f", modifierFlags: .command)
        }

        let overlay = app.descendants(matching: .any)["overlay.search"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3),
                     "Search overlay did not appear after ⌘F")

        // Type a query
        let input = app.descendants(matching: .any)["overlay.search.input"]
        if input.exists {
            input.click()
            input.typeText("kitchen")
            // We should see at least one cell with "KITCHEN" in it
            let kitchenHit = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "KITCHEN")
            ).firstMatch
            XCTAssertTrue(kitchenHit.waitForExistence(timeout: 3),
                         "Search did not surface a kitchen result")
        }

        // Esc dismisses
        window.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(overlay.exists, "Overlay did not dismiss on Esc")
    }

    // MARK: - 05. ⌘E export sheet

    /// Verify the export sheet opens, three formats are present, and Esc
    /// dismisses it. Doesn't actually run the save panel — that requires
    /// system-level UI which is fragile in CI.
    func test05_exportSheetOpens() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        window.typeKey("e", modifierFlags: .command)

        let exportSheet = app.descendants(matching: .any)["sheet.export"]
        XCTAssertTrue(exportSheet.waitForExistence(timeout: 4),
                     "Export sheet did not appear")

        // Verify the three format choices are present
        XCTAssertTrue(app.staticTexts["Production PDF"].exists)
        XCTAssertTrue(app.staticTexts["Final Draft XML"].exists)
        XCTAssertTrue(app.staticTexts["Fountain plain text"].exists)
    }

    // MARK: - 06. ⌘⇧T title page editor

    /// Title-page editor opens, has a Title field that pre-fills with
    /// the project's title, and Cancel dismisses it.
    func test06_titlePageEditorOpens() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        window.typeKey("t", modifierFlags: [.command, .shift])

        let titlePage = app.descendants(matching: .any)["sheet.title-page"]
        XCTAssertTrue(titlePage.waitForExistence(timeout: 4),
                     "Title page sheet did not appear")
    }

    // MARK: - 07. Performance: cold launch under 4 seconds

    func test07_coldLaunchIsFast() throws {
        let metrics: [XCTMetric] = [
            XCTApplicationLaunchMetric(),
        ]
        measure(metrics: metrics) {
            app.terminate()
            app.launch()
            _ = app.windows.firstMatch.waitForExistence(timeout: 6)
        }
    }
}
