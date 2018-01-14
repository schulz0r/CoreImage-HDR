//
//  scaleHDRImage.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 14.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

kernel void scaleHDR(texture2d<half, access::read_write> HDRImage,
                     texture1d<half, access::read> MinMax,
                     uint2 gid [[thread_position_in_grid]]) {
    
    const half3 Minimum = MinMax.read(uint(0)).rgb;
    const half3 Maximum = MinMax.read(uint(1)).rgb;
    const half3 Range = Maximum - Minimum;
    
    const half3 pixel = HDRImage.read(gid).rgb;
    HDRImage.write(half4((pixel - Minimum) / Range, 1), gid);
}
