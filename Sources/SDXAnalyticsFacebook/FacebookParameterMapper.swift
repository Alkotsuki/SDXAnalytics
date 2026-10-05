//
//  FacebookParameterMapper.swift
//  SDXAnalyticsFacebook
//
//  `SDXAnalyticsValue` → the `[AppEvents.ParameterName: Any]` the Facebook SDK takes.
//
//  Pure, so it is testable without the SDK being initialised. `.bool` becomes `1`/`0` for the same
//  reason as in the other destinations: the dashboards must show the same thing.
//

import Foundation
import FacebookCore
import SDXAnalytics

enum FacebookParameterMapper {

    static func map(_ values: [String: SDXAnalyticsValue]) -> [AppEvents.ParameterName: Any] {
        values.reduce(into: [:]) { result, pair in
            result[AppEvents.ParameterName(pair.key)] = value(pair.value)
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
