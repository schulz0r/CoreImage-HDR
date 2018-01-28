//
//  extensions.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 22.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//


extension Int {
    func isPowerOfTwo() -> Bool {
        return (self & (self - 1)) == 0
    }
}

extension MTLTexture {
    
    func getDescriptor() -> MTLTextureDescriptor {
        let Descriptor = MTLTextureDescriptor()
        Descriptor.arrayLength = self.arrayLength
        Descriptor.depth = self.depth
        Descriptor.height = self.height
        Descriptor.mipmapLevelCount = self.mipmapLevelCount
        Descriptor.pixelFormat = self.pixelFormat
        Descriptor.sampleCount = self.sampleCount
        Descriptor.storageMode = self.storageMode
        Descriptor.textureType = self.textureType
        Descriptor.usage = self.usage
        Descriptor.width = self.width
        
        return Descriptor
    }
    
    func size() -> MTLSize {
        return MTLSizeMake(self.width, self.height, self.depth)
    }
}
