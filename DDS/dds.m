#include <stddef.h>
#include <libkern/OSByteOrder.h>

#include "dds.h"


// FOURCC codes that we know how to deal with
typedef enum {
    FOURCC_UNKNOWN    = 0,
    // Values that can appear in sPixelFormat.dwFlags
    FOURCC_DXT1       = 0x31545844,
    FOURCC_DXT2       = 0x32545844,
    FOURCC_DXT3       = 0x33545844,
    FOURCC_DXT4       = 0x34545844,
    FOURCC_DXT5       = 0x35545844,
    FOURCC_ATI1       = 0x31495441,
    FOURCC_ATI2       = 0x32495441,
    FOURCC_DX10       = 0x30315844,
    // Psuedo identifiers just for internal use
    FOURCC_RG         = 0x20204752,
    FOURCC_RGB        = 0x20424752,
    FOURCC_RGBA       = 0x41424752,
    FOURCC_RGBX       = 0x58424752,
    FOURCC_L          = 0x2020204c,
    FOURCC_LA         = 0x2020414c,
} FourCC;

static const unsigned int DDS_MAGIC   = 0x20534444;	// "DDS "


// The order of surfaces in a cubemap is  +x, -x, +y,-y, +z,-z according to http://msdn.microsoft.com/en-gb/library/windows/desktop/bb205577
static const unsigned int surface_order[6] = { DDSCAPS2_CUBEMAP_POSITIVEX,DDSCAPS2_CUBEMAP_NEGATIVEX, DDSCAPS2_CUBEMAP_POSITIVEY, DDSCAPS2_CUBEMAP_NEGATIVEY, DDSCAPS2_CUBEMAP_POSITIVEZ, DDSCAPS2_CUBEMAP_NEGATIVEZ };


// Hopefully most efficient CGBitmapContext byte ordering: http://lists.apple.com/archives/quartz-dev/2012/Mar/msg00013.html
// Corresponds to kCGBitmapByteOrder32Host | [kCGImageAlphaNoneSkipFirst || kCGImageAlphaPremultipliedFirst]
typedef union
{
    UInt32 u;
    struct
    {
        UInt8 b, g, r, a;
    };
} Color32;


//
// Helpers. Written as plain C instead of ObjC member functions for speed.
//

// DXT1 3 or 4 color palette.
inline static void makeColor32Palette(UInt32 c01, Color32 p[4])
{
    assert(p[0].a == 0xff && p[1].a == 0xff && p[2].a == 0xff); // Assumes alphas already set to opaque.

    // rrrrrggggggbbbbb,rrrrrggggggbbbbb
    p[0].r = ((c01 & 0x0000f800)) >>  8 | (c01 & 0x0000e000) >> 13;
    p[0].g = ((c01 & 0x000007e0)) >>  3 | (c01 & 0x00000600) >>  9;
    p[0].b = ((c01 & 0x0000001f)) <<  3 | (c01 & 0x0000001b) >>  2;
    p[1].r = ((c01 & 0xf8000000)) >> 24 | (c01 & 0xe0000000) >> 29;
    p[1].g = ((c01 & 0x07e00000)) >> 19 | (c01 & 0x06000000) >> 25;
    p[1].b = ((c01 & 0x001f0000)) >> 13 | (c01 & 0x001b0000) >> 18;
    if (p[0].u > p[1].u)
    {
        p[2].r = (p[0].r + p[0].r + p[1].r + 1) / 3;
        p[2].g = (p[0].g + p[0].g + p[1].g + 1) / 3;
        p[2].b = (p[0].b + p[0].b + p[1].b + 1) / 3;
        p[3].r = (p[0].r + p[1].r + p[1].r + 1) / 3;
        p[3].g = (p[0].g + p[1].g + p[1].g + 1) / 3;
        p[3].b = (p[0].b + p[1].b + p[1].b + 1) / 3;
        p[3].a = 0xff;
    }
    else
    {
        p[2].r = (p[0].r + p[1].r) / 2;
        p[2].g = (p[0].g + p[1].g) / 2;
        p[2].b = (p[0].b + p[1].b) / 2;
        p[2].a = 0xff;
        p[3].u = 0;     // Transparent
    }
}


// DXT2-5 4 color palette.
inline static void makeColor32Palette4(UInt32 c01, Color32 p[4])
{
    assert(p[0].a == 0xff && p[1].a == 0xff && p[2].a == 0xff && p[3].a == 0xff); // Assumes alphas already set to opaque.

    // rrrrrggggggbbbbb,rrrrrggggggbbbbb
    p[0].r = ((c01 & 0x0000f800)) >>  8 | (c01 & 0x0000e000) >> 13;
    p[0].g = ((c01 & 0x000007e0)) >>  3 | (c01 & 0x00000600) >>  9;
    p[0].b = ((c01 & 0x0000001f)) <<  3 | (c01 & 0x0000001b) >>  2;
    p[1].r = ((c01 & 0xf8000000)) >> 24 | (c01 & 0xe0000000) >> 29;
    p[1].g = ((c01 & 0x07e00000)) >> 19 | (c01 & 0x06000000) >> 25;
    p[1].b = ((c01 & 0x001f0000)) >> 13 | (c01 & 0x001b0000) >> 18;
    p[2].r = (p[0].r + p[0].r + p[1].r + 1) / 3;
    p[2].g = (p[0].g + p[0].g + p[1].g + 1) / 3;
    p[2].b = (p[0].b + p[0].b + p[1].b + 1) / 3;
    p[3].r = (p[0].r + p[1].r + p[1].r + 1) / 3;
    p[3].g = (p[0].g + p[1].g + p[1].g + 1) / 3;
    p[3].b = (p[0].b + p[1].b + p[1].b + 1) / 3;
}


// DXT4,DXT5,ATI1,ATI2 palette
inline static void makeLuminancePalette(UInt64 a01, UInt8 p[8])
{
    p[0] = a01;
    p[1] = a01 >> 8;
    if (p[0] > p[1])
    {
        p[2] = (6 * p[0] + 1 * p[1] + 3) / 7;
        p[3] = (5 * p[0] + 2 * p[1] + 3) / 7;
        p[4] = (4 * p[0] + 3 * p[1] + 3) / 7;
        p[5] = (3 * p[0] + 4 * p[1] + 3) / 7;
        p[6] = (2 * p[0] + 5 * p[1] + 3) / 7;
        p[7] = (1 * p[0] + 6 * p[1] + 3) / 7;
    }
    else
    {
        p[2] = (4 * p[0] + 1 * p[1] + 2) / 5;
        p[3] = (3 * p[0] + 2 * p[1] + 2) / 5;
        p[4] = (2 * p[0] + 3 * p[1] + 2) / 5;
        p[5] = (1 * p[0] + 4 * p[1] + 2) / 5;
        p[6] = 0x00;
        p[7] = 0xff;
    }
}


// Compute normal in Blue channel in-place from Red and Green channels
// Assumes Blender convention: http://wiki.blender.org/index.php/Doc:2.6/Manual/Textures/Influence/Material/Bump_and_Normal
inline static void computeColor32NormalB(Color32 c)
{
    if (c.r == 0x7f && c.g == 0x7f)
    {
        c.b = 0xff;         // Common case - flat
    }
    else
    {
        // TODO: Probably could speed this up with a lookup table or sqrt approximation
        float x = 2 * (c.r / 255.0f) - 1;   // [0, 255] -> [-1.0, 1.0]
        float y = 2 * (c.g / 255.0f) - 1;   // [0, 255] -> [-1.0, 1.0]
        float z2 = 1 - x*x + y*y;
        if (z2 > 0.9961f)
            c.b = 0xff;     // Common case - flat enough that z will round to 1
        else if (z2 <= 0)
            c.b = 0;        // Shouldn't happen: unnormalized vector
        else
            c.b = roundf(sqrtf(z2) * 255);              // [0.0, 1.0] -> [0, 255]
    }
}


// how much we need to shift right to make an 8-bit quantity
// TODO: expand to 8 bits where mask is less than 8 bits e.g. 16bit 565 data
inline static int maskshift(unsigned int mask)
{
    if (! mask)
        return 0;

    int shift = 24;
    while (! (mask & 0x80000000))
    {
        shift -= 1;
        mask <<= 1;
    }
    return shift;
};



@interface DDS()
- (int) surfaceSize;
- (int) surfaceSize: (int) mipmapLevel;
@end

@implementation DDS

// Include different versions of decode.c
#define PREMULTIPLY
#include "decode.m"
#undef PREMULTIPLY
#include "decode.m"

- (id) initWithURL: (NSURL *) url
{
    if (!(self = [super init]))
        return nil;

    char const *ddsheader;
    NSError *error;
    if (!(ddsfile = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedAlways error:&error]) ||
        ddsfile.length < sizeof(DDS_header) ||
        !(ddsheader = ddsfile.bytes) ||
        OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwMagic)) != DDS_MAGIC ||
        (OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwSize)) + sizeof(DDS_MAGIC) != sizeof(DDS_header) &&
         OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwSize)) != DDS_MAGIC))  // Some old DX8 files have the magic repeated in the size field
        return nil;

    // according to http://msdn.microsoft.com/en-us/library/bb943982 we ignore DDSD_PIXELFORMAT in dwFlags and assume that sPixelFormat is valid
    unsigned int pfflags = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwFlags));

    if (pfflags & DDPF_FOURCC)
    {
        /* DirectX10 header extension */
        if (OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwFourCC)) == FOURCC_DX10)
        {
            if (ddsfile.length < sizeof(DDS_header_DXT10))
                return nil;

            // Map DXGI formats that we know how to deal with to the corresponding FourCC code
            switch (OSReadLittleInt32(ddsheader, offsetof(DDS_header_DXT10, dxgiFormat)))
            {
                case DXGI_FORMAT_BC1_UNORM:
                    _codec = @"BC1";
                    fourcc = FOURCC_DXT1;
                    break;
                case DXGI_FORMAT_BC2_UNORM:
                    _codec = @"BC2";
                    fourcc = FOURCC_DXT3;
                    break;
                case DXGI_FORMAT_BC3_UNORM:
                    _codec = @"BC3";
                    fourcc = FOURCC_DXT5;
                    break;
                case DXGI_FORMAT_BC4_UNORM:
                    _codec = @"BC4";
                    fourcc = FOURCC_ATI1;
                    break;
                case DXGI_FORMAT_BC5_UNORM:
                    _codec = @"BC5";
                    fourcc = FOURCC_ATI2;
                    break;
                default:
                    _codec = @"DX10";
                    fourcc = FOURCC_UNKNOWN;    // unsupported encoding
            }
            ddsdata = ((unsigned char *) ddsfile.bytes) + sizeof(DDS_header_DXT10);
        }
        else
        {
            _codec = [[NSString alloc] initWithBytes:(ddsheader + offsetof(DDS_header, sPixelFormat.dwFourCC)) length:4 encoding:NSASCIIStringEncoding];
            fourcc = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwFourCC));
            ddsdata = ((unsigned char *) ddsfile.bytes) + sizeof(DDS_header);
        }

        switch (fourcc)
        {
            case FOURCC_DXT1:
                blocksize = 8;
                _bpp = 16;      // 565
                break;
            case FOURCC_DXT2:
            case FOURCC_DXT3:
                blocksize = 16;
                _bpp = 20;      // 565 + 4 bit alpha
                break;
            case FOURCC_DXT4:
            case FOURCC_DXT5:
                blocksize = 16;
                _bpp = 24;      // 565 + 8 bit alpha
                break;
            case FOURCC_ATI1:
                blocksize = 8;
                _bpp = 8;
                break;
            case FOURCC_ATI2:
                blocksize = 16;
                _bpp = 16;
                break;
            default:
                fourcc = FOURCC_UNKNOWN;    // unsupported encoding
                break;
        }
    }
    else if (pfflags & (DDPF_RGB|DDPF_LUMINANCE))
    {
        _bpp = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwRGBBitCount));
        if ((pfflags & (DDPF_LUMINANCE|DDPF_ALPHAPIXELS)) == (DDPF_LUMINANCE|DDPF_ALPHAPIXELS))
        {
            _codec = @"Luminance + Alpha";
            fourcc = FOURCC_LA;
        }
        else if (pfflags & DDPF_LUMINANCE)
        {
            _codec = @"Luminance";
            fourcc = FOURCC_L;
        }
        else if (!OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwBBitMask)))
        {
            // No Blue channel - asume this is a normal map and compute Blue from Red and Green
            _codec = @"Normal map";
            fourcc = FOURCC_RG;
        }
        else if (pfflags & DDPF_ALPHAPIXELS)
        {
            _codec = @"RGBA";
            fourcc = FOURCC_RGBA;
        }
        else if (_bpp == 32)
        {
            // No alpha channel
            _codec = @"RGBX";
            fourcc = FOURCC_RGBX;
        }
        else
        {
            _codec = @"RGB";
            fourcc = FOURCC_RGB;
        }

        pixelsize = _bpp / 8;
        if (pixelsize * 8 != _bpp || pixelsize == 0 || pixelsize > 4)
        {
            // non-byte aligned data or too large for us
            fourcc = FOURCC_UNKNOWN;    // unsupported encoding
        }
        else
        {
            rmask  = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwRBitMask));
            gmask  = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwGBitMask));
            bmask  = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwBBitMask));
            amask  = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwAlphaBitMask));
        }
        ddsdata = ((unsigned char *) ddsfile.bytes) + sizeof(DDS_header);
    }
    else
        return NULL;	// Either DDPF_FOURCC, DDPF_RGB or DDPF_LUMINANCE should be set

    _ddsCaps2 = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sCaps.dwCaps2));
    _mainSurfaceWidth = OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwWidth));
    _mainSurfaceHeight= OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwHeight));

    if (!(_ddsCaps2 & DDSCAPS2_CUBEMAP))
        _surfaceCount = 1;
    else
    {
        _surfaceCount = 0;
        for (int i=0; i<6; i++)
            if (_ddsCaps2 & surface_order[i])
                _surfaceCount++;
        if (!_surfaceCount)
            _surfaceCount = 1;
    }

    // according to http://msdn.microsoft.com/en-us/library/bb943982 we ignore DDSD_MIPMAPCOUNT in dwFlags
    _mipmapCount = OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwMipMapCount));
    if (! _mipmapCount) _mipmapCount = 1;	// assume that we always have at least one surface

    // also ignore DDSD_DEPTH in dwFlags for similar reasons
    _mainSurfaceDepth = _ddsCaps2 & DDSCAPS2_VOLUME ? OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwDepth)) : 0;
    if (! _mainSurfaceDepth) _mainSurfaceDepth = 1;

    // Check file not truncated
    if (ddsfile.length < _surfaceCount * [self surfaceSize] + (ddsdata - (unsigned char *) ddsfile.bytes))
        return nil;

    return self;
}

+ (id) ddsWithURL: (NSURL *) url
{
    DDS* dds = [[DDS alloc] initWithURL:url];
    return dds;
}


- (CGImageRef) CreateImage
{
    return [self CreateImageWithPreferredWidth:0 andPreferredHeight:0];
}

- (CGImageRef) CreateImageWithPreferredWidth:(int)width andPreferredHeight:(int)height
{
    if (fourcc == FOURCC_UNKNOWN)
        return NULL;

    const unsigned char *data_ptr = ddsdata;

    const int (*surface_layout)[2];     // position of each surface in the image [x, y]
    const int surface_layout_one [1][2] = { { 0, 0 } };
    const int surface_layout_full[6][2] = { { 2, 1 }, { 0, 1 }, { 1, 0 }, { 1, 2 }, { 1, 1 }, { 3, 1 } };
    const int surface_layout_half[3][2] = { { 1, 1 }, { 0, 0 }, { 0, 1 } };
    const int surface_layout_seqn[6][2] = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 }, { 5, 0 } };
    int surface_width = _mainSurfaceWidth;
    int surface_height= _mainSurfaceHeight;

    int img_width, img_height;  // dimensions of generated image

    if (_surfaceCount == 1)
    {
        surface_layout = surface_layout_one;
        img_width  = surface_width;
        img_height = surface_height;
    }
    else
    {
        // cubemap

        if ((_ddsCaps2 & DDSCAPS2_CUBEMAP_ALLFACES) == DDSCAPS2_CUBEMAP_ALLFACES)
        {
            //                        +y
            // We present them as: -x +z +x -z
            //                        -y
            surface_layout = surface_layout_full;
            img_width  = surface_width * 4;
            img_height = surface_height * 3;
        }
        else if ((_ddsCaps2 & DDSCAPS2_CUBEMAP_ALLFACES) == (DDSCAPS2_CUBEMAP|DDSCAPS2_CUBEMAP_POSITIVEX|DDSCAPS2_CUBEMAP_POSITIVEY|DDSCAPS2_CUBEMAP_POSITIVEZ))
        {
            //                             +y
            // Only the positive surfaces: +z +x
            surface_layout = surface_layout_half;
            img_width  = surface_width * 2;
            img_height = surface_height * 2;
        }
        else
        {
            // Some random selection of surfaces. Present them as they come.
            surface_layout = surface_layout_seqn;
            img_width  = surface_width * _surfaceCount;
            img_height = surface_height;
        }
    }

    // Find smallest mipmap that is the same size or larger than the desired size - QuickLook will scale it down to desired size
    // This doesn't handle volume textures (which look like http://msdn.microsoft.com/en-us/library/windows/desktop/bb205579 )
    int mipmap = 0;
    if ((width || height) && _mainSurfaceDepth==1)
        while (mipmap < _mipmapCount)
        {
            if (img_width / 2 >= width || img_height / 2 >= height)
            {
                if (! (surface_width /= 2)) surface_width = 1;
                if (! (surface_height/= 2)) surface_height= 1;
                if (! (img_width /= 2)) img_width = 1;
                if (! (img_height/= 2)) img_height= 1;
                mipmap ++;
            }
            else
                break;
        }

    // Draw
    UInt32 *img_data;
    if (!(img_data = (_surfaceCount > 1) ?
          calloc(img_width * img_height, 4) :  // Allocate zeroed data so bits we don't write to are transparent
          malloc(img_width * img_height * 4)))
        return NULL;

    for (int surface_num = 0; surface_num < _surfaceCount; surface_num++)
        {
            UInt32 *dst = img_data + surface_width * (*surface_layout)[0] + img_width * surface_height * (*surface_layout)[1];
            [self DecodeSurfacePremultiplied:surface_num atLevel:(int)mipmap To:dst withStride:img_width];
            surface_layout ++;
        }

    // Wangle into a CGImage via a CGBitmapContext
    // OSX wants premultiplied alpha. See "Supported Pixel Formats" at
    // https://developer.apple.com/Library/mac/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html

    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(img_data, img_width, img_height, 8, img_width * 4, rgb, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(rgb);
    if (!context)
    {
        free(img_data);
        return NULL;
    }
    CGImageRef image = CGBitmapContextCreateImage(context);	// copy or copy-on-write img_data
    CGContextRelease(context);
    free(img_data);

    return image;
}


// Size in bytes of one surface (including any mipmaps)
- (int) surfaceSize
{
    int mipmap = 0;
    int w = _mainSurfaceWidth;
    int h = _mainSurfaceHeight;
    int d = _mainSurfaceDepth;

    int surface_bytes = 0;
    while (mipmap++ < _mipmapCount)
    {
        surface_bytes += (blocksize ?
                          blocksize * ((w + 3) / 4) * ((h + 3) / 4) * d : // block aligned
                          pixelsize * w * h * d);     // byte aligned
        if (! (w /= 2)) w = 1;
        if (! (h /= 2)) h = 1;
        if (! (d /= 2)) d = 1;
    }
    return surface_bytes;
}


// Size in bytes of one surface at specified mipmap level (0-based).
- (int) surfaceSize: (int) mipmapLevel
{
    int mipmap = 0;
    int w = _mainSurfaceWidth;
    int h = _mainSurfaceHeight;
    int d = _mainSurfaceDepth;

    while (mipmap++ < mipmapLevel)
    {
        if (! (w /= 2)) w = 1;
        if (! (h /= 2)) h = 1;
        if (! (d /= 2)) d = 1;
    }
    return (blocksize ?
            blocksize * ((w + 3) / 4) * ((h + 3) / 4) * d : // block aligned
            pixelsize * w * h * d);     // byte aligned
}


@synthesize codec = _codec;
@synthesize mainSurfaceWidth  = _mainSurfaceWidth;
@synthesize mainSurfaceHeight = _mainSurfaceHeight;
@synthesize mainSurfaceDepth  = _mainSurfaceDepth;
@synthesize mipmapCount= _mipmapCount;
@synthesize ddsCaps2 = _ddsCaps2;
@synthesize bpp = _bpp;

@end
