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
    
    var computer:ResponseCurveComputer!
    
    /* Performance optimizations can be tested here */
    
    func testResponseEstimation() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        // This is an example of a performance test case.
        self.measure {
            metaComp.estimateCameraResponse(iterations: 5)
        }
    }
    
    func testBinningShaderPerformance() {
        let threadsForBinReductionShader = computer.assets["reduceBins"]?.tgConfig.tgSize
        self.measure {
            computer.commandBuffer = computer.commandQueue.makeCommandBuffer()
            computer.encode("reduceBins", threads: threadsForBinReductionShader)
            computer.commandBuffer.commit()
            computer.commandBuffer.waitUntilCompleted()
        }
    }
    
    func testResponseSummationPerformance() {
        self.measure {
            computer.commandBuffer = computer.commandQueue.makeCommandBuffer()
            computer.encode("writeMeasureToBins")
            computer.commandBuffer.commit()
            computer.commandBuffer.waitUntilCompleted()
        }
    }
    
    func testMPS() {
        guard let textures = computer.assets["writeMeasureToBins"]?.textures else {
            fatalError()
        }
        
        var histogramInfo = MPSImageHistogramInfo(
            numberOfHistogramEntries: 256, histogramForAlpha: false,
            minPixelValue: vector_float4(0,0,0,0),
            maxPixelValue: vector_float4(1,1,1,1))
        
        let calculation = MPSImageHistogram(device: device, histogramInfo: &histogramInfo)
        let bufferLength = calculation.histogramSize(forSourceFormat: textures[0].pixelFormat)
        let histogramInfoBuffer = MTKPDevice.device.makeBuffer(length: bufferLength, options: .storageModeShared)!
        
        self.measure {
            computer.commandBuffer = computer.commandQueue.makeCommandBuffer()
            textures.forEach({ texture in
                calculation.encode(to: computer.commandBuffer,
                                   sourceTexture: texture,
                                   histogram: histogramInfoBuffer,
                                   histogramOffset: 0)
            })
            computer.commandBuffer.commit()
            computer.commandBuffer.waitUntilCompleted()
        }
        
        var histogram = [uint](repeating: 0, count: 768)
        memcpy(&histogram, histogramInfoBuffer.contents(), bufferLength)
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
        ExposureTimes = Testimages.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        self.computer = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts).computer
            
        textureLoader = MTKTextureLoader(device: self.device)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
}
