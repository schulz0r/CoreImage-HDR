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
    
    /* Performance optimizations can be tested here */
    
    func testResponseEstimation() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        // This is an example of a performance test case.
        self.measure {
            let ResponseFunciton:[float3] = metaComp.estimateCameraResponse(iterations: 5)
        }
    }
    
    func testHistogramSpeedWith4streamingProcessors() {
        let ColourHistogramSize = 256 * 3
        let streamingMultiprocessorsPerBlock = 4
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(MTKPDevice.device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        // input images as textures
        let context = CIContext(mtlDevice: self.device)
        let Textures = Testimages.map{textureLoader.newTexture(CIImage: $0, context: context)}
        
        // cardinality of pixel values
        let MTLCardinalities = self.device.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)!
        
        var assets = MTKPAssets(ResponseCurveComputer.self)
        let CardinalityShaderRessources = CardinalityShaderIO(inputTextures: Textures, cardinalityBuffer: MTLCardinalities, ReplicationFactor: replicationFactor_R)
        let CardinalityShader = MTKPShader(name: "getCardinality",
                                           io: CardinalityShaderRessources,
                                           tgConfig: MTKPThreadgroupConfig(tgSize: (1,1,1), tgMemLength: [replicationFactor_R * (MTLCardinalities.length + MemoryLayout<uint>.size * 3)]))
        
        assets.add(shader: CardinalityShader)
        
        let MTLComputer = ResponseCurveComputer(assets: assets)
        
        
        self.measure {
            MTLComputer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
            MTLComputer.executeCardinalityShader(streamingMultiprocessorsPerBlock: streamingMultiprocessorsPerBlock)
            MTLComputer.commandBuffer.commit()
            MTLComputer.commandBuffer.waitUntilCompleted()
        }
    }
    
    func testHistogramSpeedWith2streamingProcessors() {
        let ColourHistogramSize = 256 * 3
        let streamingMultiprocessorsPerBlock = 2    // <- NOW THERE IS A TWO
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(MTKPDevice.device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        // input images as textures
        let context = CIContext(mtlDevice: self.device)
        let Textures = Testimages.map{textureLoader.newTexture(CIImage: $0, context: context)}
        
        // cardinality of pixel values
        let MTLCardinalities = self.device.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)!
        
        var assets = MTKPAssets(ResponseCurveComputer.self)
        let CardinalityShaderRessources = CardinalityShaderIO(inputTextures: Textures, cardinalityBuffer: MTLCardinalities, ReplicationFactor: replicationFactor_R)
        let CardinalityShader = MTKPShader(name: "getCardinality",
                                           io: CardinalityShaderRessources,
                                           tgConfig: MTKPThreadgroupConfig(tgSize: (1,1,1), tgMemLength: [replicationFactor_R * (MTLCardinalities.length + MemoryLayout<uint>.size * 3)]))
        
        assets.add(shader: CardinalityShader)
        
        let MTLComputer = ResponseCurveComputer(assets: assets)
        
        
        self.measure {
            MTLComputer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
            MTLComputer.executeCardinalityShader(streamingMultiprocessorsPerBlock: streamingMultiprocessorsPerBlock)
            MTLComputer.commandBuffer.commit()
            MTLComputer.commandBuffer.waitUntilCompleted()
        }
    }
    
    func testBinningShaderPerformance() {
        
    }
    
    func testResponseSummationPerformance() {
        
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
        
        textureLoader = MTKTextureLoader(device: self.device)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
}
