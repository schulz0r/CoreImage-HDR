//
//  sharedAssets.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 27.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

public struct sharedAssets: MTKPDeviceUser {
    
    let Textures:[MTLTexture]
    let MTLCardinalities:MTLBuffer
    public var device: MTLDevice?
    
    init(InputImages: [CIImage]) {
        guard !InputImages.isEmpty else {
            fatalError("Input image array is empty.")
        }
        guard device != nil else {
            fatalError("Device was not initialized.")
        }
        
        let textureLoader = MTKTextureLoader(device: device!)
        let context = CIContext(mtlDevice: self.device!)
        
        self.Textures = InputImages.map{textureLoader.newTexture(CIImage: $0, context: context)}    // load textures
        
        let ColourHistogramSize = 256 * 3
        MTLCardinalities = self.device!.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)!
    }
}
