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
    var library:MTLLibrary?
    
    override func setUp() {
        super.setUp()
        
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRCameraResponseProcessor.self))
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
            let texture = try MTKTextureLoader(device: device).newTexture(URL: URLs[2], options: nil)
            
            guard
                let cardinalityFunction = library!.makeFunction(name: "getCardinality"),
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
    
    func testBinningShader(){
        let lengthOfBuffer = 512;
        guard let commandQ = device.makeCommandQueue() else {fatalError()}
        var TextureFill = [float3](repeating: float3(1.0), count: lengthOfBuffer)
        var FunctionDummy = [float3](repeating: float3(1.0), count: lengthOfBuffer)
        
        // allocate half size buffer
        guard
            let imageBuffer = device.makeBuffer(bytes: &TextureFill, length: lengthOfBuffer * MemoryLayout<float3>.size, options: .storageModeManaged),
            let MTLFunctionDummyBuffer = device.makeBuffer(bytes: &FunctionDummy, length: lengthOfBuffer * MemoryLayout<float3>.size, options: .storageModeManaged)
        else {fatalError()}
        
        let testTextureDescriptor = MTLTextureDescriptor()
        testTextureDescriptor.textureType = .type2D
        testTextureDescriptor.height = 16
        testTextureDescriptor.width = 32
        testTextureDescriptor.depth = 1
        testTextureDescriptor.pixelFormat = .rgba32Float
        guard let testTexture = device.makeTexture(descriptor: testTextureDescriptor) else {fatalError()}
        
        let binningBlock = MTLSizeMake(16, 16, 1)
        let bufferLength = MemoryLayout<float3>.size * lengthOfBuffer
        
        let imageDimensions = MTLSizeMake(testTexture.width, testTexture.height, 1)
        
        // collect image in bins
        guard
            let biningFunc = library!.makeFunction(name: "writeMeasureToBins<float3>"),
            let commandBuffer = commandQ.makeCommandBuffer(),
            let blitencoder = commandBuffer.makeBlitCommandEncoder(),
            let buffer = device.makeBuffer(length: bufferLength, options: .storageModeManaged)
        else {
                fatalError("Failed to create command encoder.")
        }
        
        blitencoder.copy(from: imageBuffer,
                         sourceOffset: 0,
                         sourceBytesPerRow: imageBuffer.length / imageDimensions.height,
                         sourceBytesPerImage: imageBuffer.length,
                         sourceSize: imageDimensions,
                         to: testTexture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: MTLOriginMake(0, 0, 0))
        blitencoder.endEncoding()
        
        guard let BinEncoder = commandBuffer.makeComputeCommandEncoder() else {fatalError()}
        
        var imageCount:uint = 1
        var cameraShifts = int2(0,0)
        var exposureTime:Float = 1
        
        do {
            let biningState = try device.makeComputePipelineState(function: biningFunc)
            BinEncoder.setComputePipelineState(biningState)
            BinEncoder.setTexture(testTexture, index: 0)
            BinEncoder.setBuffer(buffer, offset: 0, index: 0)
            BinEncoder.setBytes(&imageCount, length: MemoryLayout<uint>.size, index: 1)
            BinEncoder.setBytes(&cameraShifts, length: MemoryLayout<int2>.size, index: 2)
            BinEncoder.setBytes(&exposureTime, length: MemoryLayout<Float>.size, index: 3)
            BinEncoder.setBuffers([MTLFunctionDummyBuffer, MTLFunctionDummyBuffer], offsets: [0,0], range: Range<Int>(4...5)) // only write ones here
            BinEncoder.setThreadgroupMemoryLength((MemoryLayout<Float>.size/2 + MemoryLayout<ushort>.size) * binningBlock.width * binningBlock.height, index: 0)    // threadgroup memory for each thread
            BinEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: binningBlock)
            BinEncoder.endEncoding()
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        memcpy(&FunctionDummy, buffer.contents(), buffer.length)
        let SummedElements = FunctionDummy.map{$0.x}.filter{$0 != 0}
        
        XCTAssert(SummedElements[0] == 256.0)
        XCTAssert(SummedElements[1] == 256.0)
    }
    
    func testSortAlgorithm() {
        guard
            let commandQ = device.makeCommandQueue(),
            let commandBuffer = commandQ.makeCommandBuffer()
            else {fatalError()}
        
        let threadgroupSize = MTLSizeMake(256, 1, 1)
        
        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: CoreImage_HDRTests.self))
            
            guard
                let TestBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4, options: .storageModeShared),
                let testShader = library.makeFunction(name: "testSortAlgorithm"),
                let encoder = commandBuffer.makeComputeCommandEncoder()
            else { fatalError() }
            
            let testState = try device.makeComputePipelineState(function: testShader)
            
            encoder.setComputePipelineState(testState)
            encoder.setBuffer(TestBuffer, offset: 0, index: 0)
            encoder.setThreadgroupMemoryLength(4 * threadgroupSize.width, index: 0)
            encoder.dispatchThreads(threadgroupSize, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            var counts = [Float](repeating: 0.0, count: 4)
            memcpy(&counts, TestBuffer.contents(), TestBuffer.length)
            
            XCTAssert(counts.count == 4)
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
    }
    
    func testBufferReductionShader() {
        guard
            let lib = library,
            let commandQ = device.makeCommandQueue(),
            let commandBuffer = commandQ.makeCommandBuffer(),
            let reduceShader = lib.makeFunction(name: "reduceBins") else {fatalError()}
        
        var lengthOfBuffer:uint = 512;
        var buffer = [float3](repeating: float3(1.0), count: Int(lengthOfBuffer))
        
        var cardinalities = [uint](repeating: 0, count: 256 * 3)
        
        guard
            let BinReductionEncoder = commandBuffer.makeComputeCommandEncoder()
            else {
                fatalError("Failed to create command encoder.")
        }
        
        // Assets
        let MTLbuffer = device.makeBuffer(bytes: &buffer, length: MemoryLayout<float3>.size * buffer.count, options: .cpuCacheModeWriteCombined)
        let MTLResponseFunc = device.makeBuffer(length: MemoryLayout<float3>.size * 256, options: .cpuCacheModeWriteCombined)
        let MTLCardinalities = device.makeBuffer(bytes: &cardinalities, length: MemoryLayout<uint>.size * cardinalities.count, options: .cpuCacheModeWriteCombined)
        
        do {
            let binredState = try device.makeComputePipelineState(function: reduceShader)
            BinReductionEncoder.setComputePipelineState(binredState)
            BinReductionEncoder.setBuffer(MTLbuffer, offset: 0, index: 0)
            BinReductionEncoder.setBytes(&lengthOfBuffer, length: MemoryLayout<uint>.size, index: 1)
            BinReductionEncoder.setBuffer(MTLResponseFunc, offset: 0, index: 2)
            BinReductionEncoder.setBuffer(MTLCardinalities, offset: 0, index: 3)
            BinReductionEncoder.dispatchThreadgroups(MTLSizeMake(1,1,1), threadsPerThreadgroup: MTLSizeMake(256, 1, 1))
            BinReductionEncoder.endEncoding()
        } catch let ErrorMessage {
            XCTFail(ErrorMessage.localizedDescription)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        var result = [float3](repeating: float3(0), count: 256)
        memcpy(&result, MTLResponseFunc?.contents(), 256 * MemoryLayout<float3>.size)
        
        let resultX = result.map{$0.x}
        let expectedSum = lengthOfBuffer / 256
        
        XCTAssert( resultX.allIs(value: Float(expectedSum)) )
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
}
