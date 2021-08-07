# libgpx

Welcome to **libgpx**, a multiplatform graphics library for 8bit micros. 

# Compiling libgpx

Run the `make` command with platform name as target in the root directory.

 > Supported platforms are `zxspec48` and `partner` and are 
 > case sensitive!

~~~
make PLATFORM=partner
~~~

After the compilation object and debug files are available in the `build` directory, and the `libgpx.lib` is copied to the `bin` directory. 

# Using libgpx

## Tiny coding convention

(...to be continued...)

## Dependencies

*libgpx* has been designed as an independent library. It incudes 
`stdbool.h`, and `stdint.h`, but uses its' own implementations.

## Initializing

To initialize the library, call `gpx_init()` function. This function returns a pointer to the `gpx_t` structure, which you pass to all other functions of the *libgpx*.

After you're done with using the library, you should call the `gpx_exit()`. On some platform this call just deletes the `gpx_t` structure. On others it switches from grapics back to text mode.

~~~cpp
#include <gpx.h>

void main() {
    gpt_t* g=gpx_init();
    /* your drawing code here */
    gpx_exit(g);
}
~~~

## Querying platform graphics capabilities

If you would like to know what the gpx library can do on your platform, you can call `gpx_cap().` This function will query platform graphics capabilities (resolution, no. of pages, black and white color, etc.). This function will return pointer to `gpx_cap_t`.

~~~cpp
#include <gpx.h>
#include <stdio.h>

void main() {
    /* enter gpx mode */
    gpx_t *g=gpx_init();

    /* query graphics capabilities */
    gpx_cap_t *cap=gpx_cap(g);
    printf("GRAPHICS PROPERTIES\n\n");
    printf("No. colors %d\nBack color %d\nFore color %d\n",
        cap->num_colors,
        cap->back_color,
        cap->fore_color);
    printf("Sup. pages %d\n", cap->num_pages);
    /* enum. pages */
    for(int p=0; p<cap->num_pages; p++)
        /* enum resolutions (for page) */
        for (int r=0; r<cap->pages[p].num_resolutions; r++)
            printf(" P%d Resol. %dx%d\n",
                p,
                cap->pages[p].resolutions[r].width,
                cap->pages[p].resolutions[r].height);
    
    /* leave gpx mode */
    gpx_exit(NULL);
}
~~~

And the result on ZX Spectrum 48K.

![ZX Spectrum 48K gpx_cap()](docs/img/zxspec48-gpx_cap.png)

## Page switching

If the platform supports multiple pages you can call `gpx_get_page()` and `gpx_set_page()` to switch pages. Both calls also contain `flags` member which tell whether you'd just like to redirect graphical writes to page (but not switch) or switch to a page.

Once you set the page, all operations will go to that page.

## Colors

The library at present only supports monochrome graphics, but its interface is prepared for color displays. You can set the color by calling `gpx_set_color()`, passing the `color_t` and color flags. Flags are used because on some systems you can set background and foreground color (for example: paper and ink on ZX Spectrum).

You can obtain black and white colors and number of supported colors by calling the `gpx_query_cap()`.

## Clipping

You can set a rectangular clipping region for all drawing. The clipping region is of type `rect_t` and is set by calling `gpx_set_clip()`. Passing `NULL` sets entire screen as the clipping region (=no clipping).

## Blit mode

Operations such as drawing lines, use blit mode. At present two blit modes are supported: `BM_XOR` and `BP_COPY`. You can set the blit mode using function `gpx_set_blit()` and read it by `gpx_get_blit()`.

## Patterns

### Line pattern

Call `set_line_pattern()` to pass a 1 byte line pattern. You can use predefined line patterns or custom line patterns. If you use a predefined pattern it might get hardware accelerated. 

The predefined patterns are:
 * LP_SOLID    11111111
 * LP_DOTTED   10101010
 * LP_DASHED   11001100

### Fill pattern

Call the `set_fill_pattern()` to pass a min. 1 to max 8 byte fill pattern.

## Resolution

You can obtain resolution indexes by calling `gpx_get_cap()` and iterating through the `gpx_page_t[] pages` member. Each page has a `gpx_resolution_t[] resolutions` member, which contains resolutions.

By convention the resolutions are ordered from lowest to highest.

 > On some platforem `libgpx` emulates lower resolutions (for example - 
 > gpx emulates 512x256 on Iskra Delta Partner). 

Resolution is also set per page, so make sure you set it for all pages you are using.

## Clearing the screen

Use `gpx_cls()` to clear screen.

## Drawing!

All drawing functions start with `gpx_draw_` and all fill functions start with `gpx_fill_`. They only accept coordinate arguments, because all other aspects of drawing (color, blit mode, clipping) is set by a separate function and stored in the `gpx_t` structure.

Following functions are available.
 * `gpx_draw_line()` ... draws a line
 * `gpx_draw_rect()` ... draws a rectangle
 * `gpx_fill_rect()` ... draws a filled rectangle
 * `gpx_draw_glyph()` ... draws a bitmap
 * `gpx_draw_mglyph()` ... draws a masked bitmap
 * `gpx_read_glyph()` ... read a bitmap from screen

 > All functions are optimized. For example - when drawing a line,
 > horizontal line is detected and drawn using super- speeed function.

## Fonts

Fonts are implemented using the glyph group of drawing functions, because each letter is just a bitmap, with some extra drawing hints. 

To use font you need to load it (unless already part of your C code). Each font starts with the `font_t` structure where you can find some basic font information such as average width, height, number of characters, etc.

You then simply call `gpx_draw_string()` to draw a sting. 

 > Don't forget that fonts also use the *blit mode*, and if it is not `BM_COPY`, background may not be deleted.

### Measuring text

Use `gpx_measure_string()` to measure string. 

(...to be continued...)

# Supported platforms

## Iskra Delta Partner

![Iskra Delta Partner](docs/img/partner.jpg) 

| Trait                     | Value     |
|---------------------------|----------:|
| Processor                 | Z80, 4Mhz |
| Graphics type             | Vector    |
| Native resolution         | 1024x512  |
| Colors                    | 2         |
| Page(s)                   | 2         |
| *libgpx* size in bytes    | N/A       |
| Implementation internals  | [Available](PARTNER.md) |

---

## ZX Spectrum 48K

![ZX Spectrum 48K](docs/img/zxspec48.jpg)

| Trait                     | Value     |
|---------------------------|----------:|
| Processor                 | Z80, 4Mhz |
| Graphics type             | Raster    |
| Native resolution         | 256x192   |
| Colors                    | 15        |
| Page(s)                   | 1         |
| *libgpx* size in bytes    | N/A       |
| Implementation internals  | [Available](ZXSPEC48.md) |