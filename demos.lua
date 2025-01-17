---@type colormagic_u.module
local colormagic = require "./colormagic_unsafe"

_G.test_PNG = function()
    colormagic.pnginfo(resources:get("examplepng.png") --[[@as InputStream]])
end

local amethyst = {
    [2] = vec(0x9a, 0x5c, 0xc6, 0xff),
    [3] = vec(0x6c, 0x49, 0xaa, 0xff),
    [4] = vec(0x52, 0x36, 0x87, 0xff),
    [5] = vec(0x42, 0x27, 0x76, 0xff),
}
local gold = {
    [2] = vec(0xec, 0xd9, 0x3f, 0xb0),
    [3] = vec(0xde, 0xb1, 0x2d, 0xb0),
    [4] = vec(0xb1, 0x67, 0x12, 0xb0),
    [5] = vec(0xa0, 0x45, 0x0a, 0xb0)
}

_G.test_PNG2 = function()
    local before = avatar:getCurrentInstructions()
    local info = colormagic.load(resources:get("examplepng.png") --[[@as InputStream]])
    local after = avatar:getCurrentInstructions()
    print(after - before, "load instructions")

    local variants = {}

    before = avatar:getCurrentInstructions()
    local amethyst_v = colormagic.transmute_direct(info, amethyst, "amethyst_version")
    after = avatar:getCurrentInstructions()
    print(after - before, "instructions for amethyst")
    print("amethyst", amethyst_v)
    local gold_v = colormagic.transmute_direct(info, gold, "gold_version")
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
