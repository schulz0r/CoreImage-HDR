//
//  ResponseSummationShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 01.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import MetalKitPlus

final class ResponseSummationShaderIO: MTKPIOProvider {
    
    private var inputImages:[MTLTexture]! = nil
    private var imageCount:MTLBuffer! = nil
    private var BinBuffer:MTLBuffer! = nil
    private var cameraShifts:MTLBuffer! = nil
    private var exposureTimes:MTLBuffer! = nil
    private var cameraResponse:MTLBuffer! = nil
    private var weights:MTLBuffer! = nil
    
    init(inputTextures: [MTLTexture], BinBuffer: MTLBuffer, exposureTimes: MTLBuffer, cameraShifts: MTLBuffer, cameraResponse: MTLBuffer, weights: MTLBuffer){
        guard inputTextures.count > 0 else {
            fatalError()
        }
        self.inputImages = inputTextures
        var imageCount = uint(self.inputImages.count)
        self.BinBuffer = BinBuffer
        
        self.imageCount = MTKPDevice.device.makeBuffer(bytes: &imageCount, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)!
        self.exposureTimes = exposureTimes
        self.cameraShifts = cameraShifts
        self.weights = weights
        self.cameraResponse = cameraResponse
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return inputImages
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.BinBuffer, self.imageCount, self.cameraShifts, self.exposureTimes, self.cameraResponse, self.weights]
    }
}

