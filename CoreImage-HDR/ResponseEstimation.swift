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
        let half3_size = 8
        
        guard inputImages.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard exposureTimes.count == inputImages.count else {
            fatalError("Each of the \(inputImages.count) input images require an exposure time. Only \(exposureTimes.count) could be found.")
        }
        
        let binningBlock = MTLSizeMake(16, 16, 1)
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
        let MTLCardinalities = [device.makeBuffer(length: 256 * MemoryLayout<uint>.size, options: .storageModePrivate),
                                device.makeBuffer(length: 256 * MemoryLayout<uint>.size, options: .storageModePrivate),
                                device.makeBuffer(length: 256 * MemoryLayout<uint>.size, options: .storageModePrivate)]
        var bufferLength = half3_size * (inputImages.first!.height / binningBlock.height) * (inputImages.first!.width / binningBlock.width)
        guard let buffer = device.makeBuffer(length: bufferLength, options: .storageModePrivate) else {fatalError("Could not allocate Memory in Video RAM.")}
        
        
        
        
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
            
            var imageSize = uint2(uint(inputImages[0].width), uint(inputImages[0].height))
            let blocksize = CardinalityState.threadExecutionWidth * 4
            var replicationFactor_R = min(uint(device.maxThreadgroupMemoryLength / (blocksize * MemoryLayout<uint>.size * 257 * 3)), uint(CardinalityState.threadExecutionWidth)) // replicate histograms, but not more than simd group length
            cardEncoder.setComputePipelineState(CardinalityState)
            cardEncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
            cardEncoder.setBytes(&imageSize, length: MemoryLayout<uint2>.size, index: 0)
            cardEncoder.setBytes(&replicationFactor_R, length: MemoryLayout<uint>.size, index: 1)
            cardEncoder.setBuffers(MTLCardinalities, offsets: [0,0,0], range: Range<Int>(2...4))
            cardEncoder.setThreadgroupMemoryLength(MemoryLayout<uint>.size * 257 * Int(replicationFactor_R), index: 0)
            cardEncoder.setThreadgroupMemoryLength(MemoryLayout<uint>.size * 257 * Int(replicationFactor_R), index: 1)
            cardEncoder.setThreadgroupMemoryLength(MemoryLayout<uint>.size * 257 * Int(replicationFactor_R), index: 2)
            cardEncoder.dispatchThreads(MTLSizeMake(inputImages[0].width, inputImages[0].height, inputImages.count), threadsPerThreadgroup: MTLSizeMake(blocksize, 1, 1))
            cardEncoder.endEncoding()
            
            // repeat training x times
            
            // collect image in bins
            guard
                let BinEncoder = commandBuffer.makeComputeCommandEncoder()
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
            BinEncoder.setThreadgroupMemoryLength((MemoryLayout<Float>.size/2 + MemoryLayout<simd_uchar1>.size) * binningBlock.width * binningBlock.height, index: 0)    // threadgroup memory for each thread
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
            BinReductionEncoder.setBuffer(MTLCameraShifts, offset: 0, index: 2)
            cardEncoder.setBuffers(MTLCardinalities, offsets: [0,0,0], range: Range<Int>(3...5))
            BinReductionEncoder.dispatchThreadgroups(MTLSizeMake(1,1,1), threadsPerThreadgroup: MTLSizeMake(256, 1, 1))
            BinReductionEncoder.endEncoding()
            
            // flush buffer for next iteration
            guard let flushBlitEncoder = commandBuffer.makeBlitCommandEncoder() else {fatalError()}
            flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
            flushBlitEncoder.endEncoding()
            
            // after training, make HDR
            guard
                let makeHDREncoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    fatalError("Failed to create command encoder.")
            }
            let HDRState = try device.makeComputePipelineState(function: HDRFunc)
            makeHDREncoder.setComputePipelineState(HDRState)
            makeHDREncoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
            makeHDREncoder.setTexture(HDRTexture, index: MaxImageCount)
            makeHDREncoder.setBuffer(MTLNumberOfImages, offset: 0, index: 0)
            makeHDREncoder.setBuffer(MTLCameraShifts, offset: 0, index: 1)
            makeHDREncoder.setBuffer(MTLExposureTimes, offset: 0, index: 2)
            makeHDREncoder.setBuffers([MTLResponseFunc, MTLWeightFunc], offsets: [0,0], range: Range<Int>(3...4))
            makeHDREncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            makeHDREncoder.endEncoding()
            
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
    }
}

