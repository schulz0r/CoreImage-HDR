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
                         uint2 windowSize [[threads_per_threadgroup]]){    // is expected to be even!
    
    const int colorChannel = pixelIndex.y;
    const int offsetSize = (windowSize.x / 2) - 1;
    const int relIndexOffset = windowIndex - offsetSize;
    const int globaldReadIndex = int(pixelIndex.x) + relIndexOffset;
    
    window[windowIndex] = (int(windowIndex) == 0) || (globaldReadIndex < 0) || (globaldReadIndex > 255) ? 0 : data[globaldReadIndex][colorChannel];
    
    bitonicSort(windowIndex, windowSize.x / 2, window);
    
    if(windowIndex == 0){
        data[pixelIndex.x][colorChannel] = window[(windowSize.x / 2) + 1];
    }
}
