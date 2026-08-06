//
//  AnalyticsDestination.swift
//  SDXAnalytics
//
//  The seam. Everything above this protocol is testable without a vendor.
//
//  This is the `StoreKitFacade` of this package, and it is bare-named for the same reason: it is a
//  seam rather than a value, and the `SDX` prefix is reserved for the types that cross an app's
//  boundary as data.
//
//  Only `configure`, `track` and `setEnabled` have to be implemented. Everything else defaults to a
//  no-op, so adding Mixpanel, PostHog or AppsFlyer later means writing the three or four methods that
//  vendor actually has rather than stubbing out eleven. A destination that cannot express something
//  should leave it defaulted and say so in its own documentation — the alternative is a mapping that
//  pretends, and a dashboard that quietly disagrees with its neighbour.
//
//  Implementations are `Sendable` and are called from whatever thread the app logged from. Every
//  vendor SDK here is internally thread-safe; a destination that wrapped something which was not
//  would be responsible for its own serialisation.
//

import Foundation

public protocol AnalyticsDestination: Sendable {

    /// For logs and diagnostics. Stable, lowercase, one word.
    var name: String { get }

    /// Bring the vendor up. Called exactly once, from `SDXAnalyticsClient.configure()`.
    ///
    /// Throwing takes this destination out of the fan-out for the lifetime of the process and is
    /// logged. It never propagates to the app: one vendor with a bad key must not silence the other.
    func configure() throws

    func track(_ event: SDXAnalyticsEvent)

    /// The kill switch. Also called once during `configure()` with the persisted value, before any
    /// event is sent, so a user who opted out in a previous launch never emits.
    func setEnabled(_ enabled: Bool)

    func setUserID(_ id: String?)
    func setUserProperty(_ property: SDXAnalyticsUserProperty)

    /// Merged into every subsequent event by the vendor itself where it can be
    /// (`setDefaultEventParameters`, an enrichment plugin), so that autocaptured events carry them
    /// too — which is something the client cannot do from outside.
    func setSuperProperties(_ parameters: [String: SDXAnalyticsValue])

    func trackPurchase(_ purchase: SDXAnalyticsPurchase)
    func trackScreen(name: String, class className: String?)

    /// The IDFA, or nil when the app has no authorisation for one.
    ///
    /// The app decides whether and when to ask; see `SDXAdvertisingIdentifier`. A destination that
    /// collects no advertising identifier leaves this defaulted.
    func setAdvertisingIdentifier(_ idfa: String?)

    func flush()

    /// Forget the current device/user association. For a sign-out, or a debug menu.
    func reset()
}

public extension AnalyticsDestination {
    func setUserID(_ id: String?) {}
    func setUserProperty(_ property: SDXAnalyticsUserProperty) {}
    func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {}
    func trackPurchase(_ purchase: SDXAnalyticsPurchase) {}
    func trackScreen(name: String, class className: String?) {}
    func setAdvertisingIdentifier(_ idfa: String?) {}
    func flush() {}
    func reset() {}
}
