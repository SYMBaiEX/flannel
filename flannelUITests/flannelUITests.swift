//
//  flannelUITests.swift
//  flannelUITests
//
//  Created by SYMBiEX on 6/28/26.
//

import XCTest

final class flannelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FLANNEL_RUN_UI_TESTS"] != "1",
            "Set FLANNEL_RUN_UI_TESTS=1 in a desktop session with UI automation permission to run Flannel UI tests."
        )
        app = XCUIApplication()
    }

    @MainActor
    func testNewChatShowsChatSurface() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        let newChatButton = app.buttons["New Chat"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 5))
        newChatButton.tap()

        XCTAssertTrue(findElement("New AI Chat").waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Message composer").waitForExistence(timeout: 5))
    }

    @MainActor
    func testModelHubShowsProviderModes() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        openSettingsRoute("Models")

        XCTAssertTrue(findElement("Models and providers").waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("LM Studio").waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Official OpenAI API").waitForExistence(timeout: 5))
    }

    @MainActor
    func testKnowledgeAndToolsSurfacesExist() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        openSettingsRoute("Knowledge")
        XCTAssertTrue(findElement("Knowledge and RAG").waitForExistence(timeout: 5))

        let tools = findElement("Tools")
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(findElement("Tools and permissions").waitForExistence(timeout: 5))
    }

    @MainActor
    func testSettingsFooterButtonIsAccessible() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        XCTAssertTrue(findElement("Settings").waitForExistence(timeout: 5))
    }

    @MainActor
    func testConversationSidebarDoesNotExposeModeTabs() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("New Chat").waitForExistence(timeout: 5))

        XCTAssertEqual(app.segmentedControls.count, 0)
        XCTAssertFalse(sidebarModeTabExists("Chat"))
        XCTAssertFalse(sidebarModeTabExists("Cowork"))
        XCTAssertFalse(sidebarModeTabExists("Code"))
    }

    @MainActor
    func testInWindowSettingsShowsDetailAndExitsToComposer() throws {
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        let composer = findElement("Message composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Send").waitForExistence(timeout: 5))

        let settingsFooter = findElement("Settings")
        XCTAssertTrue(settingsFooter.waitForExistence(timeout: 5))
        settingsFooter.tap()

        let exitSettings = findElement("Exit Settings")
        XCTAssertTrue(exitSettings.waitForExistence(timeout: 5))

        let generalRoute = findElement("General")
        XCTAssertTrue(generalRoute.waitForExistence(timeout: 5))
        generalRoute.tap()

        XCTAssertTrue(findElement("Startup, history, and folders.").waitForExistence(timeout: 5))

        exitSettings.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Send").waitForExistence(timeout: 5))
    }

    private func findElement(_ label: String) -> XCUIElement {
        let candidates = [
            app.buttons[label],
            app.staticTexts[label],
            app.links[label],
            app.textViews[label],
            app.textFields[label],
            app.otherElements[label]
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return app.staticTexts[label]
    }

    private func sidebarModeTabExists(_ label: String) -> Bool {
        app.segmentedControls.buttons[label].exists
    }

    private func openSettingsRoute(_ route: String) {
        let settings = findElement("Settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let routeElement = findElement(route)
        XCTAssertTrue(routeElement.waitForExistence(timeout: 5))
        routeElement.tap()
    }
}
