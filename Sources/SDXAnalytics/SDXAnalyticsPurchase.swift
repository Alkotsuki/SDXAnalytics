//
//  SDXAnalyticsPurchase.swift
//  SDXAnalytics
//
//  One purchase, in the shape both vendors need.
//
//  A purchase is not just another event. Both dashboards have a dedicated revenue path with its own
//  reporting — Amplitude's `Revenue` object feeds LTV and ARPU charts, Firebase's `purchase` event
//  feeds its monetisation reports — and an app that logs `purchase_completed` as an ordinary event
//  gets neither. So this is a separate type carried through a separate destination method.
//
//  It exists mostly to hold one disagreement in one place: **Amplitude wants the unit price and
//  multiplies by quantity itself, Firebase wants the total.** Every implementation of this that
//  computes the total per-destination eventually gets one of them wrong by a factor of the
//  quantity, and a revenue chart that is wrong by a factor is worse than no revenue chart.
//

import Foundation

public struct SDXAnalyticsPurchase: Sendable, Hashable {

    public let productID: String
    /// The **unit** price, before quantity. `Decimal` so a StoreKit `Product.price` drops straight
    /// in without a lossy `Double` round trip.
    public let price: Decimal
    /// ISO 4217, e.g. `"USD"`. Both vendors reject or mis-bucket revenue without it.
    public let currencyCode: String
    public let quantity: Int
    /// Passed to each vendor's own de-duplication, never emitted as an ordinary event parameter —
    /// a transaction identifier is not analytics.
    public let transactionID: String?
    /// Amplitude's `$revenueType` — "subscription", "pack", and so on. Ignored by Firebase.
    public let revenueType: String?
    public let parameters: [String: SDXAnalyticsValue]

    public init(
        productID: String,
        price: Decimal,
        currencyCode: String,
        quantity: Int = 1,
        transactionID: String? = nil,
        revenueType: String? = nil,
        parameters: [String: SDXAnalyticsValue] = [:]
    ) {
        self.productID = productID
        self.price = price
        self.currencyCode = currencyCode
        self.quantity = quantity
        self.transactionID = transactionID
        self.revenueType = revenueType
        self.parameters = parameters
    }

    /// `price × quantity`.
    ///
    /// Computed here rather than in either destination because the two vendors want different
    /// numbers from the same purchase: Amplitude takes `price` as the unit price and multiplies,
    /// Firebase takes this total. One property means they cannot disagree.
    public var revenue: Decimal {
        price * Decimal(quantity)
    }

    /// Whether a vendor that requires a non-zero price will accept this.
    ///
    /// Amplitude's `Revenue.isValid()` refuses a nil price, so a zero-price purchase — which is
    /// what a free-trial start looks like — is dropped there. Exposed so the mapping can log the
    /// drop rather than letting a trial silently vanish from the funnel.
    public var carriesRevenue: Bool {
        price != .zero
    }
}
