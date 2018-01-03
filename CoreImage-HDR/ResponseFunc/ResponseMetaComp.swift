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
    private var textureLoader: MTKTextureLoader! = nil
    private var textures: [MTLTexture]! = nil
    
    init(ImageBracket: [CIImage], context: CIContext? = nil) {
        guard self.device != nil else {
            fatalError("Device is not initialized.")
        }
        
        let ExposureTimes:[Float] = ImageBracket.map{
            guard let metaData = $0.properties["{Exif}"] as? Dictionary<String, Any> else {
                fatalError("Cannot read Exif Dictionary")
            }
            return metaData["ExposureTime"] as! Float
        }
        
        textureLoader = MTKTextureLoader(device: self.device!)
        textures = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: self.device!))}
        
        // create shared ressources
        guard
            let MTLCardinalities = self.device!.makeBuffer(length: MemoryLayout<uint>.size * 256 * 3, options: .storageModeShared)
        else {
                fatalError("Could not initialize Buffers")
        }
        
        let CardinalityShaderAssets = CardinalityShaderIO(inputTextures: textures, cardinalityBuffer: MTLCardinalities)
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: textures, BinBuffer: <#T##MTLBuffer#>, exposureTimes: <#T##MTLBuffer#>, cameraShifts: <#T##MTLBuffer#>, cameraResponse: <#T##MTLBuffer#>, weights: <#T##MTLBuffer#>)
    }
    
    public func estimateCameraResponse() {
        
    }
}
