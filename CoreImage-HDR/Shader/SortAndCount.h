//
//  SortAndCount.h
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 01.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#ifndef SortAndCount_h
#define SortAndCount_h

#include <metal_stdlib>
using namespace metal;

template<typename T, typename T2>
struct SortAndCountElement final {
    T element = 0;
    T2 counter = 0;
};

template<typename T>
void swap(threadgroup T & L, threadgroup T & R) {
    T buff = L;
    L = R;
    R = buff;
}

template<typename T, typename T2>
void bitonicSortAndCount(const uint tid, const uint half_of_dataLength, threadgroup SortAndCountElement<T,T2> * data) {
    
    uint log2k = 1;
    for(uint k = 2; k <= half_of_dataLength << 1; k <<= 1, log2k++) {
        uint b_id = tid >> (log2k - 1);
        uint log2j = log2k - 1;
        
        for(uint j = k >> 1; j > 0; j >>= 1, log2j--) {
            uint i1 = ((tid >> log2j) << (log2j + 1)) + (tid & (j - 1));
            uint i2 = i1 + j;
            
            if((b_id & 1) == 0) {  // is odd?
                if(data[i1].element > data[i2].element) {
                    swap(data[i1], data[i2]);
                } else if (data[i1].element == data[i2].element) {
                    data[i2].counter += data[i1].counter;
                    data[i1].counter = 0;
                }
            } else { // if odd
                if(data[i1].element < data[i2].element) {
                    swap(data[i1], data[i2]);
                } else if (data[i1].element == data[i2].element) {
                    data[i1].counter += data[i2].counter;
                    data[i2].counter = 0;
                }
            }
            
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }
}

template<typename T>
void bitonicSort(const uint tid, const uint half_of_dataLength, threadgroup T * data) {
    
    uint log2k = 1;
    for(uint k = 2; k <= half_of_dataLength << 1; k <<= 1, log2k++) {
        uint b_id = tid >> (log2k - 1);
        uint log2j = log2k - 1;
        
        for(uint j = k >> 1; j > 0; j >>= 1, log2j--) {
            uint i1 = ((tid >> log2j) << (log2j + 1)) + (tid & (j - 1));
            uint i2 = i1 + j;
            
            if((b_id & 1) == 0) {  // is odd?
                if(data[i1].element > data[i2].element) {
                    swap(data[i1], data[i2]);
                }
            } else { // if odd
                if(data[i1].element < data[i2].element) {
                    swap(data[i1], data[i2]);
                }
            }
            
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }
}
#endif /* SortAndCount_h */

