# SDXAnalytics

One logger interface that fans events out to Firebase Analytics and Amplitude at the same time, with
either installable on its own. Swift 6, strict concurrency, iOS 17+.

The package knows nothing about any particular app: no event names, no user properties, no API keys.
It takes a name and some typed parameters, applies the naming rules the strictest backend imposes,
and hands the result to every destination you installed. What to log is the app's business.

## Why it looks like this

**Three products, not one.** `SDXAnalytics` is the whole public API and has no third-party dependency
at all; `SDXAnalyticsFirebase` and `SDXAnalyticsAmplitude` are thin adapters you link only if you pay
for that dashboard. A single product would drag a static Firebase xcframework and fourteen transitive
Google packages into an app that only wanted Amplitude. SwiftPM still *resolves and fetches* both
graphs — the split saves compiling and linking, not fetching.

Package traits look like the tidier answer and are not one yet. SE-0450 applies traits *after*
dependency resolution and there is no trait-conditional `.package(...)` form, so a trait-gated
Firebase is still fetched and still pinned; traits would save exactly what these three products
already save. And an adopting `.xcodeproj` has no app-level manifest in which to select a trait.
Revisit when SwiftPM gates resolution on traits.

**`track` is synchronous.** It is called from button actions and `onAppear` closures — several hundred
call sites in a real app. An actor would make every one of them `await`, which in a synchronous
context means `Task { }`, and that costs two things worth more than the tidiness: ordering, because
two funnel steps in the same millisecond would no longer necessarily arrive in the order the user did
them; and delivery, because a `Task` spawned from a view can be cancelled on teardown, so the event
most worth having — the last one before the user left — is the one that goes missing. State lives
behind an `OSAllocatedUnfairLock`, and no SDK call ever happens inside it.

**Firebase's limits are applied to everyone.** Event name ≤ 40 characters, ≤ 25 parameters, string
values ≤ 100, user-property names ≤ 24 and values ≤ 36. Amplitude would accept far more, and letting
it means the two dashboards stop being comparable the first time a long name is silently trimmed on
one of them and not the other. Names are sanitised rather than dropped — a truncated event still
counts toward a funnel, a dropped one silently corrupts it — and a DEBUG build trips an
`assertionFailure`, so by the time anything ships the developer who typed a 45-character name has
already seen it. Reserved `firebase_`/`google_`/`ga_` prefixes are the one exception and are dropped
everywhere, because Firebase itself discards them and sending them to Amplitude alone would break the
one promise this type exists to keep.

**The kill switch is persisted here, not by the SDKs.** `Analytics.setAnalyticsCollectionEnabled`
survives a relaunch; Amplitude's `Configuration.optOut` is read from its init parameter and never
restored from storage. Left to the vendors, a user who opted out would get Firebase silence and
Amplitude noise on their second launch. `configure()` reads the stored flag and re-applies it to both
before any event is sent.

**One purchase type, because the vendors disagree about it.** Amplitude wants the *unit* price and
multiplies by quantity itself; Firebase wants the *total*. `SDXAnalyticsPurchase.revenue` computes
that once so the two cannot drift. **A zero-price purchase is not revenue and is dropped by
`SDXAnalyticsClient.purchase`** before any destination sees it: a free-trial start would otherwise be a
Firebase `purchase` worth 0, an Amplitude revenue event worth 0 and a Facebook `fb_mobile_purchase`.
Track a trial as an ordinary event (`trial_started`) and, for Facebook, map it to `.startTrial` with
`SDXFacebookDestination(conversionEvents:)`. Each vendor also gets the transaction id for its own
de-duplication (Firebase `transaction_id`, Facebook `fb_transaction_id`, Amplitude `insert_id`).

**This package never asks for ATT.** `SDXAdvertisingIdentifier` offers the status, the request and the
identifier; nothing else in the package calls it. When the prompt appears is a product decision —
showing it during start-up is the classic way to halve an opt-in rate, and only the app knows what its
user has just seen. The helper refuses to prompt while the app is not foreground-active, because iOS
would return `.denied` without showing anything and there is no second chance.

**Events recorded before `configure()` are buffered**, bounded, FIFO, oldest dropped first, with a
logged drop count. SwiftUI fires the first events from `body` and `.task`, which can beat a
`configure()` that waits on anything. Keep the buffer small: Amplitude accepts a backdated timestamp,
**Firebase has no backdating API**, so a buffered event reaches Firebase stamped at configure time.

**A destination that fails to configure is struck off, not fatal.** `configure()` does not throw. One
vendor with a bad key must not silence the other, and an app that crashed on a Firebase
misconfiguration would be trading all of its telemetry for one dashboard. But it is not quiet: the failure is
logged at `.fault` and tracked as `analytics_destination_failed` (`destination`, `reason`) to every
destination that did come up, so a dead vendor shows on the dashboards that are alive.

**The Facebook destination starts the Facebook SDK if the app has not.** A SwiftUI `App.init` runs
before the app delegate's `didFinishLaunching`, and reading Facebook's settings before the SDK starts
caches an empty app ID for the whole process. `SDXFacebookDestination.configure()` therefore checks
whether the SDK has started (via `Settings.shared.clientToken`, which needs `FacebookClientToken` in
Info.plist and is safe to read early). If it has, `configure()` works on any thread. If it has not,
`configure()` calls `ApplicationDelegate.shared.initializeSDK()` on the main thread, or fails loudly
when run off it. Starting the SDK on the main thread *before* `configure()` is still preferred: when the destination gets there first, the
delegate's own `didFinishLaunching` call becomes a no-op and deep-link launch options are lost. See the
header of `SDXFacebookDestination.swift`.

## Use

```swift
import SDXAnalytics
import SDXAnalyticsAmplitude
import SDXAnalyticsFirebase

let analytics = SDXAnalyticsClient(
    destinations: [
        SDXFirebaseDestination(),
        SDXAmplitudeDestination(options: .init(apiKey: "…", serverZone: .eu)),
    ]
)

// At launch, in App.init — before the first view body runs.
analytics.configure()

analytics.setUserProperty("preferred_path", "cloud")
analytics.track("enhance_completed", ["path": "cloud", "duration_ms": 1840, "did_fall_back": false])
analytics.purchase(
    SDXAnalyticsPurchase(
        productID: "com.example.pack.30",
        price: Decimal(string: "4.99")!,   // the UNIT price
        currencyCode: "USD",
        quantity: 1
    )
)

// After your own ATT decision, at whatever moment you chose.
_ = await SDXAdvertisingIdentifier.requestAuthorization()
analytics.setAdvertisingIdentifier(SDXAdvertisingIdentifier.advertisingIdentifier)
```

Model your own taxonomy as an enum and conform it to `SDXAnalyticsEventConvertible`, so every name in
the app is reviewable in one file:

```swift
extension MyEvent: SDXAnalyticsEventConvertible {
    var analyticsEvent: SDXAnalyticsEvent { .init(name: name, parameters: parameters) }
}

analytics.track(MyEvent.enhanceCompleted(path: .cloud, durationMilliseconds: 1840))
```

> `SDXAnalyticsFirebase` links **`FirebaseAnalyticsCore`**, which contains no IDFA collection, so
> adopting this package does not by itself oblige you to declare tracking. If you want the ad
> identifier, add Firebase's own additive `FirebaseAnalyticsIdentitySupport` product to your app
> target; nothing in this package changes. Both variants vend the same `FirebaseAnalytics` module, so
> the mistake is invisible in source and only surfaces in App Store review.

> `IS_ANALYTICS_ENABLED` in `GoogleService-Info.plist` is a **dead key** — the string does not appear
> in the shipping GoogleAppMeasurement binary. The keys the SDK reads are
> `FIREBASE_ANALYTICS_COLLECTION_ENABLED` and `FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED`, and both
> live in the app's **Info.plist**. Never build a kill switch on the `_DEACTIVATED` one: it is
> permanent for the install and `setAnalyticsCollectionEnabled(true)` cannot undo it.

## Adding another system

Conform to `AnalyticsDestination`. Only `configure()`, `track(_:)` and `setEnabled(_:)` have no
default — everything else is a no-op, so a vendor with no concept of super properties or of an
advertising identifier simply leaves those alone. Do not fake a capability the vendor lacks; a mapping
that pretends produces a dashboard that quietly disagrees with its neighbour.

## Testing

This package is iOS-only with no macOS platform declared, so `swift test` cannot build it. Tests run
on a Simulator destination, against the **aggregate** scheme — `SDXAnalytics` is the library product
scheme and carries no test action:

```bash
xcodebuild test -scheme SDXAnalytics-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`Support/FakeAnalyticsDestination` is a scriptable recorder — a class over a lock rather than an actor,
because `AnalyticsDestination` is synchronous and an actor could not conform without hiding the calls
behind `Task`s, which would make the fan-out arrive after the `#expect` checking for it.

The vendor mappings are covered as **pure functions** (`FirebaseParameterMapper`,
`AmplitudeRevenueMapper`) rather than through a configured SDK: `FirebaseApp.configure()` is a
process-wide one-shot side effect and an `Amplitude` instance opens storage and a network client.
Nothing here proves either vendor actually *delivered* anything — that needs a real key and a
dashboard, and is a manual step (`-FIRDebugEnabled` plus Firebase DebugView, and Amplitude's live
event stream). The mappers are pure precisely so everything up to the SDK boundary is covered without
one.

`SDXAnalyticsTests` depends on all three products. That is the only thing compiling the two vendor
mappings in CI; it costs a Firebase download on a cold checkout, and a mapping that silently stopped
compiling costs a release.

A run logs a `kTCCErrorDomain` line from reading the ATT status in a bare test host with no bundle
identity. It is OS noise, not a failure.
