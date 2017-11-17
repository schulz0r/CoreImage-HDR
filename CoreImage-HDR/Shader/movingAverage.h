//
//  denoiseHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 20.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//
#pragma once
#include <metal_stdlib>
using namespace metal;

half weightFunction(uint x);

void movingAverage(thread half3 * linearPixel, constant float * t, const uint arraySize) {
    half3 zaehler, nenner, weight;
    for(uint a = 0; a < arraySize - 1; a++){  // -1 for last pixel not being corrected
        zaehler = 0;
        nenner = 0;
        
        // from image a onwards, calculate the weighted sum of the image and its successive ones
        for(uint j = a; j < arraySize; j++) {
            const int3 indices = int3(linearPixel[j] * 255);
            weight.rgb = j == a? half3(1) : half3( weightFunction(indices.r), weightFunction(indices.g), weightFunction(indices.b) );
            zaehler.rgb += linearPixel[j] * weight;
            nenner.rgb += weight.rgb * t[j];
        }
        linearPixel[a] = t[a] * (zaehler / nenner);
    }
}

// weight function puts less weight on saturated pixels
half weightFunction(uint x){
    half h;
    if(x < 200){
        return 1.0;
    } else if( (200 <= x) && (x < 250) ){
        h = 1.0 - (half(250 - x) / 50.0);
        return 1.0 - 3.0 * powr(h, 2.h) + 2.0 * powr(h, 3.h);
    } else {
        return 0.0;
    }
}
