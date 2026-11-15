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
