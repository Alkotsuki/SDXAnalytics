//
//  DestinationMappingTests.swift
//  SDXAnalyticsTests
//
//  The vendor translations, as pure functions.
//
//  Nothing here configures Firebase or Amplitude. `FirebaseApp.configure()` is a process-wide one-shot
//  side effect and an `Amplitude` instance opens storage and a network client, so neither belongs in a
//  unit test. The mappers were split out of the destinations precisely so the interesting part — which
//  price goes in which field, how a boolean is flattened, what happens to a mutation a vendor cannot
//  express — is reachable without either.
//

import Foundation
import Testing
@testable import SDXAnalytics
@testable import SDXAnalyticsAmplitude
@testable import SDXAnalyticsFirebase

struct PurchaseMappingTests {

    @Test func revenueIsUnitPriceTimesQuantity() {
        #expect(SDXAnalyticsFixtures.pack.revenue == Decimal(string: "14.97")!)
    }

    @Test func amplitudeReceivesTheUnitPriceBesideTheQuantity() {
        // Amplitude multiplies for itself. Handing it the total alongside a quantity greater than one
        // would overstate revenue by a factor of the quantity — which looks like growth.
        let revenue = AmplitudeRevenueMapper.map(SDXAnalyticsFixtures.pack)
        #expect(revenue.price == 4.99)
        #expect(revenue.quantity == 3)
        #expect(revenue.productId == "com.sdx.Evoke.pack.30")
        #expect(revenue.currency == "USD")
        #expect(revenue.revenueType == "pack")
    }

    @Test func firebaseAndAmplitudeDisagreeAboutWhichPriceTheyWant() {
        // Stated as a test because it is the single most likely thing for someone to "tidy up" into one
        // shared number, and the bug would be invisible for any purchase of quantity 1.
        let purchase = SDXAnalyticsFixtures.pack
        let amplitudePrice = AmplitudeRevenueMapper.map(purchase).price
        let firebaseValue = NSDecimalNumber(decimal: purchase.revenue).doubleValue

        #expect(amplitudePrice == 4.99)
        // Compared with a tolerance rather than for equality: Firebase's API takes a `Double`, and
        // 14.97 has no exact binary representation. This is also the reason `price` is a `Decimal`
        // everywhere above the vendor boundary — the lossy step happens once, here, at the edge.
        #expect(abs(firebaseValue - 14.97) < 0.0001)
        #expect(purchase.revenue == Decimal(string: "14.97")!)
    }

    @Test func aZeroPricePurchaseIsFlaggedRatherThanSilentlySwallowed() {
        // Amplitude's `Revenue.isValid()` requires a non-nil price, so a trial start is dropped there.
        // `carriesRevenue` is what lets the destination log that instead of losing it.
        #expect(SDXAnalyticsFixtures.trial.carriesRevenue == false)
        #expect(SDXAnalyticsFixtures.pack.carriesRevenue)
    }
}

struct ParameterMappingTests {

    @Test func bothVendorsFlattenBooleansTheSameWay() {
        // Firebase supports only String, Int and Double, so a real Bool would arrive as a value its
        // reporting cannot aggregate. Amplitude could carry one — and deliberately does not, because a
        // property reading `true` on one dashboard and `1` on the other needs translating in every
        // query that touches it.
        #expect(FirebaseParameterMapper.value(.bool(true)) as? Int == 1)
        #expect(FirebaseParameterMapper.value(.bool(false)) as? Int == 0)
        #expect(AmplitudeRevenueMapper.value(.bool(true)) as? Int == 1)
        #expect(AmplitudeRevenueMapper.value(.bool(false)) as? Int == 0)
    }

    @Test func scalarsSurviveWithTheirTypes() {
        #expect(FirebaseParameterMapper.value(.string("cloud")) as? String == "cloud")
        #expect(FirebaseParameterMapper.value(.int(42)) as? Int == 42)
        #expect(FirebaseParameterMapper.value(.double(1.5)) as? Double == 1.5)
    }

    @Test func everyKeySurvivesTheMapping() {
        let mapped = FirebaseParameterMapper.map(SDXAnalyticsFixtures.valid.parameters)
        #expect(Set(mapped.keys) == Set(SDXAnalyticsFixtures.valid.parameters.keys))
    }
}

struct UserPropertyMappingTests {

    @Test func amplitudeMapsEachMutationOntoItsOwnOperation() {
        // Amplitude can express all four. Asserted on the chosen operation rather than on the resulting
        // `Identify`, whose accumulated operations the SDK keeps internal.
        #expect(AmplitudeRevenueMapper.operation(for: .set("x")) == .set)
        #expect(AmplitudeRevenueMapper.operation(for: .setOnce("x")) == .setOnce)
        #expect(AmplitudeRevenueMapper.operation(for: .increment(1)) == .add)
        #expect(AmplitudeRevenueMapper.operation(for: .unset) == .unset)
    }

    @Test func anIncrementIsNeverTurnedIntoASet() {
        // Firebase has no atomic increment and skips it. What it must never do is downgrade to `set`,
        // which would replace a running total with a delta and corrupt the property permanently.
        #expect(AmplitudeRevenueMapper.operation(for: .increment(1)) != .set)
    }

    @Test func firebaseRendersEveryValueAsAString() {
        // Firebase's user properties are string-only, so `stringValue` is the wire format rather than a
        // debugging convenience — and booleans render as 1/0 to match the event-parameter flattening.
        #expect(SDXAnalyticsValue.string("cloud").stringValue == "cloud")
        #expect(SDXAnalyticsValue.int(3).stringValue == "3")
        #expect(SDXAnalyticsValue.bool(true).stringValue == "1")
        #expect(SDXAnalyticsValue.bool(false).stringValue == "0")
    }
}

struct AutocaptureMappingTests {

    @Test func theDefaultIsSessionsAndAppLifecyclesOnly() {
        // Screen views and element interactions walk the UIKit hierarchy and find one hosting controller
        // in a SwiftUI app, reporting its name for every screen. Volume without information.
        #expect(SDXAnalyticsAutocapture.default == [.sessions, .appLifecycles])
        #expect(SDXAnalyticsAutocapture.default.contains(.screenViews) == false)
        #expect(SDXAnalyticsAutocapture.default.contains(.elementInteractions) == false)
        #expect(SDXAnalyticsAutocapture.default.contains(.networkRequests) == false)
    }
}

struct AdvertisingIdentifierTests {

    @Test func theAllZerosIdentifierIsNotAnIdentifier() {
        // iOS hands this back rather than nil when tracking is unauthorised. A caller that forwarded it
        // would be reporting every unauthorised device as the same user.
        #expect(
            SDXAdvertisingIdentifier.zeroedIdentifier.uuidString
                == "00000000-0000-0000-0000-000000000000"
        )
    }

    @Test func onlyAuthorizedAllowsTracking() {
        #expect(SDXAdvertisingIdentifier.AuthorizationStatus.authorized.allowsTracking)
        for status in [
            SDXAdvertisingIdentifier.AuthorizationStatus.notDetermined,
            .restricted,
            .denied,
            .unknown,
        ] {
            #expect(status.allowsTracking == false)
        }
    }

    @Test func thereIsAnUnknownCaseForAFutureSystemStatus() {
        // `ATTrackingManager.AuthorizationStatus` is a non-frozen NS_ENUM. Without an escape hatch a
        // case Apple adds later would have to map onto an existing one, and the only safe-looking wrong
        // answer is `.authorized` — which ships an identifier the user never agreed to.
        #expect(SDXAdvertisingIdentifier.AuthorizationStatus(rawValue: "unknown") != nil)
    }

    @Test func statusIsReadableWithoutPrompting() {
        // Just that reading it is side-effect-free and terminates. The prompt itself needs a host app
        // and a user, and is a manual verification step rather than something to fake here.
        _ = SDXAdvertisingIdentifier.authorizationStatus
    }
}
