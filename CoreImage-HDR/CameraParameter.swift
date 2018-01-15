//
//  CameraParameter.swift
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 15.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//
import MetalKit

public struct CameraParameter {
    public var weightFunction:[float3]
    public var responseFunction:[float3]
    
    public init(withTrainingWeight: Float) {
        responseFunction = Array<Float>(stride(from: 0.0, to: 2.0, by: 2.0/256.0)).map{float3($0)}
        weightFunction = (0...255).map{ float3( exp(-withTrainingWeight * pow( (Float($0)-127.5)/127.5, 2)) ) }
    }
}
