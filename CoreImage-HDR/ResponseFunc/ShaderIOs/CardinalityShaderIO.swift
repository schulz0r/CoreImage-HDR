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
    
    private var inputImages:[MTLTexture]! = nil
    private var cardinalityBuffer:MTLBuffer! = nil
    private var imageDimensions:MTLBuffer! = nil
    private var R:MTLBuffer! = nil
    let streamingMultiprocessorsPerBlock = 4
    
    
    init(inputTextures: [MTLTexture], cardinalityBuffer: MTLBuffer){
        guard self.device != nil else {
            fatalError()
        }
        self.inputImages = inputTextures
        self.cardinalityBuffer = cardinalityBuffer
        
        var imageDim = uint2(uint(inputTextures[0].width), uint(inputTextures[0].height))
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        var replicationFactor_R:uint = max(uint(self.device!.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize)), 1)
        
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
