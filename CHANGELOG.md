# `colormagic` changelog

## v1.2.1 - bug fixes and size improvements
* feat: `colormagic_min.lua`. smaller footprint-ish, smaller featureset. based on `unsafe`.
    * `pnginfo` just prints a message about being unavailable
    * `toBase64Chunked` and `fromBase64Chunked` throw errors
* feat?: trimmed a bunch of stuff you don't need in production from `colormagic_unsafe`.
* fix: the AST compressor doesn't understand the nuances of CRLFs (also `\x` escape codes)
* docs: documentation as usual

## v1.2.0 - `load` from non-resource textures
* feat: `colormagic.load_avatar_tex` for imporing a texture by name (like the `textures` table, not `resources`), but only those bundled into the avatar data. Using this functionality *will work*, but will throw up a huge warning. **Please read the warning.**
* feat: `colormagic.load` now accepts a `string`, `InputStream`, or `Texture` and does an appropriate thing with it:
    * `string`: tries to load as raw PNG data (not base64!)
    * `InputStream`: tries to read the stream in its entirety and load it as raw PNG data
    * `Texture`: gets the name and passes it to `load_avatar_tex`

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