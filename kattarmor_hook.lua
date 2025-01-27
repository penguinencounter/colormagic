-- provides on-demand textures to KattArmor trim sets
-- set up your custom materials before this.

local cm = require "colormagic.colormagic"
local schemes = require "colormagic.trim_data"

---@alias cm_ka.ColorReplacements {[Vector4]: Vector4}
---@alias cm_ka.layerid 1 | 2

---@class cm_ka.MaterialBinding 
---@field normal cm_ka.ColorReplacements
---@field darker cm_ka.ColorReplacements

---@class cm_ka.TrimBinding
---@field [1] colormagic.file_pack
---@field [2]? colormagic.file_pack

---@type {[string]: cm_ka.MaterialBinding}
local materials = {
    amethyst = {
        normal = schemes.amethyst,
        darker = schemes.amethyst
    },
    copper = {
        normal = schemes.copper,
        darker = schemes.copper
    },
    diamond = {
        normal = schemes.diamond,
        darker = schemes.diamond_darker
    }
}

local trims = {
    bolt = cm.load_raw [[
    ]]
}

local 

---@param kattarmor_inst KattArmor.Instance
return function (kattarmor_inst)
    for k, v in pairs(materials) do
        local mat = kattarmor_inst.TrimMaterials[k]
        local matt_meta = getmetatable(mat.textures) or {}
        local original_index = type(matt_meta.__index) == ""
    end
end