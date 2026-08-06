//
//  PendingBufferTests.swift
//  SDXAnalyticsTests
//
//  What happens to events recorded before `configure()`.
//

import Foundation
import Testing
@testable import SDXAnalytics

struct PendingBufferTests {

    @Test func eventsRecordedBeforeConfigureArriveAfterIt() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.track("first")
        client.track("second")
        #expect(destination.events.isEmpty)

        client.configure()

        #expect(destination.names == ["first", "second"])
    }

    @Test func bufferedEventsKeepTheOrderTheyWereRecordedIn() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        for index in 0..<10 { client.track("event_\(index)") }
        client.configure()

        #expect(destination.names == (0..<10).map { "event_\($0)" })
    }

    @Test func screensAndPurchasesAreBufferedToo() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.screen("library")
        client.purchase(SDXAnalyticsFixtures.pack)
        client.configure()

        #expect(destination.screenNames == ["library"])
        #expect(destination.purchases.count == 1)
    }

    @Test func theBufferStopsAtItsLimitAndReportsWhatItDropped() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination], pendingEventLimit: 3)

        for index in 0..<5 { client.track("event_\(index)") }

        #expect(client.pendingEventCount == 3)
        #expect(client.droppedPendingEventCount == 2)

        client.configure()

        // The recent end of the session survives — it is the end closest to whatever the user did last.
        #expect(destination.names == ["event_2", "event_3", "event_4"])
    }

    @Test func aZeroLimitDropsImmediatelyRatherThanBuffering() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination], pendingEventLimit: 0)

        client.track("first")
        client.configure()

        #expect(destination.events.isEmpty)
        #expect(client.droppedPendingEventCount == 1)
    }

    @Test func identityIsPushedBeforeTheFirstBufferedEvent() {
        // A buffered event that reached a dashboard ahead of the user id would be attributed to an
        // anonymous device and could never be re-associated, so the ordering here is load-bearing.
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.setUserID("someone")
        client.setUserProperty("cohort", "2026-W32")
        client.setSuperProperties(["build": "release"])
        client.track("first")

        #expect(destination.userIDs.isEmpty)
        #expect(destination.userProperties.isEmpty)

        client.configure()

        #expect(destination.userIDs == ["someone"])
        #expect(destination.userProperties.count == 1)
        #expect(destination.superProperties == ["build": .string("release")])
        #expect(destination.names == ["first"])
    }

    @Test func userPropertiesSetBeforeConfigureAreNotDroppedByTheEventLimit() {
        // A property set during start-up describes the whole session, so losing it would mis-segment
        // every event in that session. It is held separately from the bounded event buffer.
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination], pendingEventLimit: 1)

        for index in 0..<5 { client.setUserProperty("prop_\(index)", .int(index)) }
        client.configure()

        #expect(destination.userProperties.count == 5)
    }

    @Test func advertisingIdentifierSetBeforeConfigureIsPushedOnce() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.setAdvertisingIdentifier("ABCDEF")
        client.configure()

        #expect(destination.advertisingIdentifiers == ["ABCDEF"])
    }
}
