//
//  Created by Philipp Waxweiler on 27.11.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

import Foundation
import MetalKit
import MetalKitPlus

final class smoothResponseShaderIO: MTKPIOProvider {
    private let cameraParameters: CameraParametersShaderIO
    private let cubicMatrix, controlPointBuffer: MTLBuffer
    
    init(cameraParameterIO: CameraParametersShaderIO, controlPointCount: Int) {
        
        var controlPoints = Array<Int32>( stride(from: 0, to: 255, by: 256/controlPointCount) )
        controlPoints.insert(0, at: 0)
        // only place holder
        controlPoints.append(255)
        controlPoints.append(255)
        controlPoints.append(255)
        
        var matrix:[float4] = [float4(-1.0/6.0,0.5,-0.5,1.0/6.0),
                               float4(0.5,-1,0,2.0/3.0),
                               float4(-0.5,0.5,0.5,1.0/6.0),
                               float4(1.0/6.0,0,0,0)]    // = float4x4
        
        guard
            let cubicMatrix = MTKPDevice.instance.makeBuffer(bytes: &matrix, length: MemoryLayout<float4>.size * 4, options: .cpuCacheModeWriteCombined),
            let controlPointBuffer = MTKPDevice.instance.makeBuffer(bytes: &controlPoints, length: MemoryLayout<Int32>.size * controlPoints.count, options: .cpuCacheModeWriteCombined) else {
                fatalError()
        }
        
        self.cubicMatrix = cubicMatrix
        self.controlPointBuffer = controlPointBuffer
        self.cameraParameters = cameraParameterIO
    }
    
    func fetchTextures() -> [MTLTexture?]? {
        return nil
    }
    
    func fetchBuffers() -> [MTLBuffer]? {
        return cameraParameters.fetchBuffers()! + [controlPointBuffer, cubicMatrix]
    }
}

