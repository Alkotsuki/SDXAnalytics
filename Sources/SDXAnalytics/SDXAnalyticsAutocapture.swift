//
//  SDXAnalyticsAutocapture.swift
//  SDXAnalytics
//
//  Which events a destination collects on its own.
//
//  Our own option set rather than Amplitude's `AutocaptureOptions` for two reasons. The core target
//  has no third-party dependency, so it cannot see Amplitude's type at all; and Amplitude's type
//  comes from a Swift 5 module and carries no `Sendable` conformance, so it could not be stored in a
//  `Sendable` options struct even if core could see it.
//

import Foundation

public struct SDXAnalyticsAutocapture: OptionSet, Sendable, Hashable {

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let sessions = SDXAnalyticsAutocapture(rawValue: 1 << 0)
    public static let appLifecycles = SDXAnalyticsAutocapture(rawValue: 1 << 1)
    public static let screenViews = SDXAnalyticsAutocapture(rawValue: 1 << 2)
    public static let elementInteractions = SDXAnalyticsAutocapture(rawValue: 1 << 3)
    public static let networkRequests = SDXAnalyticsAutocapture(rawValue: 1 << 4)

    /// Sessions and app lifecycles, and nothing else.
    ///
    /// Screen views and element interactions are UIKit view-hierarchy walkers. In a SwiftUI app they
    /// find one hosting controller and report its name for every screen in the app, which produces a
    /// large volume of data that says nothing. Emit screen events explicitly from whatever the app
    /// actually uses for routing. Network capture additionally logs the app's own API calls, which is
    /// rarely what anyone wants on a product-analytics dashboard.
    public static let `default`: SDXAnalyticsAutocapture = [.sessions, .appLifecycles]
}
