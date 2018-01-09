//
//  ResponseCurveComputer.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 28.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import MetalKitPlus

final class ResponseCurveComputer : MTKPComputer {
    var assets:MTKPAssets
    var commandQueue:MTLCommandQueue
    public var commandBuffer: MTLCommandBuffer!
    
    init(assets: MTKPAssets) {
        self.assets = assets
        self.commandQueue = MTKPDevice.commandQueue
        self.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
    }
    
    // shader execution functions
    public func encode(_ name:String, threads: MTLSize? = nil) {
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        else {
            fatalError()
        }
        guard (threads != nil) || (descriptor.textures != nil) else {
            fatalError("The thread count is unknown. Pass it as an argument to the encode function.")
        }
        let threadCount = threads ?? MTLSizeMake(descriptor.textures![0].width, descriptor.textures![0].height, 1)
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        if let textures = descriptor.textures {
            computeEncoder.setTextures(textures, range: 0..<textures.count)
        }
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        if let TGMemSize = descriptor.tgConfig.tgMemLength {
            TGMemSize.enumerated().forEach({
                computeEncoder.setThreadgroupMemoryLength($0.element, index: $0.offset)
            })
        }
        computeEncoder.dispatchThreads(threadCount, threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
    // if number of threadgroups are to be set
    public func encode(_ name:String, threadgroups: MTLSize) {
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()
            else {
                fatalError()
        }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        if let textures = descriptor.textures {
            computeEncoder.setTextures(textures, range: 0..<textures.count)
        }
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        if let TGMemSize = descriptor.tgConfig.tgMemLength {
            TGMemSize.enumerated().forEach({
                computeEncoder.setThreadgroupMemoryLength($0.element, index: $0.offset)
            })
        }
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
    public func executeCardinalityShader() {
        
        let name = "getCardinality"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
            else {fatalError()}
        
        guard let ImageCount = descriptor.textures?.count else { fatalError("NumberOfTextures is Unknown.") }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        if let TGMemSize = descriptor.tgConfig.tgMemLength {
            TGMemSize.enumerated().forEach({
                computeEncoder.setThreadgroupMemoryLength($0.element, index: $0.offset)
            })
        }
        
        let streamingMultiprocessorsPerBlock = 4
        let blocksize = descriptor.state!.threadExecutionWidth * streamingMultiprocessorsPerBlock
        let remainder = firstTexture.width % blocksize
        let threads = MTLSizeMake(firstTexture.width + remainder, firstTexture.height, ImageCount)
        
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(blocksize, 1, 1))
        computeEncoder.endEncoding()
    }
    
    public func flush(buffer: MTLBuffer) {
        guard let flushBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
        flushBlitEncoder.endEncoding()
    }
}
