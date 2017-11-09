//
//  HDRProcessor.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 09.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import Foundation
import CoreImage

final class HDRProcessor: CIImageProcessorKernel {
    static let device = MTLCreateSystemDefaultDevice()
    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String : Any]?, output: CIImageProcessorOutput) throws {
        
    }
}
