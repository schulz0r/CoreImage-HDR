//
//  ResponseEstimatioknTests.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 02.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import XCTest
import CoreImage
import MetalPerformanceShaders
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
    
    func testBinningShader(){
        var cameraShifts = int2(0,0)
        var exposureTime:Float = 1
        let TGSizeOfSummationShader = (16,16,1)
        let lengthOfBuffer = 512;
        guard let commandQ = device.makeCommandQueue() else {fatalError()}
        var TextureFill = [float3](repeating: float3(0.5), count: lengthOfBuffer)
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
        
        var assets = MTKPAssets(HDRComputer.self)
        let MTLexposureTimes = device.makeBuffer(bytes: &exposureTime, length: MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<int2>.size, options: .cpuCacheModeWriteCombined)
        
        let reponseSumShaderIO = ResponseSummationShaderIO(inputTextures: [testTexture],
                                                           BinBuffer: buffer,
                                                           exposureTimes: MTLexposureTimes!,
                                                           cameraShifts: MTLCameraShifts!,
                                                           cameraResponse: MTLFunctionDummyBuffer,
                                                           weights: MTLFunctionDummyBuffer)
        
        let function = MTKPShader(name: "writeMeasureToBins_float32", io: reponseSumShaderIO, tgConfig: MTKPThreadgroupConfig(tgSize: TGSizeOfSummationShader, tgMemLength: [4 * TGSizeOfSummationShader.0 * TGSizeOfSummationShader.1]))
        assets.add(shader: function)
        let computer = HDRComputer(assets: assets)
        computer.encode("writeMeasureToBins_float32")
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        
        memcpy(&FunctionDummy, buffer.contents(), buffer.length)
        let SummedElements = FunctionDummy.map{$0.x}.filter{$0 != 0}
        
        XCTAssert(SummedElements.count > 0)
        XCTAssert(SummedElements[0] == 256.0)
        XCTAssert(SummedElements[1] == 256.0)
    }
    
    func testSortAlgorithm() {
        guard let commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer() else {fatalError()}
        
        let threadgroupSize = MTLSizeMake(256, 1, 1)
        
        do {
            let library = try MTKPDevice.device.makeDefaultLibrary(bundle: Bundle(for: CoreImage_HDRTests.self))
            var unsorted:[Float] = (1...4).map{ _ in Float((arc4random() % 9) + 1) }
            let threadgroupSizeSortShader = MTLSizeMake(unsorted.count, 1, 1)
            
            guard unsorted.count.isPowerOfTwo() else {
                fatalError("Length of median filter must be a power of two.")
            }
            
            guard
                let TestSortNCountBuffer = MTKPDevice.device.makeBuffer(length: MemoryLayout<Float>.size * 4, options: .storageModeShared),
                let TestSortBuffer = MTKPDevice.device.makeBuffer(bytes: &unsorted, length: MemoryLayout<Float>.size * unsorted.count, options: .storageModeShared),
                let testShader = library.makeFunction(name: "testSortAlgorithm"),
                let sortShader = library.makeFunction(name: "testSortAlgorithmNoCount"),
                let encoder = commandBuffer.makeComputeCommandEncoder()
                else { fatalError() }
            
            let testState = try MTKPDevice.device.makeComputePipelineState(function: testShader)
            let testSortState = try MTKPDevice.device.makeComputePipelineState(function: sortShader)
            
            encoder.setComputePipelineState(testState)
            encoder.setBuffer(TestSortNCountBuffer, offset: 0, index: 0)
            encoder.setThreadgroupMemoryLength(4 * threadgroupSize.width, index: 0)
            encoder.dispatchThreads(threadgroupSize, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
            
            guard let sortEncoder = commandBuffer.makeComputeCommandEncoder() else {
                fatalError()
            }
            
            sortEncoder.setComputePipelineState(testSortState)
            sortEncoder.setBuffer(TestSortBuffer, offset: 0, index: 0)
            sortEncoder.setThreadgroupMemoryLength(MemoryLayout<Float>.size * unsorted.count, index: 0)
            sortEncoder.dispatchThreads(threadgroupSizeSortShader, threadsPerThreadgroup: threadgroupSizeSortShader)
            sortEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            var counts = [Float](repeating: 0.0, count: 4)
            var sorted = [Float](repeating: 0.0, count: unsorted.count)
            memcpy(&counts, TestSortNCountBuffer.contents(), TestSortNCountBuffer.length)
            memcpy(&sorted, TestSortBuffer.contents(), TestSortBuffer.length)
            
            print("\(unsorted) -> \(sorted)")
            
            XCTAssert(counts.count == 4)
            XCTAssertTrue(sorted.isAscendinglySorted(), "Unsorted element could not be sorted on GPU.")
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
    }
    
    func testBufferReductionShader() {
        let lengthOfBuffer:uint = 512;
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
        
        
        var assets = MTKPAssets(HDRComputer.self)
        let ShaderIO = bufferReductionShaderIO(BinBuffer: MTLbuffer, bufferlength: buffer.count, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        let Shader = MTKPShader(name: "reduceBins_float", io: ShaderIO, tgConfig: MTKPThreadgroupConfig(tgSize: (256,1,1)))
        assets.add(shader: Shader)
        
        let computer = HDRComputer(assets: assets)
        computer.encode("reduceBins_float", threads: MTLSizeMake(256, 1, 1))
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        
        var result = [float3](repeating: float3(0), count: 256)
        memcpy(&result, MTLResponseFunc.contents(), 256 * MemoryLayout<float3>.size)
        
        let resultX = result.map{$0.x}
        let expectedSum = lengthOfBuffer / 256
        
        XCTAssert( resultX.allNonSaturatedEqual(value: Float(expectedSum)) )
    }
    
    func testResponseFunctionEstimation() {
        let cameraShifts = [int2](repeating: int2(0,0), count: self.Testimages.count)
        var camParams = CameraParameter(withTrainingWeight: 10)
        
        let metaComp = ResponseEstimator(ImageBracket: self.Testimages, CameraShifts: cameraShifts)
        metaComp.estimate(cameraParameters: &camParams, iterations: 10)
        
        print("Response: \(camParams.responseFunction.description)\n\nWeights: \(camParams.weightFunction.description)")
        
        XCTAssert(camParams.responseFunction[1..<255].reduce(true){$0 && ($1.x.isNormal) && ($1.y.isNormal) && ($1.z.isNormal)})
    } 
}

