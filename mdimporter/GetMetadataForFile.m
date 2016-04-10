#import <Cocoa/Cocoa.h>

#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>
#import <ApplicationServices/ApplicationServices.h>

#import "DDS/dds.h"

// https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/MDImporters/Concepts/WritingAnImp.html
// http://msdn.microsoft.com/en-us/library/bb943991


Boolean GetMetadataForURL(void* thisInterface,
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFURLRef url)
{
    @autoreleasepool
    {

        DDS *dds = [DDS ddsWithURL: (__bridge NSURL*) url];
        if (!dds)
            return FALSE;	/* Not a DDS file! */

        NSMutableDictionary *attrs = (__bridge NSMutableDictionary *)attributes;   // Prefer to use Objective-C

        [attrs setValue:[NSArray arrayWithObject:dds.codec] forKey:(NSString *)kMDItemCodecs];

        int nlayers = 0;
        NSObject *layers[2];
        int ddsCaps2 = dds.ddsCaps2;
        if (ddsCaps2 & DDSCAPS2_VOLUME)
            layers[nlayers++] = @"volume";
        else if ((ddsCaps2 & DDSCAPS2_CUBEMAP_ALLFACES) == DDSCAPS2_CUBEMAP_ALLFACES)
            layers[nlayers++] = @"cubemap";
        else if (ddsCaps2 & DDSCAPS2_CUBEMAP)
            layers[nlayers++] = @"partial cubemap";
        if (dds.mipmapCount > 1)
            layers[nlayers++] = @"mipmaps";
        if (nlayers)
            [attrs setValue:[NSArray arrayWithObjects:layers count:nlayers] forKey:(NSString *)kMDItemLayerNames];

        [attrs setValue:[NSNumber numberWithInt:dds.mainSurfaceWidth]  forKey:(NSString *)kMDItemPixelWidth];
        [attrs setValue:[NSNumber numberWithInt:dds.mainSurfaceHeight] forKey:(NSString *)kMDItemPixelHeight];
        if (dds.bpp)
            [attrs setValue:[NSNumber numberWithInt:dds.bpp] forKey:(NSString *)kMDItemBitsPerSample];

    }
    return TRUE;
}
