//
//  SDXAdvertisingIdentifier.swift
//  SDXAnalytics
//
//  App Tracking Transparency and the ad identifier, in one place.
//
//  **This type never prompts on its own, and nothing else in this package calls it.** When the ATT
//  sheet appears is a product decision, not a library one: showing it during start-up is the classic
//  way to halve an opt-in rate, and stacking it on top of another system alert is a review risk. Only
//  the app knows what its user has just seen. So the package offers the three things that are the same
//  everywhere — the status, the request, the identifier — and leaves the timing alone.
//
//  Lives in the core target rather than a destination because `AppTrackingTransparency` and `AdSupport`
//  are system frameworks: this adds no third-party dependency, and an app that installs only Amplitude
//  can still use it. The trade-off is that every consumer links both frameworks, which is acceptable
//  because App Store privacy declarations follow from *use* rather than from linkage.
//

import AdSupport
import AppTrackingTransparency
import Foundation
import UIKit
import os

public enum SDXAdvertisingIdentifier {

    /// Mirrors `ATTrackingManager.AuthorizationStatus`.
    ///
    /// `unknown` exists because that type is a non-frozen `NS_ENUM` — without an escape hatch, a case
    /// Apple adds later would have to be mapped onto one of the existing ones, and the only safe
    /// wrong answer would be to treat it as `.authorized`, which is exactly the mistake that ships an
    /// identifier the user did not agree to.
    public enum AuthorizationStatus: String, Sendable, Hashable {
        case notDetermined
        case restricted
        case denied
        case authorized
        case unknown

        public var allowsTracking: Bool { self == .authorized }
    }

    /// The all-zeros UUID iOS returns instead of nil when tracking is not authorised.
    static let zeroedIdentifier = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    public static var authorizationStatus: AuthorizationStatus {
        map(ATTrackingManager.trackingAuthorizationStatus)
    }

    /// Show the system prompt, once, and report what the user said.
    ///
    /// Two things silently defeat this and both are worth knowing before calling it:
    ///
    /// - **The app must be foreground-active.** Called while inactive or backgrounded, iOS returns
    ///   `.denied` without showing anything, and there is no second chance — the status is now
    ///   determined. This checks and refuses rather than burning the one prompt the app gets.
    /// - **`NSUserTrackingUsageDescription` must be in the app's Info.plist.** Without it the request
    ///   is a silent denial.
    ///
    /// Calling this when the status is already determined is harmless and returns the existing answer
    /// without a prompt — which is the correct idempotency guard. Do not add a `UserDefaults` flag
    /// beside it; the system's own status is authoritative and a second flag can only disagree with it.
    @discardableResult
    public static func requestAuthorization() async -> AuthorizationStatus {
        let current = authorizationStatus
        guard current == .notDetermined else { return current }

        guard await isForegroundActive() else {
            Logger(subsystem: "SDXAnalytics", category: "tracking").warning(
                "Refused to request tracking authorisation while the app was not active; iOS would have returned denied without prompting."
            )
            return current
        }

        return map(await ATTrackingManager.requestTrackingAuthorization())
    }

    /// The IDFA, or nil.
    ///
    /// Nil whenever tracking is not authorised — including the case that catches people out, where
    /// `ASIdentifierManager` hands back the all-zeros UUID rather than nil. That is not an identifier,
    /// and a caller that forwarded it would be reporting every unauthorised device as the same user.
    public static var advertisingIdentifier: String? {
        guard authorizationStatus.allowsTracking else { return nil }
        let identifier = ASIdentifierManager.shared().advertisingIdentifier
        guard identifier != zeroedIdentifier else { return nil }
        return identifier.uuidString
    }

    // MARK: - Private

    static func map(_ status: ATTrackingManager.AuthorizationStatus) -> AuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .unknown
        }
    }

    @MainActor
    private static func isForegroundActive() -> Bool {
        UIApplication.shared.applicationState == .active
    }
}
