//
//  SDXFacebookDestination.swift
//  SDXAnalyticsFacebook
//
//  Facebook App Events, behind `AnalyticsDestination`.
//
//  **The app owns SDK start-up.** `ApplicationDelegate.shared.application(_:didFinishLaunchingWithOptions:)`
//  must run from the app delegate, as Facebook requires; this destination only logs through
//  `AppEvents`. It never initialises the SDK.
//
//  **The kill switch is two things, because the SDK has no single one.** The SDK logs its own events
//  (install, app activation) when `FacebookAutoLogAppEventsEnabled` allows, and nothing in `AppEvents`
//  stops a custom `logEvent`. So `setEnabled` flips `Settings.isAutoLogAppEventsEnabled` for the former
//  and gates `track` on a flag for the latter. An app that must stay silent until this destination
//  enables it (a debug build, a user who opted out) sets `FacebookAutoLogAppEventsEnabled` to `NO` in its
//  Info.plist, so the SDK is quiet from the first launch rather than from the first `setEnabled`.
//
//  What Facebook cannot express is left defaulted: user properties (it has a separate `setUserData`
//  with fixed PII fields, which this package never carries), super properties, and screen views.
//

import Foundation
import FacebookCore
import SDXAnalytics
import os

public final class SDXFacebookDestination: AnalyticsDestination, @unchecked Sendable {

    public let name = "facebook"

    private let enabled = OSAllocatedUnfairLock(initialState: false)

    private let conversionEvents: [String: AppEvents.Name]

    /// - Parameter conversionEvents: SDX event name → Facebook standard (conversion) event, e.g.
    ///   `["signup_completed": .completedRegistration, "trial_started": .startTrial]`. A mapped event is
    ///   logged under the standard name so Meta can optimise ads for it, its `value` parameter (if
    ///   numeric) becomes `valueToSum`, and its `currency` parameter becomes `fb_currency`. Unmapped events
    ///   keep their own name. Never map to `.purchased`: purchases go through `trackPurchase`, and a
    ///   second path would count them twice. A free trial is a zero-price purchase that `trackPurchase`
    ///   skips, so map its event to `.startTrial` to get it into Ads Manager.
    public init(conversionEvents: [String: AppEvents.Name] = [:]) {
        precondition(
            !conversionEvents.values.contains(.purchased),
            "Log purchases with SDXAnalyticsClient.purchase, not a .purchased conversion event."
        )
        self.conversionEvents = conversionEvents
    }

    public func configure() throws {
        // Nothing to do: the app has already started the SDK. Fail loudly if it has not, since events
        // logged before `ApplicationDelegate` initialises are silently dropped.
        guard Settings.shared.appID?.isEmpty == false else {
            throw SDXAnalyticsError.missingAPIKey(name)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        let changed = self.enabled.withLock { current -> Bool in
            defer { current = enabled }
            return current != enabled
        }
        Settings.shared.isAutoLogAppEventsEnabled = enabled
        // The SDK logs the install and the first activation from `didBecomeActive`, which has already
        // happened by the time the client enables us. Replay it, once.
        if enabled, changed { AppEvents.shared.activateApp() }
    }

    public func track(_ event: SDXAnalyticsEvent) {
        guard enabled.withLock({ $0 }) else { return }
        guard let standard = conversionEvents[event.name] else {
            AppEvents.shared.logEvent(
                AppEvents.Name(event.name),
                parameters: FacebookParameterMapper.map(event.parameters)
            )
            return
        }
        let parameters = FacebookParameterMapper.conversionParameters(event.parameters)
        if let value = FacebookParameterMapper.conversionValue(event.parameters) {
            AppEvents.shared.logEvent(standard, valueToSum: value, parameters: parameters)
        } else {
            AppEvents.shared.logEvent(standard, parameters: parameters)
        }
    }

    public func setUserID(_ id: String?) {
        AppEvents.shared.userID = id
    }

    public func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        guard enabled.withLock({ $0 }), purchase.carriesRevenue else { return }
        // The **total**, like Firebase; Facebook has no quantity field.
        AppEvents.shared.logPurchase(
            amount: NSDecimalNumber(decimal: purchase.revenue).doubleValue,
            currency: purchase.currencyCode,
            parameters: FacebookParameterMapper.purchaseParameters(purchase)
        )
    }

    public func flush() {
        AppEvents.shared.flush()
    }

    public func reset() {
        AppEvents.shared.userID = nil
        AppEvents.shared.clearUserData()
    }
}
