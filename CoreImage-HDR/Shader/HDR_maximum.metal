//
//  normImg.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 18.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "defines.metal"

inline float chooseMaximum(float3 pixel, float localMax){
    return fmax(localMax, fmax(pixel.r, fmax(pixel.g, pixel.b)) );
}

inline float reduce_max_2D(threadgroup float * data, uint threadgroupsizeX, thread uint2 id);

kernel void HDR_maximum(texture2d<float, access::read> input [[texture(0)]],
                          device float * maximalBrightness [[buffer(0)]],
                          uint2 id [[thread_position_in_grid]]) {
    
    float4 pixel = 0;
    uint width = input.get_width();
    uint height = input.get_width();
    threadgroup float maxima[TGsize][TGsize];
    
    // Maximum
    maxima[id.x][id.y] = 0.0;
    
    for(uint x = id.x; x < width; x += TGsize){
        for(uint y = id.y; y < height; y += TGsize){
            
            pixel = input.read( uint2(x,y), 0 );
            
            if(all(pixel.rgb != INFINITY)){
                maxima[id.x][id.y] = chooseMaximum(pixel.rgb, maxima[id.x][id.y]);
            }
        }
    }
    
    maximalBrightness[0] = reduce_max_2D(*maxima, TGsize, id);
}

// helper functions

inline float reduce_max_2D(threadgroup float * data, uint threadgroupsizeX, thread uint2 id){
    for(uint s = threadgroupsizeX/2; s > 0; s >>=1){
        if( (id.x<s) && (id.y<s) ){
            data[id.x + (id.y * threadgroupsizeX)] = fmax(data[id.x + (id.y * threadgroupsizeX)],
                                                          fmax(data[id.x+s + (id.y * threadgroupsizeX)],
                                                               fmax(data[id.x + ((id.y + s) * threadgroupsizeX)] ,
                                                                    data[ id.x + s + ((id.y + s) * threadgroupsizeX)]
                                                                    )
                                                               )
                                                          );
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    return data[0];
}
