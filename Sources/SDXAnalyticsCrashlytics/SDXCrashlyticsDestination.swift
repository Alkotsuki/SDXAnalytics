//
//  SDXCrashlyticsDestination.swift
//  SDXAnalyticsCrashlytics
//
//  Firebase Crashlytics, behind `AnalyticsDestination`.
//
//  Crashlytics has no event log and no dashboard — it has a crash report, and what this destination
//  sends is context for the *next* one: `track` becomes a breadcrumb (`log`), `setUserID` and
//  `setUserProperty` become the identifiers Crashlytics attaches to a report. `trackPurchase` and
//  `trackScreen` are left at the protocol's no-op default: a screen view or a purchase is not a crash
//  breadcrumb, and logging one on every screen would drown the breadcrumbs that actually matter in the
//  90-second window Crashlytics keeps before a crash.
//
//  Shares `SDXFirebaseOptions.AppOwnership` with `SDXAnalyticsFirebase` rather than declaring its own
//  copy — an app almost always links both, and "who calls `FirebaseApp.configure()`" is one decision,
//  not two that could disagree.
//

import Foundation
import FirebaseCore
import FirebaseCrashlytics
import SDXAnalytics
import SDXAnalyticsFirebase
import os

public struct SDXCrashlyticsOptions: Sendable, Hashable {
    public let appOwnership: SDXFirebaseOptions.AppOwnership

    public init(appOwnership: SDXFirebaseOptions.AppOwnership = .ifNeeded) {
        self.appOwnership = appOwnership
    }
}

public final class SDXCrashlyticsDestination: AnalyticsDestination, @unchecked Sendable {

    public let name = "crashlytics"

    private let options: SDXCrashlyticsOptions
    private let logger = Logger(subsystem: "SDXAnalytics", category: "crashlytics")

    public init(options: SDXCrashlyticsOptions = SDXCrashlyticsOptions()) {
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
                FirebaseApp.configure()
            }
        }
    }

    public func track(_ event: SDXAnalyticsEvent) {
        Crashlytics.crashlytics().log(breadcrumb(for: event))
    }

    public func setEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    public func setUserID(_ id: String?) {
        Crashlytics.crashlytics().setUserID(id ?? "")
    }

    public func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        switch property.mutation {
        case .set(let value), .setOnce(let value):
            if case .setOnce = property.mutation {
                logger.notice(
                    "Crashlytics has no set-once custom key; \(property.name, privacy: .public) was overwritten."
                )
            }
            Crashlytics.crashlytics().setCustomValue(rawValue(of: value), forKey: property.name)
        case .increment(let amount):
            logger.notice(
                "Crashlytics has no incrementable custom key; skipped \(property.name, privacy: .public) += \(amount, privacy: .public)."
            )
        case .unset:
            // No removal API. The key is left with its last value rather than corrupted with a
            // placeholder that would be indistinguishable from real data on a crash report.
            logger.notice("Crashlytics has no custom-key removal; \(property.name, privacy: .public) was left as is.")
        }
    }

    public func reset() {
        Crashlytics.crashlytics().setUserID("")
    }

    private func rawValue(of value: SDXAnalyticsValue) -> Any {
        switch value {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value ? 1 : 0
        }
    }

    private func breadcrumb(for event: SDXAnalyticsEvent) -> String {
        guard !event.parameters.isEmpty else { return event.name }
        let parameters = event.parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.stringValue)" }
            .joined(separator: " ")
        return "\(event.name) \(parameters)"
    }
}
