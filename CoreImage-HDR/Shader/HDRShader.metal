//
//  makeHDR.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 15.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "movingAverage.h"
#include "calculateHDR.h"

#define MAX_IMAGE_COUNT 5


kernel void makeHDR(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                    texture2d<half, access::write> HDRImage [[texture(MAX_IMAGE_COUNT)]],
                    constant uint & NumberOfinputImages [[buffer(0)]],
                    constant int2 * cameraShifts [[buffer(1)]],
                    constant float * exposureTimes [[buffer(2)]],
                    constant float3 * response [[buffer(3)]],
                    constant float3 * weights [[buffer(4)]],
                    uint2 gid [[thread_position_in_grid]]){
    
    half3 linearData[MAX_IMAGE_COUNT];
    array<uchar3,MAX_IMAGE_COUNT> indices;
    
    metal::array_ref<half3> linearDataArray = metal::array_ref<half3>(linearData, NumberOfinputImages);
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        indices[i] = uchar3(pixel * 255);
        linearData[i] = half3(response[indices[i].x].x, response[indices[i].y].y, response[indices[i].z].z);
    }
    
    // calculate moving average to reduce noise
    movingAverage(linearData, exposureTimes, NumberOfinputImages);
    
    // calculate HDR Value
    const half3 enhancedPixel = HDRValue(linearDataArray, indices, exposureTimes, weights);
    HDRImage.write(half4(enhancedPixel, 1), gid);
}

kernel void scaleHDR(texture2d<half, access::read> HDRImage,
                     texture2d<half, access::write> scaledHDRImage,
                     texture1d<half, access::read> MinMax,
                     uint2 gid [[thread_position_in_grid]]) {
    
    const half3 Minimum = MinMax.read(uint(0)).rgb;
    const half3 Maximum = MinMax.read(uint(1)).rgb;
    
    const half3 absoluteMaximum = metal::fmax(Maximum.r, metal::fmax(Maximum.g, Maximum.b));
    const half3 absoluteMinimum = metal::fmin(Minimum.r, metal::fmin(Minimum.g, Minimum.b));
    
    const half3 Range = absoluteMaximum - absoluteMinimum;
    
    const half3 pixel = HDRImage.read(gid).rgb;
    scaledHDRImage.write(half4((pixel - absoluteMinimum) / Range, 1), gid);
}

