//
//  CardinalityShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 23.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

final class CardinalityShaderIO: MTKPIOProvider, MTKPDeviceUser {
    public var device: MTLDevice?
    
    private let inputImages:[MTLTexture]
    private let cardinalityBuffer:MTLBuffer
    private let imageDimensions:MTLBuffer
    private let R:MTLBuffer
    let streamingMultiprocessorsPerBlock = 4
    
    
    init(sharedRessources: sharedAssets){
        guard self.device != nil else {
            fatalError()
        }
        
        var imageDim = uint2(uint(sharedRessources.Textures[0].width), uint(sharedRessources.Textures[0].height))
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        var replicationFactor_R:uint = max(uint(self.device!.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize)), 1)
        
        self.inputImages = sharedRessources.Textures
        self.cardinalityBuffer = sharedRessources.MTLCardinalities
        self.imageDimensions = self.device!.makeBuffer(bytes: &imageDim, length: MemoryLayout<uint2>.size, options: .cpuCacheModeWriteCombined)!
        self.R = self.device!.makeBuffer(bytes: &replicationFactor_R, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)!
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.imageDimensions, self.R, self.cardinalityBuffer]
    }
}
