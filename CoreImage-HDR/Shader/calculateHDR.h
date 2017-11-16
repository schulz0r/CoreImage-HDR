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

half3 HDRValue(thread half3 * linearPixel, const uint arrayLength, constant float * t, constant float3 * W, half maximum) {
    half3 zaehler = 0.0, nenner = 0.0, result = 0.0, weight;
    
    if(all(linearPixel[0].rgb != 255)){
        // read out array and calculate HDR value
        for(uint i = 0; i < arrayLength; i++){ // iterate through all images at position gid
            weight.rgb = half3( W[int(linearPixel[i].r)].r, W[int(linearPixel[i].g)].g, W[int(linearPixel[i].b)].b );
            zaehler += weight.rgb * t[i] * linearPixel[i].rgb;    // ACHTUNG: statt I[pixel[i]] steht hier linearDenoisedPixel[i], da beim denoisen schon linearisiert wurde
            nenner += weight.rgb * t[i] * t[i];
        }
        result = zaehler / nenner;
    } else {
        result = maximum;
    }
    
    return result;
}
