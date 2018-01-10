//
//  TestSortNCount.metal
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 11.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

// importing from framework gives segmentation fault
//#include "CoreImage-HDR/Shaders/SortAndCount.h"

#include "SortAndCount.h"

// thus include a copy of the shader
kernel void testSortAlgorithm(device float * output [[buffer(0)]],
                              threadgroup SortAndCountElement<ushort, half> * Buffer [[threadgroup(0)]],
                              uint threadID [[thread_position_in_threadgroup]],
                              uint threadCount [[threads_per_threadgroup]]){
    
    Buffer[threadID].element = threadID % 4;    // arbitrary number for element
    Buffer[threadID].counter = 1.0;
    
    bitonicSortAndCount(threadID, threadCount / 2, Buffer);
    
    if(Buffer[threadID].counter > 0) {
        output[Buffer[threadID].element] = Buffer[threadID].counter;
    }
}

// thus include a copy of the shader
kernel void testSortAlgorithmNoCount(device float * unsorted [[buffer(0)]],
                              threadgroup float * sortBuffer [[threadgroup(0)]],
                              uint threadID [[thread_position_in_threadgroup]],
                              uint threadCount [[threads_per_threadgroup]]){
    
    sortBuffer[threadID] = unsorted[threadID];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    bitonicSort(threadID, threadCount / 2, sortBuffer);
    unsorted[threadID] = sortBuffer[threadID];
}
