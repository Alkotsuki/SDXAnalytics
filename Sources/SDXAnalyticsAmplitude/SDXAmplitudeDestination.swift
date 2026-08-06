//
//  SDXAmplitudeDestination.swift
//  SDXAnalyticsAmplitude
//
//  Amplitude, behind `AnalyticsDestination`.
//
//  Two facts about the SDK shape this file, and both are the kind of thing that is invisible until it
//  bites:
//
//  `Configuration` is a class whose `apiKey`, `autocapture` and `instanceName` are `public
//  internal(set)` — they can only be supplied through `init`. So the whole configuration has to be
//  complete before the instance exists, which is why `SDXAmplitudeOptions` is a value handed in at
//  construction and why the `Amplitude` handle is built inside `configure()` rather than lazily on
//  first use.
//
//  And `Configuration.optOut` is set from its init parameter and never restored from storage, while
//  Firebase's own collection flag *does* survive a relaunch. That asymmetry is why
//  `SDXAnalyticsClient` owns the persisted kill switch and pushes it in here — left to the two SDKs, a
//  user who opted out would get Firebase silence and Amplitude noise on their second launch.
//
//  `@unchecked Sendable` is earned by one rule: the handle is written exactly once, inside `configure()`,
//  before any other method can observe it, and every later method only reads it and hands work to an SDK
//  that is itself thread-safe. `Amplitude`, `Configuration` and `AutocaptureOptions` all come from a
//  Swift 5 module and carry no `Sendable` conformance, so they are built and consumed entirely inside
//  `configure()` and never stored in one of this package's value types.
//

import Foundation
import AmplitudeSwift
import SDXAnalytics
import os

public struct SDXAmplitudeOptions: Sendable, Hashable {

    public enum ServerZone: String, Sendable, Hashable {
        case us
        case eu
    }

    /// The write key. There is no default and none is baked into this package: a key compiled into a
    /// library ships to every consumer of it and cannot be rotated without a release.
    public let apiKey: String
    /// Events sent to the wrong zone are accepted and then silently dropped, so this is worth checking
    /// against the Amplitude project's own settings rather than assuming.
    public let serverZone: ServerZone
    public let instanceName: String?
    public let autocapture: SDXAnalyticsAutocapture
    public let flushQueueSize: Int
    public let minTimeBetweenSessionsMillis: Int

    public init(
        apiKey: String,
        serverZone: ServerZone = .us,
        instanceName: String? = nil,
        autocapture: SDXAnalyticsAutocapture = .default,
        flushQueueSize: Int = 30,
        minTimeBetweenSessionsMillis: Int = 300_000
    ) {
        self.apiKey = apiKey
        self.serverZone = serverZone
        self.instanceName = instanceName
        self.autocapture = autocapture
        self.flushQueueSize = flushQueueSize
        self.minTimeBetweenSessionsMillis = minTimeBetweenSessionsMillis
    }
}

public final class SDXAmplitudeDestination: AnalyticsDestination, @unchecked Sendable {

    public let name = "amplitude"

    private let options: SDXAmplitudeOptions
    private let plugin = AmplitudeGlobalPropertiesPlugin()
    private let logger = Logger(subsystem: "SDXAnalytics", category: "amplitude")
    private var amplitude: Amplitude?

    public init(options: SDXAmplitudeOptions) {
        self.options = options
    }

    public func configure() throws {
        guard !options.apiKey.isEmpty else {
            throw SDXAnalyticsError.missingAPIKey(name)
        }
        guard amplitude == nil else { return }

        let configuration = Configuration(
            apiKey: options.apiKey,
            flushQueueSize: options.flushQueueSize,
            instanceName: options.instanceName ?? Configuration.Defaults.instanceName,
            serverZone: options.serverZone == .eu ? .EU : .US,
            minTimeBetweenSessionsMillis: options.minTimeBetweenSessionsMillis,
            autocapture: Self.autocapture(options.autocapture)
        )

        let instance = Amplitude(configuration: configuration)
        instance.add(plugin: plugin)
        amplitude = instance
    }

    public func track(_ event: SDXAnalyticsEvent) {
        amplitude?.track(
            eventType: event.name,
            eventProperties: AmplitudeRevenueMapper.parameters(event.parameters)
        )
    }

    public func setEnabled(_ enabled: Bool) {
        amplitude?.optOut = !enabled
    }

    public func setUserID(_ id: String?) {
        amplitude?.setUserId(userId: id)
    }

    public func setUserProperty(_ property: SDXAnalyticsUserProperty) {
        amplitude?.identify(identify: AmplitudeRevenueMapper.identify(property))
    }

    public func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        plugin.setSuperProperties(parameters)
    }

    public func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        // `Revenue.isValid()` requires a non-nil price, so Amplitude drops a zero-price purchase — and
        // a zero-price purchase is exactly what a free-trial start looks like. Log it rather than let a
        // trial quietly vanish from the funnel; the ordinary event for it still went through `track`.
        guard purchase.carriesRevenue else {
            logger.notice(
                "Amplitude drops zero-price purchases; \(purchase.productID, privacy: .public) was not sent as revenue."
            )
            return
        }
        amplitude?.revenue(revenue: AmplitudeRevenueMapper.map(purchase))
    }

    public func trackScreen(name screenName: String, class className: String?) {
        // The SDK's own screen event type, so this lands in Amplitude's native screen reporting rather
        // than as a custom event that looks like one. Deliberately asymmetric with Firebase, which
        // takes a screen class alongside the name; Amplitude has nowhere to put it.
        amplitude?.track(event: ScreenViewedEvent(screenName: screenName))
    }

    public func setAdvertisingIdentifier(_ idfa: String?) {
        plugin.setAdvertisingIdentifier(idfa)
    }

    public func flush() {
        amplitude?.flush()
    }

    public func reset() {
        amplitude?.reset()
    }

    // MARK: - Private

    private static func autocapture(
        _ options: SDXAnalyticsAutocapture
    ) -> AutocaptureOptions {
        var mapped: AutocaptureOptions = []
        if options.contains(.sessions) { mapped.insert(.sessions) }
        if options.contains(.appLifecycles) { mapped.insert(.appLifecycles) }
        if options.contains(.screenViews) { mapped.insert(.screenViews) }
        if options.contains(.elementInteractions) { mapped.insert(.elementInteractions) }
        // Note the name: the SDK calls this `networkTracking`, not `networkRequests`.
        if options.contains(.networkRequests) { mapped.insert(.networkTracking) }
        return mapped
    }
}
