//
//  HDRCalcShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 27.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import Foundation
import MetalKit
import MetalKitPlus

final class HDRCalcShaderIO: MTKPIOProvider {
    
    private let inputImages:[MTLTexture]
    private let HDR:MTLTexture
    private let MTLNumberOfInputImages:MTLBuffer
    private var MTLCameraShifts:MTLBuffer
    private var MTLExposureTimes:MTLBuffer
    private var MTLWeightFunc:MTLBuffer
    private var MTLResponseFunc:MTLBuffer
    
    init(inputTextures: [MTLTexture], maximumLDRCount: Int, HDRImage: MTLTexture, exposureTimes: [Float], cameraShifts: [int2], cameraParameters: CameraParameter){
        self.inputImages = inputTextures
        self.HDR = HDRImage
        var imageCount = inputTextures.count
        
        self.MTLNumberOfInputImages = MTKPDevice.device.makeBuffer(bytes: &imageCount, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)!
        self.MTLCameraShifts = MTKPDevice.device.makeBuffer(bytes: cameraShifts, length: MemoryLayout<uint2>.size * inputImages.count, options: .cpuCacheModeWriteCombined)!
        self.MTLExposureTimes = MTKPDevice.device.makeBuffer(bytes: exposureTimes, length: MemoryLayout<Float>.size * inputImages.count, options: .cpuCacheModeWriteCombined)!
        self.MTLWeightFunc = MTKPDevice.device.makeBuffer(bytes: cameraParameters.weightFunction, length: cameraParameters.weightFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)!
        self.MTLResponseFunc = MTKPDevice.device.makeBuffer(bytes: cameraParameters.responseFunction, length: cameraParameters.responseFunction.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)!
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages + [HDR]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [MTLNumberOfInputImages, MTLCameraShifts, MTLExposureTimes, MTLResponseFunc, MTLWeightFunc]
    }
}

