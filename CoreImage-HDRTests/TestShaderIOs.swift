//
//  TestShaderIOs.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 09.03.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import CoreImage
import MetalKit
import MetalKitPlus
@testable import CoreImage_HDR

final class testBinningShaderIO: MTKPIOProvider {
    let LDRInput, camParameters : MTKPIOProvider
    var BinBuffer, bufferSize, MTLCardinalities : MTLBuffer
    
    init(inputTextureSize: MTLSize) {
        let lengthOfBuffer = inputTextureSize.height * inputTextureSize.width
        var camerafunctions = CameraParameter(withTrainingWeight: 0)
        
        camerafunctions.responseFunction = [float3](repeating: float3(1.0), count: 256)
        camerafunctions.weightFunction = [float3](repeating: float3(1.0), count: 256)
        
        var cardinalities = [uint](repeating: 1, count: 256 * 3)
        let TGSizeOfSummationShader = (16, 16, 1)
        let totalBlocksCount = (inputTextureSize.height / TGSizeOfSummationShader.1) * (inputTextureSize.width / TGSizeOfSummationShader.0)
        var bufferLen = totalBlocksCount * 256
        
        // allocate IO
        guard
            let testImage = MTKPDevice.instance.makeTexture(descriptor: MTLTextureDescriptor().makeTestTextureDescriptor(width: inputTextureSize.width, height: inputTextureSize.height)),
            let buffer = MTKPDevice.instance.makeBuffer(length: MemoryLayout<float3>.size * lengthOfBuffer, options: .storageModeManaged),
            let bufferSize = MTKPDevice.instance.makeBuffer(bytes: &bufferLen, length: MemoryLayout<uint>.size, options: .cpuCacheModeWriteCombined),
            let MTLCardinalities = MTKPDevice.instance.makeBuffer(bytes: &cardinalities, length: MemoryLayout<uint>.size * cardinalities.count, options: .cpuCacheModeWriteCombined)
        else {
            fatalError()
        }
        
        self.LDRInput = LDRImagesShaderIO(inputTextures: [testImage], exposureTimes: [1.0], cameraShifts: [int2(0,0)])
        self.camParameters = CameraParametersShaderIO(cameraParameters: camerafunctions)
        
        self.BinBuffer = buffer
        self.bufferSize = bufferSize
        self.MTLCardinalities = MTLCardinalities
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return LDRInput.fetchTextures()
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return [self.BinBuffer, self.bufferSize, self.MTLCardinalities] + LDRInput.fetchBuffers()! + camParameters.fetchBuffers()!
    }
}
