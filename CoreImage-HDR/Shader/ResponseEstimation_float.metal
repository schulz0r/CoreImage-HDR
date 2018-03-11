//
//  ResponseEstimation_float.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 12.03.18.
//  Copyright © 2018 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "SortAndCount.h"
#include "calculateHDR.h"
#include "colourHistogram.h"

#define MAX_IMAGE_COUNT 5
#define BIN_COUNT 256

// Kernels for 32 bit input data. This file does not contain a special version of the response smoothing kernel because the response is an array of floats anyway. Following kernels are used only in the unit test module.

/*  write MeasureToBins
 This function implements the response estimation function in:
 
 Robertson, Mark A., Sean Borman, and Robert L. Stevenson. "Estimation-theoretic approach to dynamic range enhancement using multiple exposures." Journal of Electronic Imaging 12.2 (2003): 219-228.
 
 Here, only the summands needed for the response function estimation are calculated and written into a buffer.
 The summation and division by the cardinality are done in the kernel "binReduction", which you find below. Since this algorithm is hardly
 parallel, following approach has been used to avoid collisions:
 
 Shams, Ramtin, et al. "Parallel computation of mutual information on the GPU with application to real-time registration of 3D medical images." Computer methods and programs in biomedicine 99.2 (2010): 133-146.
 */

inline uchar3 toUChar(const thread half3 & pixel){
    return uchar3(pixel * 255);
}

kernel void writeMeasureToBins_float32(const metal::array<texture2d<float, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                                       device metal::array<float3, 256> * outputbuffer [[buffer(0)]],
                                       constant uint & NumberOfinputImages [[buffer(3)]],
                                       constant int2 * cameraShifts [[buffer(4)]],
                                       constant float * exposureTimes [[buffer(5)]],
                                       constant float3 * cameraResponse [[buffer(6)]],
                                       constant float3 * weights [[buffer(7)]],
                                       threadgroup SortAndCountElement<ushort, half> * ElementsToSort [[threadgroup(0)]],
                                       uint2 gid [[thread_position_in_grid]],
                                       uint tid [[thread_index_in_threadgroup]],
                                       uint2 threadgroupSize [[threads_per_threadgroup]],
                                       uint2 threadgroupID [[threadgroup_position_in_grid]],
                                       uint2 numberOfThreadgroups [[threadgroups_per_grid]]) {
    
    const uint numberOfThreadsPerThreadgroup = threadgroupSize.x * threadgroupSize.y;
    const uint threadgroupIndex = threadgroupID.x + numberOfThreadgroups.x * threadgroupID.y;
    device metal::array<float3, 256> & outputBufferSegment = outputbuffer[threadgroupIndex];
    
    metal::array<uchar3, MAX_IMAGE_COUNT> PixelIndices;
    half3 linearizedPixels[MAX_IMAGE_COUNT];
    
    metal::array_ref<half3> linearDataArray = metal::array_ref<half3>(linearizedPixels, NumberOfinputImages);
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const float3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        PixelIndices[i] = uchar3(pixel * 255);
        linearizedPixels[i] = half3(cameraResponse[PixelIndices[i].x].x, cameraResponse[PixelIndices[i].y].y, cameraResponse[PixelIndices[i].z].z);
    }
    
    // calculate HDR Value
    const half3 HDRPixel = HDRValue(linearDataArray, PixelIndices, exposureTimes, cameraResponse);
    
    for(uint imageIndex = 0; imageIndex < NumberOfinputImages; imageIndex++) {
        const half3 µ = HDRPixel * exposureTimes[imageIndex];   // X * t_i is the mean value according to the model
        for(uint colorChannelIndex = 0; colorChannelIndex < 3; colorChannelIndex++) {
            
            ElementsToSort[tid].element = PixelIndices[imageIndex][colorChannelIndex];
            ElementsToSort[tid].counter = µ[colorChannelIndex];
            
            threadgroup_barrier(mem_flags::mem_threadgroup);
            
            bitonicSortAndCount<ushort, half>(tid, numberOfThreadsPerThreadgroup / 2, ElementsToSort);
            
            if(ElementsToSort[tid].counter > 0) {
                outputBufferSegment[ElementsToSort[tid].element][colorChannelIndex] += ElementsToSort[tid].counter;
            }
        }
    }
}

/* After the summands have been calculated by the kernel named "writeMeasureToBins_float32", this kernel sums up the partial results into one final result. */

kernel void reduceBins_float(device float3 * buffer [[buffer(0)]],
                             constant uint & bufferSize [[buffer(1)]],
                             constant colourHistogram<BIN_COUNT> & Cardinality [[buffer(2)]],
                             device float3 * cameraResponse [[buffer(6)]],
                             uint threadID [[thread_index_in_threadgroup]],
                             uint warpSize [[threads_per_threadgroup]]) {
    
    float3 localSum = 0;
    
    // collect all results
    for(uint globalPosition = threadID; globalPosition < bufferSize; globalPosition += warpSize) {
        localSum += buffer[globalPosition];
    }
    
    cameraResponse[threadID].rgb = localSum / float3(Cardinality.red[threadID], Cardinality.green[threadID], Cardinality.blue[threadID]);
}

