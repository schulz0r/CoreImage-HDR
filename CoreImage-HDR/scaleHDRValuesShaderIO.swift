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
    
    init(HDRImage: MTLTexture, darkestImage: MTLTexture, minMax: [Float]){
        self.HDR = HDRImage
        self.darkestImage = darkestImage
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return [HDR, HDR, darkestImage]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return nil
    }
}
