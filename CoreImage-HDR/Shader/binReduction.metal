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

bool isSaturated(uint pixel) {
    return all(uint2(pixel) != uint2(0, 255));
}

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
    
    if(isSaturated(threadID)){
        cameraResponse[threadID].rgb = float3(localSum / half3(Cardinality.red[threadID], Cardinality.green[threadID], Cardinality.blue[threadID]));
    }
}

kernel void reduceBins_float(device float3 * buffer [[buffer(0)]],
                       constant uint & bufferSize [[buffer(1)]],
                       device float3 * cameraResponse [[buffer(2)]],
                       constant colourHistogram<BIN_COUNT> & Cardinality [[buffer(3)]],
                       uint threadID [[thread_index_in_threadgroup]],
                       uint warpSize [[threads_per_threadgroup]]) {
    
    float3 localSum = 0;
    
    // collect all results
    for(uint globalPosition = threadID; globalPosition < bufferSize; globalPosition += warpSize) {
        localSum += buffer[globalPosition];
    }
    
    if(isSaturated(threadID)){
        cameraResponse[threadID].rgb = localSum / float3(Cardinality.red[threadID], Cardinality.green[threadID], Cardinality.blue[threadID]);
    }
}
