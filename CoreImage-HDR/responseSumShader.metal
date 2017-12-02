//
//  responseSumShader.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 01.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "SortAndCount.h"
//#include "calculateHDR.h"

#define MAX_IMAGE_COUNT 5

kernel void imageToBins(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                        constant uint & NumberOfinputImages [[buffer(0)]],
                        constant int2 * cameraShifts [[buffer(1)]],
                        constant float * exposureTimes [[buffer(2)]],
                        constant float3 * response [[buffer(3)]],
                        constant float3 * weights [[buffer(4)]],
                        threadgroup metal::array<SortAndCountElement<half3, half3>, 256> & DataBuffer [[threadgroup(0)]],
                        uint2 gid [[thread_position_in_grid]],
                        uint tid [[thread_index_in_threadgroup]]) {
    
    half3 linearData[MAX_IMAGE_COUNT];
    const array_ref<half3> PixelArray = make_array_ref(linearData, NumberOfinputImages);
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        const ushort3 indices = ushort3(pixel * 255);
        linearData[i] = half3(response[indices.x].x, response[indices.y].y, response[indices.z].z);
    }
    
    // calculate HDR Value
    DataBuffer[tid].element = HDRValue(PixelArray, exposureTimes, weights);
    DataBuffer[tid].counter = 0;
}
