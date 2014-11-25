#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h> 
#include <ApplicationServices/ApplicationServices.h>
#include <machine/endian.h>

#include "SOIL/image_DXT.h"	// For DDS_header and flags


// https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/MDImporters/Concepts/WritingAnImp.html
// http://msdn.microsoft.com/en-us/library/bb943991

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

	DDS_header *header = (DDS_header *) CFDataGetBytePtr(data);
	if (CFDataGetLength(data) < sizeof(DDS_header) ||
		memcmp(&header->dwMagic, "DDS ", 4))
	{
		CFRelease(data);
		return FALSE;	/* Not a DDS file! */
	}

	int ncodecs = 0;
	CFTypeRef codecs[3];
	CFStringRef format = NULL;
	if (header->sPixelFormat.dwFlags & DDPF_FOURCC)
		codecs[ncodecs++] = format = CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *) &header->sPixelFormat.dwFourCC, 4, kCFStringEncodingASCII, false);
	else if (header->sPixelFormat.dwFlags & DDPF_RGB)
		codecs[ncodecs++] = (header->sPixelFormat.dwFlags & DDPF_ALPHAPIXELS) ? CFSTR("RGBA") : CFSTR("RGB");
	if (header->sCaps.dwCaps2 & DDSCAPS2_CUBEMAP)
		codecs[ncodecs++] = CFSTR("cubemap");
	if ((header->dwFlags & DDSD_MIPMAPCOUNT) && header->dwMipMapCount)
		codecs[ncodecs++] = CFSTR("mipmaps");
	if (ncodecs)
	{
		CFArrayRef cfcodecs = CFArrayCreate(kCFAllocatorDefault, (const void **) codecs, ncodecs, &kCFTypeArrayCallBacks);
		CFDictionaryAddValue(attributes, kMDItemCodecs, cfcodecs);
		CFRelease(cfcodecs);
		if (format)
			CFRelease(format);
	}

	int height = OSReadLittleInt32(header, offsetof(DDS_header, dwHeight));
	CFNumberRef cfheight = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &height);
	CFDictionaryAddValue(attributes, kMDItemPixelHeight, cfheight);
	CFRelease(cfheight);
	
	int width = OSReadLittleInt32(header, offsetof(DDS_header, dwWidth));
	CFNumberRef cfwidth = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &width);
	CFDictionaryAddValue(attributes, kMDItemPixelWidth, cfwidth);
	CFRelease(cfwidth);

	CFRelease(data);
	return TRUE;
}
