//
//  FacebookMappingTests.swift
//  SDXAnalyticsTests
//
//  The Facebook translation as a pure function — nothing here touches `AppEvents`.
//

import FacebookCore
import Foundation
import Testing
@testable import SDXAnalytics
@testable import SDXAnalyticsFacebook

struct FacebookMappingTests {

    @Test func booleansFlattenToOneAndZeroLikeTheOtherDestinations() {
        let mapped = FacebookParameterMapper.map(["a": .bool(true), "b": .bool(false)])
        #expect(mapped[AppEvents.ParameterName("a")] as? Int == 1)
        #expect(mapped[AppEvents.ParameterName("b")] as? Int == 0)
    }

    @Test func stringsAndNumbersPassThrough() {
        let mapped = FacebookParameterMapper.map(["s": .string("x"), "i": .int(3), "d": .double(1.5)])
        #expect(mapped[AppEvents.ParameterName("s")] as? String == "x")
        #expect(mapped[AppEvents.ParameterName("i")] as? Int == 3)
        #expect(mapped[AppEvents.ParameterName("d")] as? Double == 1.5)
    }

    @Test func conversionValueReadsNumericValueOnly() {
        #expect(FacebookParameterMapper.conversionValue(["value": .int(3)]) == 3)
        #expect(FacebookParameterMapper.conversionValue(["value": .double(1.5)]) == 1.5)
        #expect(FacebookParameterMapper.conversionValue(["value": .string("x")]) == nil)
        #expect(FacebookParameterMapper.conversionValue([:]) == nil)
    }

    @Test func conversionCurrencyBecomesFacebookCurrency() {
        let mapped = FacebookParameterMapper.conversionParameters(["value": .double(9.99), "currency": .string("USD")])
        #expect(mapped[.currency] as? String == "USD")
        #expect(FacebookParameterMapper.conversionParameters(["value": .int(1)])[.currency] == nil)
    }

    @Test func purchaseCarriesTheKeysTheSDKDeduplicatesOn() {
        let purchase = SDXAnalyticsPurchase(
            productID: "pro.monthly", price: 9.99, currencyCode: "USD", transactionID: "t1"
        )
        let mapped = FacebookParameterMapper.purchaseParameters(purchase)
        #expect(mapped[.contentID] as? String == "pro.monthly")
        #expect(mapped[.transactionID] as? String == "t1")
    }
}
