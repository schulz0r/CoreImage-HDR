//
//  extensions.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 22.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKitPlus

extension Int {
    func isPowerOfTwo() -> Bool {
        return (self & (self - 1)) == 0
    }
}

extension MTKPComputer: MTKPShaderExecutor {
    public func execute(_ name:String) {
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let cmdBuffer = self.commandQueue.makeCommandBuffer(),
            let computeEncoder = cmdBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
        else {fatalError()}
        
        guard descriptor.tgSize != nil else {
            fatalError("execute func")
        }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        
        let threads = MTLSizeMake(firstTexture.width, firstTexture.height, 1)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(descriptor.tgSize!.0, descriptor.tgSize!.1, descriptor.tgSize!.2))
        computeEncoder.endEncoding()
        
        cmdBuffer.commit()
    }
}
