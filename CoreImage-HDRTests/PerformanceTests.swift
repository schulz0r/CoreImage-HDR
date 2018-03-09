//
//  PerformanceTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 05.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import MetalKit
import MetalKitPlus
import MetalPerformanceShaders
@testable import CoreImage_HDR

class PerformanceTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    
    var URLs:[URL] = []
    var Testimages:[CIImage] = []
    var ExposureTimes:[Float] = []
    var library:MTLLibrary?
    var textureLoader:MTKTextureLoader!
    
    var computer:HDRComputer!
    
    /* Performance optimizations can be tested here */
    
    func testResponseEstimation() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 5.1)
        let metaComp = ResponseEstimator()
        // This is an example of a performance test case.
        self.measure {
            metaComp.estimate(ImageBracket: Testimages, cameraShifts: cameraShifts, cameraParameters: &camParams, iterations: 5)
        }
    }
    
    func testBinningShaderPerformance() {
        let threadsForBinReductionShader = computer.assets["reduceBins"]?.tgConfig.tgSize
        self.measure {
            computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
            computer.encode("reduceBins", threads: threadsForBinReductionShader)
            computer.commandBuffer.commit()
            computer.commandBuffer.waitUntilCompleted()
        }
    }
    
    func testResponseSummationPerformance() {
        self.measure {
            computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
            computer.encode("writeMeasureToBins")
            computer.commandBuffer.commit()
            computer.commandBuffer.waitUntilCompleted()
        }
    }
    
    /* setup and tear down functions...... */
    override func setUp() {
        super.setUp()
        
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle(for: ResponseEstimator.self))
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
        let imageNames = ["01-qianyuan-1:250", "02-qianyuan-1:125", "03-qianyuan-1:60", "04-qianyuan-1:30", "05-qianyuan-1:15"]
        
        /* Why does the Bundle Assets never contain images? Probably a XCode bug.
         Add an Asset catalogue to this test bundle and try to load any image. */
        //let AppBundle = Bundle(for: CoreImage_HDRTests.self)  // or: HDRProcessor.self, if assets belong to the other target
        //let imagePath = AppBundle.path(forResource: "myImage", ofType: "jpg")
        
        // WORKAROUND: load images from disk
        URLs = imageNames.map{FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codes/Testpics/QianYuan/" + $0 + ".jpg")}
        
        Testimages = URLs.map{
            guard let image = CIImage(contentsOf: $0) else {
                fatalError("Could not load TestImages needed for testing!")
            }
            return image
        }
        
        // load exposure times
        ExposureTimes = Testimages.map{ $0.exposureTime() }
        
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        self.computer = ResponseEstimator().computer
            
        textureLoader = MTKTextureLoader(device: self.device)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
}
