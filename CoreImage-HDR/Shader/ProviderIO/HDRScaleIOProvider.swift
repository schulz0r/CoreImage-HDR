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
    
    private let HDR: MTLTexture
    private let LDRInputs: LDRImagesShaderIO
    let minMaxTexture:MTLTexture
    let MPSHistogramBuffer, MPSMinMaxBuffer: MTLBuffer
    
    init(HDRImage: MTLTexture, Inputs: LDRImagesShaderIO) {
        // prepare MPSMinMax shader
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        guard
            let minMaxTexture = MTKPDevice.instance.makeTexture(descriptor: descriptor),
            let MPSHistogramBuffer = MTKPDevice.instance.makeBuffer(length: 3 * MemoryLayout<Float>.size * 256, options: .storageModeShared),
            let MPSMinMaxBuffer = MTKPDevice.instance.makeBuffer(length: 2 * MemoryLayout<float3>.size, options: .storageModeShared)
        else {
            fatalError()
        }
        
        self.HDR = HDRImage
        self.minMaxTexture = minMaxTexture
        self.LDRInputs = Inputs
        self.MPSHistogramBuffer = MPSHistogramBuffer
        self.MPSMinMaxBuffer = MPSMinMaxBuffer
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return [HDR, HDR, minMaxTexture] + LDRInputs.fetchTextures()!
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return LDRInputs.fetchBuffers()
    }
}
