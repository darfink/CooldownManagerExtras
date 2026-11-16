-- Fonts and bar textures (Media.lua).
local T = ...

local function listNames(H, kind)
	local names = {}
	for _, entry in ipairs(H.CMP.Media:List(kind)) do names[#names + 1] = entry.name end
	return names
end
local function has(list, name)
	for _, n in ipairs(list) do if n == name then return true end end
	return false
end

T.test("media: atlas status bars are listed only when GetAtlasInfo knows them", function(H, T)
	-- the mock client has the Cooldown Manager bar atlas, but not the cast bar / unit frame ones
	local names = listNames(H, "statusbar")
	T.truthy(has(names, "Blizzard: Cooldown Manager"), "known atlas is listed")
	T.falsy(has(names, "Blizzard: Cast Bar"), "unknown atlas is not listed")
	T.falsy(has(names, "Blizzard: Player Health"))
	T.truthy(has(names, "Blizzard: Flat"), "file textures are always listed")
	T.truthy(has(names, "Blizzard: Classic"))
	H.atlases["ui-castingbar-filling-standard"] = true
	T.truthy(has(listNames(H, "statusbar"), "Blizzard: Cast Bar"), "listed once the client knows the atlas")
	T.falsy(has(listNames(H, "statusbar"), "Blizzard: Cast Bar (Channel)"))
end)

T.test("media: with no atlas API, no atlas entry is listed", function(H, T)
	_G.C_Texture.GetAtlasInfo = nil
	local names = listNames(H, "statusbar")
	T.falsy(has(names, "Blizzard: Cooldown Manager"))
	T.truthy(has(names, "Blizzard: Flat"))
end)

T.test("media: a GetAtlasInfo that raises does not break the list", function(H, T)
	_G.C_Texture.GetAtlasInfo = function() error("boom") end
	T.truthy(has(listNames(H, "statusbar"), "Blizzard: Flat"))
end)

T.test("media: the list is sorted and has no duplicates", function(H, T)
	local names = listNames(H, "statusbar")
	local seen, last = {}, nil
	for _, n in ipairs(names) do
		T.falsy(seen[n], "duplicate " .. n)
		seen[n] = true
		if last then T.truthy(last:lower() <= n:lower(), last .. " before " .. n) end
		last = n
	end
	local fonts = listNames(H, "font")
	T.truthy(has(fonts, "Blizzard: Standard"))
	T.truthy(has(fonts, "Arial Narrow"))
end)

T.test("media: LibSharedMedia entries are merged in; its paths win over built-ins of the same name", function(H, T)
	local lsm = {
		List = function(_, kind) return kind == "statusbar" and { "Smooth", "Blizzard: Flat" } or { "Fira" } end,
		Fetch = function(_, kind, name) return "Interface\\LSM\\" .. name end,
		RegisterCallback = function() end,
	}
	H.registerLib("LibSharedMedia-3.0", lsm)
	local names = listNames(H, "statusbar")
	T.truthy(has(names, "Smooth"))
	local count = 0
	for _, n in ipairs(names) do if n == "Blizzard: Flat" then count = count + 1 end end
	T.eq(count, 1, "no duplicate name")
	T.eq(H.CMP.Media:Fetch("statusbar", "Smooth"), "Interface\\LSM\\Smooth")
	T.eq(H.CMP.Media:Fetch("font", "Fira"), "Interface\\LSM\\Fira")
end)

T.test("media: Fetch returns nil for 'default' and unknown names, the path for built-ins", function(H, T)
	local Media = H.CMP.Media
	T.eq(Media:Fetch("statusbar", "default"), nil)
	T.eq(Media:Fetch("statusbar", nil), nil)
	T.eq(Media:Fetch("statusbar", "No Such Texture"), nil)
	T.eq(Media:Fetch("statusbar", "Blizzard: Flat"), "Interface\\Buttons\\WHITE8X8")
	T.eq(Media:Fetch("statusbar", "Blizzard: Cooldown Manager"), "UI-HUD-CoolDownManager-Bar")
end)

T.test("media: a bar texture is applied through the StatusBar API and 'default' restores the original", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	local bar = item:GetBarFrame()
	local texture = bar:GetStatusBarTexture()
	T.eq(texture:GetAtlas(), "UI-HUD-CoolDownManager-Bar")
	H.CMP:Set("BuffBar", "barTexture", "Blizzard: Flat")
	T.eq(bar:GetStatusBarTexture(), texture, "same texture object (the PRD anchors to it)")
	T.eq(texture:GetTexture(), "Interface\\Buttons\\WHITE8X8")
	H.CMP:Set("BuffBar", "barTexture", "default")
	T.eq(texture:GetAtlas(), "UI-HUD-CoolDownManager-Bar", "Blizzard's atlas is back")
end)

T.test("media: PRD bars desaturate Blizzard's colored atlases so the health/mana tint is clean", function(H, T)
	local prd = H.viewers.PRD
	local bar = prd.PowerBar
	H.atlases["ui-castingbar-filling-standard"] = true
	H.CMP:Set("PRD", "powerTexture", "Blizzard: Cast Bar")
	T.eq(bar:GetStatusBarTexture():GetAtlas(), "ui-castingbar-filling-standard")
	T.truthy(bar:GetStatusBarTexture():IsDesaturated(), "gray, tinted by the PRD")
	H.CMP:Set("PRD", "powerTexture", "Blizzard: Flat")
	T.falsy(bar:GetStatusBarTexture():IsDesaturated(), "plain textures untouched")
	H.CMP:Set("PRD", "powerTexture", "Blizzard: Cast Bar")
	H.CMP:Set("PRD", "powerTexture", "default")
	T.falsy(bar:GetStatusBarTexture():IsDesaturated(), "default restores")
end)

T.test("media: Tracked Bars keep Blizzard's colored atlases as they are", function(H, T)
	local item = H.viewers.BuffBar:AddItem({ spellID = 100 })
	H.atlases["ui-castingbar-filling-standard"] = true
	H.CMP:Set("BuffBar", "barTexture", "Blizzard: Cast Bar")
	T.falsy(item:GetBarFrame():GetStatusBarTexture():IsDesaturated())
end)

T.test("media: fonts: size and outline apply to the timer text and 'default' restores them", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = 100 })
	local timer = item.Cooldown:GetCountdownFontString()
	local path, size, flags = timer:GetFont()
	H.CMP:Set("Essential", "font", "Arial Narrow")
	H.CMP:Set("Essential", "outline", "THICKOUTLINE")
	H.CMP:Set("Essential", "timerSize", 20)
	local p2, s2, f2 = timer:GetFont()
	T.eq(p2, "Fonts\\ARIALN.TTF")
	T.eq(s2, 20)
	T.eq(f2, "THICKOUTLINE")
	H.CMP:Set("Essential", "font", "default")
	H.CMP:Set("Essential", "outline", "default")
	H.CMP:Set("Essential", "timerSize", 0)
	local p3, s3, f3 = timer:GetFont()
	T.eq(p3, path); T.eq(s3, size); T.eq(f3, flags)
end)
