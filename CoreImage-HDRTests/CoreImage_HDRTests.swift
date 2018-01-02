//
//  CoreImage_HDRTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import ImageIO
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR


class CoreImage_HDRTests: XCTestCase {
    
    let device = MTLCreateSystemDefaultDevice()!
    
    var URLs:[URL] = []
    var Testimages:[CIImage] = []
    var ExposureTimes:[Float] = []
    var library:MTLLibrary?
    var textureLoader:MTKTextureLoader!
    
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
        
        textureLoader = MTKTextureLoader(device: self.device)
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
    
    // test cardinality (histogram) shader for correct functionality
    func testHistogramShader() {
        let ColourHistogramSize = 256 * 3
        
        // input images as textures
        let context = CIContext(mtlDevice: self.device)
        let Textures = Testimages.map{textureLoader.newTexture(CIImage: $0, context: context)}
        
        // cardinality of pixel values
        let MTLCardinalities = self.device.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)!
        
        var assets = MTKPAssets(ResponseCurveComputer.self)
        let CardinalityShaderRessources = CardinalityShaderIO(inputTextures: Textures, cardinalityBuffer: MTLCardinalities)
        let CardinalityShader = MTKPShader(name: "getCardinality", io: CardinalityShaderRessources, tgSize: (0,0,0))
        
        assets.add(shader: CardinalityShader)
        
        let MTLComputer = ResponseCurveComputer(assets: assets)
        MTLComputer.executeCardinalityShader()
        
        var Cardinality_Host = [uint](repeating: 0, count: ColourHistogramSize)
        memcpy(&Cardinality_Host, MTLCardinalities.contents(), MTLCardinalities.length)
        
        let allPixelCount = Testimages.reduce(0){$0 + 3 * Int($1.extent.size.height * $1.extent.size.width)}
        
        XCTAssert(Int(Cardinality_Host.reduce(0, +)) == allPixelCount )
    }
    
    func testBinningShader(){
        var cameraShifts = int2(0,0)
        var exposureTime:Float = 1
        
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
        
        let bufferLength = MemoryLayout<float3>.size * lengthOfBuffer
        
        let imageDimensions = MTLSizeMake(testTexture.width, testTexture.height, 1)
        
        // collect image in bins
        guard
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
        commandBuffer.commit()
        
        var assets = MTKPAssets(ResponseCurveComputer.self)
        let context = CIContext(mtlDevice: self.device)
        let Textures = Testimages.map{textureLoader.newTexture(CIImage: $0, context: context)}
        let MTLexposureTimes = device.makeBuffer(bytes: &exposureTime, length: MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined)
        let reponseSumShaderIO = ResponseSummationShaderIO(inputTextures: Textures, BinBuffer: buffer, exposureTimes: MTLexposureTimes!, cameraShifts: MTLCameraShifts!, cameraResponse: MTLFunctionDummyBuffer, weights: MTLFunctionDummyBuffer)
        
        let function = MTKPShader(name: "writeMeasureToBins_float32", io: reponseSumShaderIO, tgSize: (16,16,1))
        assets.add(shader: function)
        let computer = ResponseCurveComputer(assets: assets)
        computer.executeResponseSummationShader()
     
        
        memcpy(&FunctionDummy, buffer.contents(), buffer.length)
        let SummedElements = FunctionDummy.map{$0.x}.filter{$0 != 0}
        
        XCTAssertFalse(SummedElements.isEmpty)
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
        
        var cardinalities = [uint](repeating: 1, count: 256 * 3)
        
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
    
    func testResponseFunctionEstimation() {
        
        var Error:NSErrorPointer
        let loader = MTKTextureLoader(device: self.device)
        let inputImages:[MTLTexture] = loader.newTextures(URLs: URLs, options: nil, error: Error)
        
        guard Error == nil else {
            fatalError(Error!.pointee!.localizedDescription)
        }
        
        guard
            let lib = library,
            let commandQ = device.makeCommandQueue(),
            let commandBuffer = commandQ.makeCommandBuffer()
        else {
                fatalError()
        }
        
        let MaxImageCount = 5
        let TrainingWeight:Float = 4.0
        let half3_size = 8
        
        let binningBlock = MTLSizeMake(16, 16, 1)
        let totalBlocksCount = (inputImages.first!.height / binningBlock.height) * (inputImages.first!.width / binningBlock.width)
        
        let imageDimensions = MTLSizeMake(inputImages[0].width, inputImages[0].height, 1)
        var cameraResponse:[float3] = Array<Float>(stride(from: 0.0, to: 2.0, by: 2.0/256.0)).map{float3($0)}
        var weightFunction:[float3] = (0...255).map{ float3( exp(-TrainingWeight * pow( (Float($0)-127.5)/127.5, 2)) ) }
        
        var numberOfInputImages = uint(inputImages.count)
        var cameraShifts = [int2](repeating: int2(0,0), count: inputImages.count)
        
        let MTLNumberOfImages = device.makeBuffer(bytes: &numberOfInputImages, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLExposureTimes = device.makeBuffer(bytes: self.ExposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLWeightFunc = device.makeBuffer(bytesNoCopy: &weightFunction, length: weightFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        let MTLResponseFunc = device.makeBuffer(bytesNoCopy: &cameraResponse, length: cameraResponse.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        let ColourHistogramSize = MemoryLayout<uint>.size * 256 * 3
        let MTLCardinalities = device.makeBuffer(length: ColourHistogramSize, options: .storageModeShared)
        var bufferLength:uint = uint(half3_size * totalBlocksCount * 256)
        
        
        do{
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRProcessor.self))
            guard
                let biningFunc = library.makeFunction(name: "writeMeasureToBins"),
                let cardinalityFunction = library.makeFunction(name: "getCardinality"),
                let binReductionState = library.makeFunction(name: "reduceBins"),
                let HDRFunc = library.makeFunction(name: "makeHDR")
                else { fatalError() }
            
            // get cardinality of pixels in all images
            guard
                let cardEncoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    fatalError("Failed to create command encoder.")
            }
            
            let CardinalityState = try device.makeComputePipelineState(function: cardinalityFunction)
            let streamingMultiprocessorsPerBlock = 4
            var imageSize = uint2(uint(inputImages[0].width), uint(inputImages[0].height))
            let blocksize = CardinalityState.threadExecutionWidth * streamingMultiprocessorsPerBlock
            let remainer = imageSize.x % uint(blocksize)
            let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
            
            var replicationFactor_R:uint = max(uint(device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize)), 1) // replicate histograms, but not more than simd group length
            cardEncoder.setComputePipelineState(CardinalityState)
            cardEncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
            cardEncoder.setBytes(&imageSize, length: MemoryLayout<uint2>.size, index: 0)
            cardEncoder.setBytes(&replicationFactor_R, length: MemoryLayout<uint>.size, index: 1)
            cardEncoder.setBuffer(MTLCardinalities, offset: 0, index: 2)
            cardEncoder.setThreadgroupMemoryLength(sharedColourHistogramSize * Int(replicationFactor_R), index: 0)
            cardEncoder.dispatchThreads(MTLSizeMake(inputImages[0].width + (remainer == 0 ? 0 : blocksize - Int(remainer)), inputImages[0].height, inputImages.count), threadsPerThreadgroup: MTLSizeMake(blocksize, 1, 1))
            cardEncoder.endEncoding()
            
            // repeat training x times
                // collect image in bins
                guard
                    let BinEncoder = commandBuffer.makeComputeCommandEncoder(),
                    let buffer = device.makeBuffer(length: Int(bufferLength), options: .storageModePrivate)
                    else {
                        fatalError("Failed to create command encoder.")
                }
                
                let biningState = try device.makeComputePipelineState(function: biningFunc)
                BinEncoder.setComputePipelineState(biningState)
                BinEncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
                BinEncoder.setBuffer(buffer, offset: 0, index: 0)
                BinEncoder.setBuffer(MTLNumberOfImages, offset: 0, index: 1)
                BinEncoder.setBuffer(MTLCameraShifts, offset: 0, index: 2)
                BinEncoder.setBuffer(MTLExposureTimes, offset: 0, index: 3)
                BinEncoder.setBuffers([MTLResponseFunc, MTLWeightFunc], offsets: [0,0], range: Range<Int>(4...5))
                BinEncoder.setThreadgroupMemoryLength((MemoryLayout<Float>.size/2 + MemoryLayout<ushort>.size) * binningBlock.width * binningBlock.height, index: 0)    // threadgroup memory for each thread
                BinEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: binningBlock)
                BinEncoder.endEncoding()
                
                // reduce bins and calculate response
                guard
                    let BinReductionEncoder = commandBuffer.makeComputeCommandEncoder()
                    else {
                        fatalError("Failed to create command encoder.")
                }
                
                let binredState = try device.makeComputePipelineState(function: binReductionState)
                BinReductionEncoder.setComputePipelineState(binredState)
                BinReductionEncoder.setBuffer(buffer, offset: 0, index: 0)
                BinReductionEncoder.setBytes(&bufferLength, length: MemoryLayout<uint>.size, index: 1)
                BinReductionEncoder.setBuffer(MTLResponseFunc, offset: 0, index: 2)
                BinReductionEncoder.setBuffer(MTLCardinalities, offset: 0, index: 3)
                BinReductionEncoder.dispatchThreadgroups(MTLSizeMake(1,1,1), threadsPerThreadgroup: MTLSizeMake(256, 1, 1))
                BinReductionEncoder.endEncoding()
                
                // flush buffer for next iteration
                guard let flushBlitEncoder = commandBuffer.makeBlitCommandEncoder() else {fatalError()}
                flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
                flushBlitEncoder.endEncoding()
        } catch let Errors {
            XCTFail(Errors.localizedDescription)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        var result = [float3](repeating: float3(0), count: 256)
        memcpy(&result, MTLResponseFunc?.contents(), 256 * MemoryLayout<float3>.size)
        
        XCTAssert(true)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
}
