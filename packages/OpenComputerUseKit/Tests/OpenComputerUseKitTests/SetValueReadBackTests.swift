import XCTest
@testable import OpenComputerUseKit

final class SetValueReadBackTests: XCTestCase {
    func testTextIsLiteralIncludingWhitespaceAndUnicode() {
        for text in ["", " \t中文🙂\n", "0015", "true", "e\u{301}"] {
            XCTAssertTrue(setValueMatches(requested: text, actual: text as CFString))
        }
        for (requested, actual) in [(" padded ", "padded"), ("0015", "15"), ("true", "1"), ("a", "A"), ("e\u{301}", "é")] {
            XCTAssertFalse(setValueMatches(requested: requested, actual: actual as CFString))
        }
    }
    func testOnlyActualNumericAndBooleanValuesAllowTypedComparison() {
        XCTAssertTrue(setValueMatches(requested: "15.0", actual: NSNumber(value: 15)))
        XCTAssertTrue(setValueMatches(requested: "1.0e-200", actual: NSNumber(value: 1e-200)))
        XCTAssertTrue(setValueMatches(requested: "1e200", actual: NSNumber(value: 1e200)))
        XCTAssertTrue(setValueMatches(requested: "-0.00", actual: NSNumber(value: 0)))
        XCTAssertTrue(setValueMatches(requested: "true", actual: kCFBooleanTrue))
        XCTAssertTrue(setValueMatches(requested: "0", actual: kCFBooleanFalse))
        for value in ["15garbage", "15\n", "NaN", "Infinity", "", ".", "1e", "1.2.3", "1e999999999999999999999999"] {
            XCTAssertFalse(setValueMatches(requested: value, actual: NSNumber(value: 15)))
        }
        XCTAssertFalse(setValueMatches(requested: "9007199254740993", actual: NSNumber(value: Int64(9007199254740992))))
        XCTAssertFalse(setValueMatches(requested: "1." + String(repeating: "0", count: 40) + "1", actual: NSNumber(value: 1)))
        XCTAssertFalse(setValueMatches(requested: "", actual: nil))
    }
    func testDelayedReadRetriesWithoutRewriting() throws {
        var time = 0.0, reads = 0, validations = 0
        let outcome = try verifySetValueReadBack(requested: "new", read: {
            reads += 1
            return .value((time < 0.15 ? "old" : "new") as CFString)
        }, validate: { validations += 1 }, now: { time }, sleep: { time += $0 })
        XCTAssertEqual(outcome, .verified)
        XCTAssertGreaterThan(reads, 1)
        // One validation opens each poll; a match adds the one that guards the return.
        XCTAssertEqual(validations, reads + 1)
        XCTAssertLessThanOrEqual(time, 0.6)
    }
    func testADifferentReadableValueIsMismatched() throws {
        for (actual, described) in [("old" as CFString, "\"old\""), ("NEW" as CFString, "\"NEW\"")] {
            var time = 0.0
            let outcome = try verifySetValueReadBack(requested: "new", read: { .value(actual) }, validate: {}, now: { time }, sleep: { time += $0 })
            XCTAssertEqual(outcome, .mismatched(actual: described))
            XCTAssertEqual(time, 0.6, accuracy: 0.00001)
        }
    }
    func testAnEmptyRequestMatchesAControlThatReportsOnlyWhitespace() {
        XCTAssertTrue(setValueDescribesEmptyText(requested: "", actual: "\n" as CFString))
        XCTAssertTrue(setValueDescribesEmptyText(requested: "  ", actual: "\n\n" as CFString))
        XCTAssertFalse(setValueDescribesEmptyText(requested: "a", actual: "\n" as CFString))
        XCTAssertFalse(setValueDescribesEmptyText(requested: "", actual: " x" as CFString))
        XCTAssertFalse(setValueDescribesEmptyText(requested: "", actual: nil))
        XCTAssertFalse(setValueDescribesEmptyText(requested: "", actual: NSNumber(value: 0)))
    }
    func testClearingAnElectronEditorVerifies() throws {
        var time = 0.0
        let outcome = try verifySetValueReadBack(requested: "", read: { .value("\n" as CFString) }, validate: {}, now: { time }, sleep: { time += $0 })
        XCTAssertEqual(outcome, .verified)
        XCTAssertEqual(time, 0)
    }
    func testAnUnreadableControlIsNeitherConfirmedNorDenied() throws {
        for answer: SetValueReadBack in [.unsupported, .temporarilyUnavailable] {
            var time = 0.0
            let outcome = try verifySetValueReadBack(requested: "new", read: { answer }, validate: {}, now: { time }, sleep: { time += $0 })
            XCTAssertEqual(outcome, .unreadable)
        }
    }
    func testAnUnsupportedAttributeIsNotPolledUntilTheDeadline() throws {
        var time = 0.0
        let outcome = try verifySetValueReadBack(requested: "new", read: { .unsupported }, validate: {}, now: { time }, sleep: { time += $0 })
        XCTAssertEqual(outcome, .unreadable)
        XCTAssertEqual(time, 0)
    }
    func testSessionRevocationAfterReadCannotReturnSuccess() {
        var read = false
        XCTAssertThrowsError(try verifySetValueReadBack(requested: "new", read: { read = true; return .value("new" as CFString) }, validate: {
            if read { throw ComputerUseError.message("revoked") }
        }))
    }
    func testANoteLeadsTheSnapshotText() {
        let result = ToolCallResult.text("tree").prependingText("note")
        XCTAssertEqual(result.textContent, "note\ntree")
        XCTAssertFalse(result.isError)
    }
}
