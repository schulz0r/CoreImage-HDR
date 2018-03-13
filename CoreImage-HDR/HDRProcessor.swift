//
//  HDRProcessor.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage
import MetalKit
import MetalPerformanceShaders
import MetalKitPlus

final class HDRProcessor: CIImageProcessorKernel {
    
    static let device = MTLCreateSystemDefaultDevice()
    
    override final class func process(with inputs: [CIImageProcessorInput]?, arguments: [String : Any]?, output: CIImageProcessorOutput) throws {
        guard
            let commandBuffer = output.metalCommandBuffer,
            let inputImages = inputs?.map({$0.metalTexture}),
            let HDRTexture = output.metalTexture,
            let exposureTimes = arguments?["ExposureTimes"] as? [Float],
            let cameraParameters = arguments?["CameraParameter"] as? CameraParameter
        else  {
                return
        }
        
        let MaxImageCount = 5
        guard inputImages.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard cameraParameters.responseFunction.count.isPowerOfTwo() else {
            fatalError("Length of Camera Response is not a power of two.")
        }
       
        let cameraShifts = arguments?["CameraShifts"] as? [int2] ?? [int2](repeating: int2(0,0), count: inputImages.count)
        var assets = MTKPAssets(HDRProcessor.self)
        
        // allocate ressources in IOs
        let Inputs = LDRImagesShaderIO(inputTextures: inputImages, exposureTimes: exposureTimes, cameraShifts: cameraShifts)
        let CameraParametersIO = CameraParametersShaderIO(cameraParameters: cameraParameters)
        // these IOs will provide the ressources to the kernels
        let HDRShaderIO = HDRCalcShaderIO(InputImageIO: Inputs, HDRImage: HDRTexture, cameraParametersIO: CameraParametersIO)
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRTexture, Inputs: Inputs)
        
        assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        let computer = HDRComputer(assets: assets)
        
        // encode all shaders
        computer.encode("makeHDR", to: commandBuffer)
        computer.encodeMPSMinMax(ofImage: HDRTexture, writeTo: scaleHDRShaderIO.minMaxTexture, to: commandBuffer)
        computer.encode("scaleHDR", to: commandBuffer)
    }
}
