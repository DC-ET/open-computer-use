import Foundation

/// What the accessibility layer answered when asked for the value we just wrote.
enum SetValueReadBack {
    /// A readable value came back; compare it against the request.
    case value(CFTypeRef)
    /// The read failed in a way that may settle, so keep polling until the deadline.
    case temporarilyUnavailable
    /// AX says this element has no such value at all. Polling longer cannot help.
    case unsupported
}

/// Outcome of checking a write against the control's own value.
enum SetValueVerification: Equatable {
    case verified
    /// The control reports a readable value and it differs from the request.
    /// The payload describes what came back, so a caller can tell a normalized
    /// value from an entirely unexpected one.
    case mismatched(actual: String?)
    /// No readable value exists, so the write can be neither confirmed nor denied.
    case unreadable
}

/// Render a value for an error message without dumping an entire document.
func describeSetValue(_ value: CFTypeRef) -> String {
    if CFGetTypeID(value) == CFStringGetTypeID(), let text = value as? String {
        return "\"\(text.count <= 80 ? text : String(text.prefix(80)) + "…")\""
    }
    if CFGetTypeID(value) == CFBooleanGetTypeID(), let number = value as? NSNumber {
        return number.boolValue ? "true" : "false"
    }
    if CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber {
        return number.stringValue
    }
    return "a value of CFTypeID \(CFGetTypeID(value))"
}

/// Text stays literal. Numeric/boolean coercion is allowed only when AX itself
/// returns that type, never merely because a text field looks like a number.
func setValueMatches(requested: String, actual: CFTypeRef?) -> Bool {
    guard let actual else { return false }
    if CFGetTypeID(actual) == CFStringGetTypeID(), let text = actual as? String {
        return requested.utf16.elementsEqual(text.utf16)
    }
    if CFGetTypeID(actual) == CFBooleanGetTypeID() {
        let literal = requested.lowercased()
        let expected: Bool?
        switch literal {
        case "true", "1": expected = true
        case "false", "0": expected = false
        default: expected = nil
        }
        return expected == CFBooleanGetValue((actual as! CFBoolean))
    }
    if CFGetTypeID(actual) == CFNumberGetTypeID(), let number = actual as? NSNumber {
        guard let expected = normalizedSetValueNumber(requested), let observed = normalizedSetValueNumber(number.stringValue) else { return false }
        return expected == observed
    }
    return false
}

private struct SetValueNumber: Equatable {
    let negative: Bool
    let digits: String
    let exponent: Int
}

/// Normalize decimal spelling without rounding through Double or Decimal.
/// This preserves large integers and the full exponent range of AX numbers.
private func normalizedSetValueNumber(_ text: String) -> SetValueNumber? {
    let parts = text.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    guard let first = parts.first, parts.count <= 2 else { return nil }
    var mantissa = String(first)
    let negative = mantissa.first == "-"
    if mantissa.first == "-" || mantissa.first == "+" { mantissa.removeFirst() }
    let decimal = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    guard decimal.count <= 2 else { return nil }
    let digits = decimal.joined()
    guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
    let explicitExponent: Int
    if parts.count == 2 {
        guard let value = Int(parts[1]) else { return nil }
        explicitExponent = value
    } else { explicitExponent = 0 }
    let fractionCount = decimal.count == 2 ? decimal[1].count : 0
    let (exponent, overflow) = explicitExponent.subtractingReportingOverflow(fractionCount)
    guard !overflow else { return nil }
    var significant = String(digits.drop(while: { $0 == "0" }))
    if significant.isEmpty { return .init(negative: false, digits: "0", exponent: 0) }
    var trailing = 0
    while significant.last == "0" { significant.removeLast(); trailing += 1 }
    let (adjusted, adjustmentOverflow) = exponent.addingReportingOverflow(trailing)
    guard !adjustmentOverflow else { return nil }
    return .init(negative: negative, digits: significant, exponent: adjusted)
}

/// A control that holds nothing may still report a placeholder newline:
/// Chromium's contenteditable answers "\n" for an empty editor. Treat "no text"
/// and "only whitespace" as the same empty value so clearing a field verifies.
func setValueDescribesEmptyText(requested: String, actual: CFTypeRef?) -> Bool {
    guard requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let actual,
          CFGetTypeID(actual) == CFStringGetTypeID(),
          let text = actual as? String else { return false }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Poll the control's own value after a write.
///
/// A mismatch is a real failure and must be reported. An unreadable value is not:
/// Electron contenteditable fields, for example, accept the write but expose no
/// AXValue, and calling that a failure invites an agent to write a second time.
func verifySetValueReadBack(
    requested: String,
    read: () -> SetValueReadBack,
    validate: () throws -> Void,
    now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
) throws -> SetValueVerification {
    let deadline = now() + 0.6
    var sawReadableValue = false
    var lastActual: String?
    while true {
        try validate()
        switch read() {
        case .value(let actual):
            sawReadableValue = true
            lastActual = describeSetValue(actual)
            if setValueMatches(requested: requested, actual: actual) || setValueDescribesEmptyText(requested: requested, actual: actual) {
                try validate()
                return .verified
            }
        case .unsupported:
            return .unreadable
        case .temporarilyUnavailable:
            break
        }
        let remaining = deadline - now()
        guard remaining > 0 else {
            return sawReadableValue ? .mismatched(actual: lastActual) : .unreadable
        }
        sleep(min(0.05, remaining))
    }
}
