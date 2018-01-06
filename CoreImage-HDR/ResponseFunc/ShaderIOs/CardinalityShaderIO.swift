//
//  CardinalityShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 23.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

final class CardinalityShaderIO: MTKPIOProvider {
    
    private var inputImages:[MTLTexture]! = nil
    private var cardinalityBuffer:MTLBuffer! = nil
    private var imageDimensions:MTLBuffer! = nil
    private var R:MTLBuffer! = nil
    
    
    init(inputTextures: [MTLTexture], cardinalityBuffer: MTLBuffer, ReplicationFactor: Int){
        self.inputImages = inputTextures
        self.cardinalityBuffer = cardinalityBuffer
        var imageDim = uint2(uint(inputTextures[0].width), uint(inputTextures[0].height))
        var RFactor:uint = ReplicationFactor
        
        self.imageDimensions = MTKPDevice.device.makeBuffer(bytes: &imageDim, length: MemoryLayout<uint2>.size, options: .cpuCacheModeWriteCombined)!
        self.R = MTKPDevice.device.makeBuffer(bytes: &RFactor, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)!
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.imageDimensions, self.R, self.cardinalityBuffer]
    }
}
