#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#include "DDS/dds.h"

// Undocumented options
const CFStringRef kQLThumbnailOptionScaleFactor     = CFSTR("QLThumbnailOptionScaleFactor");


/* -----------------------------------------------------------------------------
    Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize)
{
    @autoreleasepool
    {
        DDS *dds = [DDS ddsWithURL: (__bridge NSURL*) url];
        if (!dds || QLThumbnailRequestIsCancelled(thumbnail))
        {
            return kQLReturnNoError;
        }

        NSNumber *scaleFactor = [((__bridge NSDictionary *)options) valueForKey:(__bridge NSString *)kQLThumbnailOptionScaleFactor];  // can be >1 on Retina displays
        CGSize desired = scaleFactor.boolValue ? CGSizeMake(maxSize.width * scaleFactor.floatValue, maxSize.height * scaleFactor.floatValue) :CGSizeMake(maxSize.width, maxSize.height);

        CGImageRef image = [dds CreateImageWithPreferredWidth:desired.width andPreferredHeight:desired.height];     // use a lower-level mipmap
        if (!image || QLThumbnailRequestIsCancelled(thumbnail))
        {
            if (image)
                CGImageRelease(image);
            return kQLReturnNoError;
        }

        /* Add a "DDS" stamp if the thumbnail is not too small */
        NSDictionary *properties = (maxSize.height > 16 ?
                                    [NSDictionary dictionaryWithObject:@"DDS" forKey:(NSString *) kQLThumbnailPropertyExtensionKey] :
                                    NULL);
        QLThumbnailRequestSetImage(thumbnail, image, (__bridge CFDictionaryRef) properties);

        CGImageRelease(image);

        return kQLReturnNoError;
    }
}

void CancelThumbnailGeneration(void* thisInterface, QLThumbnailRequestRef thumbnail)
{
    // implement only if supported
}
