#include <stddef.h>
#include <libkern/OSByteOrder.h>

#include "dds.h"

/* Lookup table for premultiplying alpha without having to do multiplication and division */
extern const UInt8 premul_table[256][256];


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

const unsigned int DDS_MAGIC   = 0x20534444;	// "DDS "


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


// Premultiply alpha in-place
inline static Color32 premultiply(Color32 c)
{
    const UInt8 *premula = premul_table[c.a];
    c.r = premula[c.r];
    c.g = premula[c.g];
    c.b = premula[c.b];
    return c;
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
- (int) surfaceSize: (int) mipmapLevel;
@end

@implementation DDS

- (id) initWithURL: (NSURL *) url
{
    if (!(self = [super init]))
        return nil;

    char const *ddsheader;
    if (!(ddsfile = [[NSData dataWithContentsOfURL:url] retain]) ||
        ddsfile.length < sizeof(DDS_header) ||
        !(ddsheader = ddsfile.bytes) ||
        OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwMagic)) != DDS_MAGIC ||
        (OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwSize)) + sizeof(DDS_MAGIC) != sizeof(DDS_header) &&
         OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwSize)) != DDS_MAGIC))  // Some old DX8 files have the magic repeated in the size field
    {
        [self release];
        return nil;
    }

    // according to http://msdn.microsoft.com/en-us/library/bb943982 we ignore DDSD_PIXELFORMAT in dwFlags and assume that sPixelFormat is valid
    unsigned int pfflags = OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwFlags));

    if (pfflags & DDPF_FOURCC)
    {
        /* DirectX10 header extension */
        if (OSReadLittleInt32(ddsheader, offsetof(DDS_header, sPixelFormat.dwFourCC)) == FOURCC_DX10)
        {
            if (ddsfile.length < sizeof(DDS_header_DXT10))
            {
                [self release];
                return nil;
            }
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
            _codec = [[[NSString alloc] initWithBytes:(ddsheader + offsetof(DDS_header, sPixelFormat.dwFourCC)) length:4 encoding:NSASCIIStringEncoding] retain];
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

    // according to http://msdn.microsoft.com/en-us/library/bb943982 we ignore DDSD_MIPMAPCOUNT in dwFlags
    _mipmapCount = OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwMipMapCount));
    if (! _mipmapCount) _mipmapCount = 1;	// assume that we always have at least one surface

    // also ignore DDSD_DEPTH in dwFlags for similar reasons
    _mainSurfaceDepth = _ddsCaps2 & DDSCAPS2_VOLUME ? OSReadLittleInt32(ddsheader, offsetof(DDS_header, dwDepth)) : 0;
    if (! _mainSurfaceDepth) _mainSurfaceDepth = 1;

    return self;
}

+ (id) ddsWithURL: (NSURL *) url
{
    DDS* dds = [[DDS alloc] initWithURL:url];
    return [dds autorelease];
}

- (void) dealloc
{
    // release members here
    [_codec release];
    [ddsfile release];
    [super dealloc];
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

    int surface_count;                  // number of surfaces we're doing
    const int (*surface_layout)[2];     // position of each surface in the image [x, y]
    const int surface_layout_one [1][2] = { { 0, 0 } };
    const int surface_layout_full[6][2] = { { 2, 1 }, { 0, 1 }, { 1, 0 }, { 1, 2 }, { 1, 1 }, { 3, 1 } };
    const int surface_layout_half[3][2] = { { 1, 1 }, { 0, 0 }, { 0, 1 } };
    const int surface_layout_seqn[6][2] = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 3, 0 }, { 4, 0 }, { 5, 0 } };
    int surface_width = _mainSurfaceWidth;
    int surface_height= _mainSurfaceHeight;

    int img_width, img_height;  // dimensions of generated image

    if (!(_ddsCaps2 & DDSCAPS2_CUBEMAP))
    {
        surface_count = 1;
        surface_layout = surface_layout_one;
        img_width  = surface_width;
        img_height = surface_height;
    }
    else
    {
        // cubemap

        // The order of surfaces in the file is  +x, -x, +y,-y, +z,-z according to http://msdn.microsoft.com/en-gb/library/windows/desktop/bb205577
        const unsigned int surface_order[6] = { DDSCAPS2_CUBEMAP_POSITIVEX,DDSCAPS2_CUBEMAP_NEGATIVEX, DDSCAPS2_CUBEMAP_POSITIVEY, DDSCAPS2_CUBEMAP_NEGATIVEY, DDSCAPS2_CUBEMAP_POSITIVEZ, DDSCAPS2_CUBEMAP_NEGATIVEZ };

        if ((_ddsCaps2 & DDSCAPS2_CUBEMAP_ALLFACES) == DDSCAPS2_CUBEMAP_ALLFACES)
        {
            //                        +y
            // We present them as: -x +z +x -z
            //                        -y
            surface_count = 6;
            surface_layout = surface_layout_full;
            img_width  = surface_width * 4;
            img_height = surface_height * 3;
        }
        else if ((_ddsCaps2 & DDSCAPS2_CUBEMAP_ALLFACES) == (DDSCAPS2_CUBEMAP|DDSCAPS2_CUBEMAP_POSITIVEX|DDSCAPS2_CUBEMAP_POSITIVEY|DDSCAPS2_CUBEMAP_POSITIVEZ))
        {
            //                             +y
            // Only the positive surfaces: +z +x
            surface_count = 3;
            surface_layout = surface_layout_half;
            img_width  = surface_width * 2;
            img_height = surface_height * 2;
        }
        else
        {
            // Some random selection of surfaces. Present them as they come.
            surface_count = 0;
            for (int i=0; i<6; i++)
                if (_ddsCaps2 & surface_order[i])
                    surface_count++;
            if (!surface_count) return NULL;    // eh?
            surface_layout = surface_layout_seqn;
            img_width  = surface_width * surface_count;
            img_height = surface_height;
        }
    }

    int surface_bytes = 0;  // size of each surface, including lower-level mipmaps
    int mipmap = 1;
    while (mipmap <= _mipmapCount)
        surface_bytes += [self surfaceSize:mipmap++];

    // Find smallest mipmap that is the same size or larger than the desired size - QuickLook will scale it down to desired size
    // This doesn't handle volume textures (which look like http://msdn.microsoft.com/en-us/library/windows/desktop/bb205579)
    mipmap = 1;
    if ((width || height) && _mainSurfaceDepth==1)
        while (mipmap < _mipmapCount)
        {
            if (img_width / 2 >= width || img_height / 2 >= height)
            {
                if (! (surface_width /= 2)) surface_width = 1;
                if (! (surface_height/= 2)) surface_height= 1;
                if (! (img_width /= 2)) img_width = 1;
                if (! (img_height/= 2)) img_height= 1;
                data_ptr += [self surfaceSize:mipmap];
                mipmap ++;
            }
            else
                break;
        }

    // Draw
    UInt32 *img_data;
    if (! (img_data = calloc(img_width * img_height, 4))) // Allocate zeroed data so bits we don't write to are transparent
        return NULL;
    for (int surface_num = 0; surface_num < surface_count; surface_num++)
        {
            UInt32 *dst = img_data + surface_width * (*surface_layout)[0] + img_width * surface_height * (*surface_layout)[1];
            [self DrawSurfaceWithDataAt:data_ptr andWidth:surface_width andHeight:surface_height To:dst withStride:img_width];
            surface_layout ++;
            data_ptr += surface_bytes;
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


// Draw a DDS surface into an ARGB bitmap.
// src points to the DDS surface data [bytes]. width and height specify the dimensions of the surface.
// dst points to the target bitmap [pixels]. stride specifies the width of the target bitmap [pixels].
- (void) DrawSurfaceWithDataAt:(const UInt8 *)src andWidth:(int)width andHeight:(int)height To:(UInt32 *)dst withStride:(int)stride
{
    if (blocksize)
    {
        // See http://msdn.microsoft.com/en-us/library/bb694531 for descriptions of compression scheme

        for (int y=0; y < height; y += 4)
        {
            Color32 c = { -1 }; // output pixel color
            Color32 p[4] = { -1, -1, -1, -1 };  // Color palette for DXT1-DXT5

            if (fourcc == FOURCC_DXT1)  // 1bit alpha
                for (int x=0; x < width; x += 4)
                {
                    makeColor32Palette(OSReadLittleInt32(src, 0), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 4);

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            dst[yy + xx] = p[c_idx & 3].u;
                            c_idx >>= 2;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT2) // premultiplied alpha
                for (int x=0; x < width; x += 4)
                {
                    UInt64 alpha = OSReadLittleInt64(src, 0);
                    makeColor32Palette(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = (alpha & 0xf) | ((alpha & 0xf) << 4);    // extend
                            dst[yy + xx] = c.u;
                            c_idx >>= 2;
                            alpha >>= 4;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT3)
                for (int x=0; x < width; x += 4)
                {
                    UInt64 alpha = OSReadLittleInt64(src, 0);
                    makeColor32Palette(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = (alpha & 0xf) | ((alpha & 0xf) << 4);    // extend
                            dst[yy + xx] = premultiply(c).u;
                            c_idx >>= 2;
                            alpha >>= 4;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT4) // premultiplied alpha
                for (int x=0; x < width; x += 4)
                {
                    UInt8 lum[8];
                    UInt64 alpha = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(alpha, lum);
                    alpha >>= 16;
                    makeColor32Palette(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = lum[alpha & 0x7];
                            dst[yy + xx] = c.u;
                            c_idx >>= 2;
                            alpha >>= 3;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT5)
                for (int x=0; x < width; x += 4)
                {
                    UInt8 lum[8];
                    UInt64 a_idx = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(a_idx, lum);
                    a_idx >>= 16;
                    makeColor32Palette(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = lum[a_idx & 0x7];
                            dst[yy + xx] = premultiply(c).u;
                            c_idx >>= 2;
                            a_idx >>= 3;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_ATI1)
                for (int x=0; x < width; x += 4)
                {
                    UInt8 lum[8];
                    UInt64 l_idx = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(l_idx, lum);
                    l_idx >>= 16;

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.r = c.g = c.b = lum[l_idx & 0x7];
                            dst[yy + xx] = c.u;
                            l_idx >>= 3;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            else if (fourcc == FOURCC_ATI2)
                for (int x=0; x < width; x += 4)
                {
                    UInt8 red[8], grn[8];
                    UInt64 r_idx = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(r_idx, red);
                    r_idx >>= 16;
                    UInt64 g_idx = OSReadLittleInt64(src, 8);
                    makeLuminancePalette(g_idx, grn);
                    g_idx >>= 16;

                    for (int yy = 0; yy < 4*stride; yy += stride)
                        for (int xx = 0; xx < 4; xx++)
                        {
                            c.r = red[r_idx & 0x7];
                            c.g = grn[g_idx & 0x7];
                            computeColor32NormalB(c);
                            dst[yy + xx] = c.u;
                            r_idx >>= 3;
                            g_idx >>= 3;
                        }
                    dst += 4; // next 4x4 block
                    src += blocksize;
                }

            dst += (4 * stride - width);   // next set of 4 lines
        }
    }
    else
    {
        // Linear data

        UInt32 w;
        Color32 c = { -1 }; // output pixel color
        int rshift = maskshift(rmask);
        int gshift = maskshift(gmask);
        int bshift = maskshift(bmask);
        int ashift = maskshift(amask);

        for (int y = 0; y < height; y++)
        {
            if (fourcc == FOURCC_RGBA)  // common case
                for (int x = 0; x < width; x++)
                {
                    w = OSReadLittleInt32(src, 0);
                    src += pixelsize;
                    c.a = (w & amask) >> ashift;
                    c.r = (w & rmask) >> rshift;
                    c.g = (w & gmask) >> gshift;
                    c.b = (w & bmask) >> bshift;
                    *(dst++) = premultiply(c).u;
                }
            else if (fourcc == FOURCC_RG)   // normal map
                for (int x = 0; x < width; x++)
                {
                    w = OSReadLittleInt32(src, 0);
                    src += pixelsize;
                    c.r = (w & rmask) >> rshift;
                    c.g = (w & gmask) >> gshift;
                    computeColor32NormalB(c);
                    *(dst++) = c.u;
                }
            else if (fourcc == FOURCC_LA)
                for (int x = 0; x < width; x++)
                {
                    w = OSReadLittleInt32(src, 0);
                    src += pixelsize;
                    c.a = (w & amask) >> ashift;
                    c.r = c.g = c.b = (w & rmask) >> rshift;    // by convention uses the red channel
                    *(dst++) = premultiply(c).u;
                }
            else if (fourcc == FOURCC_L)   // no alpha
                for (int x = 0; x < width; x++)
                {
                    w = OSReadLittleInt32(src, 0);
                    src += pixelsize;
                    c.r = c.g = c.b = (w & rmask) >> rshift;    // by convention uses the red channel
                    *(dst++) = c.u;
                }
            else    // RGBX or RGBN - no alpha
                for (int x = 0; x < width; x++)
                {
                    w = OSReadLittleInt32(src, 0);
                    src += pixelsize;
                    c.r = (w & rmask) >> rshift;
                    c.g = (w & gmask) >> gshift;
                    c.b = (w & bmask) >> bshift;
                    *(dst++) = c.u;
                }

            dst += (stride - width);   // next line
        }

    }
}


// Size in bytes of this surface at specified mipmap level.
- (int) surfaceSize: (int) mipmapLevel
{
    int w = _mainSurfaceWidth;
    int h = _mainSurfaceHeight;
    int d = _mainSurfaceDepth;

    while (--mipmapLevel > 0)
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
