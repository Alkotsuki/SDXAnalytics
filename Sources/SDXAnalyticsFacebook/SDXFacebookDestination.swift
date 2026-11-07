//
//  SDXFacebookDestination.swift
//  SDXAnalyticsFacebook
//
//  Facebook App Events, behind `AnalyticsDestination`.
//
//  **The app should own SDK start-up; this destination makes sure it happened.** Facebook wants
//  `ApplicationDelegate.shared.application(_:didFinishLaunchingWithOptions:)` called from the app
//  delegate. But a SwiftUI `App.init` runs *before* the delegate's `didFinishLaunching`, so an app that
//  configures analytics there reaches this destination with the SDK not yet started. Reading
//  `Settings.shared.appID` at that point is not just "empty": `Settings` reads it from Info.plist
//  through a `lazy var` whose dependencies are not wired until the SDK initialises, so the early read
//  caches `nil` **for the whole process** and every later App Event fails, the SDK's own included.
//
//  So `configure()` calls `ApplicationDelegate.shared.initializeSDK()` first. It is idempotent — a no-op
//  if the app delegate already started the SDK, which is still the right order. The trade-off when this
//  destination gets there first: `initializeSDK()` marks the SDK initialised, so the app delegate's own
//  `application(_:didFinishLaunchingWithOptions:)` later returns early and its extra work never runs —
//  the launch options (the URL / source application of a deep-link launch, used for App Link
//  attribution) are lost, the `fb_sdk_initialize` auto-event and the server-configuration fetch it
//  starts are skipped, and Login/Share launch observers are not notified. `setEnabled(true)` replays
//  `activateApp()`, which fetches the server configuration, so an App-Events-only app loses only the
//  deep-link attribution. An app that cares about that must start the SDK in its delegate before
//  configuring analytics, exactly as before; this path is the safety net, not the recommendation.
//
//  **Threads.** Whether the SDK has started is read from `Settings.shared.clientToken`: the SDK has no
//  public "is initialised" flag, and unlike `appID` the client token is read through a getter that
//  returns nil *without caching* until `initializeSDK()` has wired `Settings`' dependencies, so checking
//  it cannot poison anything. (It needs `FacebookClientToken` in Info.plist, which App Events require
//  anyway.) If the app already started the SDK, `configure()` succeeds on any thread — the normal case,
//  since `SDXAnalyticsClient.configure()` is typically run on a background queue. If it has not, starting
//  it touches `UIApplication` and needs the main thread: on main, `configure()` starts it; off main it
//  throws and the client reports the failure loudly. It does not hop to main: `configure()` is
//  synchronous, so that would be `DispatchQueue.main.sync`, which deadlocks whenever main is itself
//  waiting on the queue that configures analytics.
//
//  **The kill switch is two things, because the SDK has no single one.** The SDK logs its own events
//  (install, app activation) when `FacebookAutoLogAppEventsEnabled` allows, and nothing in `AppEvents`
//  stops a custom `logEvent`. So `setEnabled` flips `Settings.isAutoLogAppEventsEnabled` for the former
//  and gates `track` on a flag for the latter. An app that must stay silent until this destination
//  enables it (a debug build, a user who opted out) sets `FacebookAutoLogAppEventsEnabled` to `NO` in its
//  Info.plist, so the SDK is quiet from the first launch rather than from the first `setEnabled`.
//
//  What Facebook cannot express is left defaulted: user properties (it has a separate `setUserData`
//  with fixed PII fields, which this package never carries), super properties, and screen views.
//

import Foundation
import FacebookCore
import SDXAnalytics
import os

public final class SDXFacebookDestination: AnalyticsDestination, @unchecked Sendable {

    public let name = "facebook"

    private let enabled = OSAllocatedUnfairLock(initialState: false)

    private let conversionEvents: [String: AppEvents.Name]

    /// Test seam. See "Threads" in the file header for why this is the signal.
    private let isSDKStarted: @Sendable () -> Bool

    /// - Parameter conversionEvents: SDX event name → Facebook standard (conversion) event, e.g.
    ///   `["signup_completed": .completedRegistration, "trial_started": .startTrial]`. A mapped event is
    ///   logged under the standard name so Meta can optimise ads for it, its `value` parameter (if
    ///   numeric) becomes `valueToSum`, and its `currency` parameter becomes `fb_currency`. Unmapped events
    ///   keep their own name. Never map to `.purchased`: purchases go through `trackPurchase`, and a
    ///   second path would count them twice. A free trial is a zero-price purchase that
    ///   `SDXAnalyticsClient.purchase` drops, so map its event to `.startTrial` to get it into Ads Manager.
    public convenience init(conversionEvents: [String: AppEvents.Name] = [:]) {
        self.init(conversionEvents: conversionEvents, isSDKStarted: {
            Settings.shared.clientToken?.isEmpty == false
        })
    }

    init(conversionEvents: [String: AppEvents.Name], isSDKStarted: @escaping @Sendable () -> Bool) {
        precondition(
            !conversionEvents.values.contains(.purchased),
            "Log purchases with SDXAnalyticsClient.purchase, not a .purchased conversion event."
        )
        self.conversionEvents = conversionEvents
        self.isSDKStarted = isSDKStarted
    }

    public func configure() throws {
        // See the file header. Nothing may read `Settings.shared.appID` before the SDK has started,
        // or the app ID is cached as nil for the process.
        if !isSDKStarted() {
            guard Thread.isMainThread else {
                throw SDXAnalyticsError.destinationFailed(Self.notStartedOffMain)
            }
            ApplicationDelegate.shared.initializeSDK()
            guard isSDKStarted() else {
                throw SDXAnalyticsError.destinationFailed(
                    "facebook: the Facebook SDK started without a FacebookClientToken in Info.plist."
                )
            }
        }
        guard Settings.shared.appID?.isEmpty == false else {
            throw SDXAnalyticsError.missingAPIKey(name)
        }
    }

    static let notStartedOffMain =
        "facebook: the Facebook SDK was not started (or FacebookClientToken is missing) and configure() ran off the main thread. Start the SDK on main first."

    public func setEnabled(_ enabled: Bool) {
        let changed = self.enabled.withLock { current -> Bool in
            defer { current = enabled }
            return current != enabled
        }
        Settings.shared.isAutoLogAppEventsEnabled = enabled
        // The SDK logs the install and the first activation from `didBecomeActive`, which has already
        // happened by the time the client enables us. Replay it, once.
        if enabled, changed { AppEvents.shared.activateApp() }
    }

    public func track(_ event: SDXAnalyticsEvent) {
        guard enabled.withLock({ $0 }) else { return }
        guard let standard = conversionEvents[event.name] else {
            AppEvents.shared.logEvent(
                AppEvents.Name(event.name),
                parameters: FacebookParameterMapper.map(event.parameters)
            )
            return
        }
        let parameters = FacebookParameterMapper.conversionParameters(event.parameters)
        if let value = FacebookParameterMapper.conversionValue(event.parameters) {
            AppEvents.shared.logEvent(standard, valueToSum: value, parameters: parameters)
        } else {
            AppEvents.shared.logEvent(standard, parameters: parameters)
        }
    }

    public func setUserID(_ id: String?) {
        AppEvents.shared.userID = id
    }

    public func trackPurchase(_ purchase: SDXAnalyticsPurchase) {
        // Zero-price purchases never get here; `SDXAnalyticsClient.purchase` drops them.
        guard enabled.withLock({ $0 }) else { return }
        // The **total**, like Firebase; the quantity rides along as `fb_num_items`.
        AppEvents.shared.logPurchase(
            amount: NSDecimalNumber(decimal: purchase.revenue).doubleValue,
            currency: purchase.currencyCode,
            parameters: FacebookParameterMapper.purchaseParameters(purchase)
        )
    }

    public func flush() {
        AppEvents.shared.flush()
    }

    public func reset() {
        AppEvents.shared.userID = nil
        AppEvents.shared.clearUserData()
    }
}
