//
//  FakeAnalyticsDestination.swift
//  SDXAnalyticsTests
//
//  A scriptable `AnalyticsDestination` that records everything it is handed.
//
//  A `final class` over a lock rather than an actor, deliberately. `AnalyticsDestination` is a
//  synchronous protocol because the client's `track` is synchronous, so an actor here could not conform
//  without hiding the calls behind `Task`s — which would make the fan-out arrive after the `#expect`
//  that was checking for it, and the ordering guarantees this package sells would become untestable in
//  exactly the shape they are actually used.
//

import Foundation
import SDXAnalytics
import os

final class FakeAnalyticsDestination: AnalyticsDestination, @unchecked Sendable {

    let name: String

    private struct State: Sendable {
        var configureCallCount = 0
        var events: [SDXAnalyticsEvent] = []
        var purchases: [SDXAnalyticsPurchase] = []
        var userProperties: [SDXAnalyticsUserProperty] = []
        var userIDs: [String?] = []
        var enabledHistory: [Bool] = []
        var superProperties: [String: SDXAnalyticsValue] = [:]
        var superPropertyCallCount = 0
        var screens: [(name: String, className: String?)] = []
        var advertisingIdentifiers: [String?] = []
        var flushCallCount = 0
        var resetCallCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Script

    /// When set, `configure()` throws it. For proving that one broken vendor does not silence the other.
    let configureError: (any Error)?

    init(name: String = "fake", configureError: (any Error)? = nil) {
        self.name = name
        self.configureError = configureError
    }

    // MARK: - Recorded

    var configureCallCount: Int { state.withLock { $0.configureCallCount } }
    var events: [SDXAnalyticsEvent] { state.withLock { $0.events } }
    var purchases: [SDXAnalyticsPurchase] { state.withLock { $0.purchases } }
    var userProperties: [SDXAnalyticsUserProperty] { state.withLock { $0.userProperties } }
    var userIDs: [String?] { state.withLock { $0.userIDs } }
    var enabledHistory: [Bool] { state.withLock { $0.enabledHistory } }
    var superProperties: [String: SDXAnalyticsValue] { state.withLock { $0.superProperties } }
    var superPropertyCallCount: Int { state.withLock { $0.superPropertyCallCount } }
    var screenNames: [String] { state.withLock { $0.screens.map(\.name) } }
    var advertisingIdentifiers: [String?] { state.withLock { $0.advertisingIdentifiers } }
    var flushCallCount: Int { state.withLock { $0.flushCallCount } }
    var resetCallCount: Int { state.withLock { $0.resetCallCount } }

    var names: [String] { events.map(\.name) }

    func event(named name: String) -> SDXAnalyticsEvent? {
        events.last { $0.name == name }
    }

    func count(of name: String) -> Int {
        events.filter { $0.name == name }.count
    }

    // MARK: - AnalyticsDestination

    func configure() throws {
        state.withLock { $0.configureCallCount += 1 }
        if let configureError { throw configureError }
    }

    func track(_ event: SDXAnalyticsEvent) {
        state.withLock { $0.events.append(event) }
    }

    func setEnabled(_ enabled: Bool) {
        state.withLock { $0.enabledHistory.append(enabled) }
    }

    func setUserID(_ id: String?) {
        state.withLock { $0.userIDs.append(id) }
    }

    func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        state.withLock { $0.userProperties.append(property) }
    }

    func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        state.withLock {
            $0.superProperties = parameters
            $0.superPropertyCallCount += 1
        }
    }

    func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        state.withLock { $0.purchases.append(purchase) }
    }

    func trackScreen(name screenName: String, class className: String?) {
        state.withLock { $0.screens.append((screenName, className)) }
    }

    func setAdvertisingIdentifier(_ idfa: String?) {
        state.withLock { $0.advertisingIdentifiers.append(idfa) }
    }

    func flush() {
        state.withLock { $0.flushCallCount += 1 }
    }

    func reset() {
        state.withLock { $0.resetCallCount += 1 }
    }
}
