//
//  HDRProcessor.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage
import MetalKit

final class HDRProcessor: CIImageProcessorKernel {
    static let device = MTLCreateSystemDefaultDevice()
    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String : Any]?, output: CIImageProcessorOutput) throws {
        guard
            let device = device,
            let commandBuffer = output.metalCommandBuffer,
            let inputImages = inputs?.map({$0.metalTexture}),
            let HDRTexture = output.metalTexture,
            let exposureTimes = arguments?["ExposureTimes"] as? [Float],
            var cameraResponse = arguments?["CameraResponse"] as? [Float]
        else  {
                return
        }
        
        let MaxImageCount = 5
        guard inputImages.count <= MaxImageCount else {
            fatalError("Only up to 5 images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        
        var numberOfInputImages = uint(inputImages.count)
        var cameraShifts = arguments?["ExposureTimes"] ?? [int2](repeating: int2(0,0), count: inputImages.count)
        var weightFunction = zip([0] + cameraResponse, cameraResponse).map{ $0.1 - $0.0}
        
        let MTLNumberOfImages = device.makeBuffer(bytes: &numberOfInputImages, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)
        let MTLCameraShifts = device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLExposureTimes = device.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
        let MTLWeightFunc = device.makeBuffer(bytesNoCopy: &weightFunction, length: weightFunction.count * MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined, deallocator: nil)
        let MTLResponseFunc = device.makeBuffer(bytesNoCopy: &cameraResponse, length: cameraResponse.count * MemoryLayout<Float>.size, options: .cpuCacheModeWriteCombined, deallocator: nil)
        
        
        guard
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            fatalError("Failed to create command encoder.")
        }
        
        do{
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: HDRProcessor.self))
            let HDRFunc = library.makeFunction(name: "makeHDR")!
            let HDRState = try device.makeComputePipelineState(function: HDRFunc)
            encoder.setComputePipelineState(HDRState)
        } catch let Errors {
            fatalError(Errors.localizedDescription)
        }
        
        encoder.setTextures(inputImages, range: Range<Int>(0..<inputImages.count))
        encoder.setTexture(HDRTexture, index: MaxImageCount)
        encoder.setBuffer(MTLNumberOfImages, offset: 0, index: 0)
        encoder.setBuffer(MTLCameraShifts, offset: 0, index: 1)
        encoder.setBuffer(MTLExposureTimes, offset: 0, index: 2)
        encoder.setBuffers([MTLResponseFunc, MTLWeightFunc], offsets: [0,0], range: Range<Int>(3...4))
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
