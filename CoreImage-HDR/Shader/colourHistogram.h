//
//  colourHistogram.h
//  CoreImage-HDR
//
//  Created by Philipp Waxweiler on 10.12.17.
//  Copyright © 2017 Philipp Waxweiler. All rights reserved.
//

#ifndef colourHistogram_h
#define colourHistogram_h

template<int N>
struct colourHistogram final {
    metal::array<atomic_uint, N> red;
    metal::array<atomic_uint, N> green;
    metal::array<atomic_uint, N> blue;
};

#endif /* colourHistogram_h */
