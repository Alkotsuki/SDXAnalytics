//
//  SDXAnalyticsFixtures.swift
//  SDXAnalyticsTests
//
//  The awkward inputs, in one place.
//
//  Most of these exist because they are exactly at or just past a vendor limit. Naming them once means a
//  test reads as a statement about behaviour rather than as an argument about whether 41 is over 40.
//

import Foundation
import SDXAnalytics

enum SDXAnalyticsFixtures {

    // MARK: - Clients

    /// A client with the validator wide open, for tests that are about fan-out rather than naming.
    static func client(
        destinations: [any AnalyticsDestination],
        validation: SDXAnalyticsConfiguration.ValidationPolicy = .off,
        pendingEventLimit: Int = 100,
        enabledByDefault: Bool = true,
        superProperties: [String: SDXAnalyticsValue] = [:],
        defaults: UserDefaults? = nil
    ) -> SDXAnalyticsClient {
        SDXAnalyticsClient(
            configuration: SDXAnalyticsConfiguration(
                validation: validation,
                pendingEventLimit: pendingEventLimit,
                superProperties: superProperties,
                enabledByDefault: enabledByDefault,
                persistedEnabledKey: "SDXAnalyticsTests.enabled",
                // These suites assert on sanitisation, so the DEBUG trap has to be off or every one
                // of them would trip on the behaviour it is checking.
                assertsOnDiagnostics: false
            ),
            destinations: destinations,
            defaults: defaults ?? isolatedDefaults()
        )
    }

    /// A `UserDefaults` nobody else writes to.
    ///
    /// Every kill-switch test persists a flag, so sharing `.standard` would let one test's opt-out decide
    /// another's starting state depending on the order Swift Testing happened to run them in.
    static func isolatedDefaults(suite: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Events

    static let valid = SDXAnalyticsEvent(
        name: "enhance_completed",
        parameters: ["path": "cloud", "duration_ms": 1840, "did_fall_back": false]
    )

    /// 45 characters — five past Firebase's limit.
    static let overlongName = "enhance_completed_with_local_adjustments_xxxx"

    static let leadingDigitName = "3rd_enhance_attempt"

    static let reservedName = "firebase_enhance_completed"

    static let punctuatedName = "enhance-completed.v2"

    /// 30 parameters, five past the 25 Firebase accepts.
    static var overstuffed: SDXAnalyticsEvent {
        var parameters: [String: SDXAnalyticsValue] = [:]
        for index in 0..<30 {
            parameters[String(format: "p%02d", index)] = .int(index)
        }
        return SDXAnalyticsEvent(name: "overstuffed", parameters: parameters)
    }

    /// 200 characters — twice the parameter-value limit.
    static let longText = String(repeating: "a", count: 200)

    // MARK: - Purchases

    static let pack = SDXAnalyticsPurchase(
        productID: "com.sdx.Evoke.pack.30",
        price: Decimal(string: "4.99")!,
        currencyCode: "USD",
        quantity: 3,
        transactionID: "2000000123456789",
        revenueType: "pack"
    )

    /// What a free-trial start looks like: a real product at no charge.
    static let trial = SDXAnalyticsPurchase(
        productID: "com.sdx.Evoke.sub.annual.3daytrial",
        price: .zero,
        currencyCode: "USD",
        revenueType: "subscription"
    )
}
