//
//  AmplitudeGlobalPropertiesPlugin.swift
//  SDXAnalyticsAmplitude
//
//  Stamps super properties and the ad identifier onto every event Amplitude sends.
//
//  Amplitude has no equivalent of Firebase's `setDefaultEventParameters`, so there is no API-level way
//  to say "put these on everything". An `EnrichmentPlugin` is the only hook that sits in the pipeline
//  every event passes through — including the ones the SDK generates itself for sessions and
//  app lifecycles, which never go near our `track` and would otherwise arrive unlabelled.
//
//  It is also the only way an IDFA ever reaches Amplitude at all: the SDK imports no `AdSupport`
//  anywhere, so it never collects one on its own. `EventOptions.idfa` is the field, and `BaseEvent`
//  inherits it.
//
//  `@unchecked Sendable` over a lock rather than an actor because `execute(event:)` is a synchronous
//  override on Amplitude's own class and cannot become `async`.
//

import Foundation
import AmplitudeSwift
import SDXAnalytics
import os

final class AmplitudeGlobalPropertiesPlugin: EnrichmentPlugin, @unchecked Sendable {

    // Held as `SDXAnalyticsValue` rather than the `[String: Any]` Amplitude's API wants, because
    // `Any` is not `Sendable` and this state crosses threads. Mapping happens in `execute(event:)`,
    // at the boundary where the SDK actually needs the untyped form.
    private struct State: Sendable {
        var superProperties: [String: SDXAnalyticsValue] = [:]
        var advertisingIdentifier: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func setSuperProperties(_ parameters: [String: SDXAnalyticsValue]) {
        state.withLock { $0.superProperties = parameters }
    }

    func setAdvertisingIdentifier(_ idfa: String?) {
        state.withLock { $0.advertisingIdentifier = idfa }
    }

    override func execute(event: BaseEvent) -> BaseEvent? {
        let snapshot = state.withLock { $0 }

        if !snapshot.superProperties.isEmpty {
            var properties = AmplitudeRevenueMapper.parameters(snapshot.superProperties)
            // The event's own properties win, matching Firebase's documented precedence for default
            // event parameters. A super property is a fact about the session; an event that states
            // the same key is correcting it for this one occurrence.
            for (key, value) in event.eventProperties ?? [:] {
                properties[key] = value
            }
            event.eventProperties = properties
        }

        if let idfa = snapshot.advertisingIdentifier {
            event.idfa = idfa
        }

        return event
    }
}
