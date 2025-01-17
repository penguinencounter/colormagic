-- colormagic: super-fast pallete swaps for indexed PNGs

local byte, char = string.byte, string.char
local shl, shr, bor, xor, bnot, band, extr = bit32.lshift, bit32.rshift, bit32.bor, bit32.bxor, bit32.bnot, bit32.band, bit32.extract
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

    -- Read the IHDR chunk.
    local cursor = 9
    local size, kind
    size, kind, cursor = raw:match("(....)(....)()", cursor)
    local a, b, c, d = byte(size, 1, 4)
    local size_real = bor(shl(a, 24), shl(b, 16), shl(c, 8), d)
    assert(kind == "IHDR", "Invalid PNG: IHDR chunk missing")

    local header_buf = data:createBuffer(size_real)
    header_buf:writeByteArray(raw:sub(cursor, cursor + size_real - 1))
    header_buf:setPosition(0)
    local width, height, bit_depth, color_type =
        header_buf:readInt(), header_buf:readInt(), header_buf:read(), header_buf:read()
    header_buf:close()

    cursor = cursor + size_real + 4 -- crc

    assert(color_type == 3,
        "This PNG isn't using indexed color mode.\n(Please read the documentation for more details on how to use this library.)")
    return cursor
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
    ---@type integer, integer
    local data_start
    while kind ~= "IEND" do
        size, kind, cursor = raw:match("(....)(....)()", cursor)
        local a, b, c, d = byte(size, 1, 4)
        size_real = bor(shl(a, 24), shl(b, 16), shl(c, 8), d)
        if important_chunks[kind] then
            if chunk_data[kind] then error("Invalid PNG: multiple " .. kind .. " chunks") end
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

---@class colormagic.locator
---@field data_at integer
---@field next_at integer
---@field crc_at integer
---@field size integer

---@class colormagic.tRNS_locator : colormagic.locator
---@field data integer[]

---@class colormagic.file_pack
---@field PLTE colormagic.locator
---@field tRNS colormagic.tRNS_locator
---@field raw string
---@field hints {[string]: integer}?

---Prepare a PNG for editing. You only need to do this once per source texture.
---Try and keep the loc_pack around to avoid wasting instructions.
---@param raw string
---@return colormagic.file_pack
local function preparse_png(raw)
    local buf_max = checkperms()

    local cursor = validate(raw)

    ---@type colormagic.file_pack
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
            if data[kind] then error("Invalid PNG: multiple " .. kind .. " chunks") end
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
    if not data.tRNS then error "Images need to have transparency for now :( (no tRNS chunk)" end
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

-- big block of magic numbers for crc32 (263 inst via luac.nl)
-- special thanks: https://wiki.osdev.org/CRC32
local poly8_lookup = {
    [0] = 0, 0x77073096, 0xEE0E612C, 0x990951BA, 0x076DC419, 0x706AF48F, 0xE963A535, 0x9E6495A3,
    0x0EDB8832, 0x79DCB8A4, 0xE0D5E91E, 0x97D2D988, 0x09B64C2B, 0x7EB17CBD, 0xE7B82D07, 0x90BF1D91,
    0x1DB71064, 0x6AB020F2, 0xF3B97148, 0x84BE41DE, 0x1ADAD47D, 0x6DDDE4EB, 0xF4D4B551, 0x83D385C7,
    0x136C9856, 0x646BA8C0, 0xFD62F97A, 0x8A65C9EC, 0x14015C4F, 0x63066CD9, 0xFA0F3D63, 0x8D080DF5,
    0x3B6E20C8, 0x4C69105E, 0xD56041E4, 0xA2677172, 0x3C03E4D1, 0x4B04D447, 0xD20D85FD, 0xA50AB56B,
    0x35B5A8FA, 0x42B2986C, 0xDBBBC9D6, 0xACBCF940, 0x32D86CE3, 0x45DF5C75, 0xDCD60DCF, 0xABD13D59,
    0x26D930AC, 0x51DE003A, 0xC8D75180, 0xBFD06116, 0x21B4F4B5, 0x56B3C423, 0xCFBA9599, 0xB8BDA50F,
    0x2802B89E, 0x5F058808, 0xC60CD9B2, 0xB10BE924, 0x2F6F7C87, 0x58684C11, 0xC1611DAB, 0xB6662D3D,
    0x76DC4190, 0x01DB7106, 0x98D220BC, 0xEFD5102A, 0x71B18589, 0x06B6B51F, 0x9FBFE4A5, 0xE8B8D433,
    0x7807C9A2, 0x0F00F934, 0x9609A88E, 0xE10E9818, 0x7F6A0DBB, 0x086D3D2D, 0x91646C97, 0xE6635C01,
    0x6B6B51F4, 0x1C6C6162, 0x856530D8, 0xF262004E, 0x6C0695ED, 0x1B01A57B, 0x8208F4C1, 0xF50FC457,
    0x65B0D9C6, 0x12B7E950, 0x8BBEB8EA, 0xFCB9887C, 0x62DD1DDF, 0x15DA2D49, 0x8CD37CF3, 0xFBD44C65,
    0x4DB26158, 0x3AB551CE, 0xA3BC0074, 0xD4BB30E2, 0x4ADFA541, 0x3DD895D7, 0xA4D1C46D, 0xD3D6F4FB,
    0x4369E96A, 0x346ED9FC, 0xAD678846, 0xDA60B8D0, 0x44042D73, 0x33031DE5, 0xAA0A4C5F, 0xDD0D7CC9,
    0x5005713C, 0x270241AA, 0xBE0B1010, 0xC90C2086, 0x5768B525, 0x206F85B3, 0xB966D409, 0xCE61E49F,
    0x5EDEF90E, 0x29D9C998, 0xB0D09822, 0xC7D7A8B4, 0x59B33D17, 0x2EB40D81, 0xB7BD5C3B, 0xC0BA6CAD,
    0xEDB88320, 0x9ABFB3B6, 0x03B6E20C, 0x74B1D29A, 0xEAD54739, 0x9DD277AF, 0x04DB2615, 0x73DC1683,
    0xE3630B12, 0x94643B84, 0x0D6D6A3E, 0x7A6A5AA8, 0xE40ECF0B, 0x9309FF9D, 0x0A00AE27, 0x7D079EB1,
    0xF00F9344, 0x8708A3D2, 0x1E01F268, 0x6906C2FE, 0xF762575D, 0x806567CB, 0x196C3671, 0x6E6B06E7,
    0xFED41B76, 0x89D32BE0, 0x10DA7A5A, 0x67DD4ACC, 0xF9B9DF6F, 0x8EBEEFF9, 0x17B7BE43, 0x60B08ED5,
    0xD6D6A3E8, 0xA1D1937E, 0x38D8C2C4, 0x4FDFF252, 0xD1BB67F1, 0xA6BC5767, 0x3FB506DD, 0x48B2364B,
    0xD80D2BDA, 0xAF0A1B4C, 0x36034AF6, 0x41047A60, 0xDF60EFC3, 0xA867DF55, 0x316E8EEF, 0x4669BE79,
    0xCB61B38C, 0xBC66831A, 0x256FD2A0, 0x5268E236, 0xCC0C7795, 0xBB0B4703, 0x220216B9, 0x5505262F,
    0xC5BA3BBE, 0xB2BD0B28, 0x2BB45A92, 0x5CB36A04, 0xC2D7FFA7, 0xB5D0CF31, 0x2CD99E8B, 0x5BDEAE1D,
    0x9B64C2B0, 0xEC63F226, 0x756AA39C, 0x026D930A, 0x9C0906A9, 0xEB0E363F, 0x72076785, 0x05005713,
    0x95BF4A82, 0xE2B87A14, 0x7BB12BAE, 0x0CB61B38, 0x92D28E9B, 0xE5D5BE0D, 0x7CDCEFB7, 0x0BDBDF21,
    0x86D3D2D4, 0xF1D4E242, 0x68DDB3F8, 0x1FDA836E, 0x81BE16CD, 0xF6B9265B, 0x6FB077E1, 0x18B74777,
    0x88085AE6, 0xFF0F6A70, 0x66063BCA, 0x11010B5C, 0x8F659EFF, 0xF862AE69, 0x616BFFD3, 0x166CCF45,
    0xA00AE278, 0xD70DD2EE, 0x4E048354, 0x3903B3C2, 0xA7672661, 0xD06016F7, 0x4969474D, 0x3E6E77DB,
    0xAED16A4A, 0xD9D65ADC, 0x40DF0B66, 0x37D83BF0, 0xA9BCAE53, 0xDEBB9EC5, 0x47B2CF7F, 0x30B5FFE9,
    0xBDBDF21C, 0xCABAC28A, 0x53B39330, 0x24B4A3A6, 0xBAD03605, 0xCDD70693, 0x54DE5729, 0x23D967BF,
    0xB3667A2E, 0xC4614AB8, 0x5D681B02, 0x2A6F2B94, 0xB40BBE37, 0xC30C8EA1, 0x5A05DF1B, 0x2D02EF8D,
}

---@param bytes string
local function crc32(bytes)
    local crc = 0xffffffff
    for i = 1, #bytes do
        crc = xor(
            poly8_lookup[xor(band(crc, 0xff), bytes:sub(i, i):byte())],
            shr(crc, 8)
        )
    end
    return bnot(crc)
end

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
---@param pack colormagic.file_pack
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

    -- crc the new PLTE data
    local plte_data = raw:sub(pack.PLTE.data_at, pack.PLTE.crc_at - 1)
    local plte_crc = crc32("PLTE" .. plte_data)
    local crc_buf = data:createBuffer(4)
    -- todo: optimize w/ math?
    crc_buf:writeInt(plte_crc)
    crc_buf:setPosition(0)
    raw = raw:sub(1, pack.PLTE.crc_at - 1) ..
        crc_buf:readByteArray(4) ..
        raw:sub(pack.PLTE.crc_at + 4)
    crc_buf:close()

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
        trns_out_buf:writeInt(crc32(crc_target))
        trns_out_buf:setPosition(0)
        
        -- this cuts the 8 bytes of length+tag from the original tRNS chunk
        raw = raw:sub(1, pack.tRNS.data_at - 9) ..
            trns_out_buf:readByteArray(chunk_size) ..
            raw:sub(pack.tRNS.next_at)
        trns_out_buf:close()
    end
    return raw
end

---@class colormagic.module
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
---@param pack colormagic.file_pack
---@param replacements {[integer]: Vector4}
---@param new_name string
---@return Texture
function exported_api.transmute_direct(pack, replacements, new_name)
    local raw = transmute(pack, replacements)
    -- yay stack
    local raw_tbl = {string.byte(raw, 1, #raw)}
    -- wow amazing WHY DOESN'T THIS FUNCTION ACCEPT RAW BYTES
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
