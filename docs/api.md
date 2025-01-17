# API documentation for v1.1.0

## Permission requirements
* at least one free buffer
* maximum buffer size at least 16 bytes (more = faster; capped at 64KiB if more than that is available)

## Public API

### `load_raw(raw: string)`
*returns `colormagic.file_pack`*

Load raw PNG data as a string and return a file pack. The file pack can be re-used to create multiple variants of the same texture.

***

### `load(is: InputStream)`
*returns `colormagic.file_pack`*

Load raw PNG data from a resource (or other non-async InputStream) and return a file pack. The file pack can be re-used to create multiple variants of the same texture. This function is implemented with `load_raw`.

***

### `pnginfo_raw(raw: string)`
*informational*

Writes palette data from the provided PNG image out to chat, if the image is in indexed mode. Errors on non-indexed images.

***

### `pnginfo(is: InputStream)`
*informational*

Writes palette data from the provided non-async InputStream containing a PNG image out to chat, if the image is in indexed mode. Errors on non-indexed images. This function is implemented with `pnginfo_raw`.

***

### `automap(pack: colormagic.file_pack, color_replacements: ColorReplacements)`
*modifies `pack`, returns [**Replacements**](#replacements) (type alias)*  
*see also [*ColorReplacements*](#colorreplacements) (type alias)*

Perform **automatic mapping** of colors in the `color_replacements` table to the palette of the provided image pack. This produces a [Replacements](#replacements) table that can be passed to one of the `transmute` functions to apply the color mapping.

***

### `toBase64Chunked(bytes: string, max_buf: integer)`
*returns `string`*

Converts the provided bytes string into its base64 representation, potentially in multiple chunks if the provided data in `bytes` is larger than `max_buf`.

***

### `fromBase64Chunked(b64: string, max_buf: integer?)`
*returns `string`*

Converts the provided base64 string into its binary representation, potentially in multiple chunks if the provided data in `b64` would decode to a size larger than `max_buf`. If `max_buf` is not provided, 64KiB will be used.

***

### `transmute_raw(pack: colormagic.file_pack, replacements: Replacements)`
*returns `string`*  
*see also [*Replacements*](#replacements) (type alias)*

Performs palette swapping on the provided PNG pack using the provided replacement rules. Returns modified raw PNG data as a string.
 
***

### `transmute_direct(pack: colormagic.file_pack, replacements: Replacements, new_name: string)`
*returns `Texture`*  
*see also [*Replacements*](#replacements) (type alias)*

Performs palette swapping on the provided PNG pack using the provided replacement rules. Returns a Figura Texture with the provided name and the modified texture data. This function is implemented with `transmute_raw`.

***

### `vec_of(hex)`
*returns `Vector4`*

Converts a hex color (`0xrrggbb`) into a Vector4 with 100% opacity (`vec(0xrr, 0xgg, 0xbb, 0xff)`).

***

### `vec_of_a(hex)`
*returns `Vector4`*

Converts a hex color with alpha (`0xrrggbbaa`) into a Vector4 (`vec(0xrr, 0xgg, 0xbb, 0xaa)`).

## Type Aliases

### *ColorReplacements*
A map between existing colors and new colors. In LuaLS, defined as `{[Vector4]: Vector4}`

### *Replacements*
A map between PNG palette slots and new colors to insert. In LuaLS, defined as `{[integer]: Vector4}`. Used in `transmute_direct` and `transmute_raw`.
