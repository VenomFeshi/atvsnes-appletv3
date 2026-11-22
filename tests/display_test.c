#include "display.h"
#include <assert.h>
#include <stdio.h>

int main(void)
{
    CGRect fullHD = CGRectMake(0, 0, 1920, 1080);
    CGRect hd = CGRectMake(0, 0, 1280, 720);
    assert(CGRectEqualToRect(ATVSNESVideoFrame(fullHD, ATVSNESAspectWide, 0), fullHD));
    assert(CGRectEqualToRect(ATVSNESVideoFrame(hd, ATVSNESAspectWide, 0), hd));
    assert(CGRectEqualToRect(ATVSNESVideoFrame(hd, ATVSNESAspectOriginal, 0), CGRectMake(160, 0, 960, 720)));
    assert(CGRectEqualToRect(ATVSNESVideoFrame(hd, ATVSNESAspectThreeTwo, 0), CGRectMake(100, 0, 1080, 720)));
    assert(CGRectEqualToRect(ATVSNESVideoFrame(hd, ATVSNESAspectSixteenTen, 0), CGRectMake(64, 0, 1152, 720)));
    CGFloat pixel = ATVSNESPixelAspect(256, 224);
    assert(pixel == ATVSNESPixelAspect(512, 224) && pixel == ATVSNESPixelAspect(512, 448));
    CGRect squarePixels = ATVSNESVideoFrame(CGRectMake(0, 0, 896, 504), ATVSNESAspectSquarePixels, pixel);
    assert(CGRectEqualToRect(squarePixels, CGRectMake(160, 0, 576, 504)));
    assert(CGRectEqualToRect(ATVSNESVideoFrame(CGRectMake(10, 30, 320, 480), ATVSNESAspectOriginal, 0),
                            CGRectMake(10, 150, 320, 240)));
    puts("Display: 4:3, 16:9 stretch, square pixels, 3:2, and 16:10 passed.");
    return 0;
}
