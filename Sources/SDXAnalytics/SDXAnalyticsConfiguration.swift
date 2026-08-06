//
//  SDXAnalyticsConfiguration.swift
//  SDXAnalytics
//
//  What an adopting app decides once, at install time.
//
//  Everything vendor-specific lives on the vendor's own options type instead, so this stays the same
//  whether an app installs one destination or three.
//

import Foundation

public struct SDXAnalyticsConfiguration: Sendable, Hashable {

    public enum ValidationPolicy: String, Sendable, Hashable {
        /// Assert in DEBUG, truncate in release. The default, and almost always right — see
        /// `SDXAnalyticsNameValidator` for why truncating beats dropping.
        case sanitise
        /// Assert in DEBUG, drop in release. For an app that would rather lose an event than show a
        /// mangled name on a dashboard.
        case strict
        /// Pass everything through untouched. Only sensible when no destination has naming limits,
        /// which today means no Firebase.
        case off
    }

    public let validation: ValidationPolicy

    /// How many events to hold if they are recorded before `configure()`.
    ///
    /// SwiftUI fires the first events from `body` and `.task`, which can beat a `configure()` that
    /// waits on anything at all. Set to 0 to drop instead of buffering.
    ///
    /// Keep it small. Amplitude accepts an original timestamp for a backdated event; **Firebase has
    /// no backdating API at all**, so a buffered event reaches Firebase stamped at configure time.
    /// The buffer is a safety net against losing the first session entirely, not a place to sit.
    public let pendingEventLimit: Int

    /// Merged underneath every event's own parameters. Facts about the session rather than the event.
    public let superProperties: [String: SDXAnalyticsValue]

    /// Whether collection starts on for a user who has never expressed a preference.
    public let enabledByDefault: Bool

    /// Where the kill switch is persisted.
    ///
    /// The client persists it rather than delegating to the SDKs, because the SDKs disagree:
    /// Firebase's `setAnalyticsCollectionEnabled` survives a relaunch and Amplitude's
    /// `Configuration.optOut` does not. Left to them, a user who opted out would get Firebase
    /// silence and Amplitude noise on their second launch.
    public let persistedEnabledKey: String

    /// Whether a validation diagnostic trips `assertionFailure` in a DEBUG build.
    ///
    /// On by default, and that is the whole reason truncating in release is safe: a name that would be
    /// quietly rewritten in the field stops the developer who typed it, on the first run. The only
    /// legitimate reason to turn it off is a test that is *asserting on* sanitisation behaviour, which
    /// would otherwise trap on the very thing it is checking. No effect in a release build.
    public let assertsOnDiagnostics: Bool

    public init(
        validation: ValidationPolicy = .sanitise,
        pendingEventLimit: Int = 100,
        superProperties: [String: SDXAnalyticsValue] = [:],
        enabledByDefault: Bool = true,
        persistedEnabledKey: String = "SDXAnalytics.enabled",
        assertsOnDiagnostics: Bool = true
    ) {
        self.validation = validation
        self.pendingEventLimit = pendingEventLimit
        self.superProperties = superProperties
        self.enabledByDefault = enabledByDefault
        self.persistedEnabledKey = persistedEnabledKey
        self.assertsOnDiagnostics = assertsOnDiagnostics
    }
}
