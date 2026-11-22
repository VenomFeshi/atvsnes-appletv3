#ifndef ATVSNES_DISPLAY_H
#define ATVSNES_DISPLAY_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

typedef enum {
    ATVSNESAspectOriginal = 0,
    ATVSNESAspectWide,
    ATVSNESAspectSquarePixels,
    ATVSNESAspectThreeTwo,
    ATVSNESAspectSixteenTen,
    ATVSNESAspectCount
} ATVSNESAspect;

static inline CGFloat ATVSNESPixelAspect(size_t width, size_t height)
{
    if (!width || !height)
        return 8.0 / 7.0;
    // SNES high-res and interlaced modes double one or both dimensions.
    return ((CGFloat)width / (width > 256 ? 2 : 1)) / ((CGFloat)height / (height > 256 ? 2 : 1));
}

static inline CGRect ATVSNESVideoFrame(CGRect bounds, ATVSNESAspect mode, CGFloat pixelAspect)
{
    CGFloat aspect;
    switch (mode) {
        case ATVSNESAspectWide: return bounds;
        case ATVSNESAspectSquarePixels: aspect = pixelAspect > 0 ? pixelAspect : 8.0 / 7.0; break;
        case ATVSNESAspectThreeTwo: aspect = 3.0 / 2.0; break;
        case ATVSNESAspectSixteenTen: aspect = 16.0 / 10.0; break;
        default: aspect = 4.0 / 3.0; break;
    }
    CGFloat width = CGRectGetHeight(bounds) * aspect;
    if (width > CGRectGetWidth(bounds))
        width = CGRectGetWidth(bounds);
    CGFloat height = width / aspect;
    return CGRectMake(CGRectGetMidX(bounds) - width / 2, CGRectGetMidY(bounds) - height / 2,
                      width, height);
}

#endif
