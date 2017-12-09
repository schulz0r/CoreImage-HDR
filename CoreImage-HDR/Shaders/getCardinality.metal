//
//  getCardinality.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
#include <metal_atomic>
using namespace metal;

#define MAX_IMAGE_COUNT 5
#define BIN_COUNT 256

kernel void getCardinality(const metal::array<texture2d<half>, MAX_IMAGE_COUNT> images [[texture(0)]],
                           constant uint2 & imageDimensions [[buffer(0)]],
                           constant uint & ReplicationFactor [[buffer(1)]],
                           device atomic_uint * Cardinality_red [[buffer(2)]],
                           device atomic_uint * Cardinality_green [[buffer(3)]],
                           device atomic_uint * Cardinality_blue [[buffer(4)]],
                           threadgroup atomic_uint * buffer_red [[threadgroup(0)]],
                           threadgroup atomic_uint * buffer_green [[threadgroup(1)]],
                           threadgroup atomic_uint * buffer_blue [[threadgroup(2)]],
                           uint3 gid [[thread_position_in_grid]],
                           uint threadID [[thread_index_in_threadgroup]],
                           uint warpsPerThreadgroup [[simdgroups_per_threadgroup]],
                           uint warpID [[simdgroup_index_in_threadgroup]],
                           uint warpSize [[threads_per_simdgroup]],
                           uint3 blockSize [[threads_per_threadgroup]],
                           uint3 threadgroupID [[threadgroup_position_in_grid]],
                           uint3 gridSize [[threads_per_grid]],
                           uint laneID [[thread_index_in_simdgroup]]) {
    
    // Allocated threadgroup memory initially contains random values.
    // You MUST set it to zero first.
    for(uint i = threadID; i < ((BIN_COUNT + 1) * ReplicationFactor); i += blockSize.x) {
        (threadgroup uint &)buffer_red[i] = 0;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    const thread uint & imageSlice = gid.z;
    // associate each thread to another histogram in shared memory to reduce collisions
    const uint replicationOffset = (BIN_COUNT + 1) * (threadID % ReplicationFactor);
    //threadgroup atomic_uint * associatedReplicate = buffer_red + replicationOffset;
    // spread locations of reads to gather diverse pixels in order to reduce collides
    const uint interleavedReadAccessOffset = (gridSize.x / warpsPerThreadgroup) * warpID + warpSize * threadgroupID.x + laneID;
    
    if(interleavedReadAccessOffset < imageDimensions.x){ // grid size may be unequal to image size...
        const uchar3 pixel = (uchar3) ( images[imageSlice].read(uint2(interleavedReadAccessOffset, gid.y)).rgb * (BIN_COUNT - 1) );
    
        atomic_fetch_add_explicit(&buffer_red[replicationOffset + pixel.r], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&buffer_green[replicationOffset + pixel.b], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&buffer_blue[replicationOffset + pixel.b], 1, memory_order::memory_order_relaxed);
        
        
        // sum up results from buffer
        uint3 sum = 0;
        for(uint pos = threadID; pos < BIN_COUNT; pos += blockSize.x, sum = uint3(0)) {
            for(uint base = 0; base < (BIN_COUNT + 1) * ReplicationFactor; base += BIN_COUNT + 1) {
                /*sum.r += (threadgroup uint &)buffer_red[pos + base];
                sum.g += (threadgroup uint &)buffer_green[pos + base];
                sum.b += (threadgroup uint &)buffer_blue[pos + base];
                */
                sum.r += atomic_load_explicit(&buffer_red[pos + base], memory_order::memory_order_relaxed);
                sum.g += atomic_load_explicit(&buffer_green[pos + base], memory_order::memory_order_relaxed);
                sum.b += atomic_load_explicit(&buffer_blue[pos + base], memory_order::memory_order_relaxed);
            }
            atomic_fetch_add_explicit(&Cardinality_red[pos], sum.r, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality_green[pos], sum.g, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality_blue[pos], sum.b, memory_order::memory_order_relaxed);
        }
    }
}
