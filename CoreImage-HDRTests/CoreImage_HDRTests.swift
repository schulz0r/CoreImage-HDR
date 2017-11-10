//
//  CoreImage_HDRTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
@testable import CoreImage_HDR

class CoreImage_HDRTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        var pix:[CIImage] = [#imageLiteral(resourceName: "dunkel"), #imageLiteral(resourceName: "mittel"), #imageLiteral(resourceName: "hell")].map{CIImage(data: $0.tiffRepresentation!)!}
        XCTAssert(true)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
