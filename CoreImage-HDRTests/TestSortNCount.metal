//
//  TestSortNCount.metal
//  CoreImage-HDRTests
//
//  Created by Philipp Waxweiler on 11.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#include "SortAndCount.h"

kernel void testSortAlgorithm(device float2 * output [[buffer(0)]],
                              threadgroup float * Buffer [[threadgroup(0)]],
                              uint threadID [[thread_position_in_threadgroup]],
                              uint threadCount [[threads_per_threadgroup]]){
    
}
