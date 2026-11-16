local addonName, ns = ...

-- Cooldown Manager Extras
--
-- Design rules (read before changing anything):
--  * Blizzard's Cooldown Manager and Edit Mode stay in charge. We never replace their
--    methods or write into their tables. We only use hooksecurefunc / HookScript and read
--    their fields.
--  * Edit Mode system frames override SetPoint/ClearAllPoints/SetScale with Lua that writes
--    into Blizzard tables. Calling those overrides from addon code would taint Edit Mode,
--    so we always call the raw C widget methods in CMP.raw instead.
--  * Never call Blizzard Lua that touches cooldown or aura values from addon code. On
--    Forever those values can be secret in combat, and tainted code cannot handle them.

local CMP = {}
ns.CMP = CMP
_G.CooldownManagerExtras = CMP -- handy for /dump; nothing reads it

CMP.LEM = ns.LibEditMode

local FrameMethods = getmetatable(CreateFrame("Frame")).__index
CMP.raw = {
	SetPoint = FrameMethods.SetPoint,
	ClearAllPoints = FrameMethods.ClearAllPoints,
	SetSize = FrameMethods.SetSize,
	SetWidth = FrameMethods.SetWidth,
	SetScale = FrameMethods.SetScale,
}

local issecretvalue = _G.issecretvalue
function CMP.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

local errorHandler = function(err) return (CallErrorHandler or geterrorhandler())(err) end
-- Runs fn and reports errors without breaking the Blizzard call stack that triggered it.
function CMP.Safe(fn, ...)
	return xpcall(fn, errorHandler, ...)
end

---------------------------------------------------------------------------
-- Frames we extend
---------------------------------------------------------------------------

CMP.frameInfos = {}
CMP.byKey = {}
CMP.byFrame = {}

local function Define(info)
	table.insert(CMP.frameInfos, info)
	CMP.byKey[info.key] = info
end

Define({ key = "Essential", global = "EssentialCooldownViewer", kind = "icons", subsystem = "Essential" })
Define({ key = "Utility", global = "UtilityCooldownViewer", kind = "icons", subsystem = "Utility" })
Define({ key = "BuffIcon", global = "BuffIconCooldownViewer", kind = "icons", buffs = true, subsystem = "BuffIcon" })
Define({ key = "BuffBar", global = "BuffBarCooldownViewer", kind = "bars", buffs = true, subsystem = "BuffBar" })
Define({ key = "PRD", global = "PersonalResourceDisplayFrame", kind = "prd" })

local FALLBACK_NAMES = {
	Essential = "Essential Cooldowns",
	Utility = "Utility Cooldowns",
	BuffIcon = "Tracked Buffs",
	BuffBar = "Tracked Bars",
	PRD = "Personal Resource Display",
}

function CMP:GetName(key)
	local info = self.byKey[key]
	local frame = info and info.frame
	if frame and frame.GetSystemName then
		local ok, name = pcall(frame.GetSystemName, frame)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	return FALLBACK_NAMES[key] or key
end

---------------------------------------------------------------------------
-- Saved settings, stored per Edit Mode layout
---------------------------------------------------------------------------

CMP.defaults = {
	-- layout inside the viewer
	align = "native", -- native | start | center | end
	collapse = false, -- buffs: close gaps left by inactive buffs
	-- position
	attachTo = "none", -- none | <frame key>
	attachSide = "BELOW", -- BELOW | ABOVE | LEFT | RIGHT
	attachAlign = "CENTER", -- START | CENTER | END
	attachGap = 2,
	attachOffset = 0,
	-- Grow From on an unattached frame: the fixed point (UI units) and which point it is
	pinX = false,
	pinY = false,
	pinPoint = false,
	-- icons
	style = "blizzard", -- blizzard | square
	iconSize = 0, -- 0 = use Edit Mode's Icon Size
	borderSize = 1, -- physical pixels
	borderColor = { r = 0, g = 0, b = 0, a = 1 },
	zoom = 8, -- percent cropped from each icon edge (square style)
	spacingX = -1, -- icons: pixels between icons in a row; -1 = Blizzard's Icon Padding
	spacingY = -1, -- icons: pixels between rows; -1 = same as spacingX
	sharedBorders = false, -- square icons / square PRD bars: neighbours share one border line
	barBackground = { r = 0, g = 0, b = 0, a = 0.5 }, -- Personal Resource Display, square style
	-- Tracked Bars: the bar itself (the icon uses style / borderSize / borderColor above)
	barStyle = "blizzard", -- blizzard | square
	barBorderSize = 1, -- physical pixels
	barBorderColor = { r = 0, g = 0, b = 0, a = 1 },
	-- width matching (Tracked Bars, Personal Resource Display)
	matchWidth = "off", -- off | target | widest
	widthAdjust = 0,
	-- text and textures (LibSharedMedia names, or "default" for Blizzard's)
	font = "default",
	outline = "default", -- default | NONE | OUTLINE | THICKOUTLINE
	timerSize = 0, -- icons: cooldown timer; 0 = Blizzard's
	countSize = 0, -- icons: charges and stacks
	textSize = 0, -- bars and Personal Resource Display
	barTexture = "default",
	-- Personal Resource Display: each bar's color and texture ("default" = Blizzard's)
	healthColorMode = "default", -- default | class | custom
	healthColor = { r = 0, g = 0.8, b = 0, a = 1 },
	healthTexture = "default",
	powerColors = false, -- { [power token] = color }: custom color per power type
	powerTexture = "default",
	-- the cost of the spell you're casting, shown on the power bar
	costTexture = "default", -- default (Blizzard's) | power (as the power bar) | texture name
	costColorMode = "default", -- default | power (a lighter power bar color) | custom
	costColor = { r = 1, g = 1, b = 1, a = 0.6 },
	-- keybind text on icons
	keybinds = false,
	keybindSize = 0, -- 0 = automatic
	keybindPoint = "TOPLEFT",
	-- attached frames: what to do when the frame they're attached to hides
	whenHidden = "keep", -- keep | fill
	-- Tracked Buffs: our own timer for tracked debuffs on you (Blizzard shows none)
	debuffTimers = true,
	-- Personal Resource Display: five-second-rule spark on the mana bar
	fsr = false,
}

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in pairs(value) do
		result[k] = Copy(v)
	end
	return result
end
CMP.Copy = Copy

-- 0.1 had one Bar Texture for all Personal Resource Display bars; now the health and power
-- bars have their own. A texture set before goes to both.
function CMP.MigratePRD(settings)
	if type(settings) ~= "table" then
		return
	end
	local shared = settings.barTexture
	if shared ~= nil and shared ~= "default" then
		if settings.healthTexture == nil or settings.healthTexture == "same" then
			settings.healthTexture = shared
		end
		if settings.powerTexture == nil then
			settings.powerTexture = shared
		end
	end
	settings.barTexture = nil
	if settings.healthTexture == "same" then
		settings.healthTexture = nil
	end
	settings.powerTextures = nil -- (an unreleased per-power-type version)
end

function CMP:LayoutName()
	return self.activeLayout
end

-- Where settings come from: a profile (if this character or its talent group uses one),
-- otherwise the current Edit Mode layout. See Profiles.lua.
function CMP:Store(layoutName, create)
	if not self.db then
		return nil
	end
	local profileName = self.Profiles and self.Profiles:ActiveName()
	if profileName then
		local profile = self.db.profiles[profileName]
		if not profile and create then
			profile = { frames = {} }
			self.db.profiles[profileName] = profile
		end
		return profile and profile.frames
	end
	local name = layoutName or self.activeLayout
	if not name then
		return nil
	end
	local layout = self.db.layouts[name]
	if not layout and create then
		layout = {}
		self.db.layouts[name] = layout
	end
	return layout
end

function CMP:FrameDB(key, layoutName, create)
	local layout = self:Store(layoutName, create)
	if not layout then
		return nil
	end
	local settings = layout[key]
	if not settings and create then
		settings = {}
		layout[key] = settings
	end
	return settings
end

function CMP:Get(key, field, layoutName)
	local settings = self:FrameDB(key, layoutName)
	local value = settings and settings[field]
	if value == nil then
		value = self.defaults[field]
	end
	return value
end

-- Writes without refreshing anything. Use for values we derive ourselves.
function CMP:SetQuiet(key, field, value, layoutName)
	local settings = self:FrameDB(key, layoutName, true)
	if settings then
		settings[field] = Copy(value)
	end
end

-- Writes a user-facing setting and refreshes the UI.
function CMP:Set(key, field, value, layoutName)
	self:SetQuiet(key, field, value, layoutName)
	if layoutName == nil or layoutName == self.activeLayout then
		self:Update()
	end
end

-- "blizzard", "square", or "masque" when Masque skins this viewer (it then owns the look).
function CMP:IconStyle(info)
	if self.Masque:IsActive(info) then
		return "masque"
	end
	return self:Get(info.key, "style")
end

function CMP:GetSpellStyle(spellID)
	return spellID and self.db and self.db.spells[spellID]
end

function CMP:SetSpellStyle(spellID, field, value)
	if not spellID then
		return
	end
	local style = self.db.spells[spellID] or {}
	style[field] = Copy(value)
	if next(style) == nil then
		style = nil
	end
	self.db.spells[spellID] = style
	self.Skin:RefreshAll()
end

function CMP:ClearSpellStyle(spellID)
	if spellID then
		self.db.spells[spellID] = nil
		self.Skin:RefreshAll()
	end
end

-- Base spell of a cooldown viewer item (viewer item or Cooldown Settings item).
function CMP:GetItemSpellID(item)
	if not item or not item.GetCooldownInfo then
		return nil
	end
	local ok, info = pcall(item.GetCooldownInfo, item)
	local spellID = ok and info and info.spellID
	if not self.IsSecret(spellID) and spellID then
		return spellID
	end
	return nil
end

---------------------------------------------------------------------------
-- Geometry helpers. "UI units" are UIParent units: what Edit Mode shows.
---------------------------------------------------------------------------

-- Size of one physical screen pixel in the region's own units.
function CMP.PixelUnit(region)
	return PixelUtil.GetPixelToUIUnitFactor() / region:GetEffectiveScale()
end

function CMP.Snap(value, region)
	local unit = CMP.PixelUnit(region)
	return math.floor(value / unit + 0.5) * unit
end

-- Factor that converts the region's own units to UI units.
function CMP.ToUI(region)
	return region:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

function CMP.RectUI(frame)
	local left, bottom, width, height = frame:GetRect()
	if CMP.IsSecret(left) or not left then
		return nil
	end
	local s = CMP.ToUI(frame)
	return left * s, bottom * s, width * s, height * s
end

-- Point on a frame ("TOPLEFT", "CENTER", ...) in UI units.
function CMP.PointUI(frame, point)
	local left, bottom, width, height = CMP.RectUI(frame)
	if not left then
		return nil
	end
	local x, y = left + width / 2, bottom + height / 2
	if point:find("LEFT", 1, true) then
		x = left
	elseif point:find("RIGHT", 1, true) then
		x = left + width
	end
	if point:find("TOP", 1, true) then
		y = bottom + height
	elseif point:find("BOTTOM", 1, true) then
		y = bottom
	end
	return x, y
end

-- A viewer in its default (unmoved) position is laid out by Blizzard's managed frame
-- container. Moving or resizing it ourselves would fight that container.
function CMP:IsManagedDefault(frame)
	return frame.isManagedFrame and frame.systemInfo and frame.systemInfo.isInDefaultPosition or false
end

-- Non-protected frames can be moved in combat. If something protected got anchored to
-- one of ours, wait until combat ends.
function CMP:CanTouch(frame)
	if InCombatLockdown() and frame:IsProtected() then
		self.pendingAfterCombat = true
		return false
	end
	return true
end

function CMP.HookMethod(object, method, fn)
	if object and type(object[method]) == "function" then
		hooksecurefunc(object, method, fn)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function CMP:Update()
	if not self.ready then
		return
	end
	self.CustomSettings:Start() -- Blizzard's settings window may load after us
	if CooldownViewerSettings and CooldownViewerSettings:IsShown() then
		-- profile / layout switches, imports and resets change the custom tiles too
		self.Safe(self.CustomSettings.Refresh, self.CustomSettings)
	end
	for _, info in ipairs(self.frameInfos) do
		if info.frame and info.kind ~= "prd" then
			self.Layout:Run(info) -- applies scale, places items, then refreshes the skin
		end
	end
	local prd = self.byKey.PRD
	if prd.frame then
		self.Safe(self.Media.StylePRD, self.Media, prd)
		self.Safe(self.Skin.StylePRD, self.Skin, prd)
	end
	self.Safe(self.Anchors.ApplyAll, self.Anchors)
	self.Overlay:Refresh()
end

-- Re-runs the extension panel under Blizzard's Edit Mode dialog, so settings that depend on
-- other settings (hidden/disabled) update. Deferred one frame so it never runs inside a
-- menu callback.
function CMP:RefreshDialog(info)
	if not info or not info.frame or self.selected ~= info.frame or not info.refreshName then
		return
	end
	if self.dialogRefreshPending then
		return
	end
	self.dialogRefreshPending = true
	C_Timer.After(0, function()
		self.dialogRefreshPending = false
		if self.selected == info.frame then
			pcall(self.LEM.EnableSystemSetting, self.LEM, info.systemID, info.refreshName, info.subSystemID)
		end
	end)
end

function CMP:Print(...)
	print("|cff4fa3ffCooldown Manager Extras:|r", ...)
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local function BindFrames()
	for _, info in ipairs(CMP.frameInfos) do
		local frame = _G[info.global]
		if frame and not info.frame then
			info.frame = frame
			CMP.byFrame[frame] = info
			if info.kind ~= "prd" then
				CMP.Layout:Hook(info)
			end
			CMP.Anchors:Hook(info)
		end
	end
end

local function TrackSelection()
	if not EditModeManagerFrame then
		return
	end
	CMP.HookMethod(EditModeManagerFrame, "SelectSystem", function(_, frame)
		CMP.selected = frame
		CMP.Overlay:Refresh()
	end)
	CMP.HookMethod(EditModeManagerFrame, "ClearSelectedSystem", function()
		CMP.selected = nil
		CMP.Overlay:Refresh()
	end)
end

local function CheckReady()
	local wasReady = CMP.ready
	CMP.ready = CMP.db ~= nil and CMP.activeLayout ~= nil and CMP.enteredWorld == true
	if CMP.ready and not wasReady then
		CMP.Profiles.lastActive = CMP.Profiles:ActiveName()
		CMP.Media:WatchLSM()
		CMP.Media:WatchPower()
		CMP.Masque:Start()
		CMP.Keybinds:Start()
		CMP.Mana:Start()
		CMP.Timers:Start()
		CMP.Lockouts:Start()
		CMP.Custom:Start()
		CMP.CustomSettings:Start()
		CMP:Update()
		-- Cooldown data and sizes settle a moment after login; run once more.
		C_Timer.After(1, function() CMP:Update() end)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			CooldownManagerExtrasDB = CooldownManagerExtrasDB or {}
			local db = CooldownManagerExtrasDB
			db.version = db.version or 1
			db.layouts = db.layouts or {}
			db.spells = db.spells or {}
			db.ui = db.ui or {}
			db.profiles = db.profiles or {}
			db.chars = db.chars or {}
			-- 0.1 "Screen (keep center fixed)" became Grow From: Center.
			for _, layout in pairs(db.layouts) do
				CMP.MigratePRD(layout.PRD)
			end
			for _, profile in pairs(db.profiles) do
				CMP.MigratePRD(profile.frames and profile.frames.PRD)
			end
			for _, layout in pairs(db.layouts) do
				for _, settings in pairs(layout) do
					if settings.attachTo == "screen" then
						settings.attachTo = "none"
						if settings.align == nil or settings.align == "native" then
							settings.align = "center"
						end
						settings.pinX, settings.pinY, settings.pinPoint = settings.screenX, settings.screenY, "TOP"
					end
					settings.screenX, settings.screenY = nil, nil
				end
			end
			CMP.db = db
			BindFrames()
			TrackSelection()
			CMP.Overlay:Init()
			CMP.Settings:Register()
			CMP.Session:Init()
			CMP.SpellMenu:Register()
			CMP.Safe(CMP.Options.Build, CMP.Options)
			CheckReady()
		elseif CMP.db then
			BindFrames() -- in case a Blizzard addon loaded after us
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		BindFrames()
		CMP.enteredWorld = true
		CheckReady()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if CMP.pendingAfterCombat then
			CMP.pendingAfterCombat = false
			CMP:Update()
		end
	else
		CMP:Update()
	end
end)

-- Edit Mode layout tracking (settings are stored per layout name).
local specEvents = CreateFrame("Frame")
for _, event in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
	pcall(specEvents.RegisterEvent, specEvents, event)
end
specEvents:SetScript("OnEvent", function()
	if CMP.ready then
		CMP.Profiles:OnTalentGroupChanged()
	end
end)

CMP.LEM:RegisterCallback("layout", function(layoutName)
	local changed = CMP.activeLayout ~= nil and CMP.activeLayout ~= layoutName
	CMP.activeLayout = layoutName
	if changed then
		CMP.Session:Rebase()
	end
	if CMP.ready then
		CMP:Update()
	else
		CheckReady()
	end
end)

CMP.LEM:RegisterCallback("create", function(layoutName, _, sourceName)
	if not CMP.db then
		return
	end
	if sourceName and CMP.db.layouts[sourceName] then
		-- "Copy Layout": that layout's settings.
		CMP.db.layouts[layoutName] = Copy(CMP.db.layouts[sourceName])
	elseif CMP.pendingNewLayout then
		-- Save on a preset layout (or a new layout from the current one): the settings in
		-- use when it was made. See EditSession.lua.
		CMP.db.layouts[layoutName] = CMP.pendingNewLayout
	end
	CMP.pendingNewLayout = nil
end)

CMP.LEM:RegisterCallback("rename", function(oldName, newName)
	if CMP.db and CMP.db.layouts[oldName] then
		CMP.db.layouts[newName] = CMP.db.layouts[oldName]
		CMP.db.layouts[oldName] = nil
	end
end)

CMP.LEM:RegisterCallback("delete", function(layoutName)
	if CMP.db then
		CMP.db.layouts[layoutName] = nil
	end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_COOLDOWNMANAGEREXTRAS1 = "/cme"
SLASH_COOLDOWNMANAGEREXTRAS2 = "/cmp" -- the name before 0.1 was Cooldown Manager Plus
SlashCmdList.COOLDOWNMANAGEREXTRAS = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "reset" then
		if CMP.activeLayout then
			CMP.db.layouts[CMP.activeLayout] = nil
			CMP:Print("Reset all settings for layout", CMP.activeLayout .. ". /reload restores Blizzard's exact layout.")
			CMP:Update()
		end
	elseif msg == "options" or msg == "profiles" then
		CMP.Options:Open()
	elseif msg:match("^profile") then
		local name = msg:match("^profile%s+(.+)$")
		if not name then
			CMP:Print("Profiles:", table.concat(CMP.Profiles:List(), ", "), "| in use:", tostring(CMP.Profiles:ActiveName() or "Edit Mode layout settings"))
		elseif name == "none" then
			CMP.Profiles:SetCharacterProfile(nil)
			CMP:Print("This character now uses the Edit Mode layout's settings.")
		else
			local match
			for _, existing in ipairs(CMP.Profiles:List()) do
				if existing:lower() == name then
					match = existing
				end
			end
			if match then
				CMP.Profiles:SetCharacterProfile(match)
				CMP:Print("This character now uses profile", match .. ".")
			else
				CMP:Print("No profile named", name .. ". Create one in /cme options.")
			end
		end
	elseif msg == "probe" then
		CMP.Diagnostics:Probe()
	elseif msg:match("^probe%s") or msg == "probe aura" then
		local kind, arg = msg:match("^probe%s+(%a+)%s*(.-)$")
		CMP.Diagnostics:ProbeOne(kind, arg)
	elseif msg == "rings" then
		CMP.Skin:ReportRings()
	elseif msg == "timers" then
		CMP.Timers:Report()
	elseif msg == "blocked" or msg == "blocked clear" then
		CMP.Diagnostics:Print(msg == "blocked clear")
	elseif msg == "status" then
		CMP:Print("layout:", tostring(CMP.activeLayout), "profile:", tostring(CMP.Profiles:ActiveName() or "-"), "talent group:", CMP.Profiles:TalentGroup(), "ready:", tostring(CMP.ready))
		for _, info in ipairs(CMP.frameInfos) do
			local frame = info.frame
			local content = CMP.Layout.content[info.key]
			print(("  %s: frame=%s attach=%s align=%s style=%s managedDefault=%s content=%.1f"):format(
				info.key, frame and "yes" or "missing", tostring(CMP:Get(info.key, "attachTo")),
				tostring(CMP:Get(info.key, "align")), tostring(CMP.Masque:Describe(info) or CMP:Get(info.key, "style")),
				frame and tostring(CMP:IsManagedDefault(frame)) or "-", content and content.width or 0))
		end
	else
		CMP:Print("Settings live in Edit Mode: select a cooldown viewer or the Personal Resource Display.")
		CMP:Print("Per-spell borders: right-click a spell in the Cooldown Settings window.")
		print("  /cme options - profiles (share a setup between characters and talent groups)")
		print("  /cme profile [name|none] - list or switch this character's profile")
		print("  /cme status - show what the addon sees")
		print("  /cme probe - can addons read your tracked auras right now? (try it in combat)")
		print("  /cme probe spell|item|slot|aura <id> - can addons read this cooldown or buff right now? (try it in combat)")
		print("  /cme timers - what the debuff timers see right now (try it when one is missing)")
		print("  /cme rings - what the addon can read from the debuff-type rings")
		print("  /cme blocked - list \"Interface action failed\" events and the addon the game blamed")
		print("  Masque: install Masque + Masque Blizzard Bars to skin the icons; this addon then leaves the icon look to Masque.")
		print("  /cme reset - reset this Edit Mode layout's settings")
	end
end
