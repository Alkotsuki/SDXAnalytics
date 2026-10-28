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

    /// The numeric `value` parameter of a conversion event, for Facebook's `valueToSum`.
    static func conversionValue(_ values: [String: SDXAnalyticsValue]) -> Double? {
        switch values["value"] {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    /// A conversion event's parameters, with a string `currency` also sent as `fb_currency` — without it
    /// Meta mis-buckets the value and cannot de-duplicate against the SDK's automatic IAP events.
    static func conversionParameters(_ values: [String: SDXAnalyticsValue]) -> [AppEvents.ParameterName: Any] {
        var parameters = map(values)
        if case .string(let currency) = values["currency"] {
            parameters[.currency] = currency
        }
        return parameters
    }

    /// A purchase's parameters plus the keys the SDK de-duplicates on. With auto-logging on, the SDK logs
    /// every StoreKit purchase itself; it drops our manual copy only if it can match `fb_content_id` or
    /// `fb_transaction_id`. Without them, Ads Manager counts each purchase twice.
    static func purchaseParameters(_ purchase: SDXAnalyticsPurchase) -> [AppEvents.ParameterName: Any] {
        var parameters = map(purchase.parameters)
        parameters[.contentID] = purchase.productID
        if let transactionID = purchase.transactionID {
            parameters[.transactionID] = transactionID
        }
        return parameters
    }
}
