/*

 * Taken from SOIL/image_DXT.h, Jonathan Dummer, 2007-07-31-10.32
 */

#ifndef HEADER_DDS
#define HEADER_DDS

#import <Cocoa/Cocoa.h>

/**	A bunch of DirectDraw Surface structures and flags **/
typedef struct
{
    unsigned int    dwMagic;
    unsigned int    dwSize;
    unsigned int    dwFlags;
    unsigned int    dwHeight;
    unsigned int    dwWidth;
    unsigned int    dwPitchOrLinearSize;
    unsigned int    dwDepth;
    unsigned int    dwMipMapCount;
    unsigned int    dwReserved1[ 11 ];

    /*  DDPIXELFORMAT	*/
    struct
    {
        unsigned int    dwSize;
        unsigned int    dwFlags;
        unsigned int    dwFourCC;
        unsigned int    dwRGBBitCount;
        unsigned int    dwRBitMask;
        unsigned int    dwGBitMask;
        unsigned int    dwBBitMask;
        unsigned int    dwAlphaBitMask;
    }
    sPixelFormat;

    /*  DDCAPS2	*/
    struct
    {
        unsigned int    dwCaps1;
        unsigned int    dwCaps2;
        unsigned int    dwDDSX;
        unsigned int    dwReserved;
    }
    sCaps;
    unsigned int    dwReserved2;
}
DDS_header ;

/*	the following constants were copied directly off the MSDN website	*/

/*	The dwFlags member of the original DDSURFACEDESC2 structure
	can be set to one or more of the following values.	*/
#define DDSD_CAPS	0x00000001
#define DDSD_HEIGHT	0x00000002
#define DDSD_WIDTH	0x00000004
#define DDSD_PITCH	0x00000008
#define DDSD_PIXELFORMAT	0x00001000
#define DDSD_MIPMAPCOUNT	0x00020000
#define DDSD_LINEARSIZE	0x00080000
#define DDSD_DEPTH	0x00800000

/*	DirectDraw Pixel Format	*/
#define DDPF_ALPHAPIXELS	0x00000001
#define DDPF_FOURCC	0x00000004
#define DDPF_RGB	0x00000040
#define DDPF_LUMINANCE	0x00020000

/*	The dwCaps1 member of the DDSCAPS2 structure can be
	set to one or more of the following values.	*/
#define DDSCAPS_COMPLEX	0x00000008
#define DDSCAPS_TEXTURE	0x00001000
#define DDSCAPS_MIPMAP	0x00400000

/*	The dwCaps2 member of the DDSCAPS2 structure can be
	set to one or more of the following values.		*/
#define DDSCAPS2_CUBEMAP	0x00000200
#define DDSCAPS2_CUBEMAP_POSITIVEX	0x00000400
#define DDSCAPS2_CUBEMAP_NEGATIVEX	0x00000800
#define DDSCAPS2_CUBEMAP_POSITIVEY	0x00001000
#define DDSCAPS2_CUBEMAP_NEGATIVEY	0x00002000
#define DDSCAPS2_CUBEMAP_POSITIVEZ	0x00004000
#define DDSCAPS2_CUBEMAP_NEGATIVEZ	0x00008000
#define DDSCAPS2_CUBEMAP_ALLFACES	(DDSCAPS2_CUBEMAP|DDSCAPS2_CUBEMAP_POSITIVEX|DDSCAPS2_CUBEMAP_NEGATIVEX|DDSCAPS2_CUBEMAP_POSITIVEY|DDSCAPS2_CUBEMAP_NEGATIVEY|DDSCAPS2_CUBEMAP_POSITIVEZ|DDSCAPS2_CUBEMAP_NEGATIVEZ)
#define DDSCAPS2_VOLUME	0x00200000


/*	DirectX10 additions */

/*	Only those formats that we support */
typedef enum DXGI_FORMAT
{
    DXGI_FORMAT_UNKNOWN 	= 0,
    DXGI_FORMAT_BC1_UNORM       = 71,	// DXT1
    DXGI_FORMAT_BC2_UNORM       = 74,	// DXT2
    DXGI_FORMAT_BC3_UNORM       = 77,	// DXT3
    DXGI_FORMAT_BC4_UNORM       = 80,	// ATI1
    DXGI_FORMAT_BC5_UNORM       = 83,	// ATI2
} DXGI_FORMAT;

typedef struct {
    DDS_header      DX9_header;
    DXGI_FORMAT     dxgiFormat;
    unsigned int    resourceDimension;
    unsigned int    miscFlag;
    unsigned int    arraySize;
    unsigned int    miscFlags2;
} DDS_header_DXT10;


@interface DDS : NSObject
{
    NSData *ddsfile;
    const unsigned char *ddsdata;   // pointer to the (potentially compressed) data
    unsigned int fourcc;            // FourCC code for recognised types
    NSString *_codec;               // Human-readable name of codec
    int _mainSurfaceWidth, _mainSurfaceHeight, _mainSurfaceDepth;   // image dimensions
    int _mipmapCount, _ddsCaps2, _bpp;
    int blocksize;                  // BCn block size for compressed images
    int pixelsize;                  // size in bytes for uncompressed images
    int amask, bmask, gmask, rmask; // channel masks for uncompressed images
    CGBitmapInfo bitmapinfo;        // type of image we will produce
}

- (id) initWithURL : (NSURL *) url;
+ (id) ddsWithURL : (NSURL *) url;

- (CGImageRef) CreateImage;
- (CGImageRef) CreateImageWithPreferredWidth:(int)width andPreferredHeight:(int)height;
- (void) DrawSurfaceWithDataAt:(const UInt8 *)src andWidth:(int)width andHeight:(int)height To:(UInt32 *)dst withStride:(int)stride;

@property (nonatomic,retain,readonly) NSString *codec;
@property (nonatomic,assign,readonly) int mainSurfaceWidth;
@property (nonatomic,assign,readonly) int mainSurfaceHeight;
@property (nonatomic,assign,readonly) int mainSurfaceDepth;
@property (nonatomic,assign,readonly) int mipmapCount;
@property (nonatomic,assign,readonly) int ddsCaps2;
@property (nonatomic,assign,readonly) int bpp;

@end


#endif /* HEADER_DDS	*/
