//
//  extensions.swift
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 20.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import CoreImage
import AppKit

extension Array where Element: Equatable{
    func allIs(value: Element) -> Bool {
        return self.reduce(true){$0 && ($1 == value)}
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
