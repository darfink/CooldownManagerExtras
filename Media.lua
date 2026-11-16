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
	-- paths, so these stay ours and aren't shared with other addons. The atlases are
	-- already colored (gold cast bar, green health, ...); see StyleBar's desaturate.
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

-- True for our built-in Blizzard atlases, which carry their own colors.
function Media:IsColoredTexture(name)
	for _, entry in ipairs(BUILTIN.statusbar) do
		if entry.name == name then
			return entry.atlas == true
		end
	end
	return false
end

local desaturatedBars = setmetatable({}, { __mode = "k" })

local function SetBarDesaturated(statusBar, desaturate)
	local texture = statusBar:GetStatusBarTexture()
	if texture and texture.SetDesaturated and (desaturate or desaturatedBars[statusBar]) then
		texture:SetDesaturated(desaturate)
		desaturatedBars[statusBar] = desaturate or nil
	end
end

-- desaturate: true = the bar is tinted by its owner (Blizzard's colored atlases are made
-- gray), "always" = a custom color: any texture is made gray. Details:
-- the bar is tinted by its owner (the Personal Resource Display colors health
-- green and mana blue). A tint on already-colored art multiplies into a muddy color, so
-- those textures are made gray first and the tint colors them as intended.
function Media:StyleBar(statusBar, textureName, desaturate)
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
		SetBarDesaturated(statusBar, desaturate == "always")
		return
	end
	if not original then
		originalBars[statusBar] = texture:GetAtlas() or texture:GetTexture() or DEFAULT_BAR_ATLAS
	end
	statusBar:SetStatusBarTexture(path)
	SetBarDesaturated(statusBar, desaturate == "always" or (desaturate == true and self:IsColoredTexture(textureName)))
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

---------------------------------------------------------------------------
-- Bar colors (Personal Resource Display)
---------------------------------------------------------------------------
-- Blizzard colors its bars itself (SetStatusBarColor: health green, mana blue, ...). A
-- custom color is put back right after each of those calls (a secure post-hook; only the
-- widget's C method is called), and Blizzard's last color is restored when it's removed.

local colorHooked = setmetatable({}, { __mode = "k" })
local blizzardColor = setmetatable({}, { __mode = "k" }) -- bar -> { r, g, b, a } Blizzard set
local wantedColor = setmetatable({}, { __mode = "k" }) -- bar -> our color
local applying = false

local function SetColor(bar, r, g, b, a)
	applying = true
	pcall(bar.SetStatusBarColor, bar, r, g, b, a)
	applying = false
end

local function HookColor(bar)
	if colorHooked[bar] or type(bar.SetStatusBarColor) ~= "function" then
		return
	end
	colorHooked[bar] = true
	local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
	if ok then
		blizzardColor[bar] = { r, g, b, a }
	end
	hooksecurefunc(bar, "SetStatusBarColor", function(self, r2, g2, b2, a2)
		if applying then
			return
		end
		blizzardColor[self] = { r2, g2, b2, a2 }
		local c = wantedColor[self]
		if c then
			SetColor(self, c.r, c.g, c.b, c.a or 1)
		end
	end)
end

-- color: { r, g, b, a } or nil for Blizzard's.
function Media:SetBarColor(bar, color)
	if not bar then
		return
	end
	HookColor(bar)
	if color then
		wantedColor[bar] = color
		SetColor(bar, color.r, color.g, color.b, color.a or 1)
	elseif wantedColor[bar] then
		wantedColor[bar] = nil
		local c = blizzardColor[bar]
		if c then
			SetColor(bar, c[1], c[2], c[3], c[4])
		end
	end
end

-- Your current power type as a token ("MANA", "RAGE", "ENERGY", ...).
function Media:PowerToken()
	local ok, _, token = pcall(UnitPowerType, "player")
	if ok and not CMP.IsSecret(token) and type(token) == "string" then
		return token
	end
	return "MANA"
end

function Media:PowerName(token)
	local name = _G[token]
	return type(name) == "string" and name or token:sub(1, 1) .. token:sub(2):lower()
end

-- Blizzard's own color for a power type (to start a custom color from).
function Media:DefaultPowerColor(token)
	local c = type(PowerBarColor) == "table" and PowerBarColor[token]
	if type(c) == "table" and type(c.r) == "number" then
		return { r = c.r, g = c.g, b = c.b, a = 1 }
	end
	return { r = 0, g = 0, b = 1, a = 1 }
end

function Media:ClassColor()
	local ok, _, classFile = pcall(UnitClass, "player")
	if not ok or type(classFile) ~= "string" then
		return nil
	end
	local c
	if C_ClassColor and C_ClassColor.GetClassColor then
		local okColor, color = pcall(C_ClassColor.GetClassColor, classFile)
		c = okColor and color or nil
	end
	c = c or (type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[classFile])
	if type(c) == "table" and type(c.r) == "number" then
		return { r = c.r, g = c.g, b = c.b, a = 1 }
	end
	return nil
end

function Media:HealthColor(key)
	local mode = CMP:Get(key, "healthColorMode")
	if mode == "class" then
		return self:ClassColor()
	elseif mode == "custom" then
		return CMP:Get(key, "healthColor")
	end
	return nil
end

-- Per power type: { [token] = color } / { [token] = texture name }.
function Media:PowerColor(key, token)
	local colors = CMP:Get(key, "powerColors")
	return type(colors) == "table" and colors[token] or nil
end

function Media:PowerTexture(key)
	return CMP:Get(key, "powerTexture")
end

function Media:HealthTexture(key)
	return CMP:Get(key, "healthTexture")
end

function Media:StylePRD(info)
	local frame = info.frame
	if not frame then
		return
	end
	local key = info.key
	local font, outline, size = CMP:Get(key, "font"), CMP:Get(key, "outline"), CMP:Get(key, "textSize")
	local token = self:PowerToken()
	local healthBar = frame.healthbar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
	local bars = {
		{ healthBar, self:HealthTexture(key), self:HealthColor(key) },
		{ frame.PowerBar, self:PowerTexture(key), self:PowerColor(key, token) },
		{ frame.AlternatePowerBar, self:PowerTexture(key), nil },
	}
	for _, entry in ipairs(bars) do
		local bar, texture, color = entry[1], entry[2], entry[3]
		if bar then
			-- a custom color needs gray art to color cleanly, whatever the texture
			self:StyleBar(bar, texture, color and "always" or true)
			self:SetBarColor(bar, color)
			self:StyleFont(bar.TextString, font, outline, size)
			self:StyleFont(bar.LeftText, font, outline, size)
			self:StyleFont(bar.RightText, font, outline, size)
		end
	end
	self:StyleCostPreview(info)
end

---------------------------------------------------------------------------
-- Cost preview (Personal Resource Display): while you cast, Blizzard shows the spell's
-- cost as a separate texture right of the power bar's fill (PowerBar.ManaCostPredictionBar),
-- colored once per power type with SetVertexColor. Its texture and color are ours to set;
-- a post-hook puts our color back after Blizzard's.
---------------------------------------------------------------------------

local costState = setmetatable({}, { __mode = "k" }) -- texture -> { original, blizzardColor, color, hooked }

local function CostTexture(frame)
	local bar = frame.PowerBar
	local texture = bar and bar.ManaCostPredictionBar
	return type(texture) == "table" and texture.SetVertexColor and texture or nil
end

local function SetCostColor(texture, r, g, b, a)
	applying = true
	pcall(texture.SetVertexColor, texture, r, g, b, a)
	applying = false
end

-- A lighter shade of the power bar's color (custom or Blizzard's), so it reads as "about
-- to be spent" on any color.
local function Lighter(color)
	if not color then
		return nil
	end
	return { r = color.r + (1 - color.r) * 0.45, g = color.g + (1 - color.g) * 0.45, b = color.b + (1 - color.b) * 0.45, a = 1 }
end

function Media:CurrentPowerColor(key, frame)
	local custom = self:PowerColor(key, self:PowerToken())
	if custom then
		return custom
	end
	local c = frame.PowerBar and blizzardColor[frame.PowerBar]
	if c and type(c[1]) == "number" and not CMP.IsSecret(c[1]) then
		return { r = c[1], g = c[2], b = c[3], a = 1 }
	end
	return self:DefaultPowerColor(self:PowerToken())
end

function Media:StyleCostPreview(info)
	local frame = info.frame
	local texture = frame and CostTexture(frame)
	if not texture then
		return
	end
	local key = info.key
	local state = costState[texture]
	if not state then
		state = {}
		costState[texture] = state
		local okFile, file = pcall(texture.GetTexture, texture)
		local okAtlas, atlas = pcall(texture.GetAtlas, texture)
		state.original = (okAtlas and atlas) and { atlas = atlas } or { file = okFile and file or "Interface\\TargetingFrame\\UI-StatusBar" }
		local ok, r, g, b, a = pcall(texture.GetVertexColor, texture)
		state.blizzardColor = ok and { r, g, b, a } or nil
		hooksecurefunc(texture, "SetVertexColor", function(self, r2, g2, b2, a2)
			if applying then
				return
			end
			state.blizzardColor = { r2, g2, b2, a2 }
			local c = state.color
			if c then
				SetCostColor(self, c.r, c.g, c.b, c.a or 1)
			end
		end)
	end
	-- texture: Blizzard's, the power bar's, or any bar texture
	local name = CMP:Get(key, "costTexture")
	if name == "power" then
		name = self:PowerTexture(key)
	end
	local path = self:Fetch("statusbar", name)
	if path then
		if self:HasAtlas(path) then
			texture:SetAtlas(path)
		else
			texture:SetTexture(path)
		end
		state.changed = true
	elseif state.changed then
		if state.original.atlas then
			texture:SetAtlas(state.original.atlas)
		else
			texture:SetTexture(state.original.file)
		end
		state.changed = false
	end
	-- color
	local mode = CMP:Get(key, "costColorMode")
	local color
	if mode == "custom" then
		color = CMP:Get(key, "costColor")
	elseif mode == "power" then
		color = Lighter(self:CurrentPowerColor(key, frame))
	end
	state.color = color
	texture:SetDesaturated(color ~= nil)
	if color then
		SetCostColor(texture, color.r, color.g, color.b, color.a or 1)
	elseif state.blizzardColor then
		local c = state.blizzardColor
		SetCostColor(texture, c[1], c[2], c[3], c[4])
	end
end

-- Druid forms and the like change the power type (and Blizzard re-textures the bar).
function Media:WatchPower()
	if self.powerEvents then
		return
	end
	self.powerEvents = CreateFrame("Frame")
	pcall(self.powerEvents.RegisterUnitEvent, self.powerEvents, "UNIT_DISPLAYPOWER", "player")
	self.powerEvents:SetScript("OnEvent", function()
		C_Timer.After(0, function() -- after Blizzard's own update
			local prd = CMP.byKey.PRD
			if prd and prd.frame then
				CMP.Safe(self.StylePRD, self, prd)
				CMP.Safe(CMP.Skin.StylePRD, CMP.Skin, prd)
			end
			CMP:RefreshDialog(prd)
		end)
	end)
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
