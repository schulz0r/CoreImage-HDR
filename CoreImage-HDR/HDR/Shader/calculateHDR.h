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

half3 HDRValue(array_ref<half3> linearPixelArray, constant float * t, constant float3 * W) {
    half3 zaehler = 0.0, nenner = 0.0, result = 0.0, weight;
    
    if(all(linearPixelArray[0].rgb != 255)){ // if darkest pixel is saturated...
        // read out array and calculate HDR value
        for(uint i = 0; i < linearPixelArray.size(); i++){ // iterate through all images at position gid
            
            weight.rgb = half3( W[int(linearPixelArray[i].r)].r, W[int(linearPixelArray[i].g)].g, W[int(linearPixelArray[i].b)].b );
            zaehler += weight.rgb * t[i] * linearPixelArray[i].rgb;
            nenner += weight.rgb * (t[i] * t[i]);
        }
        result = zaehler / nenner;
    } else {
        result = HUGE_VALH; // ... tag it as Infinity.
    }
    
    return result;
}
