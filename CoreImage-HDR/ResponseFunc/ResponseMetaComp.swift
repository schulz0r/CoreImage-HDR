//
//  ResponseMetaComp.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus
import MetalPerformanceShaders

/* A Metacomputer ensures that the computer executes/encodes the shader in the correct order
 and returns the result of the computation. */
protocol MetaComputer {
    var computer : HDRComputer {get}
}

public final class ResponseEstimator: MetaComputer {
    var computer : HDRComputer
    
    private var textures: [MTLTexture]! = nil
    private let MTLWeightFunc : MTLBuffer
    private let MTLResponseFunc : MTLBuffer
    
    init(ImageBracket: [CIImage], CameraShifts: [int2], context: CIContext? = nil) {
        guard ImageBracket.count > 1, ImageBracket.count <= 5 else {
            fatalError("Image bracket length must be at least 2 and 5 at maximum.")
        }
        guard MPSSupportsMTLDevice(MTKPDevice.device) else {
            fatalError("Your device does not support Metal Performance Shaders.")
        }
        
        let ExposureTimes:[Float] = ImageBracket.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary from image.")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        var assets = MTKPAssets(ResponseEstimator.self)
        let textureLoader = MTKTextureLoader(device: MTKPDevice.device)
        textures = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: MTKPDevice.device))}
        
        // create shared ressources
        let TGSizeOfSummationShader = (16, 16, 1)
        let totalBlocksCount = (textures.first!.height / TGSizeOfSummationShader.1) * (textures.first!.width / TGSizeOfSummationShader.0)
        let bufferLen = totalBlocksCount * 256
        
        guard
            let MTLCardinalities = MTKPDevice.device.makeBuffer(length: 3 * MemoryLayout<Float>.size * 256, options: .storageModePrivate),
            let MTLCameraShifts = MTKPDevice.device.makeBuffer(bytes: CameraShifts, length: MemoryLayout<uint2>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.device.makeBuffer(bytes: ExposureTimes, length: MemoryLayout<Float>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let buffer = MTKPDevice.device.makeBuffer(length: bufferLen * MemoryLayout<float3>.size/2, options: .storageModePrivate),  // float3 / 2 = half3
            let MTLWeightFuncBuffer = MTKPDevice.device.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .storageModeShared),
            let MTLResponseFuncBuffer = MTKPDevice.device.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .storageModeShared)
        else {
                fatalError("Could not initialize Buffers")
        }
        
        self.MTLWeightFunc = MTLWeightFuncBuffer
        self.MTLResponseFunc = MTLResponseFuncBuffer
        
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: textures, BinBuffer: buffer, exposureTimes: MTLExposureTimes, cameraShifts: MTLCameraShifts, cameraResponse: MTLResponseFunc, weights: MTLWeightFunc)
        let bufferReductionAssets = bufferReductionShaderIO(BinBuffer: buffer, bufferlength: bufferLen, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        
        // configure threadgroups for each shader
        let ResponseSummationThreadgroup = MTKPThreadgroupConfig(tgSize: TGSizeOfSummationShader, tgMemLength: [4 * TGSizeOfSummationShader.0 * TGSizeOfSummationShader.1])
        let bufferReductionThreadgroup = MTKPThreadgroupConfig(tgSize: (256,1,1))
        
        assets.add(shader: MTKPShader(name: "writeMeasureToBins", io: ResponseSummationAssets, tgConfig: ResponseSummationThreadgroup))
        assets.add(shader: MTKPShader(name: "reduceBins", io: bufferReductionAssets, tgConfig: bufferReductionThreadgroup))
        
        computer = HDRComputer(assets: assets)
    }
    
    public func estimate(cameraParameters: inout CameraParameter, iterations: Int) {
        guard
            let summationShader = computer.assets["writeMeasureToBins"],
            let buffer = summationShader.buffers?[0],
            let threadsForBinReductionShader = computer.assets["reduceBins"]?.tgConfig.tgSize,
            let MTLCardinalityBuffer = computer.assets["reduceBins"]?.buffers?[3]
        else {
            fatalError()
        }
        
        
        let smoothResponseAssets = smoothResponseShaderIO(cameraResponse: MTLResponseFunc, weightFunction: MTLWeightFunc, controlPointCount: cameraParameters.BSplineKnotCount)
        let smoothResponseThreadgroup = MTKPThreadgroupConfig(tgSize: (256 / cameraParameters.BSplineKnotCount, 1, 1))
        computer.assets.add(shader: MTKPShader(name: "smoothResponse", io: smoothResponseAssets, tgConfig: smoothResponseThreadgroup))
        
        memcpy(self.MTLResponseFunc.contents(), cameraParameters.responseFunction, cameraParameters.responseFunction.count * MemoryLayout<float3>.size)
        memcpy(self.MTLWeightFunc.contents(), cameraParameters.weightFunction, cameraParameters.weightFunction.count * MemoryLayout<float3>.size)
        
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        
        textures.forEach({ texture in
            computer.encodeMPSHistogram(forImage: texture, MTLHistogramBuffer: MTLCardinalityBuffer)
        })
        
        (0..<iterations).forEach({ iterationIdx in
            computer.encode("writeMeasureToBins")
            computer.encode("reduceBins", threads: threadsForBinReductionShader)
            computer.flush(buffer: buffer)
        })
        
        // if command buffer is not committed here, the smooth shader will not be
        // loaded for unknown reasons. This could be a metal bug.
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted() // must wait or smooth response won't be executed
        
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encode("smoothResponse", threads: MTLSizeMake(256, 1, 1))
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        cameraParameters.responseFunction = Array(UnsafeMutableBufferPointer(start: self.MTLResponseFunc.contents().assumingMemoryBound(to: float3.self), count: 256))
        cameraParameters.responseFunction = cameraParameters.responseFunction.map{$0 / cameraParameters.responseFunction[127]}
        cameraParameters.weightFunction = Array(UnsafeMutableBufferPointer(start: self.MTLWeightFunc.contents().assumingMemoryBound(to: float3.self), count: 256))
        let Max = float3(cameraParameters.weightFunction.map{$0.x}.max()!,
                         cameraParameters.weightFunction.map{$0.y}.max()!,
                         cameraParameters.weightFunction.map{$0.z}.max()!)
        cameraParameters.weightFunction = cameraParameters.weightFunction.map{$0 / Max}
    }
}
