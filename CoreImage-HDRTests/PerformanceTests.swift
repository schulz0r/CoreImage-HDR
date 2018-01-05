//
//  PerformanceTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 05.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import ImageIO
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR

class PerformanceTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    
    var URLs:[URL] = []
    var Testimages:[CIImage] = []
    var ExposureTimes:[Float] = []
    var library:MTLLibrary?
    var textureLoader:MTKTextureLoader!
    
    override func setUp() {
        super.setUp()
        
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle(for: ResponseEstimator.self))
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
        let imageNames = ["dark", "medium", "bright"]
        
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
        
        // load exposure times
        ExposureTimes = Testimages.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        textureLoader = MTKTextureLoader(device: self.device)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    func testPerformanceExample() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        // This is an example of a performance test case.
        self.measure {
            let ResponseFunciton:[float3] = metaComp.estimateCameraResponse(iterations: 5)
        }
    }
    
    
}
