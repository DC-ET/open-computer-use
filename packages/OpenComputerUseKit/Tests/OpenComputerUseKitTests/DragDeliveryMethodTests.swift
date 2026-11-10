import XCTest
@testable import OpenComputerUseKit

final class DragDeliveryMethodTests: XCTestCase {
    func testAutoUsesTheWindowServerForWebPages() {
        XCTAssertEqual(dragDeliveryPath(method: .auto, isWebContent: true, environment: [:]), .global)
        XCTAssertEqual(dragDeliveryPath(method: .auto, isWebContent: false, environment: [:]), .appPost)
    }

    func testExplicitMethodWins() {
        XCTAssertEqual(dragDeliveryPath(method: .appPost, isWebContent: true, environment: [:]), .appPost)
        XCTAssertEqual(dragDeliveryPath(method: .global, isWebContent: false, environment: [:]), .global)
    }

    func testTheGateStillSelectsGlobalForNativeTargets() {
        XCTAssertEqual(
            dragDeliveryPath(method: .auto, isWebContent: false, environment: ["OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS": "1"]),
            .global
        )
    }

    func testWebEnginesAreDetectedByTheirFrameworks() {
        XCTAssertTrue(appRunsWebDragAndDrop(bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")))
        XCTAssertFalse(appRunsWebDragAndDrop(bundleURL: URL(fileURLWithPath: "/System/Applications/TextEdit.app")))
        XCTAssertFalse(appRunsWebDragAndDrop(bundleURL: nil))
    }

    func testMethodParsingRejectsUnknownValues() throws {
        XCTAssertEqual(try parseDragDeliveryMethod(nil), .auto)
        XCTAssertEqual(try parseDragDeliveryMethod("global"), .global)
        XCTAssertEqual(try parseDragDeliveryMethod("app_post"), .appPost)
        XCTAssertThrowsError(try parseDragDeliveryMethod("post")) { error in
            XCTAssertTrue(String(describing: error).contains("auto, app_post, global"), String(describing: error))
        }
    }
}
