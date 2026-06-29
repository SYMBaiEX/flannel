//
//  flannelUITestsLaunchTests.swift
//  flannelUITests
//
//  Created by SYMBiEX on 6/28/26.
//

import XCTest

final class flannelUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FLANNEL_RUN_UI_TESTS"] != "1",
            "Set FLANNEL_RUN_UI_TESTS=1 in a desktop session with UI automation permission to run Flannel UI tests."
        )
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Flannel"].waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("New Chat", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Search chats", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Message composer", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(findElement("Settings", in: app).waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findElement(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let candidates = [
            app.buttons[label],
            app.staticTexts[label],
            app.links[label],
            app.otherElements[label]
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return app.staticTexts[label]
    }
}
