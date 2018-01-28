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
        
        guard let HDRTexture = MTKPDevice.device.makeTexture(descriptor: HDRTexDescriptor) else  {
                fatalError()
        }
        
        
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type1D
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = 2
        
        let MPSMinMax = MPSImageStatisticsMinAndMax(device: MTKPDevice.device)
        MPSMinMax.clipRectSource = MTLRegionMake2D(0, 0, HDRTexture.width, HDRTexture.height)
        
        let imageDimensions = MTLSizeMake(HDRTexture.width, HDRTexture.height, 1)
        
        var numberOfInputImages = uint(inputImages.count)
        var cameraShifts = [int2](repeating: int2(0,0), count: inputImages.count)
        
        let HDRShaderIO = HDRCalcShaderIO(inputTextures: inputImages,
                                          maximumLDRCount: MaxImageCount,
                                          HDRImage: HDRTexture,
                                          exposureTimes: exposureTimes,
                                          cameraShifts: cameraShifts,
                                          cameraParameters: cameraParameters)
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRTexture, minMax: )
        
        assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        
        let computer = HDRComputer(assets: assets)
        
        computer.encode("makeHDR")
        
        
        do {
            guard
                let scaleFunc = library.makeFunction(name: "scaleHDR"),
                let ScaleEncoder = commandBuffer.makeComputeCommandEncoder() else {
                    fatalError("Failed to create command encoder.")
            }
            
            let HDRScaleState = try MTKPDevice.device.makeComputePipelineState(function: scaleFunc)
            ScaleEncoder.setComputePipelineState(HDRScaleState)
            ScaleEncoder.setTexture(HDRTexture, index: 0)
            ScaleEncoder.setTexture(HDRTexture, index: 1)
            ScaleEncoder.setTexture(inputImages[0], index: 2)
            ScaleEncoder.setTexture(MinMaxMTLTexture, index: 3)
            ScaleEncoder.dispatchThreads(imageDimensions, threadsPerThreadgroup: MTLSizeMake(8, 8, 1))
            ScaleEncoder.endEncoding()
        } catch let error {
            fatalError(error.localizedDescription)
        }
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let HDRConfiguration: [String:Any] = [kCIImageProperties : ImageBracket.first!.properties]
        
        return CIImage(mtlTexture: HDRTexture, options: HDRConfiguration)!
    }
}
