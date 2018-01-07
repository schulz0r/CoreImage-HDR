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
    public func execute(_ name:String) {
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
            else {fatalError()}
        
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        
        let threads = MTLSizeMake(firstTexture.width, firstTexture.height, 1)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
    public func executeCardinalityShader() {
        
        let name = "getCardinality"
        
        let streamingMultiprocessorsPerBlock = 4    // TODO: get actual number of the device, then ommit barriers in shader.
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(MTKPDevice.device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
            else {fatalError()}
        
        guard let histogramBuffer = descriptor.buffers?[2] else { fatalError("Cardinality Buffer does not exist.") }
        guard let ImageCount = descriptor.textures?.count else { fatalError("NumberOfTextures is Unknown.") }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        
        let blocksize = descriptor.state!.threadExecutionWidth * streamingMultiprocessorsPerBlock
        let remainder = firstTexture.width % blocksize
        let threads = MTLSizeMake(firstTexture.width + remainder, firstTexture.height, ImageCount)
        computeEncoder.setThreadgroupMemoryLength(replicationFactor_R * (histogramBuffer.length + MemoryLayout<uint>.size * 3), index: 0)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(blocksize, 1, 1))
        computeEncoder.endEncoding()
    }
    
    public func executeResponseSummationShader() {
        
        let name = "writeMeasureToBins"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
            else {fatalError()}
        
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        
        let threads = MTLSizeMake(firstTexture.width, firstTexture.height, 1)
        computeEncoder.setThreadgroupMemoryLength(4 * descriptor.tgConfig.tgSize.width * descriptor.tgConfig.tgSize.height, index: 0)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
    public func executeBufferReductionShader() {
        
        let name = "reduceBins"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder()
            else {fatalError()}
        
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        
        guard descriptor.buffers != nil else {
            fatalError()
        }
        
        computeEncoder.setBuffers(descriptor.buffers!, offsets: [Int](repeating: 0, count: descriptor.buffers!.count), range: 0..<descriptor.buffers!.count)
        if let TGMemSize = descriptor.tgConfig.tgMemLength {
            TGMemSize.enumerated().forEach({
                computeEncoder.setThreadgroupMemoryLength($0.element, index: $0.offset)
            })
        }
        
        computeEncoder.dispatchThreadgroups(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
    public func flush(buffer: MTLBuffer) {
        guard let flushBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
        flushBlitEncoder.endEncoding()
    }
}
