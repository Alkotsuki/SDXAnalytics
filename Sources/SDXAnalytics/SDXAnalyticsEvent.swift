//
//  SDXAnalyticsEvent.swift
//  SDXAnalytics
//
//  An analytics event as a value.
//
//  A struct rather than a method signature so that an event can be built, held, compared and
//  asserted on without a client, a destination or a network. That is what lets an adopting app test
//  its own taxonomy — "every event carries a session id", "no event carries a photo identifier" —
//  as ordinary unit tests over values, which is where those rules actually get enforced.
//

import Foundation

public struct SDXAnalyticsEvent: Sendable, Hashable {

    public let name: String
    public let parameters: [String: SDXAnalyticsValue]

    public init(name: String, parameters: [String: SDXAnalyticsValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// Lets an adopting app model its events as an enum and hand one straight to `track`.
///
/// The package deliberately does not know any event names. An app conforms its own taxonomy type
/// to this and keeps its names in one file, which is the only place they can be reviewed together.
public protocol SDXAnalyticsEventConvertible: Sendable {
    var analyticsEvent: SDXAnalyticsEvent { get }
}

extension SDXAnalyticsEvent: SDXAnalyticsEventConvertible {
    public var analyticsEvent: SDXAnalyticsEvent { self }
}

extension SDXAnalyticsEvent {

    /// The same event with `defaults` merged underneath its own parameters.
    ///
    /// Per-event parameters win. That matches Firebase's documented precedence for default event
    /// parameters, and it is the only order that makes sense: a super property is a fact about the
    /// session, and an event that bothers to state the same key is correcting it.
    func merging(_ defaults: [String: SDXAnalyticsValue]) -> SDXAnalyticsEvent {
        guard !defaults.isEmpty else { return self }
        return SDXAnalyticsEvent(
            name: name,
            parameters: defaults.merging(parameters) { _, own in own }
        )
    }
}
