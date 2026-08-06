//
//  SDXFirebaseDestination.swift
//  SDXAnalyticsFirebase
//
//  Firebase Analytics, behind `AnalyticsDestination`.
//
//  This target links `FirebaseAnalyticsCore`, not `FirebaseAnalytics`. Both vend the same
//  `FirebaseAnalytics` module, so the source below would be identical either way — which is precisely
//  why the choice is worth stating here as well as in the manifest, because it is invisible in code and
//  only surfaces in App Store review. Since Firebase 12 the plain product links the full
//  GoogleAppMeasurement, which contains IDFA collection and would oblige every app adopting this package
//  to declare tracking whether it ever prompts or not. An app that wants the ad identifier adds
//  Firebase's own additive `FirebaseAnalyticsIdentitySupport` product to its target; nothing here changes,
//  and `setAdvertisingIdentifier` stays a no-op because Firebase collects it itself.
//
//  Two things about Firebase that reliably surprise people, recorded here because this is where someone
//  will look:
//
//  There is **no flush API**. `flush()` is a documented no-op rather than a fake; Firebase batches on its
//  own schedule and there is nothing to call.
//
//  `IS_ANALYTICS_ENABLED` in `GoogleService-Info.plist` is a **dead key** — the string does not appear in
//  the shipping GoogleAppMeasurement binary at all. The keys the SDK actually reads are
//  `FIREBASE_ANALYTICS_COLLECTION_ENABLED` and `FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED`, and both live
//  in the app's **Info.plist**. Never build a kill switch on the `_DEACTIVATED` one: it is permanent for
//  the install and `setAnalyticsCollectionEnabled(true)` cannot undo it.
//

import Foundation
import FirebaseAnalytics
import FirebaseCore
import SDXAnalytics
import os

public struct SDXFirebaseOptions: Sendable, Hashable {

    /// Who is responsible for `FirebaseApp.configure()`.
    public enum AppOwnership: String, Sendable, Hashable {
        /// The app configures Firebase itself, and this destination refuses to come up if it has not.
        ///
        /// Correct for an app using several Firebase products, where the order of `configure()` relative
        /// to Crashlytics, Remote Config or Messaging matters and must not be decided by whichever
        /// analytics destination happened to initialise first. A clear error at start-up beats events
        /// that silently go nowhere.
        case app
        /// Configure only when nobody else has. The default: no boilerplate for an analytics-only app,
        /// and harmless for one that configured first.
        case ifNeeded
    }

    public let appOwnership: AppOwnership
    public let sessionTimeout: TimeInterval?

    public init(appOwnership: AppOwnership = .ifNeeded, sessionTimeout: TimeInterval? = nil) {
        self.appOwnership = appOwnership
        self.sessionTimeout = sessionTimeout
    }
}

public final class SDXFirebaseDestination: AnalyticsDestination, @unchecked Sendable {

    public let name = "firebase"

    private let options: SDXFirebaseOptions
    private let logger = Logger(subsystem: "SDXAnalytics", category: "firebase")

    public init(options: SDXFirebaseOptions = SDXFirebaseOptions()) {
        self.options = options
    }

    public func configure() throws {
        switch options.appOwnership {
        case .app:
            guard FirebaseApp.app() != nil else {
                throw SDXAnalyticsError.firebaseAppNotConfigured(name)
            }
        case .ifNeeded:
            if FirebaseApp.app() == nil {
                // Fails loudly if `GoogleService-Info.plist` is not in the app bundle, which is the
                // single most common way this integration is broken — a synchronized Xcode group can
                // exclude the file from the target without anything visibly changing.
                FirebaseApp.configure()
            }
        }

        if let timeout = options.sessionTimeout {
            Analytics.setSessionTimeoutInterval(timeout)
        }
    }

    public func track(_ event: SDXAnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: FirebaseParameterMapper.map(event.parameters))
    }

    public func setEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    public func setUserID(_ id: String?) {
        Analytics.setUserID(id)
    }

    public func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        switch property.mutation {
        case .set(let value), .setOnce(let value):
            // Firebase has no set-once, so `.setOnce` overwrites. Reported rather than silently
            // downgraded — a caller that asked for set-once had a reason.
            if case .setOnce = property.mutation {
                logger.notice(
                    "Firebase has no set-once user property; \(property.name, privacy: .public) was overwritten."
                )
            }
            Analytics.setUserProperty(value.stringValue, forName: property.name)
        case .increment(let amount):
            // No atomic increment exists at all. Skipped rather than turned into a `set`, which would
            // replace the running total with a delta and corrupt the property permanently.
            logger.notice(
                "Firebase has no incrementable user property; skipped \(property.name, privacy: .public) += \(amount, privacy: .public)."
            )
        case .unset:
            Analytics.setUserProperty(nil, forName: property.name)
        }
    }

    public func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        Analytics.setDefaultEventParameters(
            parameters.isEmpty ? nil : FirebaseParameterMapper.map(parameters)
        )
    }

    public func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        // `AnalyticsParameterValue` is the **total**. Amplitude wants the unit price and multiplies
        // itself; `SDXAnalyticsPurchase.revenue` exists so the two cannot drift apart.
        var parameters: [String: Any] = [
            AnalyticsParameterValue: NSDecimalNumber(decimal: purchase.revenue).doubleValue,
            AnalyticsParameterCurrency: purchase.currencyCode,
            AnalyticsParameterItems: [
                [
                    AnalyticsParameterItemID: purchase.productID,
                    AnalyticsParameterPrice: NSDecimalNumber(decimal: purchase.price).doubleValue,
                    AnalyticsParameterQuantity: purchase.quantity,
                ]
            ],
        ]

        if let transactionID = purchase.transactionID {
            parameters[AnalyticsParameterTransactionID] = transactionID
        }

        for (key, value) in FirebaseParameterMapper.map(purchase.parameters) {
            parameters[key] = value
        }

        Analytics.logEvent(AnalyticsEventPurchase, parameters: parameters)
    }

    public func trackScreen(name screenName: String, class className: String?) {
        Analytics.logEvent(
            AnalyticsEventScreenView,
            parameters: [
                AnalyticsParameterScreenName: screenName,
                AnalyticsParameterScreenClass: className ?? "View",
            ]
        )
    }

    public func flush() {
        // Firebase Analytics has no flush API. Left empty on purpose.
    }

    public func reset() {
        Analytics.resetAnalyticsData()
    }
}
