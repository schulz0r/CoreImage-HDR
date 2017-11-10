//
//  HistogramHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 19.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "defines.metal"

kernel void HDR_Histogram(texture2d<float, access::read> input [[texture(0)]],
                          volatile device atomic_uint * histogram [[buffer(0)]],
                          constant uint & nBins [[buffer(1)]],
                          constant float & maximalBrightness [[buffer(2)]],
                          uint2 id [[thread_position_in_grid]]) {
    
    float4 pixel = 0;
    float multiplikator = float(nBins) / maximalBrightness;
    
    // Histogram
    pixel = input.read(id, 0) * multiplikator;
    
    if( any(pixel.rgb == INFINITY) ){
        pixel = maximalBrightness;
    }
    
    atomic_fetch_add_explicit(&histogram[uint(pixel.r)], 1, memory_order::memory_order_relaxed);
    atomic_fetch_add_explicit(&histogram[uint(pixel.g)], 1, memory_order::memory_order_relaxed);
    atomic_fetch_add_explicit(&histogram[uint(pixel.b)], 1, memory_order::memory_order_relaxed);
}

