//
//  responseSumShader.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 01.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "SortAndCount.h"
#include "calculateHDR.h"

#define MAX_IMAGE_COUNT 5

kernel void writeMeasureToBins(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                        texture2d<half, access::read> valuesFromLastIter [[texture(MAX_IMAGE_COUNT)]],
                        texture2d<half, access::write> outputbuffer [[texture(MAX_IMAGE_COUNT + 1)]],
                        constant uint & NumberOfinputImages [[buffer(0)]],
                        constant int2 * cameraShifts [[buffer(1)]],
                        constant float * exposureTimes [[buffer(2)]],
                        constant float3 * response [[buffer(3)]],
                        constant float3 * weights [[buffer(4)]],
                        threadgroup metal::array<SortAndCountElement<half, uchar>, 256> & DataBuffer [[threadgroup(0)]],
                        uint2 gid [[thread_position_in_grid]],
                        uint tid [[thread_index_in_threadgroup]],
                        uint2 threadgroupSize [[threads_per_threadgroup]],
                        uint2 threadgroupID [[threadgroup_position_in_grid]]) {
    
    const uint numberOfThreadsPerThreadgroup = threadgroupSize.x * threadgroupSize.y;
    const uint threadgroupIndex = threadgroupID.x * threadgroupID.y;
    
    metal::array<uchar3, MAX_IMAGE_COUNT> PixelIndices;
    metal::array<half3, MAX_IMAGE_COUNT> linearizedPixels;
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        PixelIndices[i] = uchar3(pixel * 255);
        linearizedPixels[i] = half3(response[PixelIndices[i].x].x, response[PixelIndices[i].y].y, response[PixelIndices[i].z].z);
    }
    
    // calculate HDR Value
    const half3 HDRPixel = HDRValue(linearizedPixels, exposureTimes, weights);
    
    for(uint imageIndex = 0; imageIndex < NumberOfinputImages; imageIndex++) {
        const half3 µ = HDRPixel * exposureTimes[imageIndex];   // X * t_i is the mean value according to the model
        for(uint colorChannelIndex = 0; colorChannelIndex < 3; colorChannelIndex++) {
            DataBuffer[tid].element = PixelIndices[imageIndex][colorChannelIndex];
            DataBuffer[tid].counter = µ[colorChannelIndex];
            bitonicSortAndCount(tid, numberOfThreadsPerThreadgroup, DataBuffer);
        }
        const half3 value = valuesFromLastIter.read(uint2(tid,threadgroupIndex)).rgb;
        outputbuffer.write(half4(DataBuffer[tid].counter + value, 1), uint2(tid,threadgroupIndex));
    }
}
