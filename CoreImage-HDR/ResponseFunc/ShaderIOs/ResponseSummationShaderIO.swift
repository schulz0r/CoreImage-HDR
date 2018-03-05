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
    
    private var inputImageIO:LDRImagesShaderIO
    private var camParams: CameraParametersShaderIO
    private var BinBuffer, bufferSize, MTLCardinalities: MTLBuffer
    
    init(inputTextures: LDRImagesShaderIO, camParameters: CameraParametersShaderIO){
        
        let textureDim = inputTextures.fetchTextures()!.first!!.size()
        
        let TGSizeOfSummationShader = (16, 16, 1)
        let totalBlocksCount = (textureDim.height / TGSizeOfSummationShader.1) * (textureDim.width / TGSizeOfSummationShader.0)
        var bufferLen = totalBlocksCount * 256
        
        guard
            let buffer = MTKPDevice.instance.makeBuffer(length: bufferLen * MemoryLayout<float3>.size/2, options: .storageModePrivate),
            let bufferSize = MTKPDevice.instance.makeBuffer(bytes: &bufferLen, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined),
            let MTLCardinalities = MTKPDevice.instance.makeBuffer(length: 3 * MemoryLayout<Float>.size * 256, options: .storageModePrivate)
        else {
            fatalError()
        }
        
        self.inputImageIO = inputTextures
        self.camParams = camParameters
        self.BinBuffer = buffer
        self.bufferSize = bufferSize
        self.MTLCardinalities = MTLCardinalities
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return inputImageIO.fetchTextures()
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.BinBuffer, self.bufferSize, self.MTLCardinalities] + inputImageIO.fetchBuffers()! + camParams.fetchBuffers()!
    }
}

