//
//  calculateHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 02.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//
#pragma once

#include <metal_stdlib>
using namespace metal;

inline half3 HDRValue(array_ref<half3> linearPixelArray, array_ref<uchar3> indices, constant float * t, constant float3 * W) {
    half3 zaehler = 0.0, nenner = 0.0, weight;
    
    for(uint i = 0; i < linearPixelArray.size(); i++){ // iterate through all images at position gid
        weight.rgb = half3( W[indices[i].r].r, W[indices[i].g].g, W[indices[i].b].b );
        zaehler += weight.rgb * t[i] * linearPixelArray[i].rgb;
        nenner += weight.rgb * (t[i] * t[i]);
    }
    
    return zaehler / nenner;
}
