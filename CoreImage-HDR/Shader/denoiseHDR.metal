//
//  denoiseHDR.metal
//  HDR-Module
//
//  Created by Philipp Waxweiler on 20.12.16.
//  Copyright © 2016 Philipp Waxweiler. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

inline float tauFunc(uint x);

inline void denoiseLDR(thread float3 * linearDenoisedPixel, thread uchar4 * pixelArray, constant float * t, constant float3 * I, uint arraySize){
    
    //float tau[MAX_ARRAY_SIZE];
    float3 zaehler, nenner;
    float3 weight;
    
    for(uint a = 0; a < arraySize - 1; a++){  // -1 for last pixel not being corrected
        zaehler = 0;
        nenner = 0;
        
        // from image j onwards, calculate the mean of the image and its successive ones
        for(uint j = a; j < arraySize; j++){
            if(j == a){
                weight.rgb = t[j];  // weight pixel itself with time
            } else {
                weight = float3( tauFunc(pixelArray[j].r), tauFunc(pixelArray[j].g), tauFunc(pixelArray[j].b) ) * t[j]; // weight other pixels aditionally with tau
            }
            zaehler.rgb += float3(I[pixelArray[j].r].r, I[pixelArray[j].g].g, I[pixelArray[j].b].b) * weight / t[j]; // weighted sum of linearized pixels
            nenner.rgb += weight.rgb; // weights for normalization
        }
        linearDenoisedPixel[a] = t[a] * (zaehler / nenner);
    }
    linearDenoisedPixel[arraySize-1] = float3(I[pixelArray[arraySize-1].r].r, I[pixelArray[arraySize-1].g].g, I[pixelArray[arraySize-1].b].b);
}

inline float tauFunc(uint x){
    float h;
    
    if(x < 200){
        return 1.0;
    } else if( (200 <= x) && (x < 250) ){
        h = 1.0 - (float(250 - x) / 50.0);
        return 1.0 - 3.0 * pow(h, 2.0) + 2.0 * pow(h, 3.0);
    } else {
        return 0.0;
    }
}
