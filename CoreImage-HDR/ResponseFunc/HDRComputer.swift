//
//  ResponseCurveComputer.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 28.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import MetalKitPlus
import MetalPerformanceShaders

final class HDRComputer : MTKPComputer {
    var assets:MTKPAssets
    public var commandBuffer: MTLCommandBuffer!
    
    init(assets: MTKPAssets) {
        self.assets = assets
        self.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
    }
    
    // shader execution functions
    // this encode function is being used in
    public func encode(_ name:String, to commandBuffer_: MTLCommandBuffer) {
        guard
            let descriptor = self.assets[name] as? MTKPComputePipelineStateDescriptor,
            descriptor.state != nil,
            let computeEncoder = commandBuffer_.makeComputeCommandEncoder()
            else {
                fatalError()
        }
        guard let threadCount = descriptor.textures?[0]?.size() else {
            fatalError("The thread count is unknown. Pass it as an argument to the encode function.")
        }
        computeEncoder.setComputePipelineState(descriptor.state!)
        if let textures = descriptor.textures {
            computeEncoder.setTextures(textures, range: 0..<textures.count)
        }
        if let buffers = descriptor.buffers {
            computeEncoder.setBuffers(buffers, offsets: [Int](repeating: 0, count: buffers.count), range: 0..<buffers.count)
        }
        computeEncoder.dispatchThreads(threadCount, threadsPerThreadgroup: descriptor.tgConfig.tgSize)
        computeEncoder.endEncoding()
    }
    
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
        let threadCount = threads ?? descriptor.textures![0]!.size()
        
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
    
    public func flush(buffer: MTLBuffer) {
        guard let flushBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        flushBlitEncoder.fill(buffer: buffer, range: Range(0...buffer.length), value: 0)
        flushBlitEncoder.endEncoding()
    }
    
    public func copy(texture: MTLTexture, toBuffer: MTLBuffer) {
        guard let copyBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        copyBlitEncoder.copy(from: texture,
                              sourceSlice: 0,
                              sourceLevel: 0,
                              sourceOrigin: MTLOriginMake(0, 0, 0),
                              sourceSize: texture.size(),
                              to: toBuffer,
                              destinationOffset: 0,
                              destinationBytesPerRow: toBuffer.length / texture.height,
                              destinationBytesPerImage: toBuffer.length)
        copyBlitEncoder.endEncoding()
    }
    
    public func copy(buffer: MTLBuffer, toTexture: MTLTexture) {
        guard let copyBlitEncoder = self.commandBuffer.makeBlitCommandEncoder() else {fatalError()}
        copyBlitEncoder.copy(from: buffer,
                              sourceOffset: 0,
                              sourceBytesPerRow: buffer.length / toTexture.height,
                              sourceBytesPerImage: buffer.length,
                              sourceSize: toTexture.size(),
                              to: toTexture,
                              destinationSlice: 0,
                              destinationLevel: 0,
                              destinationOrigin: MTLOriginMake(0, 0, 0))
        copyBlitEncoder.endEncoding()
    }
    
    public func encodeMPSHistogram(forImage: MTLTexture, MTLHistogramBuffer: MTLBuffer, minPixelValue: vector_float4 = vector_float4(0,0,0,0), maxPixelValue: vector_float4 = vector_float4(1,1,1,1)){
        var histogramInfo = MPSImageHistogramInfo(
            numberOfHistogramEntries: 256, histogramForAlpha: false,
            minPixelValue: minPixelValue,
            maxPixelValue: maxPixelValue)
        let calculation = MPSImageHistogram(device: MTKPDevice.instance, histogramInfo: &histogramInfo)
        calculation.zeroHistogram = false
        
        guard MTLHistogramBuffer.length == calculation.histogramSize(forSourceFormat: forImage.pixelFormat) else {
            fatalError("Did not allocate enough memory for storing histogram Data in given buffer.")
        }
        
        calculation.encode(to: commandBuffer,
                           sourceTexture: forImage,
                           histogram: MTLHistogramBuffer,
                           histogramOffset: 0)
    }
    
    public func encodeMPSMinMax(ofImage: MTLTexture, writeTo: MTLTexture) {
        let MPSMinMax = MPSImageStatisticsMinAndMax(device: MTKPDevice.instance)
        MPSMinMax.clipRectSource = MTLRegionMake2D(0, 0, ofImage.width, ofImage.height)
        MPSMinMax.encode(commandBuffer: self.commandBuffer,
                         sourceTexture: ofImage,
                         destinationTexture: writeTo)
    }
}
