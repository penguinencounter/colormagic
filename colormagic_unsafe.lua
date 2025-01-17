-- colormagic_unsafe: super-fast pallete swaps for indexed PNGs
-- this version abuses Minecraft's PNG lenience to avoid any of the CRC stuff, too!
-- It also WON'T CATCH YOUR ERRORS (e.g. providing a PNG that's not in indexed mode), so try
-- the non-unsafe version when developing first, please.

local byte, char = string.byte, string.char
local shl, bor = bit32.lshift, bit32.bor
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
    if buf_max < 16 then error "Insufficient permissions to load a PNG. Try increasing the maximum buffer size." end
    local buf_remain = avatar:getMaxBuffersCount() - avatar:getBuffersCount()
    if buf_remain < 1 then
        if avatar:getMaxBuffersCount() == 0 then
            error "Cannot load PNG: not allowed to create a buffer"
        else
            error "Cannot load PNG: all buffers already in use elsewhere"
        end
    end

    return buf_max
end

---@param raw string
---@return integer cursor
local function validate(raw)
    -- Is this a PNG at all?
    assert(raw:sub(1, 8) == "\x89PNG\x0d\x0a\x1a\x0a", "Not a PNG (wrong header)")

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
    if length % 3 ~= 0 then error "Invalid PNG: palette is an invalid size (not a multiple of 3)" end
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
    local buf_max = checkperms()

    local cursor = validate(raw)

    local chunk_data = {}

    ---@type string, string, integer
    local size, kind, size_real
    ---@type integer
    local data_start
    while kind ~= "IEND" do
        size, kind, cursor = raw:match("(....)(....)()", cursor)
        local a, b, c, d = byte(size, 1, 4)
        size_real = bor(shl(a, 24), shl(b, 16), shl(c, 8), d)
        if important_chunks[kind] then
            data_start = cursor
            if size_real > buf_max then
                error("Cannot load PNG: Insufficient buffer size for " ..
                    kind .. " chunk data")
            end
            local data_buf = data:createBuffer(size_real)
            data_buf:writeByteArray(raw:sub(data_start, data_start + size_real - 1))
            data_buf:setPosition(0)
            chunk_data[kind] = (pnginfo_chunk_actions[kind] or error "Internal error: no chunk handler")(
                data_buf, size_real)
            data_buf:close()
        end
        cursor = cursor + size_real + 4 -- crc
    end

    local PLTE, tRNS = chunk_data.PLTE, chunk_data.tRNS
    -- this is required for the color mode we're using, see validate()
    if not PLTE then error "no PLTE chunk in this image" end
    -- tRNS is optional, so it is technically legal to not have one
    if not tRNS then tRNS = {} end
    for k, v in pairs(tRNS) do
        if not PLTE[k] then error "Invalid PNG: more tRNS values than PLTE entries" end
        PLTE[k].w = v
    end
    printJson(toJson {
        text = "PNG Palette Info\n",
        underlined = true,
        color = "green",
    })
    for k, v in ipairs(PLTE) do
        local col = ("#%02x%02x%02x%02x"):format(v.x, v.y, v.z, v.w)
        local col_noalpha = ("#%02x%02x%02x"):format(v.x, v.y, v.z)
        printJson(toJson {
            {
                text = "id " .. k,
                color = "aqua",
            },
            { text = " : ", color = "gray" },
            {
                text = col,
                color = col_noalpha,
                hoverEvent = {
                    action = "show_text",
                    value = {
                        text = col,
                        color = "white",
                    },
                },
            },
            "\n",
        })
    end
end

---@class colormagic_u.locator
---@field data_at integer
---@field next_at integer
---@field crc_at integer
---@field size integer

---@class colormagic_u.tRNS_locator : colormagic_u.locator
---@field data integer[]

---@class colormagic_u.file_pack
---@field PLTE colormagic.locator
---@field tRNS colormagic.tRNS_locator
---@field raw string
---@field hints {[string]: integer}?

---Prepare a PNG for editing. You only need to do this once per source texture.
---Try and keep the loc_pack around to avoid wasting instructions.
---@param raw string
---@return colormagic_u.file_pack
local function preparse_png(raw)
    local buf_max = checkperms()
    local cursor = validate(raw)

    ---@type colormagic_u.file_pack
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
                error("Cannot load PNG: Insufficient buffer size for " ..
                    kind .. " chunk data")
            end
            -- unfortuantely the language server just doesn't understand that a union between two keys can narrow the type
            -- instead, suppress :(
            if kind == "tRNS" then
                data.tRNS = {
                    data_at = data_start,
                    next_at = crc_start + 4,
                    crc_at = crc_start,
                    size = size_real,
                    data = { byte(raw, data_start, crc_start - 1) },
                }
            else
                ---@diagnostic disable-next-line: assign-type-mismatch
                data[kind] = {
                    data_at = data_start,
                    next_at = crc_start + 4,
                    crc_at = crc_start,
                    size = size_real,
                }
            end
        end
        cursor = cursor + size_real + 4 -- crc
    end
    return data
end

---@param pack colormagic.file_pack
local function add_hints(pack)
    if pack.hints then return end
    local pal_data = {}
    local PLTE, tRNS = pack.PLTE, pack.tRNS
    local PLTEc = PLTE.size / 3
    for i = 1, PLTEc do
        local access = PLTE.data_at + (i - 1) * 3
        local r, g, b = byte(pack.raw, access, access + 2)
        pal_data[i] = vec(r, g, b, 255)
    end
    if tRNS then for i = 1, tRNS.size do
        pal_data[i].w = tRNS.data[i]
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
    -- in base64, 3 bytes = 4 characters exactly. so, if we don't have enough space, round down to a multiple of 3
    local sizeof = #bytes
    if sizeof <= max_buf then
        -- do normal conversion
        local buffer = data:createBuffer(sizeof)
        buffer:writeByteArray(bytes)
        buffer:setPosition(0)
        local result = buffer:readBase64(sizeof)
        buffer:close()
        return result
    end
    local chunk_count = floor(max_buf / 3)
    local nearest_mult = chunk_count * 3
    local cursor = 1
    local chunks = {}
    for i = 1, chunk_count do
        local buffer = data:createBuffer(nearest_mult)
        local read = buffer:writeByteArray(bytes:sub(cursor, cursor + nearest_mult - 1))
        cursor = cursor + nearest_mult
        buffer:setPosition(0)
        chunks[#chunks+1] = buffer:readBase64(read)
        buffer:close()
    end
    return concat(chunks)
end


---Base64 implementation supporting buffer sizes that are smaller than the input.
---@param b64 string
---@param max_buf integer?
---@return string
local function fromBase64Chunked(b64, max_buf)
    max_buf = max_buf or 65536
    local sizeof = #b64
    local sizeof_out = floor(sizeof / 4) * 3
    if sizeof_out <= max_buf then
        local buffer = data:createBuffer(sizeof_out)
        buffer:writeBase64(b64)
        buffer:setPosition(0)
        local result = buffer:readByteArray(sizeof_out)
        buffer:close()
        return result
    end

    local chunk_count = floor(max_buf / 3)
    local nearest_mult = chunk_count * 3
    local nearest_input = chunk_count * 4
    local cursor = 1
    local chunks = {}
    for i = 1, chunk_count do
        local buffer = data:createBuffer(nearest_mult)
        local read = buffer:writeBase64(b64:sub(cursor, cursor + nearest_input - 1))
        cursor = cursor + nearest_input
        buffer:setPosition(0)
        chunks[#chunks+1] = buffer:readByteArray(read)
        buffer:close()
    end
    return concat(chunks)
end

---Converts source colors to pallete indexes.
---@param pack colormagic.file_pack
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
---@param pack colormagic_u.file_pack
---@param replacements {[integer]: Vector4}
---@return string
local function transmute(pack, replacements)
    local raw = pack.raw
    local new_trns = setmetatable({}, { __index = pack.tRNS.data })
    local trns_size = pack.tRNS.size
    for index, replace_with in pairs(replacements) do
        local byte_index = (index - 1) * 3
        raw = raw:sub(1, pack.PLTE.data_at + byte_index - 1) ..
            char(replace_with.x, replace_with.y, replace_with.z) ..
            raw:sub(pack.PLTE.data_at + byte_index + 3)
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
        raw = raw:sub(1, pack.tRNS.data_at - 9) ..
            trns_out_buf:readByteArray(chunk_size) ..
            raw:sub(pack.tRNS.next_at)
        trns_out_buf:close()
    end
    return raw
end

---@class colormagic_u.module
local exported_api = {}

exported_api.load_raw = preparse_png
function exported_api.load(is)
    local max_buf = checkperms()
    local raw = readall(is, max_buf)
    is:close()
    return preparse_png(raw)
end

exported_api.pnginfo_raw = pnginfo
function exported_api.pnginfo(is)
    local max_buf = checkperms()
    local raw = readall(is, max_buf)
    is:close()
    return pnginfo(raw)
end

exported_api.automap = automap

exported_api.toBase64Chunked = toBase64Chunked
exported_api.fromBase64Chunked = fromBase64Chunked

---Perform the palette editing and create a new Texture.
---
---**Watch out!** The vectors in the `replacements` table use 0 to 255 for color channels, not 0 to 1 (like the rest of Figura).
---@param pack colormagic_u.file_pack
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
