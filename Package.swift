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
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.17.0"),
        .package(url: "https://github.com/amplitude/Amplitude-Swift.git", from: "1.18.0"),
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
        .testTarget(
            name: "SDXAnalyticsTests",
            dependencies: [
                "SDXAnalytics",
                "SDXAnalyticsFirebase",
                "SDXAnalyticsAmplitude",
            ]
        ),
    ]
)
