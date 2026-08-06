//
//  SDXAnalyticsUserProperty.swift
//  SDXAnalytics
//
//  A user property and the way it changes.
//
//  The mutation is part of the value rather than four separate methods on the destination, because
//  the vendors do not agree on which mutations exist. Amplitude can express all four; Firebase can
//  express `set` and `unset` and has neither a set-once nor an atomic increment. Naming them here
//  means the asymmetry is visible in one place and reported as a diagnostic when a destination
//  cannot honour a mutation — rather than a caller quietly getting an overwrite where it asked for
//  a set-once and never finding out.
//

import Foundation

public struct SDXAnalyticsUserProperty: Sendable, Hashable {

    public enum Mutation: Sendable, Hashable {
        case set(SDXAnalyticsValue)
        /// Written only if the property has no value yet. Firebase has no equivalent and will
        /// overwrite; it reports `unsupportedMutation` when it does.
        case setOnce(SDXAnalyticsValue)
        /// Added to the current value. Firebase has no equivalent and skips it entirely.
        case increment(Double)
        case unset
    }

    public let name: String
    public let mutation: Mutation

    public init(name: String, mutation: Mutation) {
        self.name = name
        self.mutation = mutation
    }

    public static func set(_ name: String, _ value: SDXAnalyticsValue) -> Self {
        Self(name: name, mutation: .set(value))
    }

    public static func setOnce(_ name: String, _ value: SDXAnalyticsValue) -> Self {
        Self(name: name, mutation: .setOnce(value))
    }

    public static func increment(_ name: String, by amount: Double) -> Self {
        Self(name: name, mutation: .increment(amount))
    }

    public static func unset(_ name: String) -> Self {
        Self(name: name, mutation: .unset)
    }
}

extension SDXAnalyticsUserProperty.Mutation {

    /// The value being written, when there is one. `nil` for `unset`, and for `increment` because a
    /// delta is not a value — a destination that can only set has nothing useful to do with it.
    var value: SDXAnalyticsValue? {
        switch self {
        case .set(let value), .setOnce(let value):
            value
        case .increment, .unset:
            nil
        }
    }
}
