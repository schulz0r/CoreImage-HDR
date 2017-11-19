//
//  CoreImage_HDRTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import AppKit
import ImageIO
@testable import CoreImage_HDR

fileprivate extension CIImage {
    func write(url: URL) {
        do {
            try NSBitmapImageRep(ciImage: self).representation(using: NSBitmapImageRep.FileType.png, properties: [:])?.write(to: url)
        } catch let Error {
            print(Error.localizedDescription)
        }
    }
}

class CoreImage_HDRTests: XCTestCase {
    
    var Testimages:[CIImage] = []
    var ExposureTimes:[Float] = []
    
    override func setUp() {
        super.setUp()
        let imageNames = ["dark", "medium", "bright"]
        
        /* Why does the Bundle Assets never contain images? Probably a XCode bug.
        Add an Asset catalogue to this test bundle and try to load any image. */
        //let AppBundle = Bundle(for: CoreImage_HDRTests.self)  // or: HDRProcessor.self, if assets belong to the other target
        //let imagePath = AppBundle.path(forResource: "myImage", ofType: "jpg")
        
        // WORKAROUND: load images from disk
        let URLs = imageNames.map{FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codes/Testpics/" + $0 + ".jpg")}
        
        Testimages = URLs.map{
            guard let image = CIImage(contentsOf: $0) else {
                fatalError("Could not load TestImages needed for testing!")
            }
            return image
        }
        
        // load exposure times
        ExposureTimes = Testimages.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary")
            }
            return metaData["ExposureTime"] as! Float
        }
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testHDR() {
        guard let HDR = try? HDRProcessor.apply(withExtent: Testimages[0].extent,
                                          inputs: Testimages,
                                          arguments: ["ExposureTimes" : self.ExposureTimes,
                                                      "CameraResponse" : Array<Float>(stride(from: 0, to: 2, by: 1.0/255.0))]
            ) else {
                fatalError()
        }
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/noob.png"))
        XCTAssertNotNil(HDR)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
}
