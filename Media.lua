local _, ns = ...
local CMP = ns.CMP

-- Fonts and bar textures. Uses LibSharedMedia-3.0 when another addon (or the standalone
-- SharedMedia addons) provides it, and a short list of Blizzard's own media otherwise.
-- Every override keeps the original values so "Default" restores Blizzard's look.
--
-- Only widget C methods are used (SetFont, SetStatusBarTexture). Bar textures are changed
-- through the StatusBar API, which keeps the same texture object, because the Personal
-- Resource Display anchors its prediction overlays to that object.

local Media = {}
CMP.Media = Media

local DEFAULT_BAR_ATLAS = "UI-HUD-CoolDownManager-Bar"

local BUILTIN = {
	font = {
		{ name = "Blizzard: Standard", path = STANDARD_TEXT_FONT },
		{ name = "Blizzard: Unit Names", path = UNIT_NAME_FONT },
		{ name = "Blizzard: Damage", path = DAMAGE_TEXT_FONT },
		{ name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	},
	-- atlas = true: one of the game's own atlases (only listed if this client has it).
	-- StatusBar:SetStatusBarTexture takes atlas names, but LibSharedMedia only holds file
	-- paths, so these stay ours and aren't shared with other addons.
	statusbar = {
		{ name = "Blizzard: Cooldown Manager", path = "UI-HUD-CoolDownManager-Bar", atlas = true },
		{ name = "Blizzard: Cast Bar", path = "ui-castingbar-filling-standard", atlas = true },
		{ name = "Blizzard: Cast Bar (Channel)", path = "ui-castingbar-filling-channel", atlas = true },
		{ name = "Blizzard: Cast Bar (Uninterruptible)", path = "ui-castingbar-uninterruptable", atlas = true },
		{ name = "Blizzard: Player Health", path = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health", atlas = true },
		{ name = "Blizzard: Player Mana", path = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana", atlas = true },
		{ name = "Blizzard: Target Health", path = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health", atlas = true },
		{ name = "Blizzard: Flat", path = "Interface\\Buttons\\WHITE8X8" },
		{ name = "Blizzard: Classic", path = "Interface\\TargetingFrame\\UI-StatusBar" },
		{ name = "Blizzard: Raid", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
	},
}

function Media:HasAtlas(name)
	if not (C_Texture and C_Texture.GetAtlasInfo) then
		return false
	end
	local ok, atlasInfo = pcall(C_Texture.GetAtlasInfo, name)
	return ok and atlasInfo ~= nil
end

function Media:LSM()
	return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

-- { name, path } for every available font or statusbar texture, sorted, no duplicates.
function Media:List(kind)
	local result, seen = {}, {}
	local lsm = self:LSM()
	if lsm then
		for _, name in ipairs(lsm:List(kind)) do
			local path = lsm:Fetch(kind, name, true)
			if path and not seen[name] then
				seen[name] = true
				table.insert(result, { name = name, path = path })
			end
		end
	end
	for _, entry in ipairs(BUILTIN[kind]) do
		if entry.path and not seen[entry.name] and (not entry.atlas or Media:HasAtlas(entry.path)) then
			seen[entry.name] = true
			table.insert(result, entry)
		end
	end
	table.sort(result, function(a, b) return a.name:lower() < b.name:lower() end)
	return result
end

function Media:Fetch(kind, name)
	if not name or name == "default" then
		return nil
	end
	local lsm = self:LSM()
	local path = lsm and lsm:Fetch(kind, name, true)
	if path then
		return path
	end
	for _, entry in ipairs(BUILTIN[kind]) do
		if entry.name == name then
			return entry.path
		end
	end
	return nil -- not registered (yet): keep Blizzard's
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------

local originalFonts = setmetatable({}, { __mode = "k" })

-- outline: "default" | "NONE" | "OUTLINE" | "THICKOUTLINE"; size 0 = keep Blizzard's
function Media:StyleFont(fontString, fontName, outline, size)
	if not fontString or not fontString.GetFont then
		return
	end
	local original = originalFonts[fontString]
	local isDefault = (fontName == "default" or not self:Fetch("font", fontName)) and outline == "default" and (not size or size <= 0)
	if not original then
		if isDefault then
			return -- never touched, nothing to restore
		end
		local path, height, flags = fontString:GetFont()
		if not path then
			return
		end
		original = { path, height, flags or "" }
		originalFonts[fontString] = original
	end
	local path = self:Fetch("font", fontName) or original[1]
	local flags = outline == "default" and original[3] or (outline == "NONE" and "" or outline)
	local height = (size and size > 0) and size or original[2]
	fontString:SetFont(path, height, flags)
	if isDefault then
		originalFonts[fontString] = nil
	end
end

---------------------------------------------------------------------------
-- Bar textures
---------------------------------------------------------------------------

local originalBars = setmetatable({}, { __mode = "k" })

function Media:StyleBar(statusBar, textureName)
	if not statusBar or not statusBar.GetStatusBarTexture then
		return
	end
	local texture = statusBar:GetStatusBarTexture()
	if not texture then
		return
	end
	local path = self:Fetch("statusbar", textureName)
	local original = originalBars[statusBar]
	if not path then
		if original then
			statusBar:SetStatusBarTexture(original)
			originalBars[statusBar] = nil
		end
		return
	end
	if not original then
		originalBars[statusBar] = texture:GetAtlas() or texture:GetTexture() or DEFAULT_BAR_ATLAS
	end
	statusBar:SetStatusBarTexture(path)
end

---------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------

local function Call(object, method)
	if object and object[method] then
		local ok, result = pcall(object[method], object)
		if ok then
			return result
		end
	end
	return nil
end

function Media:StyleItem(info, item)
	local key = info.key
	local font, outline = CMP:Get(key, "font"), CMP:Get(key, "outline")
	if info.kind == "icons" then
		local cooldown = item.Cooldown
		local timer = cooldown and cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
		self:StyleFont(timer, font, outline, CMP:Get(key, "timerSize"))
		local countSize = CMP:Get(key, "countSize")
		self:StyleFont(item.ChargeCount and item.ChargeCount.Current, font, outline, countSize)
		self:StyleFont(item.Applications and item.Applications.Applications, font, outline, countSize)
	elseif info.kind == "bars" then
		local size = CMP:Get(key, "textSize")
		self:StyleFont(Call(item, "GetNameFontString"), font, outline, size)
		self:StyleFont(Call(item, "GetDurationFontString"), font, outline, size)
		self:StyleFont(Call(item, "GetApplicationsFontString"), font, outline, size)
		self:StyleBar(Call(item, "GetBarFrame"), CMP:Get(key, "barTexture"))
	end
end

function Media:StylePRD(info)
	local frame = info.frame
	if not frame then
		return
	end
	local key = info.key
	local font, outline, size = CMP:Get(key, "font"), CMP:Get(key, "outline"), CMP:Get(key, "textSize")
	local texture = CMP:Get(key, "barTexture")
	local healthBar = frame.healthbar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
	for _, bar in pairs({ healthBar, frame.PowerBar, frame.AlternatePowerBar }) do
		self:StyleBar(bar, texture)
		self:StyleFont(bar.TextString, font, outline, size)
		self:StyleFont(bar.LeftText, font, outline, size)
		self:StyleFont(bar.RightText, font, outline, size)
	end
end

-- Media registered by other addons after login: re-apply once it exists.
function Media:WatchLSM()
	local lsm = self:LSM()
	if lsm and not self.watching then
		self.watching = true
		lsm.RegisterCallback(self, "LibSharedMedia_Registered", function()
			if not self.pending then
				self.pending = true
				C_Timer.After(0.5, function()
					self.pending = false
					CMP:Update()
				end)
			end
		end)
	end
end
