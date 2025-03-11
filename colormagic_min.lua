-- colormagic_min: port of unsafe but with less features

local byte, char = string.byte, string.char
local shl, bor, extr = bit32.lshift, bit32.bor, bit32.extract
local concat = table.concat
local floor = math.floor

---@param is InputStream
---@param buf_max integer
---@return string
local function readall(is, buf_max)
    -- not sure why 4P5's reader doesnt work (it reads 1 byte??), but this does
    -- construct a buffer to move data way faster; as long as buf_max is more than like 10, this costs less
    local buf = data:createBuffer(buf_max)
    local t = {}
    while is:available() > 0 do
        local n = buf:readFromStream(is)
        buf:setPosition(0)
        t[#t + 1] = buf:readByteArray(n)
    end
    buf:close()
    return table.concat(t)
end

--[[
potential optimizations:
- move away from shl/bor and instead multiply and add
]]

local important_chunks = {
    -- Pallete
    PLTE = true,
    -- Transparency data for pallete
    tRNS = true,
}

---@return integer
local function checkperms()
    ---@type integer
    local buf_max = avatar:getMaxBufferSize()
    --- a note: trying to create a buffer with the max size on MAX causes OOME so we arbitrarily limit it to 64k.
    --- if you want, you can increase this number for slight improvements when loading big (>64KiB) PNGs.
    --- The only time the max size is used to initialize the buffer is when loading the file, which reads in (MAX_SIZE) chunks.
    if buf_max > 65536 then buf_max = 65536 end
    if buf_max < 16 then error "insufficient buffer size" end
    local buf_remain = avatar:getMaxBuffersCount() - avatar:getBuffersCount()
    if buf_remain < 1 then
        if avatar:getMaxBuffersCount() == 0 then
            error "no buffers"
        else
            error "out of buffers"
        end
    end

    return buf_max
end

-- ast compressor sucks :(
local png_header = string.char(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)

---@param raw string
---@return integer cursor
local function validate(raw)
    -- Is this a PNG at all?
    assert(raw:sub(1, 8) == png_header, "Not a PNG (wrong header)")
    -- UNSAFE: don't check PNG header, just assume it's there and correct :)
    return 34
end

---@type {[string]: fun(buffer: Buffer, length: integer): any}
local pnginfo_chunk_actions = {}

--- returns integer RGB 0-255 colors, not 0-1 colors!!
---@return {[integer]: Vector4}
function pnginfo_chunk_actions.PLTE(buffer, length)
    ---@type {[integer]: Vector4}
    local mapping = {}
    if length % 3 ~= 0 then error "invalid PLTE size" end
    for i = 1, length / 3 do
        local r, g, b = buffer:read(), buffer:read(), buffer:read()
        mapping[i] = vec(r, g, b, 255)
    end
    return mapping
end

--- returns transparency data. any not defined here should be assumed to be 255.
---@return {[integer]: integer}
function pnginfo_chunk_actions.tRNS(buffer, length)
    ---@type {[integer]: integer}
    local mapping = {}
    for i = 1, length do
        mapping[i] = buffer:read()
    end
    return mapping
end

---@param raw string
local function pnginfo(raw)
    print("pnginfo is unavailable in the minified version")
end

---@class colormagic_m.locator
---@field d integer
---@field n integer
---@field c integer
---@field s integer

---@class colormagic_m.tRNS_locator : colormagic_m.locator
---@field z integer[]

---@class colormagic_m.file_pack
---@field PLTE colormagic_m.locator
---@field tRNS colormagic_m.tRNS_locator
---@field raw string
---@field hints {[string]: integer}?

---Prepare a PNG for editing. You only need to do this once per source texture.
---Try and keep the loc_pack around to avoid wasting instructions.
---@param raw string
---@return colormagic_m.file_pack
local function preparse_png(raw)
    local buf_max = checkperms()
    local cursor = validate(raw)

    ---@type colormagic_m.file_pack
    ---@diagnostic disable-next-line missing-fields
    local data = {
        raw = raw,
    }

    ---@type string, string, integer
    local size, kind, size_real
    ---@type integer, integer
    local data_start, crc_start
    while kind ~= "IEND" do
        size, kind, cursor = raw:match("(....)(....)()", cursor)
        local a, b, c, d = byte(size, 1, 4)
        size_real = bor(shl(a, 24), shl(b, 16), shl(c, 8), d)
        if important_chunks[kind] then
            -- UNSAFE: no multiple chunk checks
            data_start = cursor
            crc_start = cursor + size_real
            if size_real > buf_max then
                error("buf too small to load " .. kind)
            end
            -- unfortuantely the language server just doesn't understand that a union between two keys can narrow the type
            -- instead, suppress :(
            if kind == "tRNS" then
                data.tRNS = {
                    d = data_start,
                    n = crc_start + 4,
                    c = crc_start,
                    s = size_real,
                    z = { byte(raw, data_start, crc_start - 1) },
                }
            else
                ---@diagnostic disable-next-line: assign-type-mismatch
                data[kind] = {
                    d = data_start,
                    n = crc_start + 4,
                    c = crc_start,
                    s = size_real,
                }
            end
        end
        cursor = cursor + size_real + 4 -- crc
    end
    return data
end

---@param pack colormagic_m.file_pack
local function add_hints(pack)
    if pack.hints then return end
    local pal_data = {}
    local PLTE, tRNS = pack.PLTE, pack.tRNS
    local PLTEc = PLTE.s / 3
    for i = 1, PLTEc do
        local access = PLTE.d + (i - 1) * 3
        local r, g, b = byte(pack.raw, access, access + 2)
        pal_data[i] = vec(r, g, b, 255)
    end
    if tRNS then for i = 1, tRNS.s do
        pal_data[i].w = tRNS.z[i]
    end end
    ---@type {[string]: integer}
    local hints = {}
    for k, v in pairs(pal_data) do
        hints[tostring(v)] = k
    end
    pack.hints = hints
end

-- UNSAFE: NO CRC

---Base64 implementation supporting buffer sizes that are smaller than the input.
---@param bytes string
---@param max_buf integer
---@return string
local function toBase64Chunked(bytes, max_buf)
    error "toBase64Chunked unavailable in minimal version"
end


---Base64 implementation supporting buffer sizes that are smaller than the input.
---@param b64 string
---@param max_buf integer?
---@return string
local function fromBase64Chunked(b64, max_buf)
    error "fromBase64Chunked unavailable in minimal version"
end

---Converts source colors to pallete indexes.
---@param pack colormagic_m.file_pack
---@param color_replacements {[Vector4]: Vector4}
local function automap(pack, color_replacements)
    if not pack.hints then add_hints(pack) end
    local hints = pack.hints
    ---@type {[integer]: Vector4}
    local mapping = {}

    for src, dst in pairs(color_replacements) do
        local key = tostring(src)
        local index = hints[key]
        if index then
            mapping[index] = dst
        end
    end

    return mapping
end

---Does PNG magic rituals or something to convert colors.
---Uses RGBA 0-255 vectors, not 0-1 vectors.
---Returns a raw PNG string.
---@param pack colormagic_m.file_pack
---@param replacements {[integer]: Vector4}
---@return string
local function transmute(pack, replacements)
    local raw = pack.raw
    local new_trns = setmetatable({}, { __index = pack.tRNS.z })
    local trns_size = pack.tRNS.s
    for index, replace_with in pairs(replacements) do
        local byte_index = (index - 1) * 3
        raw = raw:sub(1, pack.PLTE.d + byte_index - 1) ..
            char(replace_with.x, replace_with.y, replace_with.z) ..
            raw:sub(pack.PLTE.d + byte_index + 3)
        local w = replace_with.w
        if index > trns_size then trns_size = index end
        if (new_trns[index] or 255) ~= w then
            new_trns[index] = w
        end
    end

    -- UNSAFE: CRC for PLTE should be here :P

    -- write the new tRNS chunk, if any changes have been made from the original
    if next(new_trns) then
        local trns_chunks = {}
        for i = 1, trns_size do
            trns_chunks[#trns_chunks + 1] = char(new_trns[i] or 255)
        end
        local new_trns_data = concat(trns_chunks)
        local crc_target = "tRNS" .. new_trns_data
        local chunk_size = #new_trns_data + 12
        local trns_out_buf = data:createBuffer(chunk_size)
        trns_out_buf:writeInt(#new_trns_data)
        trns_out_buf:writeByteArray(crc_target)
        -- UNSAFE: CRC for tRNS should be here
        trns_out_buf:writeInt(0)
        trns_out_buf:setPosition(0)
        
        -- this cuts the 8 bytes of length+tag from the original tRNS chunk
        raw = raw:sub(1, pack.tRNS.d - 9) ..
            trns_out_buf:readByteArray(chunk_size) ..
            raw:sub(pack.tRNS.n)
        trns_out_buf:close()
    end
    return raw
end

---@class colormagic_m.module
local exported_api = {}

exported_api.load_raw = preparse_png

---Load a PNG texture packaged with the avatar by name (the same as if you were indexing the `textures` global.)
---@param name string
---@return colormagic_m.file_pack
function exported_api.load_avatar_tex(name, suppressWarn)
    -- Load the texture from the avatar NBT if possible
    local nbt = avatar:getNBT()
    ---@type integer[]
    local texture_raw = nbt.textures.src[name]
    if not texture_raw then
        error "grab texture by name failed"
    end

    local chunks = {}
    for i = 1, #texture_raw do
        chunks[i] = char(texture_raw[i] % 256)
    end
    return preparse_png(concat(chunks))
end

---@alias colormagic_m.InFormat string | InputStream | Texture

---@type {[string]: fun(in: colormagic_m.InFormat, ...: any): colormagic_m.file_pack}
local loaders = {
    ["string"] = preparse_png,
    ---@param is InputStream
    ["InputStream"] = function(is)
        local max_buf = checkperms()
        local raw = readall(is, max_buf)
        is:close()
        return preparse_png(raw)
    end,
    ---@param tex Texture
    ---@param suppressWarn boolean
    ["Texture"] = function(tex, suppressWarn)
        return exported_api.load_avatar_tex(tex:getName(), suppressWarn)
    end,
}

---Load a PNG texture from a string, InputStream, or Texture object.
---@param input colormagic_m.InFormat
---@param ... any
function exported_api.load(input, ...)
    return (loaders[type(input)])(input, ...)
end

exported_api.pnginfo_raw = pnginfo
exported_api.pnginfo = pnginfo

exported_api.automap = automap

exported_api.toBase64Chunked = toBase64Chunked
exported_api.fromBase64Chunked = fromBase64Chunked

---Perform the palette editing and create a new Texture.
---
---**Watch out!** The vectors in the `replacements` table use 0 to 255 for color channels, not 0 to 1 (like the rest of Figura).
---@param pack colormagic_m.file_pack
---@param replacements {[integer]: Vector4}
---@param new_name string
---@return Texture
function exported_api.transmute_direct(pack, replacements, new_name)
    local raw = transmute(pack, replacements)
    local raw_tbl = {string.byte(raw, 1, #raw)}
    return textures:read(new_name, raw_tbl)
end

exported_api.transmute_raw = transmute

function exported_api.vec_of(hex)
    return vec(extr(hex, 16, 8), extr(hex, 8, 8), extr(hex, 0, 8), 0xff)
end
function exported_api.vec_of_a(hex)
    return vec(extr(hex, 24, 8), extr(hex, 16, 8), extr(hex, 8, 8), extr(hex, 0, 8))
end

return exported_api
