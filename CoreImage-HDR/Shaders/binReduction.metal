//
//  binReduction.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 03.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


kernel void reduceBins(device half3 * buffer [[buffer(0)]],
                       constant uint & bufferSize [[buffer(1)]],
                       device half3 * cameraResponse [[buffer(2)]],
                       constant uint * cardinality_red [[buffer(3)]],
                       constant uint * cardinality_green [[buffer(4)]],
                       constant uint * cardinality_blue [[buffer(5)]],
                       uint threadID [[thread_index_in_threadgroup]],
                       uint warpSize [[threads_per_threadgroup]]) {
    
    half3 localSum = 0;
    
    // collect all results
    for(uint globalPosition = threadID; globalPosition < bufferSize; globalPosition += warpSize) {
        localSum += buffer[globalPosition];
    }
    
    cameraResponse[threadID] = localSum / half3(cardinality_red[threadID], cardinality_green[threadID], cardinality_blue[threadID]);
}

