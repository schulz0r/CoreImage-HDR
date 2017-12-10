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
import MetalKit
@testable import CoreImage_HDR

fileprivate extension CIImage {
    func write(url: URL) {
        
        guard let pngFile = NSBitmapImageRep(ciImage: self).representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            fatalError("Could not convert to png.")
        }
        
        do {
            try pngFile.write(to: url)
        } catch let Error {
            print(Error.localizedDescription)
        }
    }
}

class CoreImage_HDRTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    var URLs:[URL] = []
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
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testHDR() {
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRProcessor.apply(withExtent: Testimages[0].extent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : self.ExposureTimes,
                                                     "CameraResponse" : Array<Float>(stride(from: 0, to: 2, by: 2.0/256.0)).map{float3($0)} ])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/noobs.png"))
        
        XCTAssertTrue(true)
    }
    
    func testCameraResponse() {
        var HDR:CIImage = CIImage()
        do{
            HDR = try HDRCameraResponseProcessor.apply(withExtent: Testimages[0].extent,
                                         inputs: Testimages,
                                         arguments: ["ExposureTimes" : self.ExposureTimes])
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        HDR.write(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/CameraResponse.png"))
        
        XCTAssertTrue(true)
    }
    
    func testHistogramShader() {
        let ColourHistogramSize = MemoryLayout<uint>.size * 256 * 3
        let MTLCardinalities = device.makeBuffer(length: ColourHistogramSize, options: .storageModeShared)
        
        guard
            let commandQ = device.makeCommandQueue(),
            let commandBuffer = commandQ.makeCommandBuffer()
        else {
            fatalError("Could not make command queue or Buffer.")
        }
        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRCameraResponseProcessor.self))
            let texture = try MTKTextureLoader(device: device).newTexture(URL: URLs[2], options: nil)
            
            guard
                let cardinalityFunction = library.makeFunction(name: "getCardinality"),
                let cardEncoder = commandBuffer.makeComputeCommandEncoder()
            else {
                fatalError()
            }
            
            let CardinalityState = try device.makeComputePipelineState(function: cardinalityFunction)
            let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
            let streamingMultiprocessorsPerBlock = 4
            let blocksize = CardinalityState.threadExecutionWidth * streamingMultiprocessorsPerBlock
            var imageSize = uint2(uint(texture.width), uint(texture.height))
            let remainer = imageSize.x % uint(blocksize)
            var replicationFactor_R:uint = max(uint(device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * MemoryLayout<uint>.size * 257 * 3)), 1)
            cardEncoder.setComputePipelineState(CardinalityState)
            cardEncoder.setTexture(texture, index: 0)
            cardEncoder.setBytes(&imageSize, length: MemoryLayout<uint2>.size, index: 0)
            cardEncoder.setBytes(&replicationFactor_R, length: MemoryLayout<uint>.size, index: 1)
            cardEncoder.setBuffer(MTLCardinalities, offset: 0, index: 2)
            cardEncoder.setThreadgroupMemoryLength(sharedColourHistogramSize * Int(replicationFactor_R), index: 0)
            cardEncoder.dispatchThreads(MTLSizeMake(texture.width + (remainer == 0 ? 0 : blocksize - (texture.width % blocksize)), texture.height, 1), threadsPerThreadgroup: MTLSizeMake(blocksize, 1, 1))
            cardEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted() // the shader is running...
            
            // now lets check the value of the cardinality histogram
            var Cardinality_Host = [uint](repeating: 0, count: 256 * 3)
            memcpy(&Cardinality_Host, MTLCardinalities!.contents(), MTLCardinalities!.length)
            
            XCTAssert(Cardinality_Host.reduce(0, +) == (3 * texture.width * texture.height))
        } catch let Errors {
            fatalError("Could not run shader: " + Errors.localizedDescription)
        }
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
}
