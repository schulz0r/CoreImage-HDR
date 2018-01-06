//
//  colourHistogram.h
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 10.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#ifndef colourHistogram_h
#define colourHistogram_h

#include <metal_stdlib>

template<int N>
struct colourHistogram final {
    metal::array<atomic_uint, N> red;
    metal::array<atomic_uint, N> green;
    metal::array<atomic_uint, N> blue;
    
    void vote(uint3 pixel) {
        atomic_fetch_add_explicit(&red[pixel.r], 1, memory_order::memory_order_relaxed);
    }
};

#endif /* colourHistogram_h */
