//
//  SDXConsoleDestination.swift
//  SDXAnalytics
//
//  Every call, written to the unified log instead of to a vendor.
//
//  This is what a DEBUG build should install. Pointing a debug build at the real dashboards fills them
//  with simulator and UI-test traffic that is indistinguishable from real users, and the thing a
//  developer actually needs while instrumenting is to see the name and the parameters of what they just
//  fired — which is this, immediately, with no network and no dashboard latency.
//
//  Parameters are logged `.public`. That is a deliberate exception to the usual rule, and it is safe
//  only because of the rule that governs what may be an analytics parameter in the first place: an
//  event carrying anything personal is a bug in the taxonomy, not something to paper over with a
//  privacy annotation here. Seeing the values is the entire point of this destination.
//

import Foundation
import os

public final class SDXConsoleDestination: AnalyticsDestination {

    public let name = "console"

    private let logger: Logger

    public init(subsystem: String = "SDXAnalytics", category: String = "console") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func configure() throws {
        logger.info("configured")
    }

    public func track(_ event: SDXAnalyticsEvent) {
        logger.info("\(event.name, privacy: .public) \(Self.describe(event.parameters), privacy: .public)")
    }

    public func setEnabled(_ enabled: Bool) {
        logger.info("collection \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    public func setUserID(_ id: String?) {
        // The one value here that could be personal, so the one that is not `.public`.
        logger.info("user id \(id ?? "nil", privacy: .private)")
    }

    public func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        logger.info(
            "user property \(property.name, privacy: .public) \(Self.describe(property.mutation), privacy: .public)"
        )
    }

    public func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        logger.info("super properties \(Self.describe(parameters), privacy: .public)")
    }

    public func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        logger.info(
            "purchase \(purchase.productID, privacy: .public) \(purchase.revenue.description, privacy: .public) \(purchase.currencyCode, privacy: .public) ×\(purchase.quantity, privacy: .public)"
        )
    }

    public func trackScreen(name screenName: String, class className: String?) {
        logger.info("screen \(screenName, privacy: .public) \(className ?? "", privacy: .public)")
    }

    public func setAdvertisingIdentifier(_ idfa: String?) {
        logger.info("advertising identifier \(idfa == nil ? "cleared" : "set", privacy: .public)")
    }

    public func flush() {
        logger.info("flush")
    }

    public func reset() {
        logger.info("reset")
    }

    // MARK: - Private

    /// Sorted, so two runs of the same flow produce diffable log output.
    private static func describe(_ parameters: [String: SDXAnalyticsValue]) -> String {
        guard !parameters.isEmpty else { return "{}" }
        let body = parameters.keys.sorted()
            .compactMap { key in parameters[key].map { "\(key)=\($0.stringValue)" } }
            .joined(separator: " ")
        return "{ \(body) }"
    }

    private static func describe(_ mutation: SDXAnalyticsUserProperty.Mutation) -> String {
        switch mutation {
        case .set(let value): "set \(value.stringValue)"
        case .setOnce(let value): "setOnce \(value.stringValue)"
        case .increment(let amount): "increment \(amount)"
        case .unset: "unset"
        }
    }
}
