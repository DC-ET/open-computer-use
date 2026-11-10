import XCTest
@testable import OpenComputerUseKit

final class ElementIdentityAttributeTests: XCTestCase {
    func testRoleAndSubroleNeverTolerateAnUnreadableValue() {
        XCTAssertTrue(ElementIdentity.identityAttributeAbsenceIsTolerable(.noValue, attribute: kAXRoleAttribute))
        XCTAssertTrue(ElementIdentity.identityAttributeAbsenceIsTolerable(.attributeUnsupported, attribute: kAXSubroleAttribute))
        for error: AXError in [.failure, .cannotComplete, .invalidUIElement] {
            XCTAssertFalse(ElementIdentity.identityAttributeAbsenceIsTolerable(error, attribute: kAXRoleAttribute), "\(error.rawValue)")
            XCTAssertFalse(ElementIdentity.identityAttributeAbsenceIsTolerable(error, attribute: kAXSubroleAttribute), "\(error.rawValue)")
        }
    }

    func testDescriptiveAttributesTolerateTextEditReportingFailure() {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute] {
            for error: AXError in [.noValue, .attributeUnsupported, .failure] {
                XCTAssertTrue(ElementIdentity.identityAttributeAbsenceIsTolerable(error, attribute: attribute), "\(attribute) \(error.rawValue)")
            }
            XCTAssertFalse(ElementIdentity.identityAttributeAbsenceIsTolerable(.invalidUIElement, attribute: attribute), attribute)
            XCTAssertFalse(ElementIdentity.identityAttributeAbsenceIsTolerable(.cannotComplete, attribute: attribute), attribute)
        }
    }
}
