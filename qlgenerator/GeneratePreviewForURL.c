#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#include "SOIL.h"

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options)
{
	CGDataProviderRef dataProvider = CGDataProviderCreateWithURL(url);
	if (!dataProvider) return -1;
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	CGDataProviderRelease(dataProvider);
	if (!data) return -1;
	
	int width, height, channels;
	unsigned char* rgbadata = SOIL_load_image_from_memory(CFDataGetBytePtr(data), CFDataGetLength(data), &width, &height, &channels, SOIL_LOAD_RGBA);
	CFStringRef format=CFStringCreateWithBytes(NULL, CFDataGetBytePtr(data) + 0x54, 4, kCFStringEncodingASCII, false);
    CFRelease(data);
	if (!rgbadata) return -1;
	
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(rgbadata, width, height, 8, width * 4, rgb, kCGImageAlphaPremultipliedLast);
	SOIL_free_image_data(rgbadata);
	CGColorSpaceRelease(rgb);
	if (!context) return -1;

	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	if (!image) return -1;

	/* Add basic metadata to title */
	CFStringRef name = CFURLCopyLastPathComponent(url);
	CFTypeRef keys[1] = {kQLPreviewPropertyDisplayNameKey};
	CFTypeRef values[1] = {CFStringCreateWithFormat(NULL, NULL, CFSTR("%@ (%dx%d %@)"), name, width, height, format)};
 	CFDictionaryRef properties = CFDictionaryCreate(NULL, (const void**)keys, (const void**)values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFRelease(name);

	context = QLPreviewRequestCreateContext(preview, CGSizeMake(width, height), true, properties);
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	QLPreviewRequestFlushContext(preview, context);
	
	CGContextRelease(context);
	CFRelease(format);
	CFRelease(properties);
	
	return noErr;
}

void CancelPreviewGeneration(void* thisInterface, QLPreviewRequestRef preview)
{
    // implement only if supported
}
