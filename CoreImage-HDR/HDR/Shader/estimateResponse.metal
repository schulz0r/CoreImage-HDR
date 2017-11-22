//
//  hdr-kernels.metal
//  HiCam
//
//  Created by Philipp Waxweiler on 30.01.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//
 
#include <metal_stdlib>
using namespace metal;
#include "calculateHDR.metal"
#include "defines.metal"

constant float threshold = 0.01;

inline float fensterfunktion(uint y, float W){
    return exp(-W * pow( (float(y)-127.5)/127.5, 2) );
}

void atomic_add_uint3_array(threadgroup uint3 * writeHere, thread uint3 * fromLocalMemory, uint tid, uint arrayLength);
void Cardinality(texture2d_array<float, access::read> input, threadgroup uint3 * cardinality, uint2 imageDimensions, uint arrayLength, uint tid, uint2 gid);

/*----------------------------
 RESPONSE
 ---------------------------*/

kernel void
estimate_I(texture2d_array<float, access::read> input [[texture(0)]],
           constant float *t [[buffer(0)]],
           constant float *W [[buffer(1)]],
           device float3 * CamResponseI [[buffer(2)]],
           constant uint & imageWid [[buffer(3)]],
           constant int2 * shift [[buffer(4)]],
           uint2 gid [[thread_position_in_grid]],
           uint tid [[thread_index_in_threadgroup]] ){
    
    
    uint imageWidth = imageWid;
    uint imageHeight = input.get_height();
    uint arraySize = input.get_array_size();
    uchar4 m;
    threadgroup uint counter = 0;
    
    threadgroup float3 I[256];
    threadgroup float3 I_old[256];
    threadgroup float3 WeightFunction[256];
    threadgroup bool notConverged;
    
    float3 local_I[256];
    float3 I_128;
    
    float4 HDR_pixel;
    notConverged = true;

    /* --- Calculate Cardinality --- */
    threadgroup uint3 cardinality[256];
    Cardinality(input, cardinality, uint2(imageWidth, imageHeight), arraySize, tid, gid);
    
    // --- init weight and response function ---
    I_old[tid].rgb = 2 * float(tid) / 255.0;
    WeightFunction[tid] = fensterfunktion(tid, W[0]);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // --- Iterate until convergence --- //
    
    while(notConverged && (counter < 25)){
        
        notConverged = false;
        
        // init arrays
        I[tid].rgb = 0;
        for(uint i = 0; i < 256; i++){
            local_I[i].rgb = 0.0;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        
        // a threadgroup iterates over the whole image, locally calculating a hdr value and the camera response
        for(uint x = gid.x; x < imageWidth; x += TGsize){
            for(uint y = gid.y; y < imageHeight; y += TGsize){
            
                HDR_pixel = HDR_value_noDenoise(input, int2(x,y), shift, arraySize, t, I_old, WeightFunction, 0);
                
                for(uint i = 0; i < arraySize; i++){
                    m = uchar4( input.read(uint2(x,y), i, 0) * 255);
                    local_I[m.r].r += HDR_pixel.r * t[i]; // equation for calculating I, without cardinality
                    local_I[m.g].g += HDR_pixel.g * t[i];
                    local_I[m.b].b += HDR_pixel.b * t[i];
                }
                
            }
        }
        
        // write all local values to TG memory
        for(uint idx = tid; idx < tid + 256; idx++){
            I[idx % 256] += local_I[idx % 256];
            threadgroup_barrier(mem_flags::mem_none);
        }
        
        // divide by card(m), which is a histogram value
        I[tid].rgb = I[tid].rgb / float3( cardinality[tid].rgb );
        threadgroup_barrier(mem_flags::mem_none);
        
        // normalize by I_128, the 128th entry in I
        I_128 = I[128];
        threadgroup_barrier(mem_flags::mem_none);
        I[tid] /= I_128;
        
        // check convergence
        if ( (tid > 30)  && ((tid < 230) && ( any(abs(I[tid] - I_old[tid]) > threshold) ) ) || any(I[128] == 0) ){
            notConverged = true;
        }
        I_old[tid] = I[tid];
        if(tid == 0){
            counter++;
        }
        threadgroup_barrier(mem_flags::mem_none);
    }
    
    // finally write result
    CamResponseI[tid] = I_old[tid];
    if( any(CamResponseI[255] == 0) ){
        CamResponseI[255] = CamResponseI[254];
    }
}

void Cardinality(texture2d_array<float, access::read> input, threadgroup uint3 * cardinality, uint2 imageDimensions, uint arrayLength, uint tid, uint2 gid){
    
    uint3 localHist[256] = {0};
    uchar4 m;
    cardinality[tid] = 0;
    threadgroup_barrier(mem_flags::mem_none);
    
    for(uint i = 0; i < 256; i++){
        localHist[i].rgb = 0;   // init buffer with 0
    }
    
    
    for(uint x = gid.x; x < imageDimensions.x; x += TGsize){
        for(uint y = gid.y; y < imageDimensions.y; y += TGsize){
            
            for(uint slice = 0; slice < arrayLength; slice++){
                m = uchar4( input.read(uint2(x,y), slice, 0) * 255 );
                localHist[m.r].r++;
                localHist[m.g].g++;
                localHist[m.b].b++;
            }
        }
    }
    atomic_add_uint3_array(cardinality, localHist, tid, 256);
}

void atomic_add_uint3_array(threadgroup uint3 * writeHere, thread uint3 * fromLocalMemory, uint tid, uint arrayLength){
    for(uint idx = tid; idx < tid + arrayLength; idx++){
        writeHere[idx % arrayLength] += fromLocalMemory[idx % arrayLength];
        threadgroup_barrier(mem_flags::mem_none);
    }
}
