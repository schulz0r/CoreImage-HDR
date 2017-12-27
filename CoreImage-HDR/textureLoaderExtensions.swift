//
//  textureLoaderExtensions.swift
//  HDR-Module
//
//  Created by Philipp Waxweiler on 30.11.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

import MetalKit
import CoreImage

extension MTKTextureLoader {
    func newTexture(CIImage: CIImage, context: CIContext, mips: Int = 0) -> MTLTexture {
        
        let colorspace = CIImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.arrayLength = 1
        textureDescriptor.height = Int(CIImage.extent.height)
        textureDescriptor.width = Int(CIImage.extent.width)
        textureDescriptor.pixelFormat = .rgba16Unorm
        textureDescriptor.storageMode = .managed
        textureDescriptor.textureType = .type2D
        textureDescriptor.mipmapLevelCount = mips
        textureDescriptor.usage = .unknown
        let metalTexture = self.device.makeTexture(descriptor: textureDescriptor)
        
        let cmdQueue = device.makeCommandQueue()
        let cmdBuffer = cmdQueue?.makeCommandBuffer()

        context.render(CIImage, to: metalTexture!, commandBuffer: cmdBuffer, bounds: CIImage.extent, colorSpace: colorspace)
        
        if metalTexture!.mipmapLevelCount > 1 {
            let encoder = cmdBuffer?.makeBlitCommandEncoder()
            encoder?.generateMipmaps(for: metalTexture!)
            encoder?.endEncoding()
        }
        
        
        cmdBuffer?.commit()
        return metalTexture!
    }

}
