//
//  ResponseMetaComp.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

public final class ResponseEstimator : MTKPDeviceUser {
    private var assets = MTKPAssets(ResponseEstimator.self)
    private var textureLoader: MTKTextureLoader! = nil
    private var textures: [MTLTexture]! = nil
    
    init(ImageBracket: [CIImage], CameraShifts: [int2], context: CIContext? = nil) {
        guard self.device != nil else {
            fatalError("Device is not initialized.")
        }
        guard ImageBracket.count > 1 else {
            fatalError("Image bracket count must be at least 2.")
        }
        
        let ExposureTimes:[Float] = ImageBracket.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary from image.")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        textureLoader = MTKTextureLoader(device: self.device!)
        textures = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: self.device!))}
        
        // create shared ressources
        let TrainingWeight:Float = 4
        let TGSizeOfSummationShader = MTLSizeMake(16, 16, 1)
        let totalBlocksCount = (textures.first!.height / TGSizeOfSummationShader.height) * (textures.first!.width / TGSizeOfSummationShader.width)
        let bufferLen = totalBlocksCount * 256
        // define intial functions which are to estimate
        var initialCamResponse:[float3] = Array<Float>(stride(from: 0.0, to: 2.0, by: 2.0/256.0)).map{float3($0)}
        var initialWeightFunc:[float3] = (0...255).map{ float3( exp(-TrainingWeight * pow( (Float($0)-127.5)/127.5, 2)) ) }
        
        guard
            let MTLCardinalities = device!.makeBuffer(length: MemoryLayout<uint>.size * 256 * 3, options: .cpuCacheModeWriteCombined),
            let MTLCameraShifts = device!.makeBuffer(bytes: CameraShifts, length: MemoryLayout<uint2>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let MTLExposureTimes = device!.makeBuffer(bytes: ExposureTimes, length: MemoryLayout<Float>.size * ImageBracket.count, options: .cpuCacheModeWriteCombined),
            let buffer = device!.makeBuffer(length: bufferLen * MemoryLayout<float3>.size/2, options: .storageModePrivate),  // float3 / 2 = half3
            let MTLWeightFunc = device!.makeBuffer(bytesNoCopy: &initialWeightFunc, length: initialWeightFunc.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined),
            let MTLResponseFunc = device!.makeBuffer(bytesNoCopy: &initialCamResponse, length: initialCamResponse.count * MemoryLayout<float3>.size, options: .cpuCacheModeWriteCombined)
        else {
                fatalError("Could not initialize Buffers")
        }
        
        let CardinalityShaderAssets = CardinalityShaderIO(inputTextures: textures, cardinalityBuffer: MTLCardinalities)
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: textures, BinBuffer: buffer, exposureTimes: MTLExposureTimes, cameraShifts: MTLCameraShifts, cameraResponse: MTLResponseFunc, weights: MTLWeightFunc)
        let bufferReductionAssets = bufferReductionShaderIO(BinBuffer: buffer, bufferlength: bufferLen, cameraResponse: MTLResponseFunc, Cardinality: MTLCardinalities)
        
        assets.add(shader: MTKPShader(name: "getCardinality", io: CardinalityShaderAssets, tgSize: (0,0,0)))
        assets.add(shader: MTKPShader(name: "writeMeasureToBins", io: ResponseSummationAssets, tgSize: (16,16,1)))
        assets.add(shader: MTKPShader(name: "reduceBins", io: bufferReductionAssets, tgSize: (256,1,1)))
    }
    
    public func estimateCameraResponse() {
        
    }
}
