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
    half3 zaehler = 0.0, nenner = 1e-6, weight;
    
    for(uint i = 0; (i < linearPixelArray.size()) && all((indices[i] != 255)); i++){ // iterate through all images at position gid
        if(all(indices[i] != 255)){
            weight.rgb = half3( W[indices[i].r].r, W[indices[i].g].g, W[indices[i].b].b );
            zaehler += weight.rgb * linearPixelArray[i].rgb * t[i];
            nenner += weight.rgb * (t[i] * t[i]);
        }
    }
    
    return zaehler / nenner;
}
