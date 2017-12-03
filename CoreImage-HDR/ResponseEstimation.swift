//
//  ResponseEstimation.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 24.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import CoreImage
import MetalKit

final class HDRCameraResponseProcessor: CIImageProcessorKernel {
    
    static let device = MTLCreateSystemDefaultDevice()
    
    override final class func process(with inputs: [CIImageProcessorInput]?, arguments: [String : Any]?, output: CIImageProcessorOutput) throws {
        guard
            let device = device,
            let commandBuffer = output.metalCommandBuffer,
            let inputImages = inputs?.flatMap({$0.metalTexture}),
            let HDRTexture = output.metalTexture,
            let exposureTimes = arguments?["ExposureTimes"] as? [Float]
            else  {
                return
        }
        
        let MaxImageCount = 5
        let TrainingWeight:Float = 4.0
        
        guard inputImages.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard exposureTimes.count == inputImages.count else {
            fatalError("Each of the \(inputImages.count) input images require an exposure time. Only \(exposureTimes.count) could be found.")
        }
        
        let blocksize = MTLSizeMake(16, 16, 1)
        
        let imageDimensions = MTLSizeMake(inputImages[0].width, inputImages[0].height, 1)
        var cameraResponse = Array<Float>(stride(from: 0.0, to: 2.0, by: 2.0/256.0)).map{float3($0)}
        
        var numberOfInputImages = uint(inputImages.count)
        var cameraShifts = arguments?["CameraShifts"] ?? [int2](repeating: int2(0,0), count: inputImages.count)
        var weightFunction = (0...255).map{ exp(-TrainingWeight * pow( (Float($0)-127.5)/127.5, 2) ) }
        
        let MTLNumberOfImages = device.makeBuffer(bytes: &numberOfInputImages, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLExposureTimes = device.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLWeightFunc = device.makeBuffer(bytesNoCopy: &weightFunction, length: weightFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        let MTLResponseFunc = device.makeBuffer(bytesNoCopy: &cameraResponse, length: cameraResponse.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        let MTLCardinality = device.makeBuffer(length: 256 * MemoryLayout<uint>.size, options: .storageModePrivate)
        
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 256
        descriptor.height = (inputImages.first!.height / blocksize.height) * (inputImages.first!.width / blocksize.width)
        descriptor.pixelFormat = inputImages.first!.pixelFormat
        descriptor.mipmapLevelCount = 0
        descriptor.resourceOptions = .storageModePrivate
        let buffer = device.makeTexture(descriptor: descriptor)
        
        
        
        do{
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRProcessor.self))
            guard
            let biningFunc = library.makeFunction(name: "writeMeasureToBins"),
            let cardinalityFunction = library.makeFunction(name: "getCardinality")
            else { fatalError() }
            
            guard
                let cardEncoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    fatalError("Failed to create command encoder.")
            }
            let CardinalityState = try device.makeComputePipelineState(function: cardinalityFunction)
            cardEncoder.setComputePipelineState(CardinalityState)
            cardEncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
            cardEncoder.setBuffer(MTLCardinality, offset: 0, index: 0)
            cardEncoder.setThreadgroupMemoryLength(MemoryLayout<uint>.size * 256, index: 0)
            cardEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: MTLSizeMake(CardinalityState.threadExecutionWidth, 1, 1))
            
            guard
                let BinEncoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    fatalError("Failed to create command encoder.")
            }
            let biningState = try device.makeComputePipelineState(function: biningFunc)
            BinEncoder.setComputePipelineState(biningState)
            BinEncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
            BinEncoder.setTexture(buffer, index: MaxImageCount)
            BinEncoder.setTexture(buffer, index: MaxImageCount + 1)
            BinEncoder.setBuffer(MTLNumberOfImages, offset: 0, index: 0)
            BinEncoder.setBuffer(MTLCameraShifts, offset: 0, index: 1)
            BinEncoder.setBuffer(MTLExposureTimes, offset: 0, index: 2)
            BinEncoder.setBuffers([MTLResponseFunc, MTLWeightFunc], offsets: [0,0], range: Range<Int>(3...4))
            BinEncoder.setThreadgroupMemoryLength((MemoryLayout<Float>.size/2 + MemoryLayout<simd_uchar1>.size) * blocksize.width * blocksize.height, index: 0)    // threadgroup memory for each thread
            BinEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: blocksize)
            BinEncoder.endEncoding()
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
    }
}

