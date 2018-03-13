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

public final class MTKPHDR: MetaComputer {
    internal var computer : HDRComputer
    
    init() {
        let assets = MTKPAssets(MTKPHDR.self)
        self.computer = HDRComputer(assets: assets)
    }
    
    /* Before you can calculate a HDR image, you should use this function to estimate the camera parameters. In order to do so, first create an instance of the CameraParameter struct (see file "CameraParameter.swift" for details).
     Pass the CameraParameter struct to this function along with a bracket of images. The higher the resolution of the images and the less noisy the images are, the better are the expected results. Anyway, the estimated parameters will be smoothed to reduce the influence of noise. The response curve is specific to the camera, so you do not need to estimate it every time you process an image. Instead, calculate it once for each camera and store it on disk for the next time you make a HDR image. */
    
    public func estimateResponse(ImageBracket: [CIImage], cameraShifts: [int2], cameraParameters: inout CameraParameter, iterations: Int) {
        /*
         Parameters:
         ImageBracket       ... An array of CIImages which show the same scene at different exposure levels.
         cameraShifts       ... Hand-held cameras potentially introduce shifts between images of a bracket which can be passed as a parameter.
         cameraParameters   ... struct which contains the weight and response functions which will be estimated here
         iterations         ... number of iterations for estimating the response curve
         */
        
        guard ImageBracket.count > 1, ImageBracket.count <= 5 else {
            fatalError("Image bracket length must be at least 2 and 5 at maximum.")
        }
        
        // create shared ressources
        let TGSizeOfSummationShader = (16, 16, 1)
        
        let Inputs = LDRImagesShaderIO(ImageBracket: ImageBracket, cameraShifts: cameraShifts)
        let CameraParametersIO = CameraParametersShaderIO(cameraParameters: &cameraParameters)
        let ResponseSummationAssets = ResponseSummationShaderIO(inputTextures: Inputs, camParameters: CameraParametersIO)
        
        // configure threadgroups for each shader
        let ResponseSummationThreadgroup = MTKPThreadgroupConfig(tgSize: TGSizeOfSummationShader, tgMemLength: [4 * TGSizeOfSummationShader.0 * TGSizeOfSummationShader.1])
        let bufferReductionThreadgroup = MTKPThreadgroupConfig(tgSize: (256,1,1))
        
        let smoothResponseAssets = smoothResponseShaderIO(cameraParameterIO: CameraParametersIO, controlPointCount: cameraParameters.BSplineKnotCount)
        let smoothResponseThreadgroup = MTKPThreadgroupConfig(tgSize: (256 / cameraParameters.BSplineKnotCount, 1, 1))
        
        self.computer.assets.add(shader: MTKPShader(name: "writeMeasureToBins", io: ResponseSummationAssets, tgConfig: ResponseSummationThreadgroup))
        self.computer.assets.add(shader: MTKPShader(name: "reduceBins", io: ResponseSummationAssets, tgConfig: bufferReductionThreadgroup))
        self.computer.assets.add(shader: MTKPShader(name: "smoothResponse", io: smoothResponseAssets, tgConfig: smoothResponseThreadgroup))
        
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        Inputs.fetchTextures()!.forEach({ texture in
            computer.encodeMPSHistogram(forImage: texture!, MTLHistogramBuffer: ResponseSummationAssets.fetchBuffers()![2])
        })
        
        (0..<iterations).forEach({ iterationIdx in
            computer.encode("writeMeasureToBins")
            computer.encode("reduceBins", threads: bufferReductionThreadgroup.tgSize)
            computer.flush(buffer: ResponseSummationAssets.fetchBuffers()![0])
        })
        
        // if command buffer is not committed here, the smooth shader will not be
        // loaded for unknown reasons. This could be a metal bug.
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted() // must wait or smooth response won't be executed
        
        computer.execute("smoothResponse", threads: MTLSizeMake(256, 1, 1))
        
        cameraParameters.responseFunction = Array(UnsafeMutableBufferPointer(start: CameraParametersIO.fetchBuffers()![0].contents().assumingMemoryBound(to: float3.self), count: 256))
        cameraParameters.responseFunction = cameraParameters.responseFunction.map{$0 / cameraParameters.responseFunction[127]}
        cameraParameters.weightFunction = Array(UnsafeMutableBufferPointer(start: CameraParametersIO.fetchBuffers()![1].contents().assumingMemoryBound(to: float3.self), count: 256))
        let Max = float3(cameraParameters.weightFunction.map{$0.x}.max()!,
                         cameraParameters.weightFunction.map{$0.y}.max()!,
                         cameraParameters.weightFunction.map{$0.z}.max()!)
        cameraParameters.weightFunction = cameraParameters.weightFunction.map{$0 / Max}
    }
    
    public func makeHDR(ImageBracket: [CIImage], cameraParameters: CameraParameter, cameraShifts: [int2]? = nil) -> CIImage {
        /*
         Parameters:
         ImageBracket       ... An array of CIImages which show the same scene at different exposure levels.
         cameraShifts       ... Hand-held cameras potentially introduce shifts between images of a bracket which can be passed as a parameter.
         cameraParameters   ... struct which contains the weight and response functions which will be estimated here
         */
        let MaxImageCount = 5
        guard ImageBracket.count <= MaxImageCount else {
            fatalError("Only up to \(MaxImageCount) images are allowed. It is an arbitrary number and can be changed in the HDR kernel any time.")
        }
        guard cameraParameters.responseFunction.count.isPowerOfTwo() else {
            fatalError("Length of Camera Response is not a power of two.")
        }
        let cameraShifts_ = cameraShifts ?? [int2](repeating: int2(0,0), count: ImageBracket.count)   // if there are no shifts defined, initialize with zeros
        
        let Inputs = LDRImagesShaderIO(ImageBracket: ImageBracket, cameraShifts: cameraShifts_)
        let HDRImage = HDRImageIO(size: Inputs.fetchTextures()!.first!!.size())
        let CameraParametersIO = CameraParametersShaderIO(cameraParameters: cameraParameters)
        let HDRShaderIO = HDRCalcShaderIO(InputImageIO: Inputs, HDRImage: HDRImage.HDRTexture, cameraParametersIO: CameraParametersIO)
        
        let scaleHDRShaderIO = scaleHDRValueShaderIO(HDRImage: HDRImage.HDRTexture, Inputs: Inputs)
        
        computer.assets.add(shader: MTKPShader(name: "makeHDR", io: HDRShaderIO))
        computer.assets.add(shader: MTKPShader(name: "scaleHDR", io: scaleHDRShaderIO))
        
        // generate HDR image
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encode("makeHDR")
        computer.encodeMPSMinMax(ofImage: HDRImage.HDRTexture, writeTo: scaleHDRShaderIO.minMaxTexture)
        computer.copy(texture: scaleHDRShaderIO.minMaxTexture, toBuffer: scaleHDRShaderIO.MPSMinMaxBuffer)
        computer.commandBuffer.commit()
        computer.commandBuffer.waitUntilCompleted()
        
        var MinMax = Array(UnsafeBufferPointer(start: scaleHDRShaderIO.MPSMinMaxBuffer.contents().assumingMemoryBound(to: float3.self), count: 2))
        
        // CLIP UPPER 1% OF PIXEL VALUES TO DISCARD NUMERICAL OUTLIERS
        // ... for that, get a histogram
        computer.commandBuffer = MTKPDevice.commandQueue.makeCommandBuffer()
        computer.encodeMPSHistogram(forImage: HDRImage.HDRTexture,
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
        return CIImage(mtlTexture: HDRImage.HDRTexture, options: HDRConfiguration)!
    }
}
