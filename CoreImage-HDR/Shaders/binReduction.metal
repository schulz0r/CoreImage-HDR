//
//  binReduction.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "colourHistogram.h"

#define BIN_COUNT 256

kernel void reduceBins(device half3 * buffer [[buffer(0)]],
                       constant uint & bufferSize [[buffer(1)]],
                       device float3 * cameraResponse [[buffer(2)]],
                       constant colourHistogram<BIN_COUNT> & Cardinality [[buffer(3)]],
                       uint threadID [[thread_index_in_threadgroup]],
                       uint warpSize [[threads_per_threadgroup]]) {
    
    half3 localSum = 0;
    
    // collect all results
    for(uint globalPosition = threadID; globalPosition < bufferSize; globalPosition += warpSize) {
        localSum += buffer[globalPosition];
    }
    
    cameraResponse[threadID] = float3(localSum / half3((constant uint &)Cardinality.red[threadID], (constant uint &)Cardinality.green[threadID], (constant uint &)Cardinality.blue[threadID]));
}

