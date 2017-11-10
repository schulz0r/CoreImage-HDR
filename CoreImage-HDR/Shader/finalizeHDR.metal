//
//  finalizeHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 20.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "defines.metal"

kernel void stretchContrastHDR(texture2d<float, access::read> input [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant float * upperBound [[buffer(0)]],
                               constant float * lowerBound [[buffer(1)]],
                               uint2 id [[thread_position_in_grid]]) {

    float4 pixel = input.read(id, 0);
    pixel.rgb = (pixel.rgb - lowerBound[0]) / (upperBound[0] - lowerBound[0]);
    output.write(saturate(pixel), id, 0);
}

