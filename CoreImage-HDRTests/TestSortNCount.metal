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
                              device float * unsorted [[buffer(1)]],
                              threadgroup SortAndCountElement<ushort, half> * Buffer [[threadgroup(0)]],
                              threadgroup float * sortBuffer [[threadgroup(1)]],
                              uint threadID [[thread_position_in_threadgroup]],
                              uint threadCount [[threads_per_threadgroup]],
                              uint simdGroup [[simdgroup_index_in_threadgroup]]){
    
    Buffer[threadID].element = threadID % 4;    // arbitrary number for element
    Buffer[threadID].counter = 1.0;
    
    bitonicSortAndCount(threadID, threadCount / 2, Buffer);
    
    if(Buffer[threadID].counter > 0) {
        output[Buffer[threadID].element] = Buffer[threadID].counter;
    }
    
    if(threadID < 16) {
        sortBuffer[threadID] = unsorted[threadID];
        bitonicSort(threadID, 16 / 2, sortBuffer);
        unsorted[Buffer[threadID].element] = sortBuffer[threadID];
    }
}
