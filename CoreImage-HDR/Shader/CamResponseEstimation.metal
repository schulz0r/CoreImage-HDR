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
#include "colourHistogram.h"

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

inline uchar3 toUChar(const thread half3 & pixel){
    return uchar3(pixel * 255);
}

kernel void writeMeasureToBins(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                               device metal::array<half3, 256> * outputbuffer [[buffer(0)]],
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
    device metal::array<half3, 256> & outputBufferSegment = outputbuffer[threadgroupIndex];
    
    metal::array<uchar3, MAX_IMAGE_COUNT> PixelIndices;
    metal::array<half3, MAX_IMAGE_COUNT> linearizedPixels;
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        PixelIndices[i] = toUChar(pixel);
        linearizedPixels[i] = half3(cameraResponse[PixelIndices[i].x].x, cameraResponse[PixelIndices[i].y].y, cameraResponse[PixelIndices[i].z].z);
    }
    
    // calculate HDR Value
    const half3 HDRPixel = HDRValue(linearizedPixels, PixelIndices, exposureTimes, weights);
    
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

kernel void writeMeasureToBins_float32(const metal::array<texture2d<float, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
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
    
    metal::array<uchar3, MAX_IMAGE_COUNT> PixelIndices;
    metal::array<half3, MAX_IMAGE_COUNT> linearizedPixels;
    
    // linearize pixel
    for(uint i = 0; i < NumberOfinputImages; i++) {
        const float3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        PixelIndices[i] = uchar3(pixel * 255);
        linearizedPixels[i] = half3(cameraResponse[PixelIndices[i].x].x, cameraResponse[PixelIndices[i].y].y, cameraResponse[PixelIndices[i].z].z);
    }
    
    // calculate HDR Value
    const half3 HDRPixel = HDRValue(linearizedPixels, PixelIndices, exposureTimes, weights);
    
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

template<typename T> inline void interpolatedApproximation(constant float4x4 & matrix, float t, int i, T function, constant uint * ControlPoints, uint id);
inline void derivativeOfInverseOfFunction(device float3 * invertedFunc, device float3 * function, uint id);

/*---------------------------------------------------
 Cubic Spline Interpolation and final weight function
 ---------------------------------------------------*/

kernel void smoothResponse(device float3 * inverseResponse [[buffer(0)]],
                           device float3 * WeightFunction [[ buffer(1) ]],
                           constant uint * ControlPoints [[ buffer(2) ]],
                           constant float4x4 & cubicMatrix [[ buffer(3) ]],
                           uint tid [[thread_index_in_threadgroup]],
                           uint i [[threadgroup_position_in_grid]],
                           uint gid [[thread_position_in_grid]],
                           uint tgSize [[threads_per_threadgroup]],
                           uint lastThreadgroup [[threadgroups_per_grid]]){
    
    /* Smooth Inverse Response */
    float t = float(tid) / tgSize;
    interpolatedApproximation(cubicMatrix, t, i, inverseResponse, ControlPoints, gid);
    
    /* Approximate derivation of non-inverse Response - in logarithmic domain */
    derivativeOfInverseOfFunction(WeightFunction, inverseResponse, gid);    // derivative of inverse function
    
    /* The spline must be zero at both ends */
    WeightFunction[0] = 0;
    WeightFunction[255] = 0;
    
    if( (i == 0) || (i == lastThreadgroup-1) ){
        interpolatedApproximation(cubicMatrix, t, i, WeightFunction, ControlPoints, gid);
    }
    
    WeightFunction[0] = 0;
    WeightFunction[255] = 0;
}

inline void derivativeOfInverseOfFunction(device float3 * invertedFunc, device float3 * function, uint id){
    // f'(x) = 1 / f'^-1(x)
    // the derivative of the root of a function is inverse proportional to the derivative of the function
    // weights = (I(x)')^-1
    float3 f_0 = log(float3(function[id].r, function[id].g, function[id].b));
    float3 f_1 = log(float3(function[id + 1].r, function[id + 1].g, function[id + 1].b));
    invertedFunc[id] = 1 / (f_1 - f_0);
}

template<typename T>
inline void interpolatedApproximation(constant float4x4 & matrix, float t, int i, T function, constant uint * ControlPoints, uint id){
    
    float4x3 P;   // relevant control points come here
    float4 leftOperator = (float4(pow(t,3.0),pow(t,2.0),t, 1)) * matrix;
    P = float4x3(function[ControlPoints[i]],
                 function[ControlPoints[i+1]],
                 function[ControlPoints[i+2]],
                 function[ControlPoints[i+3]]
                 );
    function[id] = leftOperator * transpose(P);
}
