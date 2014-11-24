#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#include "SOIL/SOIL.h"

/* -----------------------------------------------------------------------------
    Generate a thumbnail for file

   This function's job is to create thumbnail for designated file as fast as possible
   ----------------------------------------------------------------------------- */

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize)
{
	CGDataProviderRef dataProvider = CGDataProviderCreateWithURL(url);
	if (!dataProvider) return -1;
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	CGDataProviderRelease(dataProvider);
	if (!data) return -1;

	int width, height, channels;
	unsigned char* rgbadata = SOIL_load_image_from_memory(CFDataGetBytePtr(data), CFDataGetLength(data), &width, &height, &channels, SOIL_LOAD_RGBA);
    CFRelease(data);
	if (!rgbadata) return -1;

	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(rgbadata, width, height, 8, width * 4, rgb, kCGImageAlphaPremultipliedLast);
    	CGColorSpaceRelease(rgb);
	if (!context) return -1;

	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	if (!image) return -1;

	/* Add a "DDS" stamp if the thumbnail is not too small */
	if (maxSize.height > 16)
	{
		CFTypeRef keys[1] = {kQLThumbnailPropertyExtensionKey};
		CFTypeRef values[1] = {CFSTR("DDS")};
		CFDictionaryRef properties = CFDictionaryCreate(NULL, (const void**)keys, (const void**)values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		QLThumbnailRequestSetImage(thumbnail, image, properties);
		CFRelease(properties);
	}
	else
	{
		QLThumbnailRequestSetImage(thumbnail, image, NULL);
	}

	return noErr;
}

void CancelThumbnailGeneration(void* thisInterface, QLThumbnailRequestRef thumbnail)
{
    // implement only if supported
}
