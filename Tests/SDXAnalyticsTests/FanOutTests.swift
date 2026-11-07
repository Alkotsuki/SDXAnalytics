//
//  FanOutTests.swift
//  SDXAnalyticsTests
//
//  One call in, every destination out — and the same value at each of them.
//
//  The equality assertion between two fakes is the important one in this file. "Both dashboards see the
//  same thing" is the promise the whole package exists to keep, and it is the kind of promise that
//  degrades quietly: nobody notices that one vendor is getting a slightly different parameter set until
//  a quarter of numbers have been compared that should not have been.
//

import Foundation
import Testing
@testable import SDXAnalytics

struct FanOutTests {

    @Test func oneEventReachesEveryDestinationExactlyOnce() {
        let first = FakeAnalyticsDestination(name: "first")
        let second = FakeAnalyticsDestination(name: "second")
        let client = SDXAnalyticsFixtures.client(destinations: [first, second])
        client.configure()

        client.track(SDXAnalyticsFixtures.valid)

        #expect(first.events.count == 1)
        #expect(second.events.count == 1)
    }

    @Test func everyDestinationReceivesTheIdenticalEvent() {
        let first = FakeAnalyticsDestination(name: "first")
        let second = FakeAnalyticsDestination(name: "second")
        let client = SDXAnalyticsFixtures.client(destinations: [first, second])
        client.configure()

        client.track(SDXAnalyticsFixtures.valid)

        #expect(first.events == second.events)
    }

    @Test func aDestinationThatFailsToConfigureIsStruckOffWithoutSilencingTheOthers() {
        let broken = FakeAnalyticsDestination(
            name: "broken",
            configureError: SDXAnalyticsError.missingAPIKey("broken")
        )
        let working = FakeAnalyticsDestination(name: "working")
        let client = SDXAnalyticsFixtures.client(destinations: [broken, working])
        client.configure()

        client.track(SDXAnalyticsFixtures.valid)

        #expect(broken.events.isEmpty)
        #expect(working.count(of: SDXAnalyticsFixtures.valid.name) == 1)
    }

    @Test func aDestinationThatFailsToConfigureIsReportedToTheSurvivors() throws {
        // The failure has to reach a dashboard: release builds are the only ones carrying vendor
        // destinations, and nobody reads a release device's log.
        let broken = FakeAnalyticsDestination(
            name: "broken",
            configureError: SDXAnalyticsError.missingAPIKey("broken")
        )
        let working = FakeAnalyticsDestination(name: "working")
        let client = SDXAnalyticsFixtures.client(destinations: [broken, working])
        client.configure()

        let event = try #require(working.event(named: SDXAnalyticsClient.destinationFailedEvent))
        #expect(event.parameters["destination"] == .string("broken"))
        #expect(event.parameters["reason"] == .string("broken was created without an API key."))
    }

    @Test func aFailedDestinationIsNotReportedForAUserWhoOptedOut() {
        let broken = FakeAnalyticsDestination(
            name: "broken",
            configureError: SDXAnalyticsError.missingAPIKey("broken")
        )
        let working = FakeAnalyticsDestination(name: "working")
        let client = SDXAnalyticsFixtures.client(destinations: [broken, working], enabledByDefault: false)
        client.configure()

        #expect(working.events.isEmpty)
    }

    @Test func configureIsIdempotent() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.configure()
        client.configure()
        client.configure()

        #expect(destination.configureCallCount == 1)
        #expect(client.isConfigured)
    }

    @Test func trackingByNameAndByValueProduceTheSameEvent() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.track("thing_happened", ["count": 2])
        client.track(SDXAnalyticsEvent(name: "thing_happened", parameters: ["count": 2]))

        #expect(destination.events.count == 2)
        #expect(destination.events[0] == destination.events[1])
    }

    @Test func aReservedNameReachesNoDestinationAtAll() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination], validation: .sanitise)
        client.configure()

        client.track(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.reservedName))

        #expect(destination.events.isEmpty)
    }

    @Test func screensAndPurchasesTakeTheirOwnPathsRatherThanBecomingEvents() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.screen("library")
        client.purchase(SDXAnalyticsFixtures.pack)

        #expect(destination.events.isEmpty)
        #expect(destination.screenNames == ["library"])
        #expect(destination.purchases.count == 1)
    }

    @Test func aZeroPricePurchaseReachesNoDestination() {
        // A free-trial start. Every vendor would otherwise count it as a sale worth 0.
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.purchase(SDXAnalyticsFixtures.trial)

        #expect(destination.purchases.isEmpty)
    }

    @Test func aZeroPricePurchaseIsNotBufferedBeforeConfigureEither() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])

        client.purchase(SDXAnalyticsFixtures.trial)
        client.purchase(SDXAnalyticsFixtures.pack)
        client.configure()

        #expect(destination.purchases == [SDXAnalyticsFixtures.pack])
    }

    @Test func flushAndResetReachEveryDestination() {
        let first = FakeAnalyticsDestination(name: "first")
        let second = FakeAnalyticsDestination(name: "second")
        let client = SDXAnalyticsFixtures.client(destinations: [first, second])
        client.configure()

        client.flush()
        client.reset()

        #expect(first.flushCallCount == 1)
        #expect(second.flushCallCount == 1)
        #expect(first.resetCallCount == 1)
        #expect(second.resetCallCount == 1)
    }
}

struct SuperPropertyPrecedenceTests {

    @Test func superPropertiesAreMergedIntoEveryEvent() throws {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()
        client.setSuperProperties(["build": "release"])

        client.track("thing_happened")

        let event = try #require(destination.event(named: "thing_happened"))
        #expect(event.parameters["build"] == .string("release"))
    }

    @Test func anEventParameterBeatsASuperPropertyOfTheSameName() throws {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()
        client.setSuperProperties(["path": "on_device"])

        client.track("thing_happened", ["path": "cloud"])

        let event = try #require(destination.event(named: "thing_happened"))
        #expect(event.parameters["path"] == .string("cloud"))
    }

    @Test func superPropertiesFromConfigurationApplyWithoutAnExplicitCall() throws {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(
            destinations: [destination],
            superProperties: ["build": "debug"]
        )
        client.configure()

        client.track("thing_happened")

        let event = try #require(destination.event(named: "thing_happened"))
        #expect(event.parameters["build"] == .string("debug"))
    }

    @Test func clearingSuperPropertiesPropagatesAndStopsTheMerge() throws {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()
        client.setSuperProperties(["build": "release"])
        client.clearSuperProperties()

        client.track("thing_happened")

        let event = try #require(destination.event(named: "thing_happened"))
        #expect(event.parameters["build"] == nil)
        #expect(destination.superProperties.isEmpty)
    }

    @Test func destinationsAreToldSoTheyCanStampAutocapturedEventsToo() {
        let destination = FakeAnalyticsDestination()
        let client = SDXAnalyticsFixtures.client(destinations: [destination])
        client.configure()

        client.setSuperProperties(["build": "release"])

        #expect(destination.superProperties == ["build": .string("release")])
    }
}
