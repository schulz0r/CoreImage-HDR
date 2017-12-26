//
//  CardinalityShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 23.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import MetalKitPlus

struct CardinalityShaderIO: MTKPIOProvider {
    let inputImages:[MTLTexture]
    let cardinalityBuffer:MTLBuffer
    
    init(inputImages: [MTLTexture], cardinalityBuffer: MTLBuffer){
        self.inputImages = inputImages
        self.cardinalityBuffer = cardinalityBuffer
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.cardinalityBuffer]
    }
}
