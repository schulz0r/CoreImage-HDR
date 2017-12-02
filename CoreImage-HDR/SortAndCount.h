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
struct SortAndCountElement {
    T element;
    T2 counter;
};

template<typename T>
void swap(threadgroup T & L, threadgroup T & R) {
    T buff = L;
    L = R;
    R = buff;
}

template<typename T, typename T2>
void bitonicSortAndCount(const uint tid, const uint threads, threadgroup SortAndCountElement<T, T2> * data) {
    uint log2k = 1;
    for(uint k = 2; k <= threads << 1; k <<= 1, log2k++) {
        uint b_id = tid >> (log2k - 1);
        uint log2j = log2k - 1;
        
        for(uint j = k >> 1; j > 0; log2j--) {
            uint i1 = ((tid >> log2j) << (log2j + 1)) + (tid & (j - 1));
            uint i2 = i1 + j;
            
            switch(b_id & 1) {
            case 0:
                if(data[i1].element > data[i2].element) {
                    swap(data[i1], data[i2]);
                } else if (data[i1].element == data[i2].element) {
                    data[i2].counter = data[i1].counter + data[i2].counter;
                    data[i1].counter = 0;
                }
                break;
            default:
                if(data[i1].element < data[i2].element) {
                    swap(data[i1], data[i2]);
                } else if (data[i1].element == data[i2].element) {
                    data[i1].counter = data[i1].counter + data[i2].counter;
                    data[i2].counter = 0;
                }
                break;
            }
            
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
    }
}
#endif /* SortAndCount_h */
