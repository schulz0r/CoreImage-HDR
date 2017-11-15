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
        guard
            let device = device,
            let commandBuffer = output.metalCommandBuffer,
            let inputImages = inputs?.map({$0.metalTexture}),
            let destinationTexture = output.metalTexture,
            let exposureTimes = arguments?["ExposureTimes"] as? [Float]
        else  {
                return
        }
        
        guard inputImages.count <= 5 else {
            fatalError("Only up to 5 images are allowed. If you want more, you can easily edit the HDRProcessor code.")
        }
        
            
    }
}
