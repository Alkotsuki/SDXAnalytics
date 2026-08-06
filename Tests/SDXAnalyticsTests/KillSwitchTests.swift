//
//  KillSwitchTests.swift
//  SDXAnalyticsTests
//
//  Opting out, and staying opted out.
//
//  The last test in this file is the one that matters. Amplitude reads `optOut` from its init parameter
//  and never restores it from storage, while Firebase's own flag does survive a relaunch — so if the
//  client ever stopped persisting this itself, a user who opted out would get Firebase silence and
//  Amplitude noise on their second launch, and nothing in a single-session test would notice.
//

import Foundation
import Testing
@testable import SDXAnalytics

struct KillSwitchTests {

    @Test func disablingStopsEventsReachingAnyDestination() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.setEnabled(false)
        client.track(SDXAnalyticsFixtures.valid)

        #expect(destination.events.isEmpty)
        #expect(client.isEnabled == false)
    }

    @Test func disablingIsPropagatedToEveryDestination() {
        let first = FakeAnalyticsDestination(name: "first")
        let second = FakeAnalyticsDestination(name: "second")
        let client = SDXAnalyticsFixtures.client(destinations: [first, second])
        client.configure()

        client.setEnabled(false)

        #expect(first.enabledHistory == [true, false])
        #expect(second.enabledHistory == [true, false])
    }

    @Test func reEnablingRestoresDelivery() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.setEnabled(false)
        client.track(SDXAnalyticsFixtures.valid)
        client.setEnabled(true)
        client.track(SDXAnalyticsFixtures.valid)

        #expect(destination.events.count == 1)
    }

    @Test func screensAndPurchasesAreSuppressedToo() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.setEnabled(false)
        client.screen("library")
        client.purchase(SDXAnalyticsFixtures.pack)

        #expect(destination.screenNames.isEmpty)
        #expect(destination.purchases.isEmpty)
    }

    @Test func theChoiceSurvivesIntoANewClientOverTheSameDefaults() {
        let defaults = SDXAnalyticsFixtures.isolatedDefaults()

        let first = SDXAnalyticsFixtures.client(destinations: [], defaults: defaults)
        first.configure()
        first.setEnabled(false)

        let destination = FakeAnalyticsDestination()
        let second = SDXAnalyticsFixtures.client(destinations: [destination], defaults: defaults)
        second.configure()

        #expect(second.isEnabled == false)
        #expect(destination.enabledHistory == [false])
    }

    @Test func aPersistedOptOutIsAppliedBeforeAnyEventCanBeSent() {
        let defaults = SDXAnalyticsFixtures.isolatedDefaults()
        defaults.set(false, forKey: "SDXAnalyticsTests.enabled")

        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination], defaults: defaults)

        // Recorded before `configure()`, so it goes through the pending buffer — which is precisely the
        // path that could leak an event past a stored opt-out if the flag were read too late.
        client.track(SDXAnalyticsFixtures.valid)
        client.configure()

        #expect(destination.events.isEmpty)
        #expect(destination.enabledHistory.first == false)
    }

    @Test func enabledByDefaultDecidesTheAnswerForAUserWhoNeverChose() {
        let optedOut = SDXAnalyticsFixtures.client(
            destinations: [],
            enabledByDefault: false,
            defaults: SDXAnalyticsFixtures.isolatedDefaults()
        )
        optedOut.configure()
        #expect(optedOut.isEnabled == false)

        let optedIn = SDXAnalyticsFixtures.client(
            destinations: [],
            enabledByDefault: true,
            defaults: SDXAnalyticsFixtures.isolatedDefaults()
        )
        optedIn.configure()
        #expect(optedIn.isEnabled)
    }
}
