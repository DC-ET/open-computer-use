import XCTest
@testable import OpenComputerUseKit

final class UnknownArgumentTests: XCTestCase {
    private let declared = ToolDefinitions.declaredArgumentNames

    func testDeclaredArgumentsComeFromTheFullSchema() {
        XCTAssertEqual(declared["press_key"], ["app", "key", "key_method"])
        XCTAssertTrue(declared["set_value"]?.contains("text") == true, "selector arguments must count as declared")
        XCTAssertTrue(declared["set_value"]?.contains("role") == true)
        XCTAssertTrue(declared["get_app_state"]?.contains("window_placement") == true,
                      "runtime trimming must not turn a known argument into an unknown one")
        XCTAssertTrue(declared["list_apps"]?.isEmpty == true)
    }

    func testOnlyUndeclaredArgumentsAreReported() {
        XCTAssertEqual(unknownArgumentNames(tool: "press_key", arguments: ["app": "Finder", "key": "cmd+v"], declared: declared), [])
        XCTAssertEqual(unknownArgumentNames(tool: "press_key", arguments: ["app": "Finder", "key": "v", "modifiers": ["cmd"]], declared: declared), ["modifiers"])
        XCTAssertEqual(unknownArgumentNames(tool: "click", arguments: ["app": "Finder", "zzz": 1, "aaa": 2], declared: declared), ["aaa", "zzz"])
    }

    func testHostMetadataIsNotTreatedAsToolIntent() {
        XCTAssertEqual(unknownArgumentNames(tool: "press_key", arguments: ["app": "Finder", "key": "Return", "_meta": ["trace": "1"]], declared: declared), [])
    }

    func testUnknownToolIsLeftToTheToolSwitch() {
        XCTAssertEqual(unknownArgumentNames(tool: "not_a_tool", arguments: ["anything": 1], declared: declared), [])
    }

    func testMessageNamesTheOffenderAndTheAcceptedSet() {
        let message = unknownArgumentMessage(tool: "click", unknown: ["zzz"], allowed: ["app", "x", "y"])
        XCTAssertEqual(message, "click: unknown argument zzz. Accepted: app, x, y.")
        XCTAssertEqual(
            unknownArgumentMessage(tool: "click", unknown: ["aaa", "zzz"], allowed: ["app"]),
            "click: unknown arguments aaa, zzz. Accepted: app."
        )
    }

    func testModifiersHintPointsAtTheKeySyntax() {
        let message = unknownArgumentMessage(tool: "press_key", unknown: ["modifiers"], allowed: ["app", "key"])
        XCTAssertTrue(message.contains("Press combinations go in key"), message)
        XCTAssertTrue(message.contains("cmd+v"), message)
        XCTAssertFalse(unknownArgumentMessage(tool: "click", unknown: ["modifiers"], allowed: ["app"]).contains("Press combinations"))
    }

    func testDispatcherRejectsTheModifiersMistakeBeforeTouchingTheKeyboard() {
        let result = ComputerUseToolDispatcher().callToolAsResult(
            name: "press_key",
            arguments: ["app": "Finder", "key": "v", "modifiers": ["cmd"]]
        )
        XCTAssertTrue(result.isError)
        let text = result.textContent
        XCTAssertTrue(text.contains("unknown argument modifiers"), text)
        XCTAssertTrue(text.contains("cmd+v"), text)
    }
}
