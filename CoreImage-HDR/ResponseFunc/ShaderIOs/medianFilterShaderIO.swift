//
//  medianFilterShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 09.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import MetalKitPlus

final class medianFilterShaderIO: MTKPIOProvider {
    
    private let cameraResponse: MTLBuffer
    
    init(cameraResponse: MTLBuffer) {
        self.cameraResponse = cameraResponse
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return nil
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        
        return [cameraResponse]
    }
}
