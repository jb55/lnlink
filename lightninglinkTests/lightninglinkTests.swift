//
//  lightninglinkTests.swift
//  lightninglinkTests
//
//  Created by William Casarin on 2022-01-07.
//

import XCTest
@testable import lightninglink

class lightninglinkTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        XCTAssert(false)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func test_parse_lnurl() throws {
        let lnurl = "LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS"
        
        let m_decode = decode_bech32(lnurl)
        XCTAssert(m_decode != nil)
        let decode = m_decode!
        
        XCTAssert(decode.hrp == "LNURL")
    }

    func testAnyAmountParsesOk() throws {
        let inv = "lnbc1p3psxjypp5335lq3qyr4vaexez53yxac5jfatdavwyq5eskkkvnrx6yw9j75vsdqvw3jhxarpdeusxqyjw5qcqpjsp5z65t0t70q4e6yp0t2rcajwslkz6uqmaw2eu5s3fkdfgaf5sdm7vsrzjqv7cv43pj3u8qy38rxwt6mm8qv6u34qg4y4w3zuk93yafhqws0sz2z2z0yqq40qqqqqqqqlgqqqqqeqqjq9qyyssqd432fhw3shf0l3zy0l3ku3xv8re6lhaayeyr8u0ayfcy46348vrzjsa46j7prz70l34wklyennpk7dzsw8eqacde74z92jylvevvdhgpzcxhyn"

        let mamt = parseInvoiceString(inv)

        XCTAssert(mamt != nil)
        let amt = mamt!

        switch amt {
        case .amount(let _):
            XCTAssert(false)
        case .any:
            XCTAssert(true)
        }
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
