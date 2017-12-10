//
//  getCardinality.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "colourHistogram.h"

#define MAX_IMAGE_COUNT 5
#define BIN_COUNT 256

/*  getCardinality
    Generates a RGB Histogram, which is not normalized. To reduce the amount of collisions,
    multiple histograms are allocated in shared memory. Each thread is assigned to one of
    these histograms.
    Please refer to following paper for more information:
 
    Gómez-Luna, Juan, et al. "An optimized approach to histogram computation on GPU." Machine Vision and Applications 24.5 (2013): 899-908.
 
 */
kernel void getCardinality(const metal::array<texture2d<half>, MAX_IMAGE_COUNT> images [[texture(0)]],
                           constant uint2 & imageDimensions [[buffer(0)]],
                           constant uint & ReplicationFactor [[buffer(1)]],
                           device colourHistogram<BIN_COUNT> & Cardinality [[buffer(2)]],
                           threadgroup colourHistogram<BIN_COUNT+1> * sharedHistograms [[threadgroup(0)]],
                           uint3 gid [[thread_position_in_grid]],
                           uint threadID [[thread_index_in_threadgroup]],
                           uint warpsPerThreadgroup [[simdgroups_per_threadgroup]],
                           uint warpID [[simdgroup_index_in_threadgroup]],
                           uint warpSize [[threads_per_simdgroup]],
                           uint3 blockSize [[threads_per_threadgroup]],
                           uint3 threadgroupID [[threadgroup_position_in_grid]],
                           uint3 gridSize [[threads_per_grid]],
                           uint laneID [[thread_index_in_simdgroup]]) {
    
    const thread uint & imageSlice = gid.z;
    
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
    
    // (1) Assign each thread to one of the histograms in shared memory
    threadgroup colourHistogram<BIN_COUNT+1> & threadHistogram = sharedHistograms[threadID % ReplicationFactor];
    
    // spread locations of reads over the image to gather diverse pixels to further reduce collisions
    const uint interleavedReadAccessOffset = (gridSize.x / warpsPerThreadgroup) * warpID + warpSize * threadgroupID.x + laneID;
    
    if(interleavedReadAccessOffset < imageDimensions.x){ // grid size may be unequal to image size...
        const uchar3 pixel = (uchar3) ( images[imageSlice].read(uint2(interleavedReadAccessOffset, gid.y)).rgb * (BIN_COUNT - 1) );
        // (2) add pixel to shared memory
        atomic_fetch_add_explicit(&threadHistogram.red[pixel.r], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&threadHistogram.green[pixel.g], 1, memory_order::memory_order_relaxed);
        atomic_fetch_add_explicit(&threadHistogram.blue[pixel.b], 1, memory_order::memory_order_relaxed);
        
        threadgroup_barrier(mem_flags::mem_threadgroup);
        
        // (3) accumulate results over all replicated histograms
        uint3 sum = 0;
        for(uint pos = threadID; pos < BIN_COUNT; pos += blockSize.x, sum = uint3(0)) {
            for(uint replHistIndex = 0; replHistIndex < ReplicationFactor; replHistIndex++) {
                // atomicity is not needed here because there won't be any further writes.
                sum.r += (threadgroup uint &)sharedHistograms[replHistIndex].red[pos];
                sum.g += (threadgroup uint &)sharedHistograms[replHistIndex].green[pos];
                sum.b += (threadgroup uint &)sharedHistograms[replHistIndex].blue[pos];
            }
            
            // (4) write final result to global memory
            atomic_fetch_add_explicit(&Cardinality.red[pos], sum.r, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality.green[pos], sum.g, memory_order::memory_order_relaxed);
            atomic_fetch_add_explicit(&Cardinality.blue[pos], sum.b, memory_order::memory_order_relaxed);
        }
    }
}
