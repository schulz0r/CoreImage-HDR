//
//  ResponseSummationShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 01.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import MetalKitPlus

final class ResponseSummationShaderIO: MTKPIOProvider, MTKPDeviceUser {
    
    private var inputImages:[MTLTexture]! = nil
    private var imageDimensions:MTLBuffer! = nil
    private var BinBuffer:MTLBuffer! = nil
    private var cameraShifts:MTLBuffer! = nil
    private var exposureTimes:MTLBuffer! = nil
    private var cameraResponse:MTLBuffer! = nil
    private var weights:MTLBuffer! = nil
    
    init(inputTextures: [MTLTexture], BinBuffer: MTLBuffer, exposureTimes: MTLBuffer, cameraShifts: MTLBuffer, cameraResponse: MTLBuffer, weights: MTLBuffer){
        guard self.device != nil else {
            fatalError()
        }
        self.inputImages = inputTextures
        var imageDim = uint2(uint(inputTextures[0].width), uint(inputTextures[0].height))
        self.BinBuffer = BinBuffer
        
        self.imageDimensions = self.device!.makeBuffer(bytes: &imageDim, length: MemoryLayout<uint2>.size, options: .cpuCacheModeWriteCombined)!
        self.exposureTimes = exposureTimes
        self.cameraShifts = cameraShifts
        self.weights = weights
        self.cameraResponse = cameraResponse
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.BinBuffer, self.imageDimensions, self.imageDimensions, self.cameraShifts, self.exposureTimes, self.cameraResponse, self.weights]
    }
}

