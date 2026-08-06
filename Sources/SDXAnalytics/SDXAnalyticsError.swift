//
//  SDXAnalyticsError.swift
//  SDXAnalytics
//
//  The one error type, and the diagnostic the validator emits.
//
//  Only `configure()` throws. Nothing else in this package does, and that is on purpose: an
//  instrumentation call that can fail is an instrumentation call that acquires a `try` at every one
//  of several hundred call sites, and no caller has anything useful to do about a dropped event
//  anyway. Failures after configuration are logged and counted; they are never surfaced upward.
//

import Foundation

public enum SDXAnalyticsError: LocalizedError, Sendable, Hashable {
    case notConfigured
    case destinationFailed(String)
    case firebaseAppNotConfigured(String)
    case missingAPIKey(String)
    case invalidEventName(String)
    case invalidUserPropertyName(String)
    case unsupportedByDestination(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "The analytics client has not been configured."
        case .destinationFailed(let reason):
            reason
        case .firebaseAppNotConfigured(let name):
            "\(name) requires the app to have called FirebaseApp.configure() first."
        case .missingAPIKey(let name):
            "\(name) was created without an API key."
        case .invalidEventName(let name):
            "The event name \(name) is not accepted by every configured destination."
        case .invalidUserPropertyName(let name):
            "The user property name \(name) is not accepted by every configured destination."
        case .unsupportedByDestination(let reason):
            reason
        }
    }
}

/// What the validator changed on the way through, and why.
///
/// Only recorded in DEBUG, where it is drained by tests. The point is that sanitisation is never
/// silent: a name that got truncated in a release build already tripped an `assertionFailure` on
/// somebody's simulator, and this is the value that assertion reports.
public struct SDXAnalyticsDiagnostic: Sendable, Hashable {

    public enum Kind: String, Sendable, Hashable {
        case eventNameTruncated
        case eventNameSanitised
        case eventNameReserved
        case eventDropped
        case parameterNameTruncated
        case parameterNameSanitised
        case parameterValueTruncated
        case parametersTrimmed
        case userPropertyNameTruncated
        case userPropertyNameSanitised
        case userPropertyValueTruncated
        case unsupportedMutation
    }

    public let kind: Kind
    public let original: String
    public let replacement: String?

    public init(kind: Kind, original: String, replacement: String? = nil) {
        self.kind = kind
        self.original = original
        self.replacement = replacement
    }
}

extension SDXAnalyticsDiagnostic: CustomStringConvertible {
    public var description: String {
        if let replacement {
            "\(kind.rawValue): \(original) → \(replacement)"
        } else {
            "\(kind.rawValue): \(original)"
        }
    }
}
