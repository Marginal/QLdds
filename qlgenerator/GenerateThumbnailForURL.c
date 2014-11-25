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
	if (!data) return kQLReturnNoError;

	int width, height, channels;
	unsigned char* rgbadata = SOIL_load_image_from_memory(CFDataGetBytePtr(data), CFDataGetLength(data), &width, &height, &channels, SOIL_LOAD_RGBA);
    CFRelease(data);
	if (!rgbadata || QLThumbnailRequestIsCancelled(thumbnail))
	{
		SOIL_free_image_data(rgbadata);
		return kQLReturnNoError;
	}

	// Wangle into a CGImage via a CGBitmapContext
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(rgbadata, width, height, 8, width * 4, rgb, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(rgb);
	if (!context || QLThumbnailRequestIsCancelled(thumbnail))
	{
		if (context)
			CGContextRelease(context);
		SOIL_free_image_data(rgbadata);
		return kQLReturnNoError;
	}

	CGImageRef image = CGBitmapContextCreateImage(context);	// copy or copy-on-write
	CGContextRelease(context);
	SOIL_free_image_data(rgbadata);
	if (!image || QLThumbnailRequestIsCancelled(thumbnail))
	{
		if (image)
			CGImageRelease(image);
		return kQLReturnNoError;
	}

	/* Add a "DDS" stamp if the thumbnail is not too small */
	if (maxSize.height > 16)
	{
		CFStringRef badge = CFSTR("DDS");
		CFDictionaryRef properties = CFDictionaryCreate(NULL, (const void **) &kQLThumbnailPropertyExtensionKey, (const void **) &badge, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		QLThumbnailRequestSetImage(thumbnail, image, properties);
		CFRelease(properties);
	}
	else
	{
		QLThumbnailRequestSetImage(thumbnail, image, NULL);
	}

	CGImageRelease(image);

	return kQLReturnNoError;
}

void CancelThumbnailGeneration(void* thisInterface, QLThumbnailRequestRef thumbnail)
{
    // implement only if supported
}
