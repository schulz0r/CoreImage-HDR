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

