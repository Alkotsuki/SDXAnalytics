//
//  NameValidationTests.swift
//  SDXAnalyticsTests
//
//  The limits, and what happens at each of them.
//
//  Mostly against `SDXAnalyticsNameValidator` directly rather than through the client, because it is a
//  pure value type — which is the point of it being one.
//

import Foundation
import Testing
@testable import SDXAnalytics

struct EventNameValidationTests {

    private let validator = SDXAnalyticsNameValidator()

    @Test func aValidNamePassesThroughUntouched() throws {
        let outcome = validator.validate(SDXAnalyticsFixtures.valid)
        let event = try #require(outcome.value)
        #expect(event == SDXAnalyticsFixtures.valid)
        #expect(outcome.diagnostics.isEmpty)
    }

    @Test func anOverlongNameIsTruncatedRatherThanDropped() throws {
        let outcome = validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.overlongName))
        let event = try #require(outcome.value)
        #expect(event.name.count == SDXAnalyticsNameValidator.maxEventNameLength)
        #expect(SDXAnalyticsFixtures.overlongName.hasPrefix(event.name))
        #expect(outcome.diagnostics.contains { $0.kind == .eventNameTruncated })
    }

    @Test func truncationIsStableSoOneNameNeverBecomesTwo() throws {
        let first = try #require(
            validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.overlongName)).value
        )
        let second = try #require(
            validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.overlongName)).value
        )
        #expect(first.name == second.name)
    }

    @Test func aNameStartingWithADigitGainsALetterPrefix() throws {
        let outcome = validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.leadingDigitName))
        let event = try #require(outcome.value)
        #expect(event.name.first?.isLetter == true)
        #expect(outcome.diagnostics.contains { $0.kind == .eventNameSanitised })
    }

    @Test func punctuationBecomesUnderscores() throws {
        let outcome = validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.punctuatedName))
        let event = try #require(outcome.value)
        #expect(event.name == "enhance_completed_v2")
    }

    @Test func aReservedPrefixDropsTheEventEntirely() {
        let outcome = validator.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.reservedName))
        #expect(outcome.value == nil)
        #expect(outcome.diagnostics.contains { $0.kind == .eventNameReserved })
    }

    @Test(arguments: SDXAnalyticsNameValidator.reservedPrefixes)
    func everyReservedPrefixIsRefused(prefix: String) {
        let outcome = validator.validate(SDXAnalyticsEvent(name: prefix + "thing_happened"))
        #expect(outcome.value == nil)
    }

    @Test func theTwentySixthParameterIsTrimmed() throws {
        let outcome = validator.validate(SDXAnalyticsFixtures.overstuffed)
        let event = try #require(outcome.value)
        #expect(event.parameters.count == SDXAnalyticsNameValidator.maxParameterCount)
        #expect(outcome.diagnostics.contains { $0.kind == .parametersTrimmed })
    }

    @Test func parameterTrimmingIsDeterministicBySortedKey() throws {
        let event = try #require(validator.validate(SDXAnalyticsFixtures.overstuffed).value)
        // Keys are p00…p29; the first 25 by sort order are the ones that survive.
        #expect(event.parameters["p00"] != nil)
        #expect(event.parameters["p24"] != nil)
        #expect(event.parameters["p25"] == nil)
        #expect(event.parameters["p29"] == nil)
    }

    @Test func anOverlongStringValueIsClamped() throws {
        let outcome = validator.validate(
            SDXAnalyticsEvent(name: "thing_happened", parameters: ["note": .string(SDXAnalyticsFixtures.longText)])
        )
        let event = try #require(outcome.value)
        guard case .string(let note) = try #require(event.parameters["note"]) else {
            Issue.record("expected a string parameter")
            return
        }
        #expect(note.count == SDXAnalyticsNameValidator.maxParameterValueLength)
        #expect(outcome.diagnostics.contains { $0.kind == .parameterValueTruncated })
    }

    @Test func numericValuesAreNeverClamped() throws {
        let outcome = validator.validate(
            SDXAnalyticsEvent(name: "thing_happened", parameters: ["ms": .int(1_234_567_890)])
        )
        let event = try #require(outcome.value)
        #expect(event.parameters["ms"] == .int(1_234_567_890))
        #expect(outcome.diagnostics.isEmpty)
    }

    @Test func strictPolicyDropsWhatSanitiseWouldRewrite() {
        let strict = SDXAnalyticsNameValidator(policy: .strict)
        #expect(strict.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.overlongName)).value == nil)
        #expect(strict.validate(SDXAnalyticsFixtures.valid).value != nil)
    }

    @Test func offPolicyPassesEverythingThrough() throws {
        let off = SDXAnalyticsNameValidator(policy: .off)
        let event = try #require(off.validate(SDXAnalyticsEvent(name: SDXAnalyticsFixtures.reservedName)).value)
        #expect(event.name == SDXAnalyticsFixtures.reservedName)
    }
}

struct UserPropertyValidationTests {

    private let validator = SDXAnalyticsNameValidator()

    @Test func userPropertyLimitsAreTighterThanEventLimits() {
        #expect(
            SDXAnalyticsNameValidator.maxUserPropertyNameLength
                < SDXAnalyticsNameValidator.maxEventNameLength
        )
        #expect(
            SDXAnalyticsNameValidator.maxUserPropertyValueLength
                < SDXAnalyticsNameValidator.maxParameterValueLength
        )
    }

    @Test func anOverlongPropertyNameIsClampedToTwentyFour() throws {
        let outcome = validator.validate(.set("a_very_long_user_property_name_indeed", "x"))
        let property = try #require(outcome.value)
        #expect(property.name.count == SDXAnalyticsNameValidator.maxUserPropertyNameLength)
    }

    @Test func anOverlongPropertyValueIsClampedToThirtySix() throws {
        let outcome = validator.validate(.set("cohort", .string(SDXAnalyticsFixtures.longText)))
        let property = try #require(outcome.value)
        guard case .set(let value) = property.mutation, case .string(let text) = value else {
            Issue.record("expected a set mutation carrying a string")
            return
        }
        #expect(text.count == SDXAnalyticsNameValidator.maxUserPropertyValueLength)
    }

    @Test func anIncrementCarriesNoValueToClamp() throws {
        let outcome = validator.validate(.increment("lifetime_edits", by: 1))
        let property = try #require(outcome.value)
        #expect(property.mutation == .increment(1))
        #expect(outcome.diagnostics.isEmpty)
    }
}
