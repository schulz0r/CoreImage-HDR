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
    
    init(assets: MTKPAssets) {
        self.assets = assets
    }
    
    // shader execution functions
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
    
    public func executeCardinalityShader() {
        guard self.device != nil else {
            fatalError("Device was not initialized.")
        }
        //guard self.commandQueue != nil else {fatalError()}
        guard let CommandQ = self.commandQueue ?? device!.makeCommandQueue() else { fatalError("Could not intitialize command queue.") }
        
        let name = "getCardinality"
        
        let streamingMultiprocessorsPerBlock = 4    // TODO: get actual number of the device, then ommit barriers in shader.
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(self.device!.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let cmdBuffer = CommandQ.makeCommandBuffer(),
            let computeEncoder = cmdBuffer.makeComputeCommandEncoder(),
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
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
    }
    
    public func executeResponseSummationShader() {
        guard self.device != nil else {
            fatalError("Device was not initialized.")
        }
        //guard self.commandQueue != nil else {fatalError()}
        guard let CommandQ = self.commandQueue ?? device!.makeCommandQueue() else { fatalError("Could not intitialize command queue.") }
        
        let name = "writeMeasureToBins"
        
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let cmdBuffer = CommandQ.makeCommandBuffer(),
            let computeEncoder = cmdBuffer.makeComputeCommandEncoder(),
            let textures = descriptor.textures,
            let firstTexture = textures.first,
            let sharedMemSize = descriptor.tgSize
            else {fatalError()}
        
        guard descriptor.tgSize != nil else {
            fatalError("execute func")
        }
        
        guard let ImageCount = descriptor.textures?.count else { fatalError("NumberOfTextures is Unknown.") }
        
        computeEncoder.setComputePipelineState(descriptor.state!)
        computeEncoder.setTextures(textures, range: 0..<textures.count)
        
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        
        let threads = MTLSizeMake(firstTexture.width, firstTexture.height, 1)
        computeEncoder.setThreadgroupMemoryLength(4 * sharedMemSize.0 * sharedMemSize.1, index: 0)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: MTLSizeMake(sharedMemSize.0, sharedMemSize.1, sharedMemSize.2))
        computeEncoder.endEncoding()
        
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
    }
}
