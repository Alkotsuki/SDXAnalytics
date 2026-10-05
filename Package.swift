// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDXAnalytics",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SDXAnalytics", targets: ["SDXAnalytics"]),
        .library(name: "SDXAnalyticsFirebase", targets: ["SDXAnalyticsFirebase"]),
        .library(name: "SDXAnalyticsAmplitude", targets: ["SDXAnalyticsAmplitude"]),
        .library(name: "SDXAnalyticsCrashlytics", targets: ["SDXAnalyticsCrashlytics"]),
        .library(name: "SDXAnalyticsFacebook", targets: ["SDXAnalyticsFacebook"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.19.0"),
        .package(url: "https://github.com/amplitude/Amplitude-Swift.git", from: "1.19.0"),
        .package(url: "https://github.com/facebook/facebook-ios-sdk", from: "18.1.0"),
    ],
    targets: [
        .target(name: "SDXAnalytics"),
        .target(
            name: "SDXAnalyticsFirebase",
            dependencies: [
                "SDXAnalytics",
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
            ]
        ),
        .target(
            name: "SDXAnalyticsAmplitude",
            dependencies: [
                "SDXAnalytics",
                .product(name: "AmplitudeSwift", package: "Amplitude-Swift"),
            ]
        ),
        .target(
            name: "SDXAnalyticsCrashlytics",
            dependencies: [
                "SDXAnalytics",
                "SDXAnalyticsFirebase",
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
            ]
        ),
        .target(
            name: "SDXAnalyticsFacebook",
            dependencies: [
                "SDXAnalytics",
                .product(name: "FacebookCore", package: "facebook-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "SDXAnalyticsTests",
            dependencies: [
                "SDXAnalytics",
                "SDXAnalyticsFirebase",
                "SDXAnalyticsAmplitude",
                "SDXAnalyticsCrashlytics",
                "SDXAnalyticsFacebook",
            ]
        ),
    ]
)
