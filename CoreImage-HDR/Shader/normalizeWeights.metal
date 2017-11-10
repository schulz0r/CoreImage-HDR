//
//  normalizeWeights.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 26.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

inline float3 reduce_max(threadgroup float3 * data, uint threadgroupsize, thread uint id);

kernel void normalizeWeights(device float3 *weights [[buffer(0)]],
                             uint gid [[thread_position_in_grid]]) {
    threadgroup float3 buffer[256];
    
    buffer[gid] = weights[gid];
    weights[gid] /= reduce_max(buffer, 256, gid);
}

inline float3 reduce_max(threadgroup float3 * data, uint threadgroupsize, uint id){
    for(uint s = threadgroupsize/2; s > 0; s >>=1){
        if(id < s){
            data[id].rgb = fmax(data[id].rgb, data[id+s].rgb);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    return data[0];
}
