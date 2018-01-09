//
//  medianFiler.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 09.01.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "SortAndCount.h"

kernel void medianFilter(device float3 * data [[buffer(0)]],
                         threadgroup float * window [[threadgroup(0)]],
                         uint windowIndex [[thread_index_in_threadgroup]],
                         uint2 pixelIndex [[threadgroup_position_in_grid]],
                         uint windowSize [[threads_per_threadgroup]]){    // is expected to be even!
    
    const int colorChannel = pixelIndex.y;
    const int offsetSize = (windowSize / 2) - 1;
    const int relIndexOffset = windowIndex - offsetSize;
    const int lastIndexInWindow = windowSize - 1;
    
    window[windowIndex] = (windowIndex == lastIndexInWindow) ? 0 : signbit(pixelIndex + relIndexOffset) ? 0 : data[pixelIndex + relIndexOffset][colorChannel];
    
    bitonicSort(windowIndex, windowSize / 2, window);
    
    if(windowIndex == 0){
        data[pixelIndex][colorChannel] = window[windowSize / 2];
    }
}
