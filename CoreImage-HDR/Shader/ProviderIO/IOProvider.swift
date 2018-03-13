//
//  ShaderIOs.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 04.03.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import CoreImage
import MetalKit
import MetalKitPlus


final class LDRImagesShaderIO: MTKPIOProvider {
    private var inputImages = [MTLTexture?](repeating: nil, count: 5)
    var MTLNumberOfInputImages, MTLCameraShifts, MTLExposureTimes : MTLBuffer
    
    init(inputTextures: [MTLTexture?], exposureTimes: [Float], cameraShifts: [int2]) {
        self.inputImages.replaceSubrange(0..<inputTextures.count, with: inputTextures)
        var imageCount = inputTextures.count
        
        guard
            let MTLNumberOfInputImages = MTKPDevice.instance.makeBuffer(bytes: &imageCount, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined),
            let MTLCameraShifts = MTKPDevice.instance.makeBuffer(bytes: cameraShifts, length: MemoryLayout<uint2>.size * 5, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.instance.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * 5, options: .cpuCacheModeWriteCombined)
        else {
            fatalError()
        }
        
        
        self.MTLNumberOfInputImages = MTLNumberOfInputImages
        self.MTLCameraShifts = MTLCameraShifts
        self.MTLExposureTimes = MTLExposureTimes
    }
    
    init(ImageBracket: [CIImage], cameraShifts: [int2]) {
        
        let textureLoader = MTKTextureLoader(device: MTKPDevice.instance)
        let inputTextures:[MTLTexture?] = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: CIContext(mtlDevice: MTKPDevice.instance))}
        self.inputImages.replaceSubrange(0..<inputTextures.count, with: inputTextures)
        
        var imageCount = inputTextures.count
        let exposureTimes = ImageBracket.map{$0.exposureTime()}
        
        guard
            let MTLNumberOfInputImages = MTKPDevice.instance.makeBuffer(bytes: &imageCount, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined),
            let MTLCameraShifts = MTKPDevice.instance.makeBuffer(bytes: cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.instance.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined)
            else {
                fatalError()
        }
        
        
        self.MTLNumberOfInputImages = MTLNumberOfInputImages
        self.MTLCameraShifts = MTLCameraShifts
        self.MTLExposureTimes = MTLExposureTimes
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [MTLNumberOfInputImages, MTLCameraShifts, MTLExposureTimes]
    }
}

final class HDRImageIO: MTKPIOProvider {
    var HDRTexture: MTLTexture
    
    init(size: MTLSize) {
        let HDRTexDescriptor = MTLTextureDescriptor()
        HDRTexDescriptor.width = size.width
        HDRTexDescriptor.height = size.height
        HDRTexDescriptor.textureType = .type2D
        HDRTexDescriptor.resourceOptions = .storageModePrivate
        HDRTexDescriptor.usage = .shaderWrite
        HDRTexDescriptor.pixelFormat = .rgba16Float
        
        guard
            let HDRTexture = MTKPDevice.instance.makeTexture(descriptor: HDRTexDescriptor)
        else  {
                fatalError()
        }
        
        self.HDRTexture = HDRTexture
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return [HDRTexture]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return nil
    }
}

final class CameraParametersShaderIO: MTKPIOProvider {
    private var MTLWeightFunc, MTLResponseFunc:MTLBuffer
    
    init(cameraParameters: CameraParameter) {
        guard
            let MTLWeightFunc = MTKPDevice.instance.makeBuffer(bytes: cameraParameters.weightFunction, length: cameraParameters.weightFunction.count * MemoryLayout<float3>.size, options: .storageModeShared),
            let MTLResponseFunc = MTKPDevice.instance.makeBuffer(bytes: cameraParameters.responseFunction, length: cameraParameters.responseFunction.count * MemoryLayout<float3>.size, options: .storageModeShared)
            else {
                fatalError()
        }
        
        self.MTLResponseFunc = MTLResponseFunc
        self.MTLWeightFunc = MTLWeightFunc
    }
    
    init(cameraParameters: inout CameraParameter) {
        guard
            let MTLWeightFunc = MTKPDevice.instance.makeBuffer(bytes: cameraParameters.weightFunction, length: cameraParameters.weightFunction.count * MemoryLayout<float3>.size, options: .storageModeShared),
            let MTLResponseFunc = MTKPDevice.instance.makeBuffer(bytes: cameraParameters.responseFunction, length: cameraParameters.responseFunction.count * MemoryLayout<float3>.size, options: .storageModeShared)
            else {
                fatalError()
        }
        
        self.MTLResponseFunc = MTLResponseFunc
        self.MTLWeightFunc = MTLWeightFunc
    }
    
    init() {
        guard
            let MTLWeightFunc = MTKPDevice.instance.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .storageModeShared),
            let MTLResponseFunc = MTKPDevice.instance.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .storageModeShared)
        else {
                fatalError()
        }
        
        self.MTLResponseFunc = MTLResponseFunc
        self.MTLWeightFunc = MTLWeightFunc
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return nil
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [MTLResponseFunc, MTLWeightFunc]
    }
}
