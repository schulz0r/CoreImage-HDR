//
//  HDRCalcShaderIO.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 27.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import Foundation
import MetalKit
import MetalKitPlus

final class HDRCalcShaderIO: MTKPIOProvider {
    
    private let HDR: MTLTexture
    private var inputImages: LDRImagesShaderIO
    private var CamParametersIO:CameraParametersShaderIO
    
    init(InputImageIO: LDRImagesShaderIO, HDRImage: MTLTexture, cameraParametersIO: CameraParametersShaderIO){
        self.HDR = HDRImage
        self.inputImages = InputImageIO
        self.CamParametersIO = cameraParametersIO
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return inputImages.fetchTextures()! + [HDR]
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return inputImages.fetchBuffers()! + CamParametersIO.fetchBuffers()!
    }
}

