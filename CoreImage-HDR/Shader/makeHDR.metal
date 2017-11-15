//
//  makeHDR.metal
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 15.11.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#include "movingAverage.h"

#define MAX_IMAGE_COUNT 5

struct CameraCalibration {
    constant float3 * response;
    constant float3 * weights;
};

kernel void makeHDR(const metal::array<texture2d<half>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                    texture2d<half, access::write> HDRImage [[texture(MAX_IMAGE_COUNT)]],
                    constant int & NumberOfinputImages [[buffer(0)]],
                    constant int2 * cameraShifts [[buffer(1)]],
                    constant float * exposureTimes [[buffer(2)]],
                    constant CameraCalibration & CalibrationData,
                    uint2 gid [[thread_position_in_grid]]){
    
    metal::array<half3, MAX_IMAGE_COUNT> linearData;
    
    // linearize pixel
    for(int i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        linearData[i] = half3(CalibrationData.response[int(pixel.x * 255)].x, CalibrationData.response[int(pixel.y * 255)].y, CalibrationData.response[int(pixel.z * 255)].z);
    }
    
    // calculate moving average to reduce noise
    movingAverage(linearData, thread uchar4 * pixelArray, exposureTimes, CameraData.response, NumberOfinputImages);
    
    // calculate HDR Value
    /*
    float4 result = HDR_value(input, int2(gid), cameraShifts, arraySize, t, I, WeightFunction, INFINITY);
    output.write( (result), gid, 0);*/
}
