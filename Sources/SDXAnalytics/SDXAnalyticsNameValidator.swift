//
//  SDXAnalyticsNameValidator.swift
//  SDXAnalytics
//
//  Firebase's naming limits, enforced on every destination.
//
//  The limits below are Firebase's, and they are the strictest of any vendor here — Amplitude will
//  happily accept a 200-character event name with spaces in it. Applying the strict set to everyone
//  is the whole reason this type exists: if `enhance_completed_with_local_adjustments` silently
//  becomes `enhance_completed_with_local_adjustment` on one dashboard and stays intact on the other,
//  the two stop being comparable and nobody notices for a quarter.
//
//  The policy is to sanitise, not to drop. A truncated event still counts toward a funnel; a dropped
//  one silently corrupts it. And because DEBUG builds trip an `assertionFailure`, a release build
//  essentially never truncates in practice — the developer who typed a 45-character name hit it the
//  first time they ran.
//
//  One exception, and it is important: a **reserved prefix is dropped everywhere**. Firebase itself
//  discards `firebase_`/`google_`/`ga_` events and replaces them with an `error` event. Stripping the
//  prefix would change the event's identity; sending it anyway would put it on Amplitude and not on
//  Firebase, which breaks the one promise this type exists to keep.
//

import Foundation

public struct SDXAnalyticsNameValidator: Sendable, Hashable {

    public static let maxEventNameLength = 40
    public static let maxParameterCount = 25
    public static let maxParameterNameLength = 40
    public static let maxParameterValueLength = 100
    public static let maxUserPropertyNameLength = 24
    public static let maxUserPropertyValueLength = 36

    public static let reservedPrefixes = ["firebase_", "google_", "ga_"]

    /// The outcome of validating something. A `nil` `value` means "dropped, do not send".
    public struct Outcome<Wrapped: Sendable & Hashable>: Sendable, Hashable {
        public let value: Wrapped?
        public let diagnostics: [SDXAnalyticsDiagnostic]

        public init(value: Wrapped?, diagnostics: [SDXAnalyticsDiagnostic] = []) {
            self.value = value
            self.diagnostics = diagnostics
        }
    }

    public let policy: SDXAnalyticsConfiguration.ValidationPolicy

    public init(policy: SDXAnalyticsConfiguration.ValidationPolicy = .sanitise) {
        self.policy = policy
    }

    // MARK: - Events

    public func validate(_ event: SDXAnalyticsEvent) -> Outcome<SDXAnalyticsEvent> {
        guard policy != .off else { return Outcome(value: event) }

        var diagnostics: [SDXAnalyticsDiagnostic] = []

        if let prefix = Self.reservedPrefixes.first(where: { event.name.hasPrefix($0) }) {
            diagnostics.append(
                .init(kind: .eventNameReserved, original: event.name, replacement: prefix)
            )
            return Outcome(value: nil, diagnostics: diagnostics)
        }

        let name = sanitise(
            event.name,
            limit: Self.maxEventNameLength,
            truncated: .eventNameTruncated,
            sanitised: .eventNameSanitised,
            into: &diagnostics
        )

        guard policy != .strict || name == event.name else {
            diagnostics.append(.init(kind: .eventDropped, original: event.name))
            return Outcome(value: nil, diagnostics: diagnostics)
        }

        let parameters = validateParameters(event.parameters, into: &diagnostics)
        return Outcome(
            value: SDXAnalyticsEvent(name: name, parameters: parameters),
            diagnostics: diagnostics
        )
    }

    private func validateParameters(
        _ parameters: [String: SDXAnalyticsValue],
        into diagnostics: inout [SDXAnalyticsDiagnostic]
    ) -> [String: SDXAnalyticsValue] {
        var validated: [String: SDXAnalyticsValue] = [:]

        // Sorted, so trimming is deterministic. An event that dropped a different parameter on each
        // launch would look like two different events to anyone reading the dashboard.
        for key in parameters.keys.sorted() {
            guard let value = parameters[key] else { continue }

            guard validated.count < Self.maxParameterCount else {
                diagnostics.append(.init(kind: .parametersTrimmed, original: key))
                continue
            }

            let name = sanitise(
                key,
                limit: Self.maxParameterNameLength,
                truncated: .parameterNameTruncated,
                sanitised: .parameterNameSanitised,
                into: &diagnostics
            )

            if value.characterCount > Self.maxParameterValueLength {
                diagnostics.append(
                    .init(kind: .parameterValueTruncated, original: name)
                )
            }

            validated[name] = value.clamped(to: Self.maxParameterValueLength)
        }

        return validated
    }

    // MARK: - User properties

    public func validate(
        _ property: SDXAnalyticsUserProperty
    ) -> Outcome<SDXAnalyticsUserProperty> {
        guard policy != .off else { return Outcome(value: property) }

        var diagnostics: [SDXAnalyticsDiagnostic] = []

        let name = sanitise(
            property.name,
            limit: Self.maxUserPropertyNameLength,
            truncated: .userPropertyNameTruncated,
            sanitised: .userPropertyNameSanitised,
            into: &diagnostics
        )

        guard policy != .strict || name == property.name else {
            return Outcome(value: nil, diagnostics: diagnostics)
        }

        let mutation = clamp(property.mutation, name: name, into: &diagnostics)
        return Outcome(
            value: SDXAnalyticsUserProperty(name: name, mutation: mutation),
            diagnostics: diagnostics
        )
    }

    private func clamp(
        _ mutation: SDXAnalyticsUserProperty.Mutation,
        name: String,
        into diagnostics: inout [SDXAnalyticsDiagnostic]
    ) -> SDXAnalyticsUserProperty.Mutation {
        let limit = Self.maxUserPropertyValueLength

        switch mutation {
        case .set(let value):
            if value.characterCount > limit {
                diagnostics.append(.init(kind: .userPropertyValueTruncated, original: name))
            }
            return .set(value.clamped(to: limit))
        case .setOnce(let value):
            if value.characterCount > limit {
                diagnostics.append(.init(kind: .userPropertyValueTruncated, original: name))
            }
            return .setOnce(value.clamped(to: limit))
        case .increment, .unset:
            return mutation
        }
    }

    // MARK: - Sanitising

    /// Alphanumerics and underscores only, must start with a letter, clamped to `limit`.
    ///
    /// Order matters: substitute first, then prefix a letter if the result still starts with a digit
    /// or an underscore, and only then clamp. Clamping first would let a name that grew by one
    /// character on the prefix step exceed the limit again.
    private func sanitise(
        _ name: String,
        limit: Int,
        truncated: SDXAnalyticsDiagnostic.Kind,
        sanitised: SDXAnalyticsDiagnostic.Kind,
        into diagnostics: inout [SDXAnalyticsDiagnostic]
    ) -> String {
        var result = String(
            name.map { character in
                character.isASCII && (character.isLetter || character.isNumber) ? character
                    : character == "_" ? character
                    : "_"
            }
        )

        if result.first?.isLetter != true {
            result = "x_" + result
        }

        if result != name {
            diagnostics.append(.init(kind: sanitised, original: name, replacement: result))
        }

        guard result.count > limit else { return result }

        let clamped = String(result.prefix(limit))
        diagnostics.append(.init(kind: truncated, original: name, replacement: clamped))
        return clamped
    }
}
