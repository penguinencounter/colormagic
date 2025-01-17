# `colormagic` changelog

## v1.1.0 - `automap`
* feat: `colormagic.automap`: read color-to-color tables (type: `{[Vector4]: Vector4}`) and converts them to an appropriate palette replacement table.
* feat: `colormagic.pnginfo_raw` / `colormagic.load_raw`: load/info raw PNG data.
* feat: `colormagic.fromBase64Chunked`: converts base64 to binary, provides default buffer size if none is provided
* feat: `colormagic.vec_of`: accepts hex RGB color (in `0xabcdef` form) and converts it to a 0-255 vector with 100% opacity
* feat: `colormagic.vec_of_a`: accepts hex RGBA color (in `0xabcdefff` form) and converts it to a 0-255 vector
* feat(unsafe): made `toBase64Chunked`, `fromBase64Chunked` available
* extra: `trim_data.lua` provides color information for vanilla trim palettes, for use with `automap`. It doesn't use any of the `colormagic` APIs so it should be portable for other projects too.

## v1.0.0
* Initial release