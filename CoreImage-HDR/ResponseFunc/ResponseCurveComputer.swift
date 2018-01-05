//
//  ResponseCurveComputer.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 28.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import MetalKitPlus

final class ResponseCurveComputer : MTKPComputer, MTKPCommandQueueUser {
    var assets: MTKPAssets
    internal var commandQueue: MTLCommandQueue!
    internal var commandBuffer: MTLCommandBuffer!
    
    init(assets: MTKPAssets) {
        self.assets = assets
        self.commandQueue = self.commandQueue ?? device!.makeCommandQueue()
        self.commandBuffer = self.commandQueue.makeCommandBuffer()
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
    }
    
    public func executeCardinalityShader() {
        guard self.device != nil else {
            fatalError("Device was not initialized.")
        }
        
        let name = "getCardinality"
        
        let streamingMultiprocessorsPerBlock = 4    // TODO: get actual number of the device, then ommit barriers in shader.
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(self.device!.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first
            else {fatalError()}
        
        guard descriptor.tgSize != nil else {
            fatalError("execute func")
        }
        
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
        guard self.device != nil else {
            fatalError("Device was not initialized.")
        }
        
        let name = "writeMeasureToBins"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first,
            let sharedMemSize = descriptor.tgSize
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
        computeEncoder.setThreadgroupMemoryLength(4 * sharedMemSize.0 * sharedMemSize.1, index: 0)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(sharedMemSize.0, sharedMemSize.1, sharedMemSize.2))
        computeEncoder.endEncoding()
    }
    
    public func executeBufferReductionShader() {
        guard self.device != nil else {
            fatalError("Device was not initialized.")
        }
        
        let name = "reduceBins"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer.makeComputeCommandEncoder(),
            let sharedMemSize = descriptor.tgSize
            else {fatalError()}
        
        guard descriptor.tgSize != nil else {
            fatalError("execute func")
        }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        
        guard descriptor.buffers != nil else {
            fatalError()
        }
        
        computeEncoder.setBuffers(descriptor.buffers!, offsets: [Int](repeating: 0, count: descriptor.buffers!.count), range: 0..<descriptor.buffers!.count)
        
        computeEncoder.setThreadgroupMemoryLength(4 * sharedMemSize.0 * sharedMemSize.1, index: 0)
        computeEncoder.dispatchThreadgroups(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(sharedMemSize.0, sharedMemSize.1, sharedMemSize.2))
        computeEncoder.endEncoding()
    }
    
    public func flush(buffer: MTLBuffer) {
        guard let flushBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
        flushBlitEncoder.endEncoding()
    }
}
