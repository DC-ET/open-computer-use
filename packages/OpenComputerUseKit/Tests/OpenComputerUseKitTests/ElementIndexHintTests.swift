import XCTest
@testable import OpenComputerUseKit

final class ElementIndexHintTests: XCTestCase {
    func testAnUnknownIndexNamesBothWaysOut() {
        let message = unknownElementIndexMessage("132")
        XCTAssertTrue(message.contains("unknown element_index '132'"), message)
        XCTAssertTrue(message.contains("get_app_state"), message)
        XCTAssertTrue(message.contains("text/role"), message)
    }

    func testANonSettableElementExplainsAStaleIndex() {
        let message = nonSettableSetValueErrorMessage + staleElementIndexHint("132")
        XCTAssertTrue(message.hasPrefix("Cannot set a value for an element that is not settable"), message)
        XCTAssertTrue(message.contains("'132'"), message)
        XCTAssertTrue(message.contains("get_app_state"), message)
        XCTAssertTrue(message.contains("text/role"), message)
    }
}
