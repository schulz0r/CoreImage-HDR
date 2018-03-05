//
//  extensions.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 22.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//
import MetalKit

extension CIImage {
    func exposureTime() -> Float {
        guard let metaData = self.properties["{Exif}"] as? Dictionary<String, Any> else {
            fatalError("Cannot read Exif Dictionary from image.")
        }
        return metaData["ExposureTime"] as! Float
    }
}

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

extension Array where Element == uint3 {
    func indexOfUpper(percent: Float) -> Int {
        var index = 0
        var sum = float3(0)
        let totalPixelCount = self.reduce(uint3(0), &+)
        let totalPixelCount_float = float3(Float(totalPixelCount.x), Float(totalPixelCount.y), Float(totalPixelCount.z))
        
        for (idx, bin) in self.reversed().enumerated() {
            sum += float3(Float(bin.x), Float(bin.y), Float(bin.z)) / totalPixelCount_float
            if sum.max()! > percent {
                index = idx
                break
            }
        }
        
        return index
    }
}
