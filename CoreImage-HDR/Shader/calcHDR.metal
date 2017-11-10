//
//  calcHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 23.11.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
//#include "calculateHDR.metal"
//#include "defines.metal"


/*----------------------------
 HDR estimation
 ---------------------------*/
/*
kernel void
calculate_xRGB(texture2d_array<float, access::read> input [[texture(0)]],
               texture2d<float, access::write> output [[texture(1)]],
               constant float * t [[buffer(0)]],
               constant float3 * I [[buffer(1)]],
               constant float3 * WeightFunction [[buffer(2)]],
               constant int2 * cameraShifts [[buffer(3)]],
               uint2 gid [[thread_position_in_grid]]){
    
    float4 result;
    uint arraySize = input.get_array_size();
    
    result = HDR_value(input, int2(gid), cameraShifts, arraySize, t, I, WeightFunction, INFINITY);
    output.write( (result), gid, 0);
}


*/
