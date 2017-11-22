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
#include "calculateHDR.h"

#define MAX_IMAGE_COUNT 3

struct CameraCalibration {
    constant float3 * response;
    constant float3 * weights;
};
/*
kernel void makeHDR(const metal::array<texture2d<half, access::read>, MAX_IMAGE_COUNT> inputArray [[texture(0)]],
                    texture2d<half, access::write> HDRImage [[texture(MAX_IMAGE_COUNT)]],
                    constant uint & NumberOfinputImages [[buffer(0)]],
                    constant int2 * cameraShifts [[buffer(1)]],
                    constant float * exposureTimes [[buffer(2)]],
                    constant CameraCalibration & CalibrationData,
                    uint2 gid [[thread_position_in_grid]]){
    
    thread half3 linearData[MAX_IMAGE_COUNT];
    
    // linearize pixel
    for(int i = 0; i < NumberOfinputImages; i++) {
        const half3 pixel = inputArray[i].read(uint2(int2(gid) + cameraShifts[i])).rgb;
        const uint3 indices = uint3(pixel * 255);
        linearData[i] = half3(CalibrationData.response[indices.x].x, CalibrationData.response[indices.y].y, CalibrationData.response[indices.z].z);
    }
    
    // calculate moving average to reduce noise
    movingAverage(linearData, exposureTimes, NumberOfinputImages);
    
    // calculate HDR Value
    const half3 enhancedPixel = HDRValue(linearData, NumberOfinputImages, exposureTimes, CalibrationData.weights);
    HDRImage.write(half4(enhancedPixel, 1), gid);
}
*/
kernel void makeHDRImage(texture2d<half, access::read> inputArray [[texture(0)]],
                    texture2d<half, access::write> HDRImage [[texture(1)]],
                    uint2 gid [[thread_position_in_grid]]){
    
    HDRImage.write(inputArray.read(gid), gid);
}
