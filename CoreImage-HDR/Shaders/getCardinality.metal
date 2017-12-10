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

struct colourHistogram {
    metal::array<atomic_uint, 257> red;
    metal::array<atomic_uint, 257> blue;
    metal::array<atomic_uint, 257> green;
};

kernel void getCardinality(const metal::array<texture2d<half>, MAX_IMAGE_COUNT> images [[texture(0)]],
                           constant uint2 & imageDimensions [[buffer(0)]],
                           constant uint & ReplicationFactor [[buffer(1)]],
                           device atomic_uint * Cardinality_red [[buffer(2)]],
                           device atomic_uint * Cardinality_green [[buffer(3)]],
                           device atomic_uint * Cardinality_blue [[buffer(4)]],
                           threadgroup colourHistogram * sharedHistograms [[threadgroup(0)]],
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
    for(uint sharedHistogramIndex = 0; sharedHistogramIndex < ReplicationFactor; sharedHistogramIndex++){
        for(uint i = threadID; i < (BIN_COUNT + 1); i += blockSize.x) {
            (threadgroup uint &)sharedHistograms[sharedHistogramIndex].red[i] = 0;
            (threadgroup uint &)sharedHistograms[sharedHistogramIndex].blue[i] = 0;
            (threadgroup uint &)sharedHistograms[sharedHistogramIndex].green[i] = 0;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    const thread uint & imageSlice = gid.z;
    // associate each thread to another histogram in shared memory to reduce collisions
    threadgroup colourHistogram & threadHistogram = sharedHistograms[threadID % ReplicationFactor];
    
    // spread locations of reads to gather diverse pixels in order to reduce collides
    const uint interleavedReadAccessOffset = (gridSize.x / warpsPerThreadgroup) * warpID + warpSize * threadgroupID.x + laneID;
    
    if(interleavedReadAccessOffset < imageDimensions.x){ // grid size may be unequal to image size...
        const uchar3 pixel = (uchar3) ( images[imageSlice].read(uint2(interleavedReadAccessOffset, gid.y)).rgb * (BIN_COUNT - 1) );
        // add to shared memory here
        atomic_fetch_add_explicit(&threadHistogram.red[pixel.r], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&threadHistogram.green[pixel.g], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&threadHistogram.blue[pixel.b], 1, memory_order::memory_order_relaxed);
        
        threadgroup_barrier(mem_flags::mem_threadgroup);
        // sum up results from buffer
        uint3 sum = 0;
        for(uint pos = threadID; pos < BIN_COUNT; pos += blockSize.x, sum = uint3(0)) {
            for(uint base = 0; base < ReplicationFactor; base++) {
                /*sum.r += (threadgroup uint &)buffer_red[pos + base];
                sum.g += (threadgroup uint &)buffer_green[pos + base];
                sum.b += (threadgroup uint &)buffer_blue[pos + base];
                */
                sum.r += atomic_load_explicit(&sharedHistograms[base].red[pos], memory_order::memory_order_relaxed);
                sum.g += atomic_load_explicit(&sharedHistograms[base].green[pos], memory_order::memory_order_relaxed);
                sum.b += atomic_load_explicit(&sharedHistograms[base].blue[pos], memory_order::memory_order_relaxed);
            }
            atomic_fetch_add_explicit(&Cardinality_red[pos], sum.r, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality_green[pos], sum.g, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality_blue[pos], sum.b, memory_order::memory_order_relaxed);
        }
    }
}
