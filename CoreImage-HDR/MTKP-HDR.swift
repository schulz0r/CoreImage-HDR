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
        let textureLoader = MTKTextureLoader(device: MTKPDevice.device)
        let inputImages = ImageBracket.map{textureLoader.newTexture(CIImage: $0, context: context ?? CIContext(mtlDevice: MTKPDevice.device))}
        
        
        let HDRTexDescriptor = inputImages.first!.getDescriptor()
        HDRTexDescriptor.pixelFormat = .rgba16Float
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        
        guard
            let minMaxTexture = MTKPDevice.device.makeTexture(descriptor: descriptor),
            let HDRTexture = MTKPDevice.device.makeTexture(descriptor: HDRTexDescriptor),
            let MPSHistogramBuffer = MTKPDevice.device.makeBuffer(length: 3 * MemoryLayout<Float>.size * 256, options: .storageModeShared),
            let MPSMinMaxBuffer = MTKPDevice.device.makeBuffer(length: 2 * MemoryLayout<float3>.size, options: .storageModeShared)
        else  {
                fatalError()
        }
        
        
        
        let cameraShifts = [int2](repeating: int2(0,0), count: inputImages.count)
        
        let HDRShaderIO = HDRCalcShaderIO(inputTextures: inputImages,
                                          maximumLDRCount: MaxImageCount,
                                          HDRImage: HDRTexture,
                                          exposureTimes: exposureTimes,
                                          cameraShifts: cameraShifts,
                                          cameraParameters: cameraParameters)
        
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRTexture, darkestImage: inputImages[0], minMaxTexture: minMaxTexture)
        
        assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        
        let computer = HDRComputer(assets: assets)
        
        // generate HDR image
        computer.encode("makeHDR")
        computer.encodeMPSMinMax(ofImage: HDRTexture, writeTo: minMaxTexture)
        computer.copy(texture: minMaxTexture, toBuffer: MPSMinMaxBuffer)
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        var MinMax = Array(UnsafeBufferPointer(start: MPSMinMaxBuffer.contents().assumingMemoryBound(to: float3.self), count: 2))
        
        // CLIP UPPER 1% OF PIXEL VALUES TO DISCARD NUMERICAL OUTLIERS
        // ... for that, get a histogram
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encodeMPSHistogram(forImage: HDRTexture,
                                    MTLHistogramBuffer: MPSHistogramBuffer,
                                    minPixelValue: vector_float4(MinMax.first!.x, MinMax.first!.y, MinMax.first!.z, 0),
                                    maxPixelValue: vector_float4(MinMax.last!.x, MinMax.last!.y, MinMax.last!.z, 1))
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        let histogram:[uint3] = Array(UnsafeBufferPointer(start: MPSHistogramBuffer.contents().assumingMemoryBound(to: uint3.self), count: 256))
        
        var sum = float3(0)
        for (idx, bin) in histogram.reversed().enumerated() {
            sum += float3(Float(bin.x), Float(bin.y), Float(bin.z)) / float3(256)
            if sum.max()! > 0.01 {
                MinMax[1] = (1 - Float(idx) / 256) * MinMax[1]
                memcpy(MPSMinMaxBuffer.contents(), MinMax, MPSMinMaxBuffer.length)
                break
            }
        }
        
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.copy(buffer: MPSMinMaxBuffer, toTexture: minMaxTexture)
        computer.encode("scaleHDR")
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        let HDRConfiguration: [String:Any] = [kCIImageProperties : ImageBracket.first!.properties]
        return CIImage(mtlTexture: HDRTexture, options: HDRConfiguration)!
    }
}
