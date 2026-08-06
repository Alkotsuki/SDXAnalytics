//
//  SDXAnalyticsValue.swift
//  SDXAnalytics
//
//  The closed set of types an event parameter or a user property may hold.
//
//  Four cases and no `Any`. Every analytics vendor accepts a slightly different set of scalars and
//  silently mangles the rest, so the only way two dashboards can be compared is to narrow to the
//  intersection here and translate once per destination. Firebase's own header is explicit that it
//  supports `String`, `Int` and `Double`; `bool` is carried as a distinct case rather than folded
//  into `int` at the call site so that a destination which *can* express a boolean keeps the type,
//  and the two that cannot both flatten it the same way.
//
//  There is deliberately no `date` and no `array`. A date is a formatting decision that belongs to
//  the caller, and an array parameter is unrepresentable in Firebase — offering either would let a
//  call site write something that arrives on one dashboard and not the other.
//

import Foundation

public enum SDXAnalyticsValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

// MARK: - Literals

// Purely so instrumentation call sites read as data rather than as construction:
//
//     ["path": "cloud", "duration_ms": 1840, "did_fall_back": true]
//
// rather than `.string("cloud")`, `.int(1840)`, `.bool(true)`. With sixty-odd events across an app
// that difference is the difference between a readable taxonomy file and a wall of ceremony.

extension SDXAnalyticsValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension SDXAnalyticsValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension SDXAnalyticsValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension SDXAnalyticsValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: - Rendering

extension SDXAnalyticsValue {

    /// The value as a string, for destinations that accept nothing else.
    ///
    /// Firebase's user properties are string-only, so this is not a debugging convenience — it is
    /// the wire format for half of one destination. `bool` renders as `"1"`/`"0"` rather than
    /// `"true"`/`"false"` to match how `bool` is flattened for event parameters; a dashboard that
    /// showed `1` in one place and `true` in another would be reporting on two different things.
    public var stringValue: String {
        switch self {
        case .string(let value):
            value
        case .int(let value):
            String(value)
        case .double(let value):
            String(value)
        case .bool(let value):
            value ? "1" : "0"
        }
    }

    /// The number of characters this value occupies on the wire, for the validator's length limits.
    var characterCount: Int {
        switch self {
        case .string(let value):
            value.count
        default:
            // Numbers and booleans cannot approach any vendor's limit, and measuring them would
            // mean formatting them twice.
            0
        }
    }

    /// The same value with any string clamped to `limit` characters.
    func clamped(to limit: Int) -> SDXAnalyticsValue {
        guard case .string(let value) = self, value.count > limit else { return self }
        return .string(String(value.prefix(limit)))
    }
}
