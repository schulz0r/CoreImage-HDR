//
//  asset.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 23.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

import MetalKitPlus
import CoreImage

final class ResponseEstimationIO: MTKPShaderIO {
    
    let Assets = MTKPAssets()
    
    convenience init(InputImages: [CIImage]) {
        self.init()
        
        guard self.device != nil else {
            fatalError("No Device Available.")
        }
        //let Textures = InputImages.map{self.textureLoader.load($0)}    // load textures
        let ColourHistogramSize = 256 * 3
        let MTLCardinalities = self.device!.makeBuffer(length: MemoryLayout<uint>.size * ColourHistogramSize, options: .storageModeShared)
        
        let threadExecutionWidth:Int = {
            var someState:MTLComputePipelineState
            guard
                let lib = Assets.library,
                let someFunction = lib.makeFunction(name: "getCardinality"),
                let device = self.device
            else {fatalError()}
            do { someState = try device.makeComputePipelineState(function: someFunction) } catch let Errors { fatalError(Errors.localizedDescription) }
            return someState.threadExecutionWidth
        }()
        
        let streamingMultiprocessorsPerBlock = 4 // TODO: replace with actual number of streaming multiprocessors which share memory
        let blocksize = threadExecutionWidth * streamingMultiprocessorsPerBlock
        
        let CardinalityShaderRessources = CardinalityShaderIO(inputImages: <#T##[MTLTexture]#>, cardinalityBuffer: MTLCardinalities)
        let CardinalityShader = MTKPShader(name: "getCardinality", io: CardinalityShaderRessources, tgSize: MTLSizeMake(blocksize, 1, 1))
        
        Assets.add(shader: CardinalityShader)
    }
}