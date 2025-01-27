# A really short setup for armor trims
(You should read the README file first to understand what's going on here.)

```lua
local colormagic = require "colormagic"
local trim_data = require "trim_data"

local trim = colormagic.load(resources:get("trim.png"))
local trim_leggings = colormagic.load(resources:get("trim_leggings.png"))

local textured_trims = {}
```