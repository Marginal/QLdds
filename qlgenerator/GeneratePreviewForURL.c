#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>

#include "SOIL/SOIL.h"
#include "SOIL/image_DXT.h"	// For DDS_header and flags

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file

   https://developer.apple.com/library/prerelease/mac/documentation/UserExperience/Conceptual/Quicklook_Programming_Guide/Articles/QLImplementationOverview.html

   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
	CGDataProviderRef dataProvider = CGDataProviderCreateWithURL(url);
	if (!dataProvider) return -1;
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	CGDataProviderRelease(dataProvider);
	if (!data) return kQLReturnNoError;
	
	if (QLPreviewRequestIsCancelled(preview))
	{
		CFRelease(data);
		return kQLReturnNoError;
	}

	int width, height, channels;
	DDS_header *header = (DDS_header *) CFDataGetBytePtr(data);
	unsigned char *rgbadata = SOIL_load_image_from_memory((unsigned char *) header, CFDataGetLength(data), &width, &height, &channels, SOIL_LOAD_RGBA);
	if (!rgbadata || QLPreviewRequestIsCancelled(preview))
	{
		SOIL_free_image_data(rgbadata);
		CFRelease(data);
		return kQLReturnNoError;
	}

	// Make title string while we still have access to the file data
 	CFStringRef format = NULL;
	if (header->sPixelFormat.dwFlags & DDPF_FOURCC)
		format = CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *) &header->sPixelFormat.dwFourCC, 4, kCFStringEncodingASCII, false);
	else if (header->sPixelFormat.dwFlags & DDPF_RGB)
		format = (header->sPixelFormat.dwFlags & DDPF_ALPHAPIXELS) ? CFSTR("RGBA") : CFSTR("RGB");
	else
		format = CFSTR("???");	// Shouldn't have got here

	CFStringRef name = CFURLCopyLastPathComponent(url);
	CFStringRef title = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@ (%dx%d %@)"), name, width, height, format);
	CFDictionaryRef properties = CFDictionaryCreate(NULL, (const void **) &kQLPreviewPropertyDisplayNameKey, (const void **) &title, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(title);
	CFRelease(name);
	CFRelease(format);
	
	CFRelease(data);

	// Wangle into a CGImage via a CGBitmapContext
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(rgbadata, width, height, 8, width * 4, rgb, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(rgb);
	if (!context || QLPreviewRequestIsCancelled(preview))
	{
		if (context)
			CGContextRelease(context);
		CFRelease(properties);
		SOIL_free_image_data(rgbadata);
		return kQLReturnNoError;
	}

	CGImageRef image = CGBitmapContextCreateImage(context);	// copy or copy-on-write
	CGContextRelease(context);
	SOIL_free_image_data(rgbadata);
	if (!image || QLPreviewRequestIsCancelled(preview))
	{
		if (image)
			CGImageRelease(image);
		return kQLReturnNoError;
	}

	context = QLPreviewRequestCreateContext(preview, CGSizeMake(width, height), true, properties);
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	QLPreviewRequestFlushContext(preview, context);
	CGContextRelease(context);

	CGImageRelease(image);
	CFRelease(properties);
	
	return kQLReturnNoError;
}

void CancelPreviewGeneration(void* thisInterface, QLPreviewRequestRef preview)
{
    // implement only if supported
}
