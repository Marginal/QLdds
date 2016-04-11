//
//  decode.m
//  QLdds
//
//  Created by Jonathan Harris on 10/04/2016.
//
//  This file is included into dds.m twice to provide premultiplied
//  and non-premultiplied decode functions.
//

#ifndef HEADER_DDS
# error This file is intended to be included into dds.m rather than compiled directly
#endif


#ifdef PREMULTIPLY

#define DIVIDE_BY_255(v) (((((unsigned)(v)) << 8) + ((unsigned)(v)) + 255) >> 16)

// Premultiply alpha in-place
inline static Color32 alpha_premultiply(Color32 c, UInt8 a)
{
    if (a == 0)
        c.u = 0;     // Transparent
    else if (a == 0xff)
        c.a = 0xff;
    else
    {
        c.r = DIVIDE_BY_255(c.r * a);
        c.g = DIVIDE_BY_255(c.g * a);
        c.b = DIVIDE_BY_255(c.b * a);
        c.a = a;
    }
    return c;
}
# define PREFN(c,a) alpha_premultiply((c),(a))

#else

inline static Color32 alpha_nonmultiply(Color32 c, UInt8 a)
{
    c.a = a;
    return c;
}
# define PREFN(c,a) alpha_nonmultiply((c),(a))

#endif


#ifdef PREMULTIPLY
- (void) DecodeSurfacePremultiplied:(int)surface atLevel:(int)mipmapLevel To:(UInt32 *)dst withStride:(int)stride
#else
- (void) DecodeSurface:(int)surface atLevel:(int)mipmapLevel To:(UInt32 *)dst withStride:(int)stride
#endif
{
    if (surface < 0 || surface >= _surfaceCount || mipmapLevel < 0 || mipmapLevel >= _mipmapCount)
        return;

    const unsigned char *src = ddsdata;

    // See https://msdn.microsoft.com/en-us/library/windows/desktop/bb205577 for cubemap layout
    if (surface)
        src += surface * [self surfaceSize];

    int mipmap = 0;
    int width = _mainSurfaceWidth;
    int height= _mainSurfaceHeight;
    while (mipmap++ < mipmapLevel)
    {
         if (! (width /= 2)) width = 1;
         if (! (height/= 2)) height= 1;
         src += [self surfaceSize:mipmap];
    }

    if (blocksize)
    {
        // See http://msdn.microsoft.com/en-us/library/bb694531 for descriptions of compression scheme

        Color32 c = { -1 }; // output pixel color
        Color32 p[4] = { -1, -1, -1, -1 };  // Color palette for DXT1-DXT5

        for (int y=0; y < height*stride; y += 4*stride)
        {
            if (fourcc == FOURCC_DXT1)  // 1bit alpha
                for (int x=0; x < width; x += 4)
                {
                    makeColor32Palette(OSReadLittleInt32(src, 0), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 4);

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            dst[yy + xx] = p[c_idx & 3].u;
                            c_idx >>= 2;
                        }
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT2) // premultiplied alpha
                for (int x=0; x < width; x += 4)
                {
                    UInt64 alpha = OSReadLittleInt64(src, 0);
                    makeColor32Palette4(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = (alpha & 0xf) | ((alpha & 0xf) << 4);    // extend
                            dst[yy + xx] = c.u;
                            c_idx >>= 2;
                            alpha >>= 4;
                        }
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT3)
                for (int x=0; x < width; x += 4)
                {
                    UInt64 alpha = OSReadLittleInt64(src, 0);
                    makeColor32Palette4(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            dst[yy + xx] = PREFN(c, (alpha & 0xf) | ((alpha & 0xf) << 4)).u;    // extend alpha
                            c_idx >>= 2;
                            alpha >>= 4;
                        }
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

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            c.a = lum[alpha & 0x7];
                            dst[yy + xx] = c.u;
                            c_idx >>= 2;
                            alpha >>= 3;
                        }
                    src += blocksize;
                }

            else if (fourcc == FOURCC_DXT5)
                for (int x=0; x < width; x += 4)
                {
                    UInt8 lum[8];
                    UInt64 a_idx = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(a_idx, lum);
                    a_idx >>= 16;
                    makeColor32Palette4(OSReadLittleInt32(src, 8), p);
                    UInt32 c_idx = OSReadLittleInt32(src, 12);

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.u = p[c_idx & 3].u;
                            dst[yy + xx] = PREFN(c, lum[a_idx & 0x7]).u;
                            c_idx >>= 2;
                            a_idx >>= 3;
                        }
                    src += blocksize;
                }

            else if (fourcc == FOURCC_ATI1)
                for (int x=0; x < width; x += 4)
                {
                    UInt8 lum[8];
                    UInt64 l_idx = OSReadLittleInt64(src, 0);
                    makeLuminancePalette(l_idx, lum);
                    l_idx >>= 16;

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.r = c.g = c.b = lum[l_idx & 0x7];
                            dst[yy + xx] = c.u;
                            l_idx >>= 3;
                        }
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

                    for (int yy = y; yy < MIN(y+4*stride, height*stride); yy += stride)
                        for (int xx = x; xx < MIN(x+4, width); xx++)
                        {
                            c.r = red[r_idx & 0x7];
                            c.g = grn[g_idx & 0x7];
                            computeColor32NormalB(c);
                            dst[yy + xx] = c.u;
                            r_idx >>= 3;
                            g_idx >>= 3;
                        }
                    src += blocksize;
                }
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
                    c.r = (w & rmask) >> rshift;
                    c.g = (w & gmask) >> gshift;
                    c.b = (w & bmask) >> bshift;
                    *(dst++) = PREFN(c, (w & amask) >> ashift).u;
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
                    c.r = c.g = c.b = (w & rmask) >> rshift;    // by convention uses the red channel
                    *(dst++) = PREFN(c, (w & amask) >> ashift).u;
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

#undef DIVIDE_BY_255
#undef PREFN
