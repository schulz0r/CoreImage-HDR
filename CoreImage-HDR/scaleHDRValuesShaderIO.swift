//
//  scaleHDRValuesShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 28.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import Foundation
import MetalKit
import MetalKitPlus

final class scaleHDRValueShaderIO: MTKPIOProvider {
    
    private let HDR:MTLTexture
    private let darkestImage:MTLTexture
    private let minMax:MTLTexture
    
    init(HDRImage: MTLTexture, darkestImage: MTLTexture){
        self.HDR = HDRImage
        self.darkestImage = darkestImage
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        guard let minMaxTexture = MTKPDevice.device.makeTexture(descriptor: descriptor) else {
            fatalError()
        }
        
        self.minMax = minMaxTexture
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return [HDR, HDR, darkestImage, minMax]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return nil
    }
}
