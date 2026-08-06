//
//  FirebaseParameterMapper.swift
//  SDXAnalyticsFirebase
//
//  `SDXAnalyticsValue` → the `[String: Any]` Firebase's API takes.
//
//  A pure function, split out from the destination so it can be tested without a `GoogleService-Info.plist`,
//  without a network and without `FirebaseApp.configure()` — which is a global, one-shot,
//  process-wide side effect and therefore the last thing a unit test should be doing.
//
//  `FIRAnalytics.h` is explicit that only `String`, `Int` (as `NSNumber`) and `Double` parameter types
//  are supported. A Swift `Bool` bridges to `NSNumber` and would technically arrive, but as an untyped
//  value that Firebase's reporting cannot aggregate — so it is flattened to `1`/`0`, and Amplitude
//  flattens it the same way so the two dashboards agree.
//

import Foundation
import SDXAnalytics

enum FirebaseParameterMapper {

    static func map(_ values: [String: SDXAnalyticsValue]) -> [String: Any] {
        values.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = value(pair.value)
        }
    }

    static func value(_ value: SDXAnalyticsValue) -> Any {
        switch value {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value ? 1 : 0
        }
    }
}
