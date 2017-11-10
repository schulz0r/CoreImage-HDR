//
//  getWeightFunction.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 23.11.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

template<typename T> inline void interpolatedApproximation(float4x4 matrix, float t, int i, T function, constant uint * ControlPoints, uint id);
inline void derivativeOfInverseOfFunction(device float3 * invertedFunc, device float3 * function, uint id);

/*---------------------------------------------------
 Cubic Spline Interpolation and final weight function
 ---------------------------------------------------*/

kernel void weightfunction(device float3 *inverseResponse [[buffer(0)]],
                           device float3 *WeightFunction [[ buffer(1) ]],
                           constant uint *ControlPoints [[ buffer(2) ]],
                           constant float4x4 *cubicMatrix [[ buffer(3) ]],
                           uint tid [[thread_index_in_threadgroup]],
                           uint i [[threadgroup_position_in_grid]],
                           uint gid [[thread_position_in_grid]],
                           uint tgSize [[threads_per_threadgroup]],
                           uint lastThreadgroup [[threadgroups_per_grid]]){

    /* Smooth Inverse Response */
    float t = float(tid)/tgSize;
    interpolatedApproximation(cubicMatrix[0], t, i, inverseResponse, ControlPoints, gid);
    
    /* Approximate derivation of non-inverse Response - in logarithmic domain */
    derivativeOfInverseOfFunction(WeightFunction, inverseResponse, gid);    // derivative of inverse function
    
    /* The spline must be zero at both ends */
    WeightFunction[0] = 0;
    WeightFunction[255] = 0;
    
    if( (i == 0) || (i == lastThreadgroup-1) ){
        interpolatedApproximation(cubicMatrix[0], t, i, WeightFunction, ControlPoints, gid);
    }
    
    WeightFunction[0] = 0;
    WeightFunction[255] = 0;
}

inline void derivativeOfInverseOfFunction(device float3 * invertedFunc, device float3 * function, uint id){
    float3 f_0 = log(float3(function[id].r, function[id].g, function[id].b));
    float3 f_1 = log(float3(function[id + 1].r, function[id + 1].g, function[id + 1].b));
    invertedFunc[id] = 1 / (f_1 - f_0);
}

template<typename T>
inline void interpolatedApproximation(float4x4 matrix, float t, int i, T function, constant uint * ControlPoints, uint id){
    
    float4x3 P;   // relevant control points come here
    float4 leftOperator = (float4(pow(t,3.0),pow(t,2.0),t, 1)) * matrix;
    P = float4x3(function[ControlPoints[i]],
                 function[ControlPoints[i+1]],
                 function[ControlPoints[i+2]],
                 function[ControlPoints[i+3]]
                 );
    function[id] = leftOperator * transpose(P);
}
