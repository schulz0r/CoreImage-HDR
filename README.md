# CoreImage-HDR
An implementation of the Robertson-HDR algorithm as a CoreImage filter. Use it to make HDR Images (without tone mapping) of a bracket of processed images. This algorithm is not meant to be used with RAW images.

## Installation
First, you need to download and compile MetalkitPlus, which you can find here: 
https://github.com/LRH539/MetalKitPlus
After Compilation, add the MetalKitPlus framework to the project or install it to your system.

## Getting started
### Getting the response curve of a camera
This algorithm assumes that your photos are processed (not RAW). That means that the pixel values are not linear. You need to estimate a camera response curve before you can render a HDR image.

First, instanciate a struct to hold these parameters:
```
var camParams = CameraParameter(withTrainingWeight: 7, BSplineKnotCount: 16)
```
You should set the training weight in accordance to the expected noise level. The number 7 is a good guess for images taken with a smartphone. If more noise is to be expected, use higher values, else use lower ones. I recommend to use images taken at daylight, which are not distorted by noise or blur. The noise affects the resulting camera response function, making B-Spline smoothing necessary. A higher knot count will result in a smoother response curve. Just use 16 knots.

To obtain these parameters, you need to create an MTKPHDR object:
```
let HDRAlgorithm = MTKPHDR()
HDRAlgorithm.estimateResponse(ImageBracket: Testimages, cameraShifts: cameraShifts, cameraParameters: &camParams, iterations: 10)
```
The image bracket should contain several images taken with different exposure times. For images taken with hand-held cameras, there is an option to pass the camera shifts as an array of int2-values (import metalkit for int2), ordered like (x,y). You should pass the camera parameters discussed above along with a number of iterations. If you use 5 images for the estimation, 5 iterations should be enough.

After the estimation, you can store the parameters on disk and reuse them for this camera model in the future.

### Getting a HDR image
There are two options to get a HDR image:
```
HDR = try HDRProcessor.apply(withExtent: ImageBracket.first!.extent,
                                         inputs: ImageBracket,
                                         arguments: ["ExposureTimes" : [0.1,0.5,0.8],
                                                     "CameraParameter" : camParams])
```
or, reusing the HDRAlgorithm object:
```
let HDR = HDRAlgorithm.makeHDR(ImageBracket: ImageBracket, cameraParameters: camParams)
```

The difference between these two functions is that the latter one clips numerical outliers which is recommendable. Unlike MetalKitPlus, CoreImage does not allow hybrid computing (CPU and GPU solving the task together). Finding the outliers cannot be efficiently implemented on the GPU, so this part is missing in core image.

## Known issues
* The MTKP implementation of the HDR algorithm and the parameter estimation use a single thread design, causing the program to halt while computations are performed.
