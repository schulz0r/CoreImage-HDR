//
//  binReduction.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


kernel void reduceBins(texture2d<half, access::read> buffer [[texture(0)]],
                       constant uint2 & imageSize [[buffer(0)]],
                       device half3 * cameraResponse [[buffer(1)]],
                       constant half3 * cardinality [[buffer(1)]],
                       threadgroup half3 * sharedBuffer [[threadgroup(0)]],
                       uint laneID [[thread_index_in_threadgroup]],
                       uint2 warpSize [[threads_per_threadgroup]],
                       uint2 gid [[thread_position_in_grid]]) {
    
    half3 localSum = 0;
    // collect bins until they can be reduced in shared memory
    for(uint globalPosition = laneID; laneID < imageSize.y; globalPosition += warpSize.y) {
        localSum += buffer.read(uint2(gid.x, globalPosition)).rgb;
    }
    
    sharedBuffer[laneID] = localSum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // reduce in threadgroup memory
    for(uint s = warpSize.y / 2; s > 0; s <<= 1) {
        if(laneID < s){
            sharedBuffer[laneID].rgb += sharedBuffer[laneID + s].rgb;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    switch(laneID) {
        case 0:
            // write to buffer
            cameraResponse[gid.x] = sharedBuffer[0].rgb / cardinality[gid.x];
            break;
        default:
            break;
    }
}

