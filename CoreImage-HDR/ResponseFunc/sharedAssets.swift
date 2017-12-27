//
//  sharedAssets.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 27.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKit
import MetalKitPlus

struct sharedAssets: MTKPDeviceUser {
    
    let Textures:[MTLTexture]
    let MTLCardinalities:MTLBuffer
    
    init(InputImages: [CIImage]) {
        guard self.device != nil else {
                fatalError("No Device Available.")
        }
        guard !InputImages.isEmpty else {
            fatalError("Input image array is empty.")
        }
        
        let textureLoader = MTKTextureLoader(device: self.device!)
        let context = CIContext(mtlDevice: self.device!)
        
        Textures = InputImages.map{textureLoader.newTexture(CIImage: $0, context: context)}    // load textures
        
        let ColourHistogramSize = 256 * 3
        guard MTLCardinalities = self.device?.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)! else {fatalError()}
    }
}
