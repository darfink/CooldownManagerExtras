-- Icon and bar styling (Skin.lua).
local T = ...

local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"

local function regionsOf(frame, objectType)
	local out = {}
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:GetObjectType() == objectType then out[#out + 1] = r end
	end
	return out
end
local function overlayRegion(item)
	for _, r in ipairs(regionsOf(item, "Texture")) do
		if r:GetAtlas() == OVERLAY_ATLAS then return r end
	end
end
-- the 4-edge border frame Skin builds (a child Frame with 4 textures)
local function borderFrame(target, H)
	for _, child in ipairs({ target:GetChildren() }) do
		if child:GetObjectType() == "Frame" and #regionsOf(child, "Texture") == 4 then return child end
	end
end

T.test("skin: Tracked Bars 'square' bar style hides BarBG (alpha 0)", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	local bg = item.Bar.BarBG
	T.eq(bg:GetAlpha(), 1, "blizzard look keeps the background art")
	H.CMP:Set("BuffBar", "barStyle", "square")
	T.eq(bg:GetAlpha(), 0, "BarBG hidden")
end)

T.test("skin: ... and restores it when set back to blizzard", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	local bg = item.Bar.BarBG
	H.CMP:Set("BuffBar", "barStyle", "square")
	T.eq(bg:GetAlpha(), 0)
	H.CMP:Set("BuffBar", "barStyle", "blizzard")
	T.eq(bg:GetAlpha(), 1, "BarBG restored")
end)

T.test("skin: square bars get a plain background texture and a border, removed again on blizzard", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	local bar = item.Bar
	H.CMP:Set("BuffBar", "barStyle", "square")
	local back
	for _, r in ipairs(regionsOf(bar, "Texture")) do
		if H.state(r).color then back = r end
	end
	T.truthy(back and back:IsShown(), "dark background texture")
	local border = borderFrame(bar, H)
	T.truthy(border and border:IsShown(), "border frame shown (border size 1)")
	H.CMP:Set("BuffBar", "barStyle", "blizzard")
	T.falsy(back:IsShown())
	T.falsy(border:IsShown())
end)

T.test("skin: a new Tracked Bars item acquired later is styled too", function(H, T)
	H.CMP:Set("BuffBar", "barStyle", "square")
	local item = H.viewers.BuffBar:AddItem({ spellID = 101 })
	H.viewers.BuffBar:RefreshData()
	T.eq(item.Bar.BarBG:GetAlpha(), 0)
end)

T.test("skin: bar border size 0 hides the border", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	H.CMP:Set("BuffBar", "barStyle", "square")
	H.CMP:Set("BuffBar", "barBorderSize", 0)
	local border = borderFrame(item.Bar, H)
	T.falsy(border and border:IsShown())
end)

T.test("skin: square icons lose the mask and overlay art, are cropped and get a border; blizzard restores", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = 100 })
	T.eq(item.Icon:GetNumMaskTextures(), 1)
	H.CMP:Set("Essential", "style", "square")
	T.eq(item.Icon:GetNumMaskTextures(), 0, "rounded mask removed")
	T.eq(overlayRegion(item):GetAlpha(), 0, "frame art hidden")
	local l, r, t, b = select(1, item.Icon:GetTexCoord()), select(3, item.Icon:GetTexCoord()), nil, nil
	T.truthy(select(1, item.Icon:GetTexCoord()) > 0, "icon cropped by the zoom setting")
	local border = borderFrame(item, H)
	T.truthy(border and border:IsShown(), "pixel border")
	T.eq(H.state(item.Cooldown).swipeTexture, "Interface\\Buttons\\WHITE8X8", "square swipe")
	H.CMP:Set("Essential", "style", "blizzard")
	T.eq(item.Icon:GetNumMaskTextures(), 1, "mask is back")
	T.eq(overlayRegion(item):GetAlpha(), 1)
	T.eq(select(1, item.Icon:GetTexCoord()), 0)
	T.eq(H.state(item.Cooldown).swipeTexture, "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	T.falsy(border:IsShown(), "border hidden")
end)

T.test("skin: a per-spell border colour draws a border on a blizzard-style icon", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = 100 })
	T.falsy(borderFrame(item, H) and borderFrame(item, H):IsShown())
	H.CMP:SetSpellStyle(100, "color", { r = 1, g = 0, b = 0, a = 1 })
	local border = borderFrame(item, H)
	T.truthy(border and border:IsShown(), "border shown")
	H.CMP:ClearSpellStyle(100)
	T.falsy(border:IsShown(), "and removed with the style")
end)

T.test("skin: Masque owning the icons keeps our square style away from mask and art", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = 100 })
	H.registerLib("Masque", { GetGroupByID = function() end })
	rawset(item, "_MSQ_CFG", {}) -- Masque registered this button
	H.CMP:Set("Essential", "style", "square")
	T.eq(H.CMP:IconStyle(H.CMP.byKey.Essential), "masque")
	T.eq(item.Icon:GetNumMaskTextures(), 1, "mask untouched")
	T.eq(overlayRegion(item):GetAlpha(), 1)
end)

T.test("skin: PRD square style hides the bars' background art and restores it", function(H, T)
	local prd = H.viewers.PRD
	local bars = { prd.HealthBarsContainer.healthBar, prd.PowerBar, prd.AlternatePowerBar }
	local function bgs(bar)
		local out = {}
		for _, r in ipairs(regionsOf(bar, "Texture")) do
			if r:GetAtlas() == "UI-HUD-CoolDownManager-Bar-BG" then out[#out + 1] = r end
		end
		return out
	end
	T.truthy(#bgs(bars[2]) > 0)
	H.CMP:Set("PRD", "style", "square")
	for _, bar in ipairs(bars) do
		for _, bg in ipairs(bgs(bar)) do T.eq(bg:GetAlpha(), 0) end
	end
	H.CMP:Set("PRD", "style", "blizzard")
	for _, bar in ipairs(bars) do
		for _, bg in ipairs(bgs(bar)) do T.eq(bg:GetAlpha(), 1) end
	end
end)

-- Blizzard's debuff-type ring (Magic blue, Curse purple, ...) sticks out of square icons.
local function debuffRing(H, item, atlas)
	H.atlases[atlas] = true
	item.DebuffBorder.Texture:SetAtlas(atlas)
	item.DebuffBorder:Show()
	item.DebuffBorder.Texture:Show()
end
-- our copy of the ring: a child frame of the item with one texture showing that atlas
local function ringCopy(item, atlas)
	for _, child in ipairs({ item:GetChildren() }) do
		if child ~= item.DebuffBorder and child:GetObjectType() == "Frame" then
			local regions = regionsOf(child, "Texture")
			if #regions == 1 and regions[1]:GetAtlas() == atlas then return child end
		end
	end
end
local MAGIC = "ui-debuff-border-magic-noicon"

T.test("skin: square icons hide Blizzard's debuff ring and show its art on the square edge", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	H.CMP:Set("BuffIcon", "style", "square")
	T.eq(item.DebuffBorder:GetAlpha(), 0, "Blizzard's ring hidden")
	local copy = ringCopy(item, MAGIC)
	T.truthy(copy and copy:IsShown(), "our copy shows the same art")
	H.CMP:Set("BuffIcon", "style", "blizzard")
	T.eq(item.DebuffBorder:GetAlpha(), 1, "ring back")
	T.falsy(copy:IsShown(), "copy gone")
end)

T.test("skin: no debuff (ring hidden) = no copy", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	item.DebuffBorder:Hide()
	H.CMP:Set("BuffIcon", "style", "square")
	local copy = ringCopy(item, MAGIC)
	T.falsy(copy and copy:IsShown())
end)

T.test("skin: the ring copy works when the atlas is secret (combat)", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	local texture = item.DebuffBorder.Texture
	local get = texture.GetAtlas
	H.secretReturn(texture, "GetAtlas", "whole")
	H.CMP:Set("BuffIcon", "style", "square")
	T.eq(item.DebuffBorder:GetAlpha(), 0)
	local shown = false
	for _, child in ipairs({ item:GetChildren() }) do
		if child ~= item.DebuffBorder and child:GetObjectType() == "Frame" and #regionsOf(child, "Texture") == 1 and child:IsShown() then
			shown = true
		end
	end
	T.truthy(shown, "copy shown from the secret atlas")
end)

T.test("skin: /cmp rings reports without raising, also with secret atlases", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("rings")
	H.secretReturn(item.DebuffBorder.Texture, "GetAtlas", "whole")
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("rings")
	T.truthy(true)
end)
