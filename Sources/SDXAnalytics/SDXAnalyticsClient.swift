//
//  SDXAnalyticsClient.swift
//  SDXAnalytics
//
//  One logger interface, fanned out to every configured destination.
//
//  A `final class` rather than an `actor`, and this is the load-bearing decision in the package.
//  `track` is called from SwiftUI button actions, `onAppear` closures and view-model methods all over
//  an adopting app — several hundred call sites in a real one. An actor would make every one of them
//  `await`, which in a synchronous context means `Task { }`, which costs two things that matter more
//  than the tidiness: ordering, because two funnel steps in the same millisecond would no longer
//  necessarily arrive in the order the user did them; and delivery, because a `Task` spawned from a
//  view can be cancelled on teardown, so the event most worth having — the last one before the user
//  left — is exactly the one that goes missing.
//
//  A `@MainActor` class would be worse again for the apps this is written for, whose image and
//  inference pipelines are deliberately `nonisolated` so they stay off the main actor. Forcing a
//  main-actor hop to log from them would add latency to the code paths where latency is the product.
//
//  So: a lock around a few fields. One rule, and it is not negotiable — **no SDK call ever happens
//  inside the lock.** Take it, snapshot or mutate, release, and only then talk to a destination.
//  `os_unfair_lock` does no priority donation, so a main-thread `track` blocking on a lock held by a
//  utility-QoS thread that is halfway through Firebase's SQLite write is a textbook priority
//  inversion and shows up as a main-thread hang.
//
//  `OSAllocatedUnfairLock` and not `Synchronization.Mutex` because this package supports iOS 17 and
//  `Mutex` is iOS 18.
//

import Foundation
import os

public final class SDXAnalyticsClient: Sendable {

    private struct State {
        var isConfigured = false
        var liveDestinations: [any AnalyticsDestination] = []
        var isEnabled = true
        var userID: String?
        var superProperties: [String: SDXAnalyticsValue] = [:]
        var advertisingIdentifier: String?
        var pendingProperties: [SDXAnalyticsUserProperty] = []
        var pending: PendingEventBuffer
        #if DEBUG
        var diagnostics: [SDXAnalyticsDiagnostic] = []
        #endif
    }

    private let configuration: SDXAnalyticsConfiguration
    private let validator: SDXAnalyticsNameValidator
    private let destinations: [any AnalyticsDestination]
    // `UserDefaults` is thread-safe but predates `Sendable` and carries no conformance.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let state: OSAllocatedUnfairLock<State>
    private let logger = Logger(subsystem: "SDXAnalytics", category: "client")

    public init(
        configuration: SDXAnalyticsConfiguration = SDXAnalyticsConfiguration(),
        destinations: [any AnalyticsDestination],
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.validator = SDXAnalyticsNameValidator(policy: configuration.validation)
        self.destinations = destinations
        self.defaults = defaults
        self.state = OSAllocatedUnfairLock(
            initialState: State(pending: PendingEventBuffer(limit: configuration.pendingEventLimit))
        )
    }

    // MARK: - Configuration

    /// Bring every destination up, push current state to it, then release anything buffered.
    ///
    /// Synchronous and idempotent. Synchronous because `FirebaseApp.configure()` and `Amplitude.init`
    /// both are, and because the natural call site is an `App.init` — making this `async` would push
    /// it into a `.task`, which runs after the first `body`, which is after the first events.
    ///
    /// Does not throw. A destination that fails is logged and struck off the fan-out for the lifetime
    /// of the process; there is no useful single answer to hand back, and an app that crashed on a
    /// Firebase misconfiguration would be trading all of its telemetry for one dashboard.
    public func configure() {
        let alreadyConfigured = state.withLock { $0.isConfigured }
        guard !alreadyConfigured else { return }

        let storedEnabled = defaults.object(forKey: configuration.persistedEnabledKey) as? Bool
        let isEnabled = storedEnabled ?? configuration.enabledByDefault

        let live = destinations.filter { destination in
            do {
                try destination.configure()
                return true
            } catch {
                logger.error(
                    "Destination \(destination.name, privacy: .public) failed to configure: \(error.localizedDescription, privacy: .public)"
                )
                return false
            }
        }

        // Push state before events, always. A buffered event that reached a dashboard ahead of the
        // user id would be attributed to an anonymous device and could never be re-associated.
        let snapshot = state.withLock { state -> (String?, [String: SDXAnalyticsValue], String?, [SDXAnalyticsUserProperty]) in
            state.liveDestinations = live
            state.isEnabled = isEnabled
            state.isConfigured = true
            if state.superProperties.isEmpty {
                state.superProperties = configuration.superProperties
            }
            return (
                state.userID,
                state.superProperties,
                state.advertisingIdentifier,
                state.pendingProperties
            )
        }

        for destination in live {
            destination.setEnabled(isEnabled)
            if let userID = snapshot.0 { destination.setUserID(userID) }
            for property in snapshot.3 { destination.setUserProperty(property) }
            if !snapshot.1.isEmpty { destination.setSuperProperties(snapshot.1) }
            if let idfa = snapshot.2 { destination.setAdvertisingIdentifier(idfa) }
        }

        let (buffered, dropped) = state.withLock { state in
            state.pendingProperties.removeAll()
            return (state.pending.drain(), state.pending.droppedCount)
        }

        if dropped > 0 {
            logger.warning(
                "Dropped \(dropped, privacy: .public) event(s) buffered before configure(); raise pendingEventLimit or configure earlier."
            )
        }

        guard isEnabled else { return }
        for item in buffered {
            switch item {
            case .event(let event):
                deliver(event, to: live)
            case .purchase(let purchase):
                for destination in live { destination.trackPurchase(purchase) }
            case .screen(let name, let className):
                for destination in live { destination.trackScreen(name: name, class: className) }
            }
        }
    }

    public var isConfigured: Bool {
        state.withLock { $0.isConfigured }
    }

    // MARK: - Events

    public func track(_ name: String, _ parameters: [String: SDXAnalyticsValue] = [:]) {
        track(SDXAnalyticsEvent(name: name, parameters: parameters))
    }

    public func track(_ event: some SDXAnalyticsEventConvertible) {
        track(event.analyticsEvent)
    }

    public func track(_ event: SDXAnalyticsEvent) {
        // Merge before validating, not after. Super properties count toward the same 25-parameter
        // ceiling and are subject to the same name limits as anything else, so merging afterwards
        // would let them push an event past a limit the validator had already signed off on.
        let merged = event.merging(state.withLock { $0.superProperties })

        let outcome = validator.validate(merged)
        report(outcome.diagnostics, subject: event.name)
        guard let validated = outcome.value else { return }

        let decision = state.withLock { state -> ([any AnalyticsDestination], Bool) in
            guard state.isEnabled else { return ([], false) }
            guard state.isConfigured else {
                state.pending.append(.event(validated))
                return ([], false)
            }
            return (state.liveDestinations, true)
        }

        guard decision.1 else { return }
        deliver(validated, to: decision.0)
    }

    public func screen(_ name: String, class className: String? = nil) {
        let decision = state.withLock { state -> ([any AnalyticsDestination], Bool) in
            guard state.isEnabled else { return ([], false) }
            guard state.isConfigured else {
                state.pending.append(.screen(name: name, className: className))
                return ([], false)
            }
            return (state.liveDestinations, true)
        }

        guard decision.1 else { return }
        for destination in decision.0 {
            destination.trackScreen(name: name, class: className)
        }
    }

    public func purchase(_ purchase: SDXAnalyticsPurchase) {
        let decision = state.withLock { state -> ([any AnalyticsDestination], Bool) in
            guard state.isEnabled else { return ([], false) }
            guard state.isConfigured else {
                state.pending.append(.purchase(purchase))
                return ([], false)
            }
            return (state.liveDestinations, true)
        }

        guard decision.1 else { return }
        for destination in decision.0 {
            destination.trackPurchase(purchase)
        }
    }

    // MARK: - Identity

    public func setUserID(_ id: String?) {
        let live = state.withLock { state -> [any AnalyticsDestination] in
            state.userID = id
            return state.isConfigured ? state.liveDestinations : []
        }
        for destination in live { destination.setUserID(id) }
    }

    public func setUserProperty(_ name: String, _ value: SDXAnalyticsValue) {
        setUserProperties([.set(name, value)])
    }

    public func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        setUserProperties([property])
    }

    public func setUserProperties(_ properties: [SDXAnalyticsUserProperty]) {
        let validated = properties.compactMap { property -> SDXAnalyticsUserProperty? in
            let outcome = validator.validate(property)
            report(outcome.diagnostics, subject: property.name)
            return outcome.value
        }
        guard !validated.isEmpty else { return }

        let live = state.withLock { state -> [any AnalyticsDestination] in
            guard state.isConfigured else {
                // Held rather than dropped: a property set during start-up describes the whole
                // session, so losing it would mis-segment every event in it.
                state.pendingProperties.append(contentsOf: validated)
                return []
            }
            return state.liveDestinations
        }

        for destination in live {
            for property in validated { destination.setUserProperty(property) }
        }
    }

    // MARK: - Super properties

    /// Facts about the session, merged underneath every subsequent event's own parameters.
    ///
    /// Handed to the destinations *as well as* being merged in `track`, which looks redundant and is
    /// not: events a vendor autocaptures — Amplitude's session and app-lifecycle events — never pass
    /// through `track` at all, so the vendor's own mechanism is the only thing that can stamp those.
    /// The overlap is harmless because both paths write identical values.
    public func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        let (live, merged) = state.withLock { state -> ([any AnalyticsDestination], [String: SDXAnalyticsValue]) in
            state.superProperties.merge(parameters) { _, new in new }
            return (state.isConfigured ? state.liveDestinations : [], state.superProperties)
        }
        for destination in live { destination.setSuperProperties(merged) }
    }

    public func clearSuperProperties() {
        let live = state.withLock { state -> [any AnalyticsDestination] in
            state.superProperties.removeAll()
            return state.isConfigured ? state.liveDestinations : []
        }
        for destination in live { destination.setSuperProperties([:]) }
    }

    // MARK: - Kill switch

    /// Turn collection off, and remember it.
    ///
    /// Persisted here rather than delegated, because the vendors disagree about whether their own
    /// flag survives a relaunch — Firebase's does and Amplitude's does not. See
    /// `SDXAnalyticsConfiguration.persistedEnabledKey`.
    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: configuration.persistedEnabledKey)
        let live = state.withLock { state -> [any AnalyticsDestination] in
            state.isEnabled = enabled
            return state.liveDestinations
        }
        for destination in live { destination.setEnabled(enabled) }
    }

    public var isEnabled: Bool {
        state.withLock { $0.isEnabled }
    }

    // MARK: - Advertising identifier

    /// Hand over the IDFA the app obtained, or nil if it has none.
    ///
    /// This package never asks for it. See `SDXAdvertisingIdentifier` for why the timing of that
    /// prompt has to belong to the app.
    public func setAdvertisingIdentifier(_ idfa: String?) {
        let live = state.withLock { state -> [any AnalyticsDestination] in
            state.advertisingIdentifier = idfa
            return state.isConfigured ? state.liveDestinations : []
        }
        for destination in live { destination.setAdvertisingIdentifier(idfa) }
    }

    // MARK: - Lifecycle

    public func flush() {
        let live = state.withLock { $0.liveDestinations }
        for destination in live { destination.flush() }
    }

    public func reset() {
        let live = state.withLock { state -> [any AnalyticsDestination] in
            state.userID = nil
            state.superProperties.removeAll()
            state.advertisingIdentifier = nil
            return state.liveDestinations
        }
        for destination in live { destination.reset() }
    }

    // MARK: - Diagnostics

    #if DEBUG
    public var pendingEventCount: Int {
        state.withLock { $0.pending.count }
    }

    public var droppedPendingEventCount: Int {
        state.withLock { $0.pending.droppedCount }
    }

    public func drainDiagnostics() -> [SDXAnalyticsDiagnostic] {
        state.withLock { state in
            defer { state.diagnostics.removeAll() }
            return state.diagnostics
        }
    }
    #endif

    // MARK: - Private

    private func deliver(_ event: SDXAnalyticsEvent, to destinations: [any AnalyticsDestination]) {
        for destination in destinations {
            destination.track(event)
        }
    }

    private func report(_ diagnostics: [SDXAnalyticsDiagnostic], subject: String) {
        guard !diagnostics.isEmpty else { return }

        #if DEBUG
        state.withLock { $0.diagnostics.append(contentsOf: diagnostics) }
        #endif

        for diagnostic in diagnostics {
            switch diagnostic.kind {
            case .eventNameReserved, .eventDropped:
                logger.error("\(diagnostic.description, privacy: .public)")
            default:
                logger.warning("\(diagnostic.description, privacy: .public)")
            }
        }

        // Loud in DEBUG, so a name that would be silently truncated in the field is caught the first
        // time it runs on somebody's simulator. This is what makes "truncate in release" safe: by the
        // time a build ships, the assert has already been paid.
        guard configuration.assertsOnDiagnostics else { return }
        assertionFailure(
            "SDXAnalytics rejected or rewrote \(subject): "
                + diagnostics.map(\.description).joined(separator: ", ")
        )
    }
}
