//
//  MTKP-HDR.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 24.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage
import MetalKit
import MetalPerformanceShaders
import MetalKitPlus

public struct MTKPHDR {
    
    public static func makeHDR(ImageBracket: [CIImage], exposureTimes: [Float], cameraParameters: CameraParameter, context: CIContext? = nil) {
        
        let MaxImageCount = 5
        guard ImageBracket.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard exposureTimes.count == ImageBracket.count else {
            fatalError("Each of the \(ImageBracket.count) input images require an exposure time. Only \(exposureTimes.count) could be found.")
        }
        guard cameraParameters.responseFunction.count.isPowerOfTwo() else {
            fatalError("Length of Camera Response is not a power of two.")
        }
        
        var assets = MTKPAssets(ResponseEstimator.self)
        let textureLoader = MTKTextureLoader(device: MTKPDevice.device)
        let inputImages = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: MTKPDevice.device))}
        
        let HDRTexDescriptor = inputImages.first!.getDescriptor()
        HDRTexDescriptor.pixelFormat = .rgba16Float
        
        guard let HDRTexture = MTKPDevice.device.makeTexture(descriptor: HDRTexDescriptor) else  {
                fatalError()
        }
        
        var library:MTLLibrary
        
        do{
            library = try MTKPDevice.device.makeDefaultLibrary(bundle: Bundle(for: HDRProcessor.self))
        } catch let error {
            fatalError(error.localizedDescription)
        }
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        let MPSMinMax = MPSImageStatisticsMinAndMax(device: MTKPDevice.device)
        MPSMinMax.clipRectSource = MTLRegionMake2D(0, 0, HDRTexture.width, HDRTexture.height)
        
        let imageDimensions = MTLSizeMake(HDRTexture.width, HDRTexture.height, 1)
        
        var numberOfInputImages = uint(inputImages.count)
        var cameraShifts = arguments?["CameraShifts"] ?? [int2](repeating: int2(0,0), count: inputImages.count)
        
        guard
            let MinMaxMTLTexture = MTKPDevice.device.makeTexture(descriptor: descriptor),
            let MTLNumberOfImages = MTKPDevice.device.makeBuffer(bytes: &numberOfInputImages, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined),
            let MTLCameraShifts = MTKPDevice.device.makeBuffer(bytes: &cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.device.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined),
            let MTLWeightFunc = MTKPDevice.device.makeBuffer(bytes: &cameraParameters.weightFunction, length: cameraParameters.weightFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined),
            let MTLResponseFunc = MTKPDevice.device.makeBuffer(bytes: &cameraParameters.responseFunction, length: cameraParameters.responseFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
            else {
                fatalError()
        }
        
        
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to create command encoder.")
        }
        
        do{
            guard
                let HDRFunc = library.makeFunction(name: "makeHDR")
                else { fatalError() }
            let HDRState = try MTKPDevice.device.makeComputePipelineState(function: HDRFunc)
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
        encoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
        encoder.endEncoding()
        
        MPSMinMax.encode(commandBuffer: commandBuffer,
                         sourceTexture: HDRTexture,
                         destinationTexture: MinMaxMTLTexture)
        
        do {
            guard
                let scaleFunc = library.makeFunction(name: "scaleHDR"),
                let ScaleEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    fatalError("Failed to create command encoder.")
            }
            
            let HDRScaleState = try MTKPDevice.device.makeComputePipelineState(function: scaleFunc)
            ScaleEncoder.setComputePipelineState(HDRScaleState)
            ScaleEncoder.setTexture(HDRTexture, index: 0)
            ScaleEncoder.setTexture(HDRTexture, index: 1)
            ScaleEncoder.setTexture(MinMaxMTLTexture, index: 2)
            ScaleEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            ScaleEncoder.endEncoding()
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }
}
