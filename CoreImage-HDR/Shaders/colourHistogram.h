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
union colourHistogram {
    struct {
        metal::array<atomic_uint, N> red;
        metal::array<atomic_uint, N> green;
        metal::array<atomic_uint, N> blue;
    };
    metal::array< metal::array<atomic_uint, N>, 3 > c;
};

#endif /* colourHistogram_h */
