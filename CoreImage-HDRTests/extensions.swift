//
//  extensions.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 20.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import CoreImage
import AppKit

extension Int {
    func isPowerOfTwo() -> Bool {
        return (self & (self - 1)) == 0
    }
}

extension Array where Element: Comparable {
    func allNonSaturatedEqual(value: Element) -> Bool {
        return self[1..<self.endIndex-1].reduce(true){$0 && ($1 == value)}
    }
    
    func isAscendinglySorted() -> Bool {
        return self.elementsEqual(self.sorted())
    }
}

extension CIImage {
    func write(url: URL) {
        
        guard let pngFile = NSBitmapImageRep(ciImage: self).representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            fatalError("Could not convert to png.")
        }
        
        do {
            try pngFile.write(to: url)
        } catch let Error {
            print(Error.localizedDescription)
        }
    }
}

extension MTLTextureDescriptor {
    func makeTestTextureDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
        let testTextureDescriptor = MTLTextureDescriptor()
        testTextureDescriptor.textureType = .type2D
        testTextureDescriptor.height = height
        testTextureDescriptor.width = width
        testTextureDescriptor.depth = 1
        testTextureDescriptor.pixelFormat = .rgba32Float
        return testTextureDescriptor
    }
}
