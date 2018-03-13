//
//  CoreImage_HDRTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR


class CoreImage_HDRTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    
    var URLs:[URL] = []
    var Testimages:[CIImage] = []
    let HDRAlgorithm = MTKPHDR()
    
    override func setUp() {
        super.setUp()
    
        let imageNames = ["pic2", "pic3", "pic4", "pic5", "pic6"]
        
        /* Why does the Bundle Assets never contain images? Probably a XCode bug.
        Add an Asset catalogue to this test bundle and try to load any image. */
        //let AppBundle = Bundle(for: CoreImage_HDRTests.self)  // or: HDRProcessor.self, if assets belong to the other target
        //let imagePath = AppBundle.path(forResource: "myImage", ofType: "jpg")
        
        // WORKAROUND: load images from disk
        URLs = imageNames.map{FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codes/Testpics/" + $0 + ".jpg")}
        
        Testimages = URLs.map{
            guard let image = CIImage(contentsOf: $0) else {
                fatalError("Could not load TestImages needed for testing!")
            }
            return image
        }
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testHDR() {
        let camParams = CameraParameter(withTrainingWeight: 4)
        let imageExtent = Testimages.first!.extent
        
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRProcessor.apply(withExtent: imageExtent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : Testimages.map{$0.exposureTime()},
                                                     "CameraParameter" : camParams])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/CI-HDR.png"))
        
        XCTAssertTrue(true)
    }
    
    func testMTKPHDR() {
        let camParams = CameraParameter(withTrainingWeight: 7)
        let HDR = HDRAlgorithm.makeHDR(ImageBracket: self.Testimages, cameraParameters: camParams)
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/MTKPHDR.png"))
        
        XCTAssertTrue(true)
    }
    
    func testWithResponse() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 7, BSplineKnotCount: 8)
        let imageExtent = Testimages.first!.extent
        
        HDRAlgorithm.estimateResponse(ImageBracket: Testimages, cameraShifts: cameraShifts, cameraParameters: &camParams, iterations: 10)
        
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRProcessor.apply(withExtent: imageExtent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : Testimages.map{$0.exposureTime()},
                                                     "CameraParameter" : camParams])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/CI-HDR-response.png"))
        
        XCTAssertTrue(true)
    }
    
    func testMTKPHDRWithResponse() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 7, BSplineKnotCount: 4)
        
        HDRAlgorithm.estimateResponse(ImageBracket: Testimages, cameraShifts: cameraShifts, cameraParameters: &camParams, iterations: 10)
        let HDR = HDRAlgorithm.makeHDR(ImageBracket: self.Testimages, cameraParameters: camParams)
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/MTKPHDRwithResponse.png"))
        
        XCTAssertTrue(true)
    }
    
    func testMTKPHDRWithLessThanMaximumImages() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 7, BSplineKnotCount: 4)
        
        HDRAlgorithm.estimateResponse(ImageBracket: Testimages, cameraShifts: cameraShifts, cameraParameters: &camParams, iterations: 10)
        let HDR = HDRAlgorithm.makeHDR(ImageBracket: Array(self.Testimages[0..<2]), cameraParameters: camParams)
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/MTKPHDRWithLessThanMaximumImages.png"))
        
        XCTAssertTrue(true)
    }
}
