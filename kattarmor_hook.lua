-- provides on-demand textures to KattArmor trim sets
-- set up your custom materials before this.

local cm = require "colormagic.colormagic"
local schemes = require "colormagic.trim_data"

---@alias cm_ka.ColorReplacements {[Vector4]: Vector4}

---@class cm_ka.MaterialBinding
---@field normal cm_ka.ColorReplacements
---@field darker? cm_ka.ColorReplacements

---@class cm_ka.TrimBinding
---@field [1] colormagic.file_pack
---@field [2]? colormagic.file_pack

---@type {[string]: cm_ka.MaterialBinding}
local materials = {
    amethyst = {
        normal = schemes.amethyst,
    },
    copper = {
        normal = schemes.copper,
    },
    diamond = {
        normal = schemes.diamond,
        darker = schemes.diamond_darker,
    },
}

---@type {[string]: cm_ka.TrimBinding}
local trims = {
    bolt = {
        cm.load_raw(cm.fromBase64Chunked [[
        ]]),
    },
}

local nop_1 = function() return nil end

---@param __index table|fun(t: table, k: any): any
---@return fun(t: table, k: any): any
local function func_index(__index)
    return ({
        ["table"] = function(_, k)
            ---@cast __index table
            return __index[k]
        end,
        ["function"] = function(t, k)
            ---@cast __index fun(t: table, k: any): any
            return __index(t, k)
        end,
        ["nil"] = nop_1,
    })[type(__index)] or nop_1
end


--- you only have 128 texture slots, so we're going to eat {this number}
--- of them up front and re-use them. the minimum is 8, and the maximum is 255 (but really 128 on vanilla Figura)
local TEX_SLOTS = 32
-- if you for some reason have naming conflicts, you can change this
local namespace = "colormagic_kattarmor"


if TEX_SLOTS > 0xff then error "Too many texture slots (needs to be representable as 1 byte)" end

local texnames = {}
local texalloc = {}

local eviqueue_chunks = {}

local _char = string.char

for i = 1, TEX_SLOTS do
    local name = ("%s_%d"):format(namespace, i)
    texnames[i] = name
    texalloc[i] = textures:newTexture(name, 1, 1)
    eviqueue_chunks[#eviqueue_chunks + 1] = _char(i)
end

-- all the names in the order that we want to use them
-- it's a string because we can (ab)use gsub to pull items out without iterating
-- in Lua
local eviqueue = table.concat(eviqueue_chunks)

local pattern_esc = setmetatable({
    ["%"] = "%%",
    ["("] = "%(",
    [")"] = "%)",
    ["."] = "%.",
    ["["] = "%[",
    ["]"] = "%]",
    ["*"] = "%*",
    ["+"] = "%+",
    ["-"] = "%-",
    ["?"] = "%?",
    ["^"] = "%^",
    ["$"] = "%$",
}, {
    __index = function(t, k) return k end,
})

local texture_cache = {}
local id_to_cache_key = {}

local automap_cache = {}

---Bump a character to the end of the queue. Keeps in-use textures from being overwritten.
local function bump(idx)
    local c = _char(idx)
    eviqueue = c .. eviqueue:gsub(pattern_esc[c], "", 1)
end

---Pop the least recently used texture from the queue, and return its index. Also bumps.
local function pop()
    local c = eviqueue:sub(-1)
    eviqueue = c .. eviqueue:sub(1, -2)
    local i = c:byte()
    -- drop the texture from the cache so we don't start rendering the wrong thing
    texture_cache[id_to_cache_key[i]] = nil
    id_to_cache_key[i] = nil
    return c:byte()
end

local function LiveAccess(matID, patID, cacheBase)
    local template = trims[patID]
    local material = materials[matID]
    return setmetatable({}, {
        __index = function(t, layerID)
            local cacheid = cacheBase .. ":" .. layerID
            local cached = texture_cache[cacheid]
            if cached then
                bump(cached)
                return texalloc[cached]
            end
            local normalized_layer = layerID
            local is_darker = layerID > 2
            if is_darker then normalized_layer = normalized_layer - 2 end

            local template_layer = template[normalized_layer]
            if not template_layer then
                -- attempt to access layer2, but no layer2 template exists
                return nil
            end
            -- if the material doesn't have a darker variant, this fallbacks on the normal variant
            -- (Lua falsy ternary stuff)
            local material_layer = is_darker and material.darker or material.normal

            -- the automap cache is *never* evicted, so if the user does a lot of switching
            -- this can save time regenerating the automap
            local automap = automap_cache[cacheid]
            if not automap then
                automap = cm.automap(template_layer, material_layer)
                automap_cache[cacheid] = automap
            end

            local idx = pop()
            local tex = cm.transmute_direct(template_layer, automap, texnames[idx])
            texture_cache[cacheid] = idx
            -- this reference is needed so that if the texture gets evicted, the cache can invalidate correctly
            id_to_cache_key[idx] = cacheid
            texalloc[idx] = tex
            return tex
        end,
    })
end

-- we only really need to construct these once
local accessor_cache = {}

---@param kattarmor_inst KattArmor.Instance
return function(kattarmor_inst)
    for k, v in pairs(materials) do
        local mat = kattarmor_inst.TrimMaterials[k]
        ---@type metatable
        local mat_tex_meta = getmetatable(mat.textures) or {}
        local original_index = func_index(mat_tex_meta.__index)
        mat_tex_meta.__index = function(t, patternID)
            local cacheKey = k .. ":" .. patternID
            local cached = accessor_cache[cacheKey]
            if cached then
                return cached
            end

            if trims[patternID] then
                local accessor = LiveAccess(k, patternID, cacheKey)
                accessor_cache[cacheKey] = accessor
                return accessor
            end

            return original_index(t, patternID)
        end
    end
end
