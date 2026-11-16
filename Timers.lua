local _, ns = ...
local CMP = ns.CMP

-- Timers the Cooldown Manager doesn't show by itself, drawn on our own Cooldown frame on
-- top of the icon:
--
--  * Debuff timers (Tracked Buffs): for auras on you the Cooldown Manager's timer only
--    counts helpful auras, so a tracked debuff such as Weakened Soul shows its icon with
--    no timer. We show the debuff's countdown instead (Blizzard's empty swipe is hidden,
--    alpha only).
--  * "Show cooldown, not buff duration" (per spell, Essential / Utility): spells that put
--    a buff on you (Power Word: Shield) show the buff's duration on their cooldown icon.
--    With this on, the icon shows the spell's own cooldown instead; Blizzard's swipe and
--    timer on that icon are hidden (alpha only).
--
-- Taint: our own frames, and only C methods on Blizzard's (SetAlpha). Durations go
-- through the game's duration objects (C_UnitAuras.GetAuraDuration,
-- C_Spell.GetSpellCooldownDuration -> SetCooldownFromDurationObject), the path made for
-- values that can be hidden from addons in combat. If the game refuses them, we step
-- aside and Blizzard's own display is back (except for known debuffs, timed from when
-- they appear; see ShowEstimate).

local Timers = {}
CMP.Timers = Timers

local NATIVE_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local overlays = setmetatable({}, { __mode = "k" }) -- item -> our Cooldown frame
local why = setmetatable({}, { __mode = "k" }) -- item -> what its last update did (/cmp timers)
local hidingNative = setmetatable({}, { __mode = "k" }) -- item -> true while Blizzard's is hidden

local function SafeCall(object, method, ...)
	local fn = object and object[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, object, ...)
	if ok then
		return a, b
	end
	return nil
end

local function Overlay(info, item)
	local cooldown = overlays[item]
	if cooldown then
		return cooldown
	end
	cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
	cooldown:SetAllPoints(item.Icon or item)
	local native = item.Cooldown
	cooldown:SetFrameLevel((native and native:GetFrameLevel() or item:GetFrameLevel()) + 1)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetSwipeColor(0, 0, 0, 0.7)
	if type(item.cooldownFont) == "string" then
		pcall(cooldown.SetCountdownFont, cooldown, item.cooldownFont)
	end
	cooldown:Hide()
	overlays[item] = cooldown
	return cooldown
end

-- Match the look of the icon's own cooldown: swipe texture (round or square), timer shown
-- or hidden (Edit Mode's Show Timer), aura vs. cooldown rounding, and our font settings.
local function Style(info, item, cooldown, reverse)
	cooldown:SetReverse(reverse)
	-- Aura timers count down slightly differently from cooldowns (15 s debuff shows 14
	-- at once, like the buff and debuff frames); reverse = an aura here.
	if cooldown.SetUseAuraDisplayTime then
		cooldown:SetUseAuraDisplayTime(reverse)
	end
	local square = CMP:IconStyle(info) ~= "blizzard"
	cooldown:SetSwipeTexture(square and WHITE or NATIVE_SWIPE)
	local hide = SafeCall(item.Cooldown, "GetHideCountdownNumbers")
	cooldown:SetHideCountdownNumbers(hide == true)
	local timer = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
	if timer then
		CMP.Media:StyleFont(timer, CMP:Get(info.key, "font"), CMP:Get(info.key, "outline"), CMP:Get(info.key, "timerSize"))
	end
end

local function SetNativeHidden(item, hidden)
	local native = item.Cooldown
	if not native then
		return
	end
	if hidden then
		native:SetAlpha(0)
		hidingNative[item] = true
	elseif hidingNative[item] then
		native:SetAlpha(1)
		hidingNative[item] = nil
	end
end

local function Stop(item)
	local cooldown = overlays[item]
	if cooldown then
		cooldown:Clear()
		cooldown:Hide()
	end
	SetNativeHidden(item, false)
end

-- Shows a duration object on our overlay. False when the game refused it.
local function Show(cooldown, duration)
	if not duration then
		return false
	end
	local ok = pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true)
	if not ok then
		return false
	end
	cooldown:Show()
	return true
end

local function CooldownInfo(item)
	return SafeCall(item, "GetCooldownInfo")
end

local function Usable(id)
	-- the secret check comes first: testing a hidden value itself is an error
	if CMP.IsSecret(id) or not id then
		return nil
	end
	return id
end

---------------------------------------------------------------------------
-- Debuff timers (Tracked Buffs)
---------------------------------------------------------------------------

local function Plain(value)
	return not CMP.IsSecret(value) and value ~= nil -- secret check first
end

-- A harmful aura's instance ID, if it's readable and certainly harmful. In combat the
-- aura's details are hidden from addons; its instance ID may still be readable, and then
-- the game can still tell us whether it's harmful.
local function HarmfulInstance(aura, unit)
	if type(aura) ~= "table" then
		return nil
	end
	local instance, harmful, helpful = aura.auraInstanceID, aura.isHarmful, aura.isHelpful
	if not Plain(instance) then
		return nil
	end
	if Plain(harmful) and harmful == true or Plain(helpful) and helpful == false then
		return instance
	end
	if Plain(harmful) or Plain(helpful) then
		return nil -- known to be helpful
	end
	local check = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
	if check then
		local ok, filtered = pcall(check, unit or "player", instance, "HARMFUL")
		if ok and Plain(filtered) and filtered == false then
			return instance
		end
	end
	return nil
end

-- The debuff on you for this tracked buff. Blizzard often already found it: it looks up
-- an item's linked spells (Weakened Soul for Power Word: Shield) on you, harmful or not,
-- and keeps that aura. Its timer, though, only counts helpful auras on you, so it stays
-- empty. Blizzard's lookup also works in combat, where ours (by spell ID) finds nothing.
-- Otherwise look the spell, its override and its linked spells up ourselves.
local function FindDebuff(item, cooldownInfo)
	local cached = SafeCall(item, "GetAuraDataCached")
	local unit = SafeCall(item, "GetAuraDataUnit")
	if cached and not CMP.IsSecret(unit) and unit == "player" then
		local instance = HarmfulInstance(cached, "player")
		if instance then
			return instance
		end
	end
	if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then
		return nil
	end
	local ids = {}
	local function Add(id)
		id = Usable(id)
		if id then
			table.insert(ids, id)
		end
	end
	Add(cooldownInfo.linkedSpellID)
	Add(cooldownInfo.overrideSpellID)
	Add(cooldownInfo.spellID)
	if type(cooldownInfo.linkedSpellIDs) == "table" then
		for _, id in ipairs(cooldownInfo.linkedSpellIDs) do
			Add(id)
		end
	end
	for _, id in ipairs(ids) do
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		local instance = ok and HarmfulInstance(aura, "player")
		if instance then
			return instance
		end
	end
	return nil
end

-- In combat the game hides the debuff completely (instance ID included), so there's no
-- real timer to show. Blizzard's item still knows the debuff is on you, though, so we time
-- it ourselves: from the moment it appears, for its full duration. Only for debuffs we've
-- read out of combat at least once, which tells us they're debuffs and their real
-- duration. Those durations are kept per character (talents can change them), so they
-- survive /reload; each new out-of-combat read updates them.
local unsaved = {} -- until the character is known

-- spellID -> duration read out of combat, for this character.
local function Learned()
	local char = CMP.Profiles and CMP.Profiles:Char(true)
	if not char then
		return unsaved
	end
	char.debuffDurations = char.debuffDurations or {}
	for id, duration in pairs(unsaved) do
		char.debuffDurations[id] = duration
	end
	wipe(unsaved)
	return char.debuffDurations
end
-- By spell, not item: Blizzard reuses its icons from a pool as auras come and go.
local estimates = {} -- spellID -> { start, duration }
-- spellID -> true once we saw it absent: the next time it's there, it has just begun.
-- Any absence we see counts, however short: we only look once per frame after an aura
-- change, so what we see absent really was removed. (Guessing "a short gap is the same
-- debuff" from when we last saw it went wrong in combat: every hit on a shield updates
-- the auras, so a debuff put on again right after it ran out looked like the old one, and
-- its timer ran out early.)
local sawEmpty = {}

-- Shown state, or nil when it can't be read.
local function Shown(item)
	local ok, shown = pcall(item.IsShown, item)
	if not ok or CMP.IsSecret(shown) then
		return nil
	end
	return shown == true
end

local function TrackedSpell(cooldownInfo)
	local id = Usable(cooldownInfo.spellID)
	local learned = Learned()
	if id and learned[id] then
		return id
	end
	id = Usable(cooldownInfo.linkedSpellID)
	if id and learned[id] then
		return id
	end
	return nil
end

-- Out of combat: remember the debuff's real start and duration for later.
local function Learn(item, cooldownInfo, instance)
	if not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID then
		return
	end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instance)
	if not ok or type(aura) ~= "table" or CMP.IsSecret(aura) then
		return
	end
	local id, duration, expires = aura.spellId, aura.duration, aura.expirationTime
	if not (Plain(id) and Plain(duration) and Plain(expires)) or duration <= 0 then
		return
	end
	Learned()[id] = duration
	estimates[id] = { start = expires - duration, duration = duration }
	sawEmpty[id] = nil
end

local function ShowEstimate(info, item, cooldownInfo)
	local cached = SafeCall(item, "GetAuraDataCached")
	local unit = SafeCall(item, "GetAuraDataUnit")
	if not cached or CMP.IsSecret(unit) or unit ~= "player" then
		why[item] = cached and "aura isn't on you" or "no aura data"
		return false
	end
	local spell = TrackedSpell(cooldownInfo)
	if not spell then
		why[item] = "not a debuff seen out of combat yet"
		return false
	end
	local now = GetTime()
	local estimate = estimates[spell]
	if sawEmpty[spell] then
		estimate = { start = now, duration = Learned()[spell] }
		estimates[spell] = estimate
		sawEmpty[spell] = nil
	elseif not estimate or now >= estimate.start + estimate.duration then
		why[item] = "already on when we started looking (start unknown)"
		return false
	end
	local cooldown = Overlay(info, item)
	Style(info, item, cooldown, true)
	if not pcall(cooldown.SetCooldown, cooldown, estimate.start, estimate.duration) then
		why[item] = "the game refused the estimate"
		return false
	end
	cooldown:Show()
	SetNativeHidden(item, true)
	why[item] = ("estimate: %.1f s left of %g"):format(estimate.start + estimate.duration - now, estimate.duration)
	return true
end

-- Debuffs we've seen on you through Tracked Buffs (this character): { spellID = duration }.
function Timers:KnownDebuffs()
	return Learned()
end

function Timers:UpdateBuffItem(info, item)
	if not CMP:Get(info.key, "debuffTimers") or Shown(item) ~= true then
		why[item] = CMP:Get(info.key, "debuffTimers") and "hidden" or "debuff timers off"
		Stop(item)
		return
	end
	local cooldownInfo = CooldownInfo(item)
	if not cooldownInfo then
		why[item] = "no cooldown info"
		Stop(item)
		return
	end
	local instance = FindDebuff(item, cooldownInfo)
	if instance and C_UnitAuras and C_UnitAuras.GetAuraDuration then
		local ok, duration = pcall(C_UnitAuras.GetAuraDuration, "player", instance)
		local cooldown = Overlay(info, item)
		Style(info, item, cooldown, true)
		if ok and Show(cooldown, duration) then
			-- Blizzard clears its own timer for these, but can briefly draw one in between
			-- refreshes; ours replaces it, so the two never show at once.
			SetNativeHidden(item, true)
			pcall(Learn, item, cooldownInfo, instance)
			why[item] = "real timer"
			return
		end
	end
	if not ShowEstimate(info, item, cooldownInfo) then
		Stop(item)
	end
end

-- /cmp timers: what the debuff timers see right now.
function Timers:Report()
	local now = GetTime()
	CMP:Print("Debuff timers (in combat: " .. tostring(InCombatLockdown()) .. ")")
	for spell, duration in pairs(Learned()) do
		local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)
		local estimate = estimates[spell]
		local left = estimate and estimate.start + estimate.duration - now
		print(("  %s (%d): learned %g s, seen absent: %s, estimate: %s"):format(
			CMP.IsSecret(name) and "?" or tostring(name or "?"), spell, duration, tostring(sawEmpty[spell] == true),
			left and ("%.1f s left"):format(left) or "none"))
	end
	for _, info in ipairs(CMP.frameInfos) do
		if info.kind == "icons" and info.buffs and info.frame then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				local cooldownInfo = item.layoutIndex and CooldownInfo(item)
				local spell = cooldownInfo and Usable(cooldownInfo.spellID)
				if spell and (why[item] ~= "hidden" or TrackedSpell(cooldownInfo)) then
					print(("  icon %d: %s"):format(spell, tostring(why[item] or "not updated yet")))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- "Show cooldown, not buff duration" (Essential / Utility)
---------------------------------------------------------------------------

function Timers:UpdateCooldownItem(info, item)
	local spellID = CMP:GetItemSpellID(item)
	local style = CMP:GetSpellStyle(spellID)
	if not style or not style.cooldownOnly or not C_Spell or not C_Spell.GetSpellCooldownDuration then
		Stop(item)
		return
	end
	local cooldownInfo = CooldownInfo(item)
	local castID = cooldownInfo and (Usable(cooldownInfo.overrideSpellID) or Usable(cooldownInfo.spellID)) or spellID
	local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, castID, true) -- ignore the global cooldown
	local cooldown = Overlay(info, item)
	Style(info, item, cooldown, false)
	if ok and Show(cooldown, duration) then
		SetNativeHidden(item, true)
	else
		Stop(item) -- refused (hidden from addons): Blizzard's display is back
	end
end

---------------------------------------------------------------------------

function Timers:UpdateItem(info, item)
	if info.kind ~= "icons" or not item.layoutIndex then
		return
	end
	if info.buffs then
		self:UpdateBuffItem(info, item)
	else
		self:UpdateCooldownItem(info, item)
	end
end

function Timers:UpdateViewer(info)
	if info.kind ~= "icons" or not info.frame then
		return
	end
	for item in pairs(CMP.Layout:Items(info.frame)) do
		CMP.Safe(self.UpdateItem, self, info, item)
	end
end

-- Which known debuffs Blizzard's Tracked Buffs currently show on you.
local function PresentDebuffs()
	local present = {}
	for _, info in ipairs(CMP.frameInfos) do
		if info.kind == "icons" and info.buffs and info.frame then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				local cooldownInfo = Shown(item) and CooldownInfo(item)
				local spell = cooldownInfo and TrackedSpell(cooldownInfo)
				if spell and SafeCall(item, "GetAuraDataCached") then
					present[spell] = true
				end
			end
		end
	end
	return present
end

function Timers:UpdateAll(buffsOnly)
	-- A debuff seen absent and then present has just begun: that's when we start timing it.
	local present = PresentDebuffs()
	for spell in pairs(Learned()) do
		if not present[spell] then
			sawEmpty[spell] = true
		end
	end
	for _, info in ipairs(CMP.frameInfos) do
		if info.kind == "icons" and (not buffsOnly or info.buffs) then
			self:UpdateViewer(info)
		end
	end
end

-- Events arrive in bursts; one update per frame is plenty.
local pending = {}
local function Schedule(kind)
	if pending[kind] then
		return
	end
	pending[kind] = true
	C_Timer.After(0, function()
		pending[kind] = nil
		Timers:UpdateAll(kind == "aura")
	end)
end

function Timers:Start()
	if self.events then
		return
	end
	self.events = CreateFrame("Frame")
	pcall(self.events.RegisterUnitEvent, self.events, "UNIT_AURA", "player")
	for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "PLAYER_ENTERING_WORLD" }) do
		pcall(self.events.RegisterEvent, self.events, event)
	end
	self.events:SetScript("OnEvent", function(_, event)
		Schedule(event == "UNIT_AURA" and "aura" or "all")
	end)
	self:UpdateAll()
end
