#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h> 
#include <ApplicationServices/ApplicationServices.h>

//	DirectDraw Pixel Format
#define DDPF_ALPHAPIXELS	0x00000001
#define DDPF_FOURCC	0x00000004
#define DDPF_RGB	0x00000040

#define D3DFMT_DXT1	0x31545844

Boolean GetMetadataForURL(void* thisInterface, 
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFURLRef url)
{

	CGDataProviderRef dataProvider = CGDataProviderCreateWithURL(url);
	if (!dataProvider) return FALSE;
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	CGDataProviderRelease(dataProvider);
	if (!data) return FALSE;
	
	const UInt8 *buf = CFDataGetBytePtr(data);
	int *height= ((int*) buf) + 3;
	int *width = ((int*) buf) + 4;
	int *pflags= ((int*) buf) + 20;

	CFStringRef format=NULL;
	if ((*pflags)&DDPF_FOURCC)
		format = CFStringCreateWithBytes(kCFAllocatorDefault, buf + 0x54, 4, kCFStringEncodingASCII, false);
	else if ((*pflags)&DDPF_RGB)
		format = (*pflags)&DDPF_ALPHAPIXELS ? CFSTR("RGBA") : CFSTR("RGB");
	if (format)
	{
		CFArrayRef codecs = CFArrayCreate(kCFAllocatorDefault, (const void **) &format, 1, &kCFTypeArrayCallBacks);
		CFDictionaryAddValue(attributes, kMDItemCodecs, codecs);
		CFRelease(format);
		CFRelease(codecs);
	}
	
	CFNumberRef cfheight = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, height);
	CFDictionaryAddValue(attributes, kMDItemPixelHeight, cfheight);
	CFRelease(cfheight);
	
	CFNumberRef cfwidth = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, width);
	CFDictionaryAddValue(attributes, kMDItemPixelWidth, cfwidth);
	CFRelease(cfwidth);

	CFRelease(data);
    return TRUE;
}
