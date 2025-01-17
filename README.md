# `colormagic`: cheap palette swaps for Figura

> *Sounds cursed. I like it!* - Katt

> ## This library is intended for people who are already familiar with scripting.

`colormagic` is a Lua package designed for doing exactly one thing:

**Replacing colors in** (some) **textures.** (usually these are armor trims that people want to palette swap)

Normally, this either involves a really complicated matrix (only supports up to 3 colors) or `applyFunc`, which costs at least 5 instructions per pixel. Because armor textures are almost always 2048 pixels, that adds up fast (you can barely fit one in the Init phase on Default permissions)

This library promises to do it in **way fewer instructions**. As a test, I re-colored the Bolt armor trim texture (64x32) for only 430 instructions\*. That's approximately 0.2 instructions per pixel.

\* using Unsafe mode, 258+172

## 1. Required Behind-the-Scenes Knowledge

This library does a whole lot of cursed stuff behind the scenes. The short version is that it's editing the **raw PNG data** of the image.

For this to work, the image needs to use **indexed color**.

### 1.1. Indexed Color

Indexed/Quantized/Paletted Color is a color mode for PNGs where each color references a fixed palette. I personally used GIMP to convert images to indexed color.

> [!TIP]  
> Many vanilla textures already use indexed color! You can try using those by downloading them directly from your game files, or https://github.com/misode/mcmeta/tree/assets. For example, the armor trims already have indexed color (very convenient!)

> [!TIP]  
> Bonus: If you've compressed your PNGs using an external tool, there's a chance that you already have Indexed Color enabled - try using the code from section 4.2 with your image to see if it is.

You'll need to make sure that you're using a PNG with Indexed Color for this library to work. In GIMP, you can convert an image to Indexed Color by going to `Image > Mode > Indexed...`. This will bring up a dialog asking how to convert the image's colors - if you have more than 256 colors (ouch...) this might change some colors in your image (!).
Otherwise, the defaults work well.

### 1.2. How It Works (actual)
The library rewrites the palette data from the image, and then loads it into the game at runtime. This involves finding the palette data in the PNG file and splicing together something that works.

## 2. What's In The Package
The package comes with two library files:

### 2.1. `colormagic.lua`
This is the main "development" library file. You should work with this while developing your avatar. It is quite a bit cheaper than any other methods of palette swapping, and produces specification-compliant PNG data. **It will also check your inputs to make sure they make sense.**

> [!NOTE]  
> `toBase64Chunked` is only available in this variant. It was intended for debugging and viewing the output PNGs in external applications. As you'll see, this isn't very useful for the other file.

### 2.2. `colormagic_unsafe.lua`
This version uses even *more* hacky techniques to trim down the instruction count. It doesn't produce spec-compliant PNG data because it completely ignores the checksums in the file (becuase Minecraft ignores them too, so it's fine.) **This version contains little to no error checking.** (There's still checks that the maximum buffer size is sufficent, etc - but passing an invalid PNG will cause problems!) There's also no `toBase64Chunked`.

Once you're done developing your avatar's features that need the library, it should be as simple as switching the `require "colormagic"` to `require "colormagic_unsafe"`. The rest of the user-facing API is the same.

Of course, using the Unsafe API is completely optional. If you don't want to use it, you don't have to.

> [!WARNING]  
> **Please avoid asking for support if you use the Unsafe API while devloping your avatar.** (If the two APIs don't have parity for some reason, please report that as a bug.)

## 3. Installation
Drop the two lua files somewhere in your avatar.

Use the following to use the library in your script:
```lua
local colormagic = require "colormagic"
```

## 4. Usage

**Don't link the target texture to a Blockbench model!** You should use the Resource API instead. Because nobody ever uses the Resource API, here's a tutorial:

> [!WARNING]  
> If you link the texture to a Blockbench model, it'll be bundled twice, which will cost you avatar space.

### 4.1. The Resource API
In `avatar.json`, there's a field named `resources` (you might need to create it.) It's a list of paths to files to bundle alongside your avatar data.

```json
{
    "resources": [
        "trim.png"
    ]
}
```

To access these files with Lua, use the `resources:get(name)` function. It returns an `InputStream`.

```lua
local trim = resources:get("trim.png")
```

`colormagic` takes `InputStream` objects as input. You can pass the `InputStream` directly to the library. (Passing a `string` containing the raw data or a `Texture` is not supported.)

### 4.2. Image Analysis

To swap colors, you need to know what slot each color is in. There is a handy tool in both `colormagic` and `colormagic_unsafe` named `colormagic.pnginfo` that can show you the colors in the palette.

Simply call `pnginfo(input_stream)` to print a list of colors and indexes:

```lua
-- prints "PNG Palette Info" table
colormagic.pnginfo(resources:get("trim.png"))
```

### 4.3. Image Loading

`colormagic` loads images in two phases: `load` and `transmute`.

To load an image, use `colormagic.load(input_stream)`:

```lua
local img_pack = colormagic.load(resources:get("trim.png"))
```

This returns a "colormagic file pack" that contains the entire texture data, as well as some location data that will make editing the image faster.

You only need to load an image once - you can re-use the pack to generate families of images (e.g. every material for an armor trim texture).

### 4.4 Replacements
To perform a palette swap, we need to know what colors to switch to! The `replacements` table is a mapping of palette slots (see section 4.2) to new colors (in the form of Vector4s).

**These Vector4s use 0 to 255 as the color range, not 0 to 1!** Don't get it mixed up! Providing floating point values may error or completely break the image. Each Vector4 is in the order of R, G, B, A.

```lua
-- see section 4.2 for what's going on with the left side of this table
-- amethyst replacement set
local amethyst_repl = {
    [2] = vec(0x9a, 0x5c, 0xc6, 0xff),
    [3] = vec(0x6c, 0x49, 0xaa, 0xff),
    [4] = vec(0x52, 0x36, 0x87, 0xff),
    [5] = vec(0x42, 0x27, 0x76, 0xff),
}
```

### 4.5 Palette Swapping
To perform the palette swap, use `colormagic.transmute_direct(img_pack, replacements, new_texture_name)`. This will return a new `Texture` with the colors replaced.

```lua
-- trim, amethyst variant
local amethyst = colormagic.transmute_direct(img_pack, amethyst_repl, "amethyst_version")
```

Congratulations! You're done. Use the texture wherever you want.

## 5. Known Issues
* not sure what will happen if an image doesn't have transparency data. adding transparency data definitely won't work though
