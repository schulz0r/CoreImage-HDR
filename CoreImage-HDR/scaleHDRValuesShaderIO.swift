//
//  scaleHDRValuesShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 28.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import MetalKitPlus

final class scaleHDRValueShaderIO: MTKPIOProvider {
    
    private let HDR:MTLTexture
    private let darkestImage:MTLTexture
    private let minMax:MTLTexture
    private let MTLCameraShifts:MTLBuffer
    
    init(HDRImage: MTLTexture, darkestImage: MTLTexture, cameraShiftOfDarkestImage: int2, minMaxTexture: MTLTexture){
        self.HDR = HDRImage
        self.darkestImage = darkestImage
        self.minMax = minMaxTexture
        
        var shift = cameraShiftOfDarkestImage
        self.MTLCameraShifts = MTKPDevice.instance.makeBuffer(bytes: &shift, length: MemoryLayout<uint2>.size, options: .cpuCacheModeWriteCombined)!
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return [HDR, HDR, darkestImage, minMax]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [MTLCameraShifts]
    }
}
