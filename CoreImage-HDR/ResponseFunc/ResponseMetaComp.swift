//
//  ResponseMetaComp.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

/* A Metacomputer ensures that the computer executes/encodes the shader in the correct order
 and returns the result of the computation. */
protocol MetaComputer {
    var computer : ResponseCurveComputer {get}
}

public final class ResponseEstimator: MetaComputer {
    var computer : ResponseCurveComputer
    
    private var textures: [MTLTexture]! = nil
    
    init(ImageBracket: [CIImage], CameraShifts: [int2], context: CIContext? = nil) {
        guard ImageBracket.count > 1, ImageBracket.count <= 5 else {
            fatalError("Image bracket length must be at least 2 and 5 at maximum.")
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
        let TrainingWeight:Float = 4    // TODO: let user decide about this weight
        let TGSizeOfSummationShader = (16, 16, 1)
        let totalBlocksCount = (textures.first!.height / TGSizeOfSummationShader.1) * (textures.first!.width / TGSizeOfSummationShader.0)
        let bufferLen = totalBlocksCount * 256
        // define intial functions which are to estimate
        var initialCamResponse:[float3] = Array<Float>(stride(from: 0.0, to: 2.0, by: 2.0/256.0)).map{float3($0)}
        var initialWeightFunc:[float3] = (0...255).map{ float3( exp(-TrainingWeight * pow( (Float($0)-127.5)/127.5, 2)) ) }
        
        guard
            let MTLCardinalities = MTKPDevice.device.makeBuffer(length: MemoryLayout<uint>.size * 256 * 3, options: .storageModePrivate),
            let MTLCameraShifts = MTKPDevice.device.makeBuffer(bytes: CameraShifts, length: MemoryLayout<uint2>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = MTKPDevice.device.makeBuffer(bytes: ExposureTimes, length: MemoryLayout<Float>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let buffer = MTKPDevice.device.makeBuffer(length: bufferLen * MemoryLayout<float3>.size/2, options: .storageModePrivate),  // float3 / 2 = half3
            let MTLWeightFunc = MTKPDevice.device.makeBuffer(bytes: &initialWeightFunc, length: initialWeightFunc.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined),
            let MTLResponseFunc = MTKPDevice.device.makeBuffer(bytes: &initialCamResponse, length: initialCamResponse.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        else {
                fatalError("Could not initialize Buffers")
        }
        
        let streamingMultiprocessorsPerBlock = 4
        let sharedColourHistogramSize = MemoryLayout<uint>.size * 257 * 3
        let replicationFactor_R = max(MTKPDevice.device.maxThreadgroupMemoryLength / (streamingMultiprocessorsPerBlock * sharedColourHistogramSize), 1)
        
        let CardinalityShaderAssets = CardinalityShaderIO(inputTextures: textures, cardinalityBuffer: MTLCardinalities, ReplicationFactor: replicationFactor_R)
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: textures, BinBuffer: buffer, exposureTimes: MTLExposureTimes, cameraShifts: MTLCameraShifts, cameraResponse: MTLResponseFunc, weights: MTLWeightFunc)
        let bufferReductionAssets = bufferReductionShaderIO(BinBuffer: buffer, bufferlength: bufferLen, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        
        
        // configure threadgroups for each shader
        let CardinalityThreadgroup = MTKPThreadgroupConfig(tgSize: (1,1,1), tgMemLength: [replicationFactor_R * (MTLCardinalities.length + MemoryLayout<uint>.size * 3)])
        let ResponseSummationThreadgroup = MTKPThreadgroupConfig(tgSize: TGSizeOfSummationShader, tgMemLength: [4 * TGSizeOfSummationShader.0 * TGSizeOfSummationShader.1])
        let bufferReductionThreadgroup = MTKPThreadgroupConfig(tgSize: (256,1,1))
        
        
        assets.add(shader: MTKPShader(name: "getCardinality", io: CardinalityShaderAssets, tgConfig: CardinalityThreadgroup))
        assets.add(shader: MTKPShader(name: "writeMeasureToBins", io: ResponseSummationAssets, tgConfig: ResponseSummationThreadgroup))
        assets.add(shader: MTKPShader(name: "reduceBins", io: bufferReductionAssets, tgConfig: bufferReductionThreadgroup))
        
        computer = ResponseCurveComputer(assets: assets)
    }
    
    public func estimateCameraResponse(iterations: Int) -> [float3] {
        var Cardinality = [float3](repeating: float3(0), count: 256)
        guard
            let summationShader = computer.assets["writeMeasureToBins"],
            let buffer = summationShader.buffers?[0],
            let MTLCardinality = summationShader.buffers?[4],
            let threadsForBinReductionShader = computer.assets["writeMeasureToBins"]?.tgConfig.tgSize
        else {
            fatalError()
        }
        
        computer.commandBuffer = computer.commandQueue.makeCommandBuffer()
        
        computer.executeCardinalityShader()
        
        (0...iterations).forEach({ _ in
            computer.encode("writeMeasureToBins")
            computer.encode("reduceBins", threads: threadsForBinReductionShader)
            computer.flush(buffer: buffer)
        })
        
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        memcpy(&Cardinality, MTLCardinality.contents(), MTLCardinality.length)
        
        return Cardinality.map{$0 / Cardinality.last!}
    }
}
