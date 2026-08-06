//
//  AmplitudeRevenueMapper.swift
//  SDXAnalyticsAmplitude
//
//  `SDXAnalyticsPurchase` → Amplitude's `Revenue`, and `SDXAnalyticsValue` → the `[String: Any]` its
//  API takes.
//
//  Split out as pure functions so both mappings are unit-testable without configuring the SDK, without
//  an API key and without a network. The `SDXAnalyticsClient` fan-out can be tested with a fake
//  destination, but the translation *into* a vendor's vocabulary is where the interesting mistakes live
//  — which price goes in which field, how a boolean is flattened — and that is exactly the part a fake
//  cannot cover.
//

import Foundation
import AmplitudeSwift
import SDXAnalytics

enum AmplitudeRevenueMapper {

    /// Builds Amplitude's revenue object.
    ///
    /// Note which price goes where: Amplitude takes the **unit** price in `price` and multiplies by
    /// `quantity` itself. Firebase wants the total. Handing Amplitude the total alongside a quantity
    /// greater than one would overstate revenue by a factor of the quantity, and it is the sort of
    /// mistake that looks like growth.
    static func map(_ purchase: SDXAnalyticsPurchase) -> Revenue {
        let revenue = Revenue()
        revenue.productId = purchase.productID
        revenue.price = NSDecimalNumber(decimal: purchase.price).doubleValue
        revenue.quantity = purchase.quantity
        revenue.currency = purchase.currencyCode
        revenue.revenueType = purchase.revenueType
        if !purchase.parameters.isEmpty {
            revenue.properties = parameters(purchase.parameters)
        }
        return revenue
    }

    /// `.bool` becomes `1`/`0` rather than a Swift `Bool`.
    ///
    /// Not because Amplitude cannot carry a boolean — it can — but because Firebase cannot, and the
    /// point of this package is that the two dashboards show the same thing. A property that read
    /// `true` on one and `1` on the other would need translating in every query that touched it.
    static func parameters(_ values: [String: SDXAnalyticsValue]) -> [String: Any] {
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

    /// Which of Amplitude's four identify operations a mutation becomes.
    ///
    /// Named separately from `identify(_:)` because `Identify` keeps its accumulated operations
    /// `internal`, so the choice is otherwise unobservable from outside the SDK — and the choice is the
    /// part worth testing. Amplitude can express all four; Firebase can express two.
    enum Operation: String, Hashable {
        case set
        case setOnce
        case add
        case unset
    }

    static func operation(for mutation: SDXAnalyticsUserProperty.Mutation) -> Operation {
        switch mutation {
        case .set: .set
        case .setOnce: .setOnce
        case .increment: .add
        case .unset: .unset
        }
    }

    static func identify(_ property: SDXAnalyticsUserProperty) -> Identify {
        let identify = Identify()
        switch property.mutation {
        case .set(let wrapped):
            identify.set(property: property.name, value: value(wrapped))
        case .setOnce(let wrapped):
            identify.setOnce(property: property.name, value: value(wrapped))
        case .increment(let amount):
            identify.add(property: property.name, value: amount)
        case .unset:
            identify.unset(property: property.name)
        }
        return identify
    }
}
