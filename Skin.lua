local _, ns = ...
local CMP = ns.CMP

-- Icon styling for Essential, Utility, Tracked Buffs and the icons of Tracked Bars.
--  * "blizzard": the native look. A spell with its own border color gets a pixel border.
--  * "square": removes the rounded mask and frame art, crops the icon edges, and draws a
--    pixel-exact border inside the icon, so the visible icon matches its frame exactly.

local Skin = {}
CMP.Skin = Skin

local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local NATIVE_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local states = setmetatable({}, { __mode = "k" })

local OUT_OF_RANGE_SQUARE = { 0, 0, 0, 0.55 }

-- Icon parts of an item. Icon viewers: the item itself. Tracked Bars: the item's Icon frame.
local function Scan(target)
	local state = states[target]
	if state then
		return state
	end
	state = { masked = true }
	state.icon = target.Icon
	state.cooldown = target.Cooldown
	state.outOfRange = target.OutOfRange
	state.flash = target.CooldownFlash
	for _, region in ipairs({ target:GetRegions() }) do
		local objectType = region:GetObjectType()
		if objectType == "MaskTexture" then
			state.mask = region
		elseif objectType == "Texture" and region:GetAtlas() == OVERLAY_ATLAS then
			state.overlay = region
		end
	end
	states[target] = state
	return state
end

-- Debuffs (Tracked Buffs, Tracked Bars): Blizzard rings the icon in the debuff type's color
-- (Magic blue, Curse purple, ...), 3 units past the icon on each side: made for round
-- icons, it sticks out of square ones. Square style hides that ring and draws our own
-- square border in the debuff type's color instead. The type is read from the ring's art
-- (atlas "ui-debuff-border-<type>-noicon"). In combat the game hides the atlas name, so
-- the type is learned per spell out of combat (a spell's debuff type doesn't change) and
-- used from there. A debuff not seen out of combat yet (your own DoTs are only ever up in
-- combat) gets the normal border; a per-spell border color (right-click it in Cooldown
-- Settings) sets one for good.
local function Plain(value)
	return not CMP.IsSecret(value) and value ~= nil -- secret check first
end

local function Visible(region)
	local ok, shown = pcall(region.IsShown, region)
	return ok and Plain(shown) and shown == true
end

-- The art of the ring Blizzard shows right now (maybe secret), or nil if none is shown.
local function RingAtlas(item)
	local ring = item.DebuffBorder
	local texture = ring and ring.Texture
	if not texture or not Visible(ring) or not Visible(texture) then
		return nil
	end
	local ok, atlas = pcall(texture.GetAtlas, texture)
	if not ok or not CMP.IsSecret(atlas) and not atlas then
		return nil
	end
	return atlas
end

-- Debuff type colors, as Blizzard's DebuffTypeColor where the client has it.
local DEBUFF_COLORS = {
	magic = { r = 0.20, g = 0.60, b = 1.00 },
	curse = { r = 0.60, g = 0.00, b = 1.00 },
	disease = { r = 0.60, g = 0.40, b = 0.00 },
	poison = { r = 0.00, g = 0.60, b = 0.00 },
	bleed = { r = 1.00, g = 0.20, b = 0.40 },
	none = { r = 0.80, g = 0.00, b = 0.00 },
}
-- Never thinner than this, so the color can be seen next to a 1-pixel black border.
local DEBUFF_BORDER_PIXELS = 2

local function DebuffTypeColorOf(kind)
	local blizzard = type(DebuffTypeColor) == "table" and kind
		and DebuffTypeColor[kind:sub(1, 1):upper() .. kind:sub(2)]
	if type(blizzard) == "table" and type(blizzard.r) == "number" then
		return blizzard
	end
	return kind and DEBUFF_COLORS[kind]
end

-- spellID -> debuff type ("magic", ...), the same for every character.
local unsavedTypes = {}
local function LearnedTypes()
	local db = CMP.db
	if not db then
		return unsavedTypes
	end
	db.debuffTypes = db.debuffTypes or {}
	for id, kind in pairs(unsavedTypes) do
		db.debuffTypes[id] = kind
	end
	wipe(unsavedTypes)
	return db.debuffTypes
end

-- For a shown ring: the debuff type's color, or nil while the type is unknown.
local function DebuffRingColor(item)
	local atlas = RingAtlas(item)
	if not CMP.IsSecret(atlas) and atlas == nil then -- secret check first
		return nil
	end
	local spell = CMP:GetItemSpellID(item)
	if not CMP.IsSecret(atlas) then
		local kind = type(atlas) == "string" and atlas:lower():match("^ui%-debuff%-border%-(%a+)")
		if kind == "default" then
			kind = "none"
		end
		local color = DebuffTypeColorOf(kind)
		if color and spell then
			LearnedTypes()[spell] = kind
		end
		return color
	end
	return spell and DebuffTypeColorOf(LearnedTypes()[spell]) or nil
end

-- /cme rings: what we can read from Blizzard's debuff rings right now.
function Skin:ReportRings()
	CMP:Print("Debuff rings (in combat: " .. tostring(InCombatLockdown()) .. ")")
	local function Show(value)
		return CMP.IsSecret(value) and "SECRET" or tostring(value)
	end
	local count = 0
	for _, info in ipairs(CMP.frameInfos) do
		if info.frame and (info.kind == "icons" or info.kind == "bars") then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				local ring = item.DebuffBorder
				local texture = ring and ring.Texture
				if texture and item.layoutIndex then
					local okShown, shown = pcall(ring.IsShown, ring)
					local okAtlas, atlas = pcall(texture.GetAtlas, texture)
					local okFile, file = pcall(texture.GetTexture, texture)
					local okColor, r, g, b = pcall(texture.GetVertexColor, texture)
					local spell = CMP:GetItemSpellID(item)
					if not (okShown and not CMP.IsSecret(shown) and shown == false) then
						count = count + 1
						local learned = spell and LearnedTypes()[spell]
						print(("  %s %s: shown=%s atlas=%s texture=%s tint=%s,%s,%s learned=%s"):format(
							info.key, Show(spell), okShown and Show(shown) or "error", okAtlas and Show(atlas) or "error",
							okFile and Show(file) or "error", okColor and Show(r) or "error", Show(g), Show(b),
							tostring(learned)))
					end
				end
			end
		end
	end
	if count == 0 then
		print("  no debuff ring is shown")
	end
end

-- Blizzard recolors / shows / hides the ring as the aura changes: restyle the item then.
local function WatchDebuffRing(info, item, state)
	if state.ringWatched or not item.DebuffBorder then
		return
	end
	state.ringWatched = true
	local function Restyle()
		CMP.Safe(Skin.ApplyItem, Skin, info, item)
	end
	CMP.HookMethod(item.DebuffBorder, "UpdateFromAuraData", Restyle)
	item.DebuffBorder:HookScript("OnShow", Restyle)
	item.DebuffBorder:HookScript("OnHide", Restyle)
end

local function SetRingHidden(item, state, hidden)
	local ring = item.DebuffBorder
	if not ring then
		return
	end
	if hidden then
		ring:SetAlpha(0)
		state.ringHidden = true
	elseif state.ringHidden then
		ring:SetAlpha(1)
		state.ringHidden = nil
	end
end

-- Square style replaces Blizzard's rounded "cooldown ready" flash with a square one.
local function EnsureSquareFlash(target, state)
	if state.squareFlash or not state.flash then
		return
	end
	local holder = CreateFrame("Frame", nil, target)
	holder:SetAllPoints(target)
	holder:SetFrameLevel(state.flash:GetFrameLevel() + 1)
	local texture = holder:CreateTexture(nil, "OVERLAY")
	texture:SetAllPoints()
	texture:SetColorTexture(1, 1, 1, 1)
	texture:SetBlendMode("ADD")
	texture:SetAlpha(0)
	local animation = texture:CreateAnimationGroup()
	local fadeIn = animation:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(0.45)
	fadeIn:SetDuration(0.08)
	fadeIn:SetOrder(1)
	local fadeOut = animation:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(0.45)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.35)
	fadeOut:SetOrder(2)
	state.squareFlash = animation
	-- Blizzard shows the flash frame when a cooldown starts and delays the animation until
	-- 0.75s before it ends. Its "ShowAnim" step finishes exactly then, so we play ours at
	-- that moment, without reading any cooldown timing.
	local showStep = state.flash.FlashAnim and state.flash.FlashAnim.ShowAnim
	if showStep and showStep.HookScript then
		pcall(showStep.HookScript, showStep, "OnFinished", function()
			if state.square then
				animation:Restart()
			end
		end)
	end
end

local function EnsureBorder(item, state)
	if state.border then
		return state.border
	end
	local border = CreateFrame("Frame", nil, item)
	border:SetAllPoints(item)
	-- Above the cooldown swipe and Blizzard's debuff border (a child frame that covers the
	-- icon edge on debuffs such as Weakened Soul).
	local level = item:GetFrameLevel()
	for _, child in ipairs({ state.cooldown, item.DebuffBorder }) do
		if child and child.GetFrameLevel then
			level = math.max(level, child:GetFrameLevel())
		end
	end
	border:SetFrameLevel(level + 1)
	border.edges = {}
	for i = 1, 4 do
		local edge = border:CreateTexture(nil, "OVERLAY", nil, 7)
		edge:SetTexelSnappingBias(0)
		edge:SetSnapToPixelGrid(false)
		border.edges[i] = edge
	end
	state.border = border
	return border
end

-- inset: distance (in the item's units) from the item's edge to where the border starts.
-- Blizzard's round icon art has a transparent edge; the border goes on the visible icon
-- edge and grows inward (like CSS box-sizing: border-box), so the icon keeps its size.
local function LayoutBorder(border, pixels, color, inset)
	if not pixels or pixels <= 0 then
		border:Hide()
		return
	end
	inset = inset or 0
	if border.inset ~= inset then
		local parent = border:GetParent()
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
		border:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
		border.inset = inset
	end
	local t = pixels * CMP.PixelUnit(border)
	local top, bottom, left, right = unpack(border.edges)
	top:ClearAllPoints()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(t)
	bottom:ClearAllPoints()
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(t)
	left:ClearAllPoints()
	left:SetPoint("TOPLEFT", 0, -t)
	left:SetPoint("BOTTOMLEFT", 0, t)
	left:SetWidth(t)
	right:ClearAllPoints()
	right:SetPoint("TOPRIGHT", 0, -t)
	right:SetPoint("BOTTOMRIGHT", 0, t)
	right:SetWidth(t)
	for _, edge in ipairs(border.edges) do
		edge:SetColorTexture(color.r, color.g, color.b, color.a or 1)
	end
	border:Show()
end

function Skin:ApplyItem(info, item)
	if info.kind ~= "icons" and info.kind ~= "bars" then
		return
	end
	local target = info.kind == "bars" and item.Icon or item
	if type(target) ~= "table" or not target.GetRegions then
		return
	end
	local state = Scan(target)
	local icon = state.icon
	if not icon then
		return
	end
	local key = info.key
	local spellStyle = CMP:GetSpellStyle(CMP:GetItemSpellID(item))
	local style = CMP:IconStyle(info)

	if style == "masque" then
		-- Masque owns mask, texcoords, swipe and frame art. Only a per-spell border is ours,
		-- drawn on our own frame above the icon.
		state.square = false
		SetRingHidden(item, state, false)
		if spellStyle and spellStyle.color then
			LayoutBorder(EnsureBorder(target, state), spellStyle.size or 2, spellStyle.color)
		elseif state.border then
			state.border:Hide()
		end
		return
	end

	if style == "square" then
		state.square = true
		if state.mask and state.masked then
			icon:RemoveMaskTexture(state.mask)
			state.masked = false
		end
		if state.overlay then
			state.overlay:SetAlpha(0)
		end
		local crop = (CMP:Get(key, "zoom") or 0) / 100
		icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
		state.cropped = true
		if state.cooldown then
			state.cooldown:SetSwipeTexture(WHITE)
			state.squareSwipe = true
		end
		-- Rounded out-of-range shadow -> a plain square shade.
		if state.outOfRange and not state.outOfRangeAtlas then
			state.outOfRangeAtlas = state.outOfRange:GetAtlas() or "UI-CooldownManager-OORshadow"
			state.outOfRange:SetColorTexture(unpack(OUT_OF_RANGE_SQUARE))
		end
		-- Rounded "ready" flash -> our square flash.
		if state.flash then
			EnsureSquareFlash(target, state)
			state.flash:SetAlpha(0)
		end
		WatchDebuffRing(info, item, state)
		SetRingHidden(item, state, true)
		local color = spellStyle and spellStyle.color
		local size = spellStyle and spellStyle.size or CMP:Get(key, "borderSize")
		if not color then -- a spell's own border color wins over the debuff type's
			local debuffColor = DebuffRingColor(item)
			if debuffColor then
				color, size = debuffColor, math.max(size or 0, DEBUFF_BORDER_PIXELS)
			end
		end
		color = color or CMP:Get(key, "borderColor")
		LayoutBorder(EnsureBorder(target, state), size, color)
	else
		state.square = false
		SetRingHidden(item, state, false)
		if state.mask and not state.masked then
			icon:AddMaskTexture(state.mask)
			state.masked = true
		end
		if state.cropped then
			icon:SetTexCoord(0, 1, 0, 1)
			state.cropped = false
		end
		if state.squareSwipe and state.cooldown then
			state.cooldown:SetSwipeTexture(NATIVE_SWIPE)
			state.squareSwipe = false
		end
		if state.outOfRangeAtlas then
			state.outOfRange:SetAtlas(state.outOfRangeAtlas)
			state.outOfRangeAtlas = nil
		end
		if state.flash then
			state.flash:SetAlpha(1)
		end
		if state.overlay then
			if state.tinted then -- older versions tinted the frame art instead
				state.overlay:SetDesaturated(false)
				state.overlay:SetVertexColor(1, 1, 1)
				state.tinted = false
			end
			state.overlay:SetAlpha(1)
		end
		-- A spell with its own border gets a real one, drawn on top of everything, on the
		-- visible edge of the icon art.
		if spellStyle and spellStyle.color then
			local edge = info.kind == "icons" and CMP.Layout.BLIZZARD_ICON_EDGE or 0
			LayoutBorder(EnsureBorder(target, state), spellStyle.size or 2, spellStyle.color, edge)
		elseif state.border then
			state.border:Hide()
		end
	end
end

function Skin:RefreshViewer(info)
	if info.kind == "prd" or not info.frame then
		return
	end
	for item in pairs(CMP.Layout:Items(info.frame)) do
		if item.layoutIndex then
			self:ApplyItem(info, item)
			if info.kind == "bars" then
				CMP.Safe(self.StyleBuffBar, self, info, item)
			end
			CMP.Media:StyleItem(info, item)
			CMP.Keybinds:ApplyItem(info, item)
			CMP.Safe(CMP.Timers.UpdateItem, CMP.Timers, info, item)
			CMP.Safe(CMP.Lockouts.UpdateItem, CMP.Lockouts, info, item)
		end
	end
	CMP.Custom:RefreshStyles(info)
end

function Skin:RefreshAll()
	for _, info in ipairs(CMP.frameInfos) do
		if info.frame then
			CMP.Safe(self.RefreshViewer, self, info)
		end
	end
	local prd = CMP.byKey.PRD
	if prd.frame then
		CMP.Safe(CMP.Media.StylePRD, CMP.Media, prd)
		CMP.Safe(self.StylePRD, self, prd)
	end
end

---------------------------------------------------------------------------
-- Personal Resource Display bars (and the bars of Tracked Bars, with their own settings)
--  * "blizzard": Blizzard's bar frame art (a background atlas with a built-in edge and
--    shadow that reaches a few pixels past the bar).
--  * "square": that art is hidden; a plain dark background and a pixel-exact border inside
--    each bar, so the bars' visible edges are exactly their size (and line up with
--    square icons of the same width).
---------------------------------------------------------------------------

local BAR_BG_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"
local barStates = setmetatable({}, { __mode = "k" })

local function PRDBars(frame)
	local bars = {}
	local health = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
	for _, bar in ipairs({ health, frame.PowerBar, frame.AlternatePowerBar }) do
		if type(bar) == "table" and bar.GetRegions then
			table.insert(bars, bar)
		end
	end
	return bars
end

local function BarState(bar)
	local state = barStates[bar]
	if not state or not state.art then
		state = state or {}
		state.art = bar.BarBG -- Tracked Bars name it; the Personal Resource Display doesn't
		for _, region in ipairs({ bar:GetRegions() }) do
			if region:GetObjectType() == "Texture" and region:GetAtlas() == BAR_BG_ATLAS then
				state.art = region
			end
		end
		barStates[bar] = state
	end
	return state
end

-- Square look on one bar (Personal Resource Display or Tracked Bars), or Blizzard's back.
local function StyleBar(bar, square, background, borderSize, borderColor)
	local state = BarState(bar)
	if square then
		if state.art then
			state.art:SetAlpha(0)
		end
		if not state.back then
			state.back = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
			state.back:SetAllPoints(bar)
		end
		state.back:SetColorTexture(background.r, background.g, background.b, background.a or 1)
		state.back:Show()
		LayoutBorder(EnsureBorder(bar, state), borderSize, borderColor)
		state.styled = true
	elseif state.styled then
		if state.art then
			state.art:SetAlpha(1)
		end
		if state.back then
			state.back:Hide()
		end
		if state.border then
			state.border:Hide()
		end
		state.styled = false
	end
end

function Skin:StylePRD(info)
	local frame = info.frame
	if not frame then
		return
	end
	local key = info.key
	local square = CMP:Get(key, "style") == "square"
	for _, bar in ipairs(PRDBars(frame)) do
		StyleBar(bar, square, CMP:Get(key, "barBackground"), CMP:Get(key, "borderSize"), CMP:Get(key, "borderColor"))
	end
end

-- Tracked Bars: the bar next to each icon. Same look as the Personal Resource Display's.
function Skin:StyleBuffBar(info, item)
	local bar = item.GetBarFrame and item:GetBarFrame() or item.Bar
	if type(bar) ~= "table" or not bar.GetRegions then
		return
	end
	local key = info.key
	StyleBar(bar, CMP:Get(key, "barStyle") == "square", CMP:Get(key, "barBackground"), CMP:Get(key, "barBorderSize"), CMP:Get(key, "barBorderColor"))
end

