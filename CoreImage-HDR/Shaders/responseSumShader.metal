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
#define BINS 256

/*  write MeasureToBins
 This function implements the response estimation function in:
 
 Robertson, Mark A., Sean Borman, and Robert L. Stevenson. "Estimation-theoretic approach to dynamic range enhancement using multiple exposures." Journal of Electronic Imaging 12.2 (2003): 219-228.
 
 Here, only the summands needed for the response function estimation are calculated and written into a buffer.
 The summation and division by the cardinality are done in "binReduction.metal". Since this algorithm is hardly
 parallel, following approach has been used to avoid collisions:
 
 Shams, Ramtin, et al. "Parallel computation of mutual information on the GPU with application to real-time registration of 3D medical images." Computer methods and programs in biomedicine 99.2 (2010): 133-146.
 */
kernel void writeMeasureToBins(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                               device metal::array<float3, 256> * outputbuffer [[buffer(0)]],
                               constant uint & NumberOfinputImages [[buffer(1)]],
                               constant int2 * cameraShifts [[buffer(2)]],
                               constant float * exposureTimes [[buffer(3)]],
                               constant float3 * cameraResponse [[buffer(4)]],
                               constant float3 * weights [[buffer(5)]],
                               threadgroup SortAndCountElement<ushort, half> * ElementsToSort [[threadgroup(0)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint tid [[thread_index_in_threadgroup]],
                               uint2 threadgroupSize [[threads_per_threadgroup]],
                               uint2 threadgroupID [[threadgroup_position_in_grid]],
                               uint2 numberOfThreadgroups [[threadgroups_per_grid]]) {
    
    const uint numberOfThreadsPerThreadgroup = threadgroupSize.x * threadgroupSize.y;
    const uint threadgroupIndex = threadgroupID.x + numberOfThreadgroups.x * threadgroupID.y;
    device metal::array<float3, 256> & outputBufferSegment = outputbuffer[threadgroupIndex];
    
    metal::array<ushort3, MAX_IMAGE_COUNT> PixelIndices;
    metal::array<half3, MAX_IMAGE_COUNT> linearizedPixels;
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        PixelIndices[i] = ushort3(pixel * 255);
        linearizedPixels[i] = half3(cameraResponse[PixelIndices[i].x].x, cameraResponse[PixelIndices[i].y].y, cameraResponse[PixelIndices[i].z].z);
    }
    
    // calculate HDR Value
    const half3 HDRPixel = HDRValue(linearizedPixels, exposureTimes, weights);
    
    for(uint imageIndex = 0; imageIndex < NumberOfinputImages; imageIndex++) {
        const half3 µ = HDRPixel * exposureTimes[imageIndex];   // X * t_i is the mean value according to the model
        for(uint colorChannelIndex = 0; colorChannelIndex < 3; colorChannelIndex++) {
            ElementsToSort[tid].element = PixelIndices[imageIndex][colorChannelIndex];
            ElementsToSort[tid].counter = µ[colorChannelIndex];
            
            bitonicSortAndCount<ushort, half>(tid, numberOfThreadsPerThreadgroup / 2, ElementsToSort);
            
            if(ElementsToSort[tid].counter > 0) {
                outputBufferSegment[ElementsToSort[tid].element][colorChannelIndex] += ElementsToSort[tid].counter;
            }
        }
    }
}
