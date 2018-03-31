#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#include "DDS/dds.h"

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file

   https://developer.apple.com/library/prerelease/mac/documentation/UserExperience/Conceptual/Quicklook_Programming_Guide/Articles/QLImplementationOverview.html

   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
    @autoreleasepool
    {
#ifdef DEBUG
        NSLog(@"Preview %@ with options %@", [(__bridge NSURL*)url path], options);
#endif

        DDS *dds = [DDS ddsWithURL: (__bridge NSURL*) url];
        if (!dds || QLPreviewRequestIsCancelled(preview))
        {
            return kQLReturnNoError;
        }

        NSNumber *previewMode = (NSNumber*)[(__bridge NSDictionary*)options objectForKey:@"QLPreviewMode"];
        CGImageRef image;
        if (previewMode && [previewMode intValue] <= 4)	// 1:"Get Info", 4:Spotlight
            image = [dds CreateImageWithPreferredWidth:1024 andPreferredHeight:1024];   // use a lower-level mipmap for speed
        else                                                // 5:User pressed space or some other context
            image = [dds CreateImage];                      // Give full resolution
        if (!image || QLPreviewRequestIsCancelled(preview))
        {
            if (image)
                CGImageRelease(image);
            return kQLReturnNoError;
        }

        // Replace title string
        NSString *title = [NSString stringWithFormat:@"%@ (%d×%d %@)", [(__bridge NSURL *)url lastPathComponent],
                           dds.mainSurfaceWidth, dds.mainSurfaceHeight, dds.codec];
        NSDictionary *properties = [NSDictionary dictionaryWithObject:title forKey:(NSString *) kQLPreviewPropertyDisplayNameKey];

        CGContextRef context = QLPreviewRequestCreateContext(preview, CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image)),
                                                             true, (__bridge CFDictionaryRef) properties);
        CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
        QLPreviewRequestFlushContext(preview, context);
        CGContextRelease(context);

        CGImageRelease(image);

        return kQLReturnNoError;
    }
}

void CancelPreviewGeneration(void* thisInterface, QLPreviewRequestRef preview)
{
    // implement only if supported
}
