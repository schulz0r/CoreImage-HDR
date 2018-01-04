//
//  ResponseEstimatioknTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 02.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import ImageIO
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR


class ResponseEstimationTests: XCTestCase {
    
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
        MTLComputer.commandBuffer.commit()
        MTLComputer.commandBuffer.waitUntilCompleted()
        
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
            let MTLFunctionDummyBuffer = device.makeBuffer(bytes: &FunctionDummy, length: FunctionDummy.count * MemoryLayout<float3>.size, options: .storageModeManaged)
            else {fatalError()}
        
        let testTextureDescriptor = MTLTextureDescriptor().makeTestTextureDescriptor(width: 32, height: 16)
        guard let testTexture = device.makeTexture(descriptor: testTextureDescriptor) else {fatalError()}
        let imageDimensions = MTLSizeMake(testTexture.width, testTexture.height, 1)
        
        // collect image in bins
        guard
            let commandBuffer = commandQ.makeCommandBuffer(),
            let blitencoder = commandBuffer.makeBlitCommandEncoder(),
            let buffer = device.makeBuffer(length: MemoryLayout<float3>.size * lengthOfBuffer, options: .storageModeManaged)
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
        let MTLexposureTimes = device.makeBuffer(bytes: &exposureTime, length: MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<int2>.size, options: .cpuCacheModeWriteCombined)
        
        let reponseSumShaderIO = ResponseSummationShaderIO(inputTextures: [testTexture],
                                                           BinBuffer: buffer,
                                                           exposureTimes: MTLexposureTimes!,
                                                           cameraShifts: MTLCameraShifts!,
                                                           cameraResponse: MTLFunctionDummyBuffer,
                                                           weights: MTLFunctionDummyBuffer)
        
        let function = MTKPShader(name: "writeMeasureToBins_float32", io: reponseSumShaderIO, tgSize: (16,16,1))
        assets.add(shader: function)
        let computer = ResponseCurveComputer(assets: assets)
        computer.executeResponseSummationShader()
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        
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
        
        var lengthOfBuffer:uint = 512;
        var buffer = [float3](repeating: float3(1.0), count: Int(lengthOfBuffer))
        var cardinalities = [uint](repeating: 1, count: 256 * 3)
        
        // Assets
        guard
            let MTLbuffer = device.makeBuffer(bytes: &buffer, length: MemoryLayout<float3>.size * buffer.count, options: .cpuCacheModeWriteCombined),
            let MTLResponseFunc = device.makeBuffer(length: MemoryLayout<float3>.size * 256, options: .cpuCacheModeWriteCombined),
            let MTLCardinalities = device.makeBuffer(bytes: &cardinalities, length: MemoryLayout<uint>.size * cardinalities.count, options: .cpuCacheModeWriteCombined)
        else {
            fatalError()
        }
        
        
        var assets = MTKPAssets(ResponseCurveComputer.self)
        let ShaderIO = bufferReductionShaderIO(BinBuffer: MTLbuffer, bufferlength: buffer.count, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        let Shader = MTKPShader(name: "reduceBins_float", io: ShaderIO, tgSize: (256,1,1))
        assets.add(shader: Shader)
        
        let computer = ResponseCurveComputer(assets: assets)
        computer.executeBufferReductionShader()
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        
        var result = [float3](repeating: float3(0), count: 256)
        memcpy(&result, MTLResponseFunc.contents(), 256 * MemoryLayout<float3>.size)
        
        let resultX = result.map{$0.x}
        let expectedSum = lengthOfBuffer / 256
        
        XCTAssert( resultX.allIs(value: Float(expectedSum)) )
    }
    
    func testResponseFunctionEstimation() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        let ResponseFunciton:[float3] = metaComp.estimateCameraResponse()
        
        print(ResponseFunciton.description)
        
        XCTAssert(ResponseFunciton.reduce(true){$0 && ($1.x > 0) && ($1.y > 0) && ($1.z > 0)})
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    
}

