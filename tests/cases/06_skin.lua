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

local function borderColor(item, H)
	local border = borderFrame(item, H)
	if not (border and border:IsShown()) then return nil end
	return regionsOf(border, "Texture")[1]:_colorTexture()
end

T.test("skin: square icons hide Blizzard's debuff ring and color the square border instead", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	H.CMP:Set("BuffIcon", "style", "square")
	T.eq(item.DebuffBorder:GetAlpha(), 0, "Blizzard's ring hidden")
	T.falsy(ringCopy(item, MAGIC), "no copy of the round art")
	local r, g, b = borderColor(item, H)
	T.truthy(b and b > 0.9 and r < 0.5, "border is Magic blue")
	H.CMP:Set("BuffIcon", "style", "blizzard")
	T.eq(item.DebuffBorder:GetAlpha(), 1, "ring back")
end)

T.test("skin: no debuff (ring hidden) = normal border", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	item.DebuffBorder:Hide()
	H.CMP:Set("BuffIcon", "style", "square")
	T.falsy(ringCopy(item, MAGIC))
	local r, g, b = borderColor(item, H)
	T.truthy(r == nil or b < 0.5, "not blue")
end)

T.test("skin: in combat (secret atlas) the type learned out of combat colors the border", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	H.CMP:Set("BuffIcon", "style", "square") -- learns 589 = magic
	H.secretReturn(item.DebuffBorder.Texture, "GetAtlas", "whole")
	H.CMP.Skin:ApplyItem(H.CMP.byKey.BuffIcon, item)
	local r, g, b = borderColor(item, H)
	T.truthy(b and b > 0.9 and r < 0.5, "still Magic blue")
	T.eq(H.CMP.db.debuffTypes[589], "magic", "saved")
end)

T.test("skin: a debuff never seen out of combat (secret atlas) gets the normal square border, no round art", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 590 })
	debuffRing(H, item, MAGIC)
	H.secretReturn(item.DebuffBorder.Texture, "GetAtlas", "whole")
	H.CMP:Set("BuffIcon", "style", "square")
	T.eq(item.DebuffBorder:GetAlpha(), 0, "Blizzard's ring hidden")
	T.falsy(ringCopy(item, MAGIC))
	local r, g, b = borderColor(item, H)
	T.eq(r, 0, "normal (black) border")
	T.eq(b, 0)
end)

T.test("skin: the 'None' debuff type (default art) gets its own color", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 591 })
	debuffRing(H, item, "ui-debuff-border-default-noicon")
	H.CMP:Set("BuffIcon", "style", "square")
	local r, g, b = borderColor(item, H)
	T.truthy(r and r > 0.5 and b < 0.2, "red")
end)

T.test("skin: /cme rings reports without raising, also with secret atlases", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 589 })
	debuffRing(H, item, MAGIC)
	_G.SlashCmdList.COOLDOWNMANAGEREXTRAS("rings")
	H.secretReturn(item.DebuffBorder.Texture, "GetAtlas", "whole")
	_G.SlashCmdList.COOLDOWNMANAGEREXTRAS("rings")
	T.truthy(true)
end)

-- the inner shadow: 4 OVERLAY -8 gradient textures on the owner itself
local function shadowEdges(owner, H)
	local out = {}
	for _, r in ipairs(regionsOf(owner, "Texture")) do
		local layer, sub = r:GetDrawLayer()
		if layer == "OVERLAY" and sub == -8 and H.state(r).gradient then out[#out + 1] = r end
	end
	return out
end

T.test("skin: inner shadow on square icons, inside the border; off and Blizzard style hide it", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = 100 })
	H.CMP:Set("Essential", "style", "square")
	T.eq(#shadowEdges(item, H), 0, "off by default")
	H.CMP:Set("Essential", "borderSize", 2)
	H.CMP:Set("Essential", "innerShadowStrength", 50)
	H.CMP:Set("Essential", "innerShadow", 3)
	local edges = shadowEdges(item, H)
	T.eq(#edges, 4, "four edges")
	local strongest = 0
	for _, e in ipairs(edges) do
		T.truthy(e:IsShown())
		local g = H.state(e).gradient
		strongest = math.max(strongest, g.min.a, g.max.a)
		T.eq(math.min(g.min.a, g.max.a), 0, "fades to nothing")
	end
	T.near(strongest, 0.5, 0.001, "strength")
	local top = edges[1]
	local _, _, _, x, y = top:GetPoint(1)
	local unit = H.CMP.PixelUnit(item)
	T.near(y, -2 * unit, 0.0001, "starts where the 2 px border ends")
	T.near(top:GetHeight(), 3 * unit, 0.0001, "3 px deep")
	H.CMP:Set("Essential", "innerShadow", 0)
	T.falsy(edges[1]:IsShown(), "0 turns it off")
	H.CMP:Set("Essential", "innerShadow", 3)
	H.CMP:Set("Essential", "style", "blizzard")
	T.falsy(edges[1]:IsShown(), "Blizzard style has none")
end)

T.test("skin: inner shadow on square PRD bars", function(H, T)
	local prd = H.viewers.PRD
	local health = prd.HealthBarsContainer.healthBar
	H.CMP:Set("PRD", "innerShadow", 2)
	T.eq(#shadowEdges(health, H), 0, "Blizzard style: none")
	H.CMP:Set("PRD", "style", "square")
	local edges = shadowEdges(health, H)
	T.eq(#edges, 4)
	T.truthy(edges[1]:IsShown())
	T.eq(#shadowEdges(prd.PowerBar, H), 4, "power bar too")
	H.CMP:Set("PRD", "style", "blizzard")
	T.falsy(edges[1]:IsShown(), "removed with the Square style")
end)
