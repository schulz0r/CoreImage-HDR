//
//  MTKP-HDR.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 24.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage
import MetalKit
import MetalPerformanceShaders
import MetalKitPlus

public struct MTKPHDR {
    
    public static func makeHDR(ImageBracket: [CIImage], exposureTimes: [Float], cameraParameters: CameraParameter, context: CIContext? = nil) -> CIImage {
        
        let MaxImageCount = 5
        guard ImageBracket.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard exposureTimes.count == ImageBracket.count else {
            fatalError("Each of the \(ImageBracket.count) input images require an exposure time. Only \(exposureTimes.count) could be found.")
        }
        guard cameraParameters.responseFunction.count.isPowerOfTwo() else {
            fatalError("Length of Camera Response is not a power of two.")
        }
        
        var assets = MTKPAssets(ResponseEstimator.self)
        let textureLoader = MTKTextureLoader(device: MTKPDevice.instance)
        let inputImages = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: MTKPDevice.instance))}
        
        let HDRTexDescriptor = inputImages.first!.getDescriptor()
        HDRTexDescriptor.pixelFormat = .rgba16Float
        
        guard let HDRTexture = MTKPDevice.instance.makeTexture(descriptor: HDRTexDescriptor) else {
            fatalError()
        }
        
        let cameraShifts = [int2](repeating: int2(0,0), count: inputImages.count)
        
        let Inputs = LDRImagesShaderIO(inputTextures: inputImages, exposureTimes: exposureTimes, cameraShifts: cameraShifts)
        let CameraParametersIO = CameraParametersShaderIO(cameraParameters: cameraParameters)
        let HDRShaderIO = HDRCalcShaderIO(InputImageIO: Inputs, HDRImage: HDRTexture, cameraParametersIO: CameraParametersIO)
        
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRTexture, Inputs: Inputs)
        
        assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        
        let computer = HDRComputer(assets: assets)
        
        // generate HDR image
        computer.encode("makeHDR")
        computer.encodeMPSMinMax(ofImage: HDRTexture, writeTo: scaleHDRShaderIO.minMaxTexture)
        computer.copy(texture: scaleHDRShaderIO.minMaxTexture, toBuffer: scaleHDRShaderIO.MPSMinMaxBuffer)
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        var MinMax = Array(UnsafeBufferPointer(start: scaleHDRShaderIO.MPSMinMaxBuffer.contents().assumingMemoryBound(to: float3.self), count: 2))
        
        // CLIP UPPER 1% OF PIXEL VALUES TO DISCARD NUMERICAL OUTLIERS
        // ... for that, get a histogram
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encodeMPSHistogram(forImage: HDRTexture,
                                    MTLHistogramBuffer: scaleHDRShaderIO.MPSHistogramBuffer,
                                    minPixelValue: vector_float4(MinMax.first!.x, MinMax.first!.y, MinMax.first!.z, 0),
                                    maxPixelValue: vector_float4(MinMax.last!.x, MinMax.last!.y, MinMax.last!.z, 1))
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        let clippingIndex = Array( UnsafeBufferPointer(start: scaleHDRShaderIO.MPSHistogramBuffer.contents().assumingMemoryBound(to: uint3.self), count: 256) ).indexOfUpper(percent: 0.02)
        MinMax[1] *= Float(256 - clippingIndex) / 256
        memcpy(scaleHDRShaderIO.MPSMinMaxBuffer.contents(), &MinMax, scaleHDRShaderIO.MPSMinMaxBuffer.length)
        
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.copy(buffer: scaleHDRShaderIO.MPSMinMaxBuffer, toTexture: scaleHDRShaderIO.minMaxTexture)
        computer.encode("scaleHDR")
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        let HDRConfiguration: [String:Any] = [kCIImageProperties : ImageBracket.first!.properties]
        return CIImage(mtlTexture: HDRTexture, options: HDRConfiguration)!
    }
}
