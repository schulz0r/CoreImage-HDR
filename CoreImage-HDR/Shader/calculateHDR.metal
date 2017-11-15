//
//  calculateHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 02.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "denoiseHDR.metal"
#include "defines.metal"


inline float4 HDR_value(texture2d_array<float, access::read> input, int2 gridPos, constant int2 * shift, uint arraySize, constant float * t, constant float3 *  I, constant float3 *  WeightFunction, float maximum);
inline float3 calculate_HDR(thread float3 * linearDenoisedPixel, thread uchar4 * pixel, uint arrayLength, constant float3 * I, constant float * t, constant float3 * W, float maximum);
inline float3 calculate_HDR_threadgroup(thread float3 * linearDenoisedPixel, thread uchar4 * pixel, uint arrayLength, threadgroup float3 * I, constant float * t, threadgroup float3 * W, float maximum);

inline float4 HDR_value_noDenoise(texture2d_array<float, access::read> input, int2 gridPos, constant int2 * shift, uint arraySize, constant float * t, threadgroup float3 * I, threadgroup float3 * WeightFunction, float maximum){
    
    uchar4 m[MAX_ARRAY_SIZE];
    float3 linearPixel[MAX_ARRAY_SIZE];
    float4 result = float4(float3(0), 1.0);
    
    for(uint i = 0; i < arraySize; i++){ // iterate through all images at position gid
        m[i] = uchar4(input.read(uint2(gridPos + shift[i]), i, 0) * 255);
        linearPixel[i] = float3(I[m[i].r].r, I[m[i].g].g, I[m[i].b].b);
    }
    result.rgb = calculate_HDR_threadgroup(linearPixel, m, arraySize, I, t, WeightFunction, maximum);
    
    return result;
}

inline float3 calculate_HDR_threadgroup(thread float3 * linearDenoisedPixel, thread uchar4 * pixel, uint arrayLength, threadgroup float3 * I, constant float * t, threadgroup float3 * W, float maximum){
    
    float3 zaehler = 0.0;
    float3 nenner = 0.0;
    float3 result = 0.0;
    float3 weight;
    
    // read out array and calculate HDR value
    for(uint i = 0; i < arrayLength; i++){ // iterate through all images at position gid
        weight.rgb = float3( W[pixel[i].r].r, W[pixel[i].g].g, W[pixel[i].b].b );
        zaehler += weight.rgb * t[i] * linearDenoisedPixel[i].rgb;    // ACHTUNG: statt I[pixel[i]] steht hier linearDenoisedPixel[i], da beim denoisen schon linearisiert wurde
        nenner += weight.rgb * powr(t[i],2.f);
    }
    result = zaehler / nenner;

    return result;
}

// FROM HERE ON FUNCTIONS ARE ONLY USED IN HDR SHADER
inline float4 HDR_value(texture2d_array<float, access::read> input, int2 gridPos, constant int2 * shift, uint arraySize, constant float * t, constant float3 * I, constant float3 * WeightFunction, float maximum){
    
    uchar4 m[MAX_ARRAY_SIZE];
    float3 linearDenoisedPixel[MAX_ARRAY_SIZE];
    float4 result = float4(float3(0), 1.0);
    
    for(uint i = 0; i < arraySize; i++){ // iterate through all images at position gid
        m[i] = uchar4(input.read(uint2(gridPos + shift[i]), i, 0) * 255);
    }
    
    denoiseLDR(linearDenoisedPixel, m, t, I, arraySize);
    result.rgb = calculate_HDR(linearDenoisedPixel, m, arraySize, I, t, WeightFunction, maximum);
    
    return result;
}

inline float3 calculate_HDR(thread float3 * linearDenoisedPixel, thread uchar4 * pixel, uint arrayLength, constant float3 * I, constant float * t, constant float3 * W, float maximum){
    
    float3 zaehler = 0.0;
    float3 nenner = 0.0;
    float3 result = 0.0;
    float3 weight;
    
    if(all(pixel[0].rgb != 255)){
        // read out array and calculate HDR value
        for(uint i = 0; i < arrayLength; i++){ // iterate through all images at position gid
            weight.rgb = float3( W[pixel[i].r].r, W[pixel[i].g].g, W[pixel[i].b].b );
            zaehler += weight.rgb * t[i] * linearDenoisedPixel[i].rgb;    // ACHTUNG: statt I[pixel[i]] steht hier linearDenoisedPixel[i], da beim denoisen schon linearisiert wurde
            nenner += weight.rgb * powr(t[i],2.f);
        }
        result = zaehler / nenner;
    } else {
        result = maximum;
    }
    
    return result;
}
