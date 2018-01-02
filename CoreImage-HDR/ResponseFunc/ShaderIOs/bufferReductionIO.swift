//
//  bufferReductionIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 02.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import MetalKitPlus

final class bufferReductionShaderIO: MTKPIOProvider, MTKPDeviceUser {
    
    private var BinBuffer:MTLBuffer! = nil
    private var cameraResponse:MTLBuffer! = nil
    private var bufferSize:MTLBuffer! = nil
    private var Cardinality:MTLBuffer! = nil
    
    init(BinBuffer: MTLBuffer, bufferlength: Int, cameraResponse: MTLBuffer, Cardinality: MTLBuffer){
        guard self.device != nil else {
                fatalError()
        }
        var bufflen = uint(bufferlength)
        
        self.BinBuffer = BinBuffer
        self.bufferSize = self.device!.makeBuffer(bytes: &bufflen, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined)!
        self.cameraResponse = cameraResponse
        self.Cardinality = Cardinality
    }
    
    func fetchTextures() -> [MTLTexture]? {
        return nil
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.BinBuffer, self.bufferSize, self.cameraResponse, self.Cardinality]
    }
}

