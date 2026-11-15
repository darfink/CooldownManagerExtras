-- Blizzard frames the addon extends, modelled on /tmp/wowsrc-cdm/CooldownViewer.xml and
-- CooldownViewer.lua (Blizzard_CooldownViewer): the four viewers, their item frames, the
-- Personal Resource Display, Edit Mode's manager and settings dialog.
--
-- Only what the addon touches is modelled. Item frames carry the mixin methods the addon calls
-- (GetCooldownInfo, GetAuraDataCached, GetAuraDataUnit, GetCooldownID, RefreshIconColor,
-- RefreshIconDesaturation, GetBarFrame ...) as plain fields, the way Blizzard's Mixin() does.

local B = {}

local VIEWERS = {
	Essential = { global = "EssentialCooldownViewer", index = 1, template = "essential", managed = true, size = 50, name = "Essential Cooldowns", stride = 8 },
	Utility = { global = "UtilityCooldownViewer", index = 2, template = "utility", managed = true, size = 30, name = "Utility Cooldowns", stride = 8 },
	BuffIcon = { global = "BuffIconCooldownViewer", index = 3, template = "buffIcon", managed = true, size = 40, name = "Tracked Buffs", stride = 0 },
	BuffBar = { global = "BuffBarCooldownViewer", index = 4, template = "buffBar", managed = false, size = 30, name = "Tracked Bars", stride = 0 },
}
B.VIEWERS = VIEWERS

function B.install(H)
	local G = H.G
	local raw -- raw frame methods (what Core.lua captures through getmetatable)
	local S = H.state
	local CreateFrame = G.CreateFrame
	local UIParent = G.UIParent

	local function Raw()
		if not raw then
			local methods = getmetatable(CreateFrame("Frame")).__index
			raw = { SetPoint = methods.SetPoint, ClearAllPoints = methods.ClearAllPoints, SetSize = methods.SetSize,
				SetWidth = methods.SetWidth, SetScale = methods.SetScale }
		end
		return raw
	end
	H.raw = setmetatable({}, { __index = function(_, k) return Raw()[k] end })

	-- Calls to the Edit Mode overrides come from addon code (the harness uses H.raw): record them.
	H.violations = {}
	local function overrideSystemMethods(frame)
		for _, name in ipairs({ "SetPoint", "ClearAllPoints", "SetScale", "SetSize" }) do
			frame[name] = function(self, ...)
				table.insert(H.violations, { frame = frame, method = name, trace = debug.traceback("", 2) })
				return Raw()[name](self, ...)
			end
		end
	end
	B.overrideSystemMethods = overrideSystemMethods

	---------------------------------------------------------------------------
	-- Edit Mode
	---------------------------------------------------------------------------
	local manager = CreateFrame("Frame", "EditModeManagerFrame", UIParent)
	manager:Hide()
	manager.registeredSystemFrames = {}
	manager.SelectSystem = function(self, systemFrame)
		self.selectedSystem = systemFrame
		local dialog = G.EditModeSystemSettingsDialog
		dialog:AttachToSystemFrame(systemFrame)
	end
	manager.ClearSelectedSystem = function(self)
		self.selectedSystem = nil
		G.EditModeSystemSettingsDialog:Hide()
	end
	manager.ShowNewLayoutDialog = function() end
	manager.EnterEditMode = function(self) self:Show() end
	manager.ExitEditMode = function(self) self:Hide() end
	manager.SetHasActiveChanges = function(self, v) self.hasActiveChanges = v end
	manager.SaveLayouts = function() end
	manager.RevertSystemChanges = function() end
	manager.RevertAllChanges = function() end
	manager.ImportLayout = function() end
	manager.SaveChangesButton = CreateFrame("Button", nil, manager)
	manager.RevertAllChangesButton = CreateFrame("Button", nil, manager)
	H.editModeManager = manager

	local dialog = CreateFrame("Frame", "EditModeSystemSettingsDialog", UIParent)
	dialog:SetSize(380, 350)
	dialog:SetMovable(true)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetFrameLevel(200)
	H.raw.SetPoint(dialog, "TOPLEFT", UIParent, "TOPLEFT", 400, -200)
	dialog:Hide()
	dialog.AttachToSystemFrame = function(self, systemFrame)
		self.attachedToSystem = systemFrame
		self:Show()
		self:UpdateSizeAndAnchors(systemFrame)
	end
	dialog.UpdateSizeAndAnchors = function() end
	dialog.UpdateButtons = function() end
	dialog.Buttons = { RevertChangesButton = CreateFrame("Button", nil, dialog) }
	H.editModeDialog = dialog

	local prompt = CreateFrame("Frame", "EditModeUnsavedChangesDialog", UIParent)
	prompt.ProceedButton = CreateFrame("Button", nil, prompt)
	prompt:Hide()

	-- Position the settings dialog (UIParent units, top-left origin measured from the bottom-left).
	function H.placeDialog(left, top, width, height)
		H.raw.ClearAllPoints(dialog)
		dialog:SetSize(width or 380, height or 350)
		H.raw.SetPoint(dialog, "TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	function H.enterEditMode()
		manager:EnterEditMode()
		H.flush()
	end
	function H.exitEditMode()
		manager:ExitEditMode()
		H.flush()
	end
	-- Select a system frame in Edit Mode like clicking on it (opens Blizzard's dialog and, through
	-- LibEditMode's SelectSystem hook, our panel).
	function H.select(frameOrKey)
		local frame = type(frameOrKey) == "string" and H.viewers[frameOrKey] or frameOrKey
		manager:SelectSystem(frame)
		H.flush()
		return frame
	end

	---------------------------------------------------------------------------
	-- Item frames
	---------------------------------------------------------------------------
	local USABLE = G.CreateColor(1, 1, 1, 1)
	local NOT_IN_RANGE = G.CreateColor(0.64, 0.15, 0.15, 1)
	local NOT_ENOUGH_MANA = G.CreateColor(0.5, 0.5, 1, 1)
	local NOT_USABLE = G.CreateColor(0.4, 0.4, 0.4, 1)

	local function baseItemMethods(item)
		item.SetViewerFrame = function(self, viewer) self.viewerFrame = viewer end
		item.GetViewerFrame = function(self) return self.viewerFrame end
		item.GetCooldownID = function(self) return self.cooldownID end
		item.SetCooldownID = function(self, id) self.cooldownID = id end
		item.ClearCooldownID = function(self) self.cooldownID = nil self.cooldownInfo = nil end
		item.GetCooldownInfo = function(self) return self.cooldownInfo end
		item.GetSpellID = function(self)
			local info = self.cooldownInfo
			return info and (info.overrideSpellID or info.spellID)
		end
		item.GetAuraDataCached = function(self) return self.auraData end
		item.GetAuraDataUnit = function(self) return self.auraUnit end
		item.GetIconTexture = function(self) return self.Icon end
		item.IsExpired = function() return false end
		item.cooldownDesaturated = false
		item.SetTimerShown = function() end
		item.SetTooltipsShown = function() end
		item.SetHideWhenInactive = function() end
		item.SetIsEditing = function() end
		item.RefreshData = function() end
		item.ResetCooldownData = function() end
	end

	-- Blizzard's own repaint (CooldownViewerCooldownItemMixin:RefreshIconDesaturation / ...IconColor)
	local function cooldownRepaint(item)
		item.RefreshIconDesaturation = function(self)
			self.Icon:SetDesaturated(self.cooldownDesaturated and not self:IsExpired())
		end
		item.RefreshIconColor = function(self)
			local spellID = self:GetSpellID()
			if not spellID then return end
			local usable, notEnoughMana = G.C_Spell.IsSpellUsable(spellID)
			local color
			if self.spellOutOfRange then color = NOT_IN_RANGE
			elseif usable then color = USABLE
			elseif notEnoughMana then color = NOT_ENOUGH_MANA
			else color = NOT_USABLE end
			self.Icon:SetVertexColor(color:GetRGBA())
			self.OutOfRange:SetShown(not not self.spellOutOfRange)
		end
	end

	local function iconParts(item, withOutOfRange)
		item.Icon = item:CreateTexture(nil, "ARTWORK")
		item.Icon:SetAllPoints()
		local mask = item:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		mask:SetAllPoints()
		item.Icon:AddMaskTexture(mask)
		local overlay = item:CreateTexture(nil, "OVERLAY")
		overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		overlay:SetPoint("TOPLEFT", -9, 8)
		overlay:SetPoint("BOTTOMRIGHT", 9, -8)
		if withOutOfRange then
			item.OutOfRange = item:CreateTexture(nil, "OVERLAY")
			item.OutOfRange:SetAtlas("UI-CooldownManager-OORshadow")
			item.OutOfRange:SetAllPoints()
		end
		item.Cooldown = CreateFrame("Cooldown", nil, item)
		item.Cooldown:SetAllPoints()
		item.Cooldown:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
	end

	local function buildCooldownItem(item, def)
		item:SetSize(def.size, def.size)
		item.cooldownFont = def.size > 40 and "GameFontHighlightHugeOutline" or "GameFontHighlightOutline"
		iconParts(item, true)
		item.ChargeCount = CreateFrame("Frame", nil, item)
		item.ChargeCount:SetAllPoints()
		item.ChargeCount.Current = item.ChargeCount:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		item.CooldownFlash = CreateFrame("Frame", nil, item)
		item.CooldownFlash:Hide()
		item.CooldownFlash.Flipbook = item.CooldownFlash:CreateTexture(nil, "ARTWORK")
		item.CooldownFlash.Flipbook:SetAtlas("UI-HUD-ActionBar-GCD-Flipbook")
		local anim = item.CooldownFlash:CreateAnimationGroup()
		anim.HideAnim = anim:CreateAnimation("Alpha")
		anim.ShowAnim = anim:CreateAnimation("Alpha")
		anim.PlayAnim = anim:CreateAnimation("FlipBook")
		item.CooldownFlash.FlashAnim = anim
		cooldownRepaint(item)
	end

	local function buildBuffIconItem(item, def)
		item:SetSize(def.size, def.size)
		iconParts(item, false)
		item.Cooldown:SetReverse(true)
		item.DebuffBorder = CreateFrame("Frame", nil, item)
		item.DebuffBorder.Texture = item.DebuffBorder:CreateTexture(nil, "ARTWORK")
		item.DebuffBorder:SetFrameLevel(item.Cooldown:GetFrameLevel() + 1)
		item.Applications = CreateFrame("Frame", nil, item)
		item.Applications.Applications = item.Applications:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	end

	local function buildBuffBarItem(item, def)
		item:SetSize(220, 30)
		local icon = CreateFrame("Frame", nil, item)
		icon:SetSize(30, 30)
		icon:SetPoint("LEFT")
		icon:SetFrameLevel(512)
		icon.Icon = icon:CreateTexture(nil, "ARTWORK")
		icon.Icon:SetAllPoints()
		local mask = icon:CreateMaskTexture()
		mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
		icon.Icon:AddMaskTexture(mask)
		local overlay = icon:CreateTexture(nil, "OVERLAY")
		overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
		icon.Applications = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		item.Icon = icon
		item.DebuffBorder = CreateFrame("Frame", nil, item)
		item.DebuffBorder:SetFrameLevel(520)
		local bar = CreateFrame("StatusBar", nil, item)
		bar:SetFrameLevel(511)
		bar:SetHeight(19)
		bar:SetPoint("LEFT", icon, "RIGHT", 2, 0)
		bar:SetPoint("RIGHT")
		bar:SetStatusBarTexture("UI-HUD-CoolDownManager-Bar")
		bar.BarBG = bar:CreateTexture(nil, "BACKGROUND")
		bar.BarBG:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
		bar.Pip = bar:CreateTexture(nil, "OVERLAY")
		bar.Pip:SetAtlas("UI-HUD-CoolDownManager-Bar-Pip")
		bar.Name = bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		bar.Duration = bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		item.Bar = bar
		item.GetIconFrame = function(self) return self.Icon end
		item.GetIconTexture = function(self) return self.Icon.Icon end
		item.GetBarFrame = function(self) return self.Bar end
		item.GetNameFontString = function(self) return self.Bar.Name end
		item.GetDurationFontString = function(self) return self.Bar.Duration end
		item.GetApplicationsFontString = function(self) return self.Icon.Applications end
	end

	local BUILDERS = { essential = buildCooldownItem, utility = buildCooldownItem, buffIcon = buildBuffIconItem, buffBar = buildBuffBarItem }

	---------------------------------------------------------------------------
	-- Viewers
	---------------------------------------------------------------------------
	H.viewers = {}
	local nextCooldownID = 100

	local function gridLayout(viewer)
		-- Blizzard's GridLayoutFrame, reduced: one row (or column), items in layoutIndex order.
		local items = {}
		for _, child in ipairs({ viewer:GetChildren() }) do
			if child.layoutIndex and (child:IsShown() or child.includeAsLayoutChildWhenHidden) then
				items[#items + 1] = child
			end
		end
		table.sort(items, function(a, b) return a.layoutIndex < b.layoutIndex end)
		local stride = viewer.stride
		if not stride or stride < 1 then stride = #items end
		local pad = viewer.childXPadding or 0
		local scale = viewer.iconScale or 1
		local maxW, maxH, x, y, rowH = 0, 0, 0, 0, 0
		local col = 0
		for _, item in ipairs(items) do
			local size, isc = S(item).size, S(item).scale
			local w, h = size.w * isc, size.h * isc -- Blizzard's own code is not tainted: no secrets here
			if viewer.isHorizontal ~= false then
				if col >= stride then col, x, y = 0, 0, y + rowH + pad rowH = 0 end
				H.raw.ClearAllPoints(item)
				H.raw.SetPoint(item, "TOPLEFT", viewer, "TOPLEFT", x / isc, -y / isc)
				x, col, rowH = x + w + pad, col + 1, math.max(rowH, h)
				maxW, maxH = math.max(maxW, x - pad), math.max(maxH, y + h)
			else
				if col >= stride then col, y, x = 0, 0, x + rowH + pad rowH = 0 end
				H.raw.ClearAllPoints(item)
				H.raw.SetPoint(item, "TOPLEFT", viewer, "TOPLEFT", x / isc, -y / isc)
				y, col, rowH = y + h + pad, col + 1, math.max(rowH, w)
				maxH, maxW = math.max(maxH, y - pad), math.max(maxW, x + w)
			end
		end
		if #items > 0 then
			H.raw.SetSize(viewer, maxW, maxH)
		end
	end

	-- Create a viewer (global frame + the fields Blizzard's mixins and Edit Mode give it).
	function H.makeViewer(key)
		local def = VIEWERS[key]
		local viewer = CreateFrame("Frame", def.global, UIParent)
		H.viewers[key] = viewer
		viewer.system = G.Enum.EditModeSystem.CooldownViewer
		viewer.systemIndex = def.index
		viewer.isManagedFrame = def.managed or nil
		viewer.systemInfo = { isInDefaultPosition = def.managed and true or false }
		viewer.isHorizontal = true
		viewer.stride = def.stride
		viewer.iconScale = 1
		viewer.childXPadding, viewer.childYPadding = -2, -2 -- icon padding 2 + Blizzard's -4
		viewer.layoutFramesGoingRight = true
		viewer.layoutFramesGoingUp = false
		viewer.GetSystemName = function() return def.name end
		viewer.OnAcquireItemFrame = function(self, item)
			item:SetViewerFrame(self)
			item:SetScale(self.iconScale)
		end
		viewer.RefreshData = function() end
		viewer.Layout = gridLayout
		overrideSystemMethods(viewer)
		-- park it on screen without going through the (recording) override
		H.raw.SetSize(viewer, def.size, def.size)
		H.raw.SetPoint(viewer, "CENTER", UIParent, "CENTER", 0, 0)
		viewer.items = {}
		viewer.nextLayoutIndex = 1

		-- spec: { spellID, linkedSpellID, overrideSpellID, linkedSpellIDs, shown }
		viewer.AddItem = function(self, spec)
			spec = spec or {}
			local item = CreateFrame("Frame", nil, self)
			item.includeAsLayoutChildWhenHidden = true
			baseItemMethods(item)
			BUILDERS[def.template](item, def)
			nextCooldownID = nextCooldownID + 1
			item.cooldownID = spec.cooldownID or nextCooldownID
			item.cooldownInfo = {
				spellID = spec.spellID, overrideSpellID = spec.overrideSpellID,
				linkedSpellID = spec.linkedSpellID, linkedSpellIDs = spec.linkedSpellIDs,
			}
			item.layoutIndex = self.nextLayoutIndex
			self.nextLayoutIndex = self.nextLayoutIndex + 1
			if spec.shown == false then item:Hide() end
			table.insert(self.items, item)
			self:OnAcquireItemFrame(item) -- what Blizzard's RefreshLayout does; addon hooks it
			H.flush()
			self:Layout()
			return item
		end
		-- Blizzard calls this when auras/cooldowns change; the buff viewers re-run their layout.
		viewer.RefreshLayoutNow = function(self) self:Layout() end
		return viewer
	end

	-- Helpers to drive an item like the game does.
	-- A harmful/helpful aura as Blizzard's item caches it.
	function H.setItemAura(item, aura, unit)
		item.auraData = aura
		item.auraUnit = aura and (unit or "player") or nil
	end
	function H.showItem(item, shown)
		item:SetShown(shown)
	end

	---------------------------------------------------------------------------
	-- Personal Resource Display
	---------------------------------------------------------------------------
	function H.makePRD()
		local prd = CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
		prd.system = G.Enum.EditModeSystem.PersonalResourceDisplay
		prd.GetSystemName = function() return "Personal Resource Display" end
		prd.isManagedFrame = nil
		prd.systemInfo = { isInDefaultPosition = false }
		H.raw.SetSize(prd, 200, 40)
		overrideSystemMethods(prd)
		H.raw.SetPoint(prd, "CENTER", UIParent, "CENTER", 0, -200)
		local function bar(parent, name)
			local b = CreateFrame("StatusBar", nil, parent)
			b:SetSize(200, 12)
			b:SetStatusBarTexture("UI-HUD-CoolDownManager-Bar")
			local bg = b:CreateTexture(nil, "BACKGROUND")
			bg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
			b.TextString = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
			b.LeftText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
			b.RightText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
			return b
		end
		prd.HealthBarsContainer = CreateFrame("Frame", nil, prd)
		prd.HealthBarsContainer.healthBar = bar(prd.HealthBarsContainer)
		prd.PowerBar = bar(prd)
		prd.AlternatePowerBar = bar(prd)
		H.viewers.PRD = prd
		return prd
	end
end

return B
