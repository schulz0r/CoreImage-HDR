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
    var computer : ResponseCurveComputer {get}
}

public final class ResponseEstimator: MetaComputer {
    var computer : ResponseCurveComputer
    
    private let calculation:MPSImageHistogram
    private var textures: [MTLTexture]! = nil
    
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
        
        var histogramInfo = MPSImageHistogramInfo(
            numberOfHistogramEntries: 256, histogramForAlpha: false,
            minPixelValue: vector_float4(0,0,0,0),
            maxPixelValue: vector_float4(1,1,1,1))
        
        self.calculation = MPSImageHistogram(device: MTKPDevice.device, histogramInfo: &histogramInfo)
        self.calculation.zeroHistogram = false
        
        // create shared ressources
        let TrainingWeight:Float = 4    // TODO: let user decide about this weight
        let TGSizeOfSummationShader = (16, 16, 1)
        let totalBlocksCount = (textures.first!.height / TGSizeOfSummationShader.1) * (textures.first!.width / TGSizeOfSummationShader.0)
        let bufferLen = totalBlocksCount * 256
        
        guard
            let MTLCardinalities = MTKPDevice.device.makeBuffer(length: calculation.histogramSize(forSourceFormat: textures[0].pixelFormat), options: .storageModePrivate),
            let MTLCameraShifts = MTKPDevice.device.makeBuffer(bytes: CameraShifts, length: MemoryLayout<uint2>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.device.makeBuffer(bytes: ExposureTimes, length: MemoryLayout<Float>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let buffer = MTKPDevice.device.makeBuffer(length: bufferLen * MemoryLayout<float3>.size/2, options: .storageModePrivate),  // float3 / 2 = half3
            let MTLWeightFunc = MTKPDevice.device.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined),
            let MTLResponseFunc = MTKPDevice.device.makeBuffer(length: 256 * MemoryLayout<float3>.size, options: .storageModeShared)
        else {
                fatalError("Could not initialize Buffers")
        }
        
        let numberOfControlPoints = 16
        
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: textures, BinBuffer: buffer, exposureTimes: MTLExposureTimes, cameraShifts: MTLCameraShifts, cameraResponse: MTLResponseFunc, weights: MTLWeightFunc)
        let bufferReductionAssets = bufferReductionShaderIO(BinBuffer: buffer, bufferlength: bufferLen, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        let smoothResponseAssets = smoothResponseShaderIO(cameraResponse: MTLResponseFunc, weightFunction: MTLWeightFunc, controlPointCount: numberOfControlPoints)
        
        // configure threadgroups for each shader
        let ResponseSummationThreadgroup = MTKPThreadgroupConfig(tgSize: TGSizeOfSummationShader, tgMemLength: [4 * TGSizeOfSummationShader.0 * TGSizeOfSummationShader.1])
        let bufferReductionThreadgroup = MTKPThreadgroupConfig(tgSize: (256,1,1))
        let smoothResponseThreadgroup = MTKPThreadgroupConfig(tgSize: (256 / numberOfControlPoints, 1, 1))
        
        assets.add(shader: MTKPShader(name: "writeMeasureToBins", io: ResponseSummationAssets, tgConfig: ResponseSummationThreadgroup))
        assets.add(shader: MTKPShader(name: "reduceBins", io: bufferReductionAssets, tgConfig: bufferReductionThreadgroup))
        assets.add(shader: MTKPShader(name: "smoothResponse", io: smoothResponseAssets, tgConfig: smoothResponseThreadgroup))
        
        computer = ResponseCurveComputer(assets: assets)
    }
    
    public func estimate(cameraParameters: inout CameraParameter, iterations: Int) {
        guard
            let MTLResponse = computer.assets["writeMeasureToBins"]?.buffers?[4],
            let MTLWeights = computer.assets["writeMeasureToBins"]?.buffers?[5],
            let summationShader = computer.assets["writeMeasureToBins"],
            let buffer = summationShader.buffers?[0],
            let MTLResponseFunc = summationShader.buffers?[4],
            let threadsForBinReductionShader = computer.assets["reduceBins"]?.tgConfig.tgSize,
            let MTLCardinalityBuffer = computer.assets["reduceBins"]?.buffers?[3]
        else {
            fatalError()
        }
        
        memcpy(MTLResponse.contents(), cameraParameters.responseFunction, cameraParameters.responseFunction.count * MemoryLayout<float3>.size)
        memcpy(MTLWeights.contents(), cameraParameters.weightFunction, cameraParameters.weightFunction.count * MemoryLayout<float3>.size)
        
        computer.commandBuffer = computer.commandQueue.makeCommandBuffer()
        
        textures.forEach({ texture in
            calculation.encode(to: computer.commandBuffer,
                               sourceTexture: texture,
                               histogram: MTLCardinalityBuffer,
                               histogramOffset: 0)
        })
        
        (0..<iterations).forEach({ _ in
            computer.encode("writeMeasureToBins")
            computer.encode("reduceBins", threads: threadsForBinReductionShader)
            computer.flush(buffer: buffer)
        })
        
        computer.encode("smoothResponse", threads: MTLSizeMake(256, 1, 1))
        
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        cameraParameters.responseFunction = Array(UnsafeMutableBufferPointer(start: MTLResponseFunc.contents().assumingMemoryBound(to: float3.self), count: 256))
        cameraParameters.responseFunction = cameraParameters.responseFunction.map{$0 / cameraParameters.responseFunction[127]}
        cameraParameters.weightFunction = Array(UnsafeMutableBufferPointer(start: MTLWeights.contents().assumingMemoryBound(to: float3.self), count: 256))
    }
}
