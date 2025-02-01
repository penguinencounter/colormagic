---@type colormagic.module
local colormagic = require "./colormagic_unsafe"

---@type colormagic.extra.trim_data
local trims = require "./trim_data"

local hv = colormagic.vec_of

_G.test_PNG = function()
    colormagic.pnginfo(resources:get("examplepng.png") --[[@as InputStream]])
end

_G.test_PNG2 = function()
    local before = avatar:getCurrentInstructions()
    -- local info = colormagic.load(resources:get("examplepng.png") --[[@as InputStream]])
    local info = colormagic.load(textures.examplepng)
    local after = avatar:getCurrentInstructions()
    print(after - before, "load instructions")

    local variants = {}

    before = avatar:getCurrentInstructions()
    local amethyst_v = colormagic.transmute_direct(info, colormagic.automap(info, trims.amethyst), "amethyst_version")
    after = avatar:getCurrentInstructions()
    print(after - before, "instructions for amethyst")
    print("amethyst", amethyst_v)
    local gold_v = colormagic.transmute_direct(info, colormagic.automap(info, trims.gold), "gold_version")
    print("gold", gold_v)

    do
    local display = models:newPart("colormagic_disp", "HUD")
    local sprite = display:newSprite("sprite")
    local dim = amethyst_v:getDimensions()
    sprite:setTexture(amethyst_v, dim.x, dim.y)
    sprite:setPos(-180, -200, 0)
    sprite:setScale(4)
    end
    do
    local display = models:newPart("colormagic_disp2", "HUD")
    local sprite = display:newSprite("sprite")
    local dim = gold_v:getDimensions()
    sprite:setTexture(gold_v, dim.x, dim.y)
    sprite:setPos(-480, -200, 0)
    sprite:setScale(4)
    end
end

test_PNG()
test_PNG2()
