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
}
