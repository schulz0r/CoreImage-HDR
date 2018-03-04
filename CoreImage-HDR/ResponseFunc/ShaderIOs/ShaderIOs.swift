//
//  ShaderIOs.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 04.03.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import Foundation
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
