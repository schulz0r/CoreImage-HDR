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
kernel void testSortAlgorithm(device float2 * output [[buffer(0)]],
                              threadgroup SortAndCountElement<ushort, half> * Buffer [[threadgroup(0)]],
                              uint threadID [[thread_position_in_threadgroup]],
                              uint threadCount [[threads_per_threadgroup]],
                              uint simdGroup [[simdgroup_index_in_threadgroup]]){
    
    Buffer[threadID].element = threadID % 4;    // arbitrary number for element
    Buffer[threadID].counter = 1.0;
    
    bitonicSortAndCount(threadID, threadCount / 2, Buffer);
    
    output[threadID].x = Buffer[threadID].element;
    output[threadID].y = Buffer[threadID].counter;
}
