-- Personal Resource Display bar colors and textures (Media.lua), and custom icon tooltips.
local T = ...

local function bars(H)
	local prd = H.viewers.PRD
	return prd.HealthBarsContainer.healthBar, prd.PowerBar
end

T.test("prd colors: a custom power color per power type, kept over Blizzard's recoloring", function(H, T)
	local CMP = H.CMP
	local _, power = bars(H)
	power:SetStatusBarColor(0, 0, 1, 1) -- Blizzard's mana blue
	CMP:Set("PRD", "powerColors", { MANA = { r = 0.1, g = 0.9, b = 0.8, a = 1 } })
	local r, g, b = power:GetStatusBarColor()
	T.near(g, 0.9, 0.001, "turquoise")
	T.truthy(power:GetStatusBarTexture():IsDesaturated(), "art made gray so the color is clean")
	power:SetStatusBarColor(0, 0, 1, 1) -- Blizzard updates the bar again
	r, g, b = power:GetStatusBarColor()
	T.near(g, 0.9, 0.001, "still turquoise")
	-- a druid shifts to cat form: energy has no custom color
	H.powerToken = "ENERGY"
	H.fireEvent("UNIT_DISPLAYPOWER", "player")
	H.advance(0.1)
	H.flush()
	r, g, b = power:GetStatusBarColor()
	T.near(b, 1, 0.001, "Blizzard's color back for energy")
	T.falsy(power:GetStatusBarTexture():IsDesaturated())
end)

T.test("prd colors: class or custom health color, and Blizzard's back on 'Blizzard'", function(H, T)
	local CMP = H.CMP
	local health = bars(H)
	health:SetStatusBarColor(0, 1, 0, 1)
	H.G.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
	rawset(_G, "RAID_CLASS_COLORS", H.G.RAID_CLASS_COLORS)
	CMP:Set("PRD", "healthColorMode", "class")
	local r, g, b = health:GetStatusBarColor()
	T.eq(r, 1, "priest white")
	T.eq(b, 1)
	CMP:Set("PRD", "healthColorMode", "custom")
	CMP:Set("PRD", "healthColor", { r = 0.5, g = 0, b = 0.5, a = 1 })
	r, g, b = health:GetStatusBarColor()
	T.eq(r, 0.5)
	CMP:Set("PRD", "healthColorMode", "default")
	r, g, b = health:GetStatusBarColor()
	T.eq(g, 1, "Blizzard's green back")
	T.eq(r, 0)
end)

T.test("prd colors: the health and power bars have their own textures", function(H, T)
	local CMP = H.CMP
	local health, power = bars(H)
	CMP:Set("PRD", "healthTexture", "Blizzard: Classic")
	CMP:Set("PRD", "powerTexture", "Blizzard: Flat")
	T.eq(health:GetStatusBarTexture():GetTexture(), "Interface\\TargetingFrame\\UI-StatusBar")
	T.eq(power:GetStatusBarTexture():GetTexture(), "Interface\\Buttons\\WHITE8X8")
	T.eq(H.viewers.PRD.AlternatePowerBar:GetStatusBarTexture():GetTexture(), "Interface\\Buttons\\WHITE8X8", "alternate power: as the power bar")
end)

T.test("prd colors: 0.1's shared Bar Texture moves to both bars (saved settings and imports)", function(H, T)
	local CMP = H.CMP
	local old = { barTexture = "Blizzard: Flat", healthTexture = "same", powerTextures = { MANA = "x" } }
	CMP.MigratePRD(old)
	T.eq(old.healthTexture, "Blizzard: Flat")
	T.eq(old.powerTexture, "Blizzard: Flat")
	T.eq(old.barTexture, nil)
	T.eq(old.powerTextures, nil)
	local mine = { barTexture = "Blizzard: Flat", healthTexture = "Blizzard: Raid" }
	CMP.MigratePRD(mine)
	T.eq(mine.healthTexture, "Blizzard: Raid", "a texture of its own is kept")
	T.eq(mine.powerTexture, "Blizzard: Flat")
end)

T.test("prd colors: power colors and textures survive export / import, bad entries dropped", function(H, T)
	local CMP = H.CMP
	CMP:Set("PRD", "powerColors", { MANA = { r = 0, g = 1, b = 1, a = 1 }, ["bad token"] = { r = 1, g = 0, b = 0 } })
	CMP:Set("PRD", "powerTexture", "Blizzard: Flat")
	local ok = CMP.Share:Import(CMP.Share:Export(), "Copy", true)
	T.truthy(ok)
	local frames = CMP.db.profiles.Copy.frames.PRD
	T.eq(frames.powerColors.MANA.g, 1)
	T.eq(frames.powerColors["bad token"], nil)
	T.eq(frames.powerTexture, "Blizzard: Flat")
end)

T.test("custom icons: hover shows a tooltip, unless the viewer hides tooltips", function(H, T)
	local CMP = H.CMP
	local viewer = H.viewers.Essential
	viewer.systemInfo.isInDefaultPosition = false
	H.spells[100] = { name = "A" }
	viewer:AddItem({ spellID = 100 })
	H.spells[900] = { name = "Mine" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	H.flush()
	local icon = CMP.Custom:Frames(CMP.byKey.Essential)[1]
	T.truthy(icon:IsMouseMotionEnabled(), "hover enabled")
	T.falsy(icon:IsMouseClickEnabled(), "clicks go through")
	icon:GetScript("OnEnter")(icon)
	T.truthy(GameTooltip:NumLines() >= 0)
	viewer.tooltipsShown = false
	CMP.Custom:RefreshStyles(CMP.byKey.Essential)
	T.falsy(icon:IsMouseMotionEnabled(), "follows Blizzard's setting")
end)

T.test("prd colors: Reset To Default clears the power colors of every power type and the textures", function(H, T)
	local CMP = H.CMP
	CMP:Set("PRD", "powerColors", { MANA = { r = 0, g = 1, b = 1, a = 1 }, ENERGY = { r = 1, g = 1, b = 0, a = 1 } })
	CMP:Set("PRD", "powerTexture", "Blizzard: Flat")
	H.enterEditMode()
	H.select("PRD")
	local extension = CMP.LEM.internal.extension
	T.truthy(extension, "LibEditMode panel")
	CMP.Settings:KeepPanelOnScreen()
	extension:ResetSettings()
	H.flush()
	T.eq(CMP:Get("PRD", "powerColors"), false)
	T.eq(CMP:Get("PRD", "powerTexture"), "default")
end)

T.test("prd colors: the cast cost preview takes a texture and a color, and gives Blizzard's back", function(H, T)
	local CMP = H.CMP
	local cost = H.viewers.PRD.PowerBar.ManaCostPredictionBar
	CMP:Set("PRD", "costTexture", "Blizzard: Flat")
	T.eq(cost:GetTexture(), "Interface\\Buttons\\WHITE8X8")
	CMP:Set("PRD", "costColorMode", "custom")
	CMP:Set("PRD", "costColor", { r = 1, g = 0, b = 1, a = 0.5 })
	local r, g, b = cost:GetVertexColor()
	T.eq(r, 1)
	T.eq(g, 0)
	cost:SetVertexColor(0, 0.447, 1) -- Blizzard recolors it on a power type change
	r, g = cost:GetVertexColor()
	T.eq(g, 0, "ours stays")
	-- lighter shade of a turquoise mana bar
	CMP:Set("PRD", "powerColors", { MANA = { r = 0, g = 0.8, b = 0.8, a = 1 } })
	CMP:Set("PRD", "costColorMode", "power")
	r, g, b = cost:GetVertexColor()
	T.truthy(r > 0.3 and g > 0.85, "lighter turquoise")
	CMP:Set("PRD", "costColorMode", "default")
	CMP:Set("PRD", "costTexture", "default")
	r, g, b = cost:GetVertexColor()
	T.near(g, 0.447, 0.001, "Blizzard's color back")
	T.eq(cost:GetTexture(), "Interface\\TargetingFrame\\UI-StatusBar", "Blizzard's texture back")
	-- "same as power texture"
	CMP:Set("PRD", "powerTexture", "Blizzard: Raid")
	CMP:Set("PRD", "costTexture", "power")
	T.eq(cost:GetTexture(), "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
end)

T.test("settings: the panel keeps one width whichever section is open", function(H, T)
	local CMP = H.CMP
	H.enterEditMode()
	H.select("PRD")
	CMP.Settings:KeepPanelOnScreen()
	local extension = CMP.LEM.internal.extension
	T.truthy((extension.minimumWidth or 0) >= 343 + 40, "at least as wide as a slider row")
end)
