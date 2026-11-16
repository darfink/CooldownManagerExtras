local _, ns = ...
local CMP = ns.CMP

-- Custom entries: spells, items and trinket slots you add yourself to Essential or Utility
-- Cooldowns, and buffs (yours or from other players) you add to Tracked Buffs. They show in the same row as Blizzard's icons, in the same look, at the place
-- you pick ("after <spell>", first or last). Added and arranged in Blizzard's Cooldown
-- Settings window (CustomSettings.lua).
--
-- Entry: { kind = "spell" | "item" | "slot" | "aura", id = spellID | itemID | inventorySlot,
--          pos = nil (last) | "start" | spellID (after Blizzard's icon of that spell),
--          always = true (items: shown with none in your bags, e.g. a potion) }
-- Stored per viewer like the other settings (Edit Mode layout or profile): "custom".
--
-- Buffs ("aura", Tracked Buffs only): read from the game when it lets addons see the buff.
-- In combat it may hide buffs from addons; then a buff you start yourself (a trinket, a
-- potion, a spell) is timed from your cast, for the duration read out of combat. The
-- add-on learns which cast starts which buff by watching it happen once out of combat.
--
-- Taint: our icons are our own frames, parented to the viewer but without a layoutIndex,
-- so Blizzard's grid layout never sees them. Layout.lua places them. Cooldowns go to our
-- own Cooldown widgets, through duration objects where the game has them (made for values
-- hidden from addons in combat), else as start/duration handed straight to the widget.

local Custom = {}
CMP.Custom = Custom

local KEYS = { Essential = true, Utility = true, BuffIcon = true }
Custom.KEYS = KEYS

local BASE_SIZE = { Essential = 50, Utility = 30, BuffIcon = 40 }
local TIMER_FONT = { Essential = "GameFontHighlightHugeOutline", Utility = "GameFontHighlightOutline" }
local COUNT_FONT = { Essential = "NumberFontNormal", Utility = "NumberFontNormalSmall", BuffIcon = "NumberFontNormal" }
local OVERLAY_INSET = { Essential = { 9, 8 }, Utility = { 6, 5 }, BuffIcon = { 8, 7 } }
local NATIVE_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local QUESTION_MARK = 134400

local function Plain(value)
	return not CMP.IsSecret(value) and value ~= nil -- secret check first
end

local function Try(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------

function Custom:Entries(key)
	local list = KEYS[key] and CMP:Get(key, "custom")
	return type(list) == "table" and list or {}
end

local function Save(key, list)
	CMP:Set(key, "custom", #list > 0 and list or nil)
	if CMP.CustomSettings then
		CMP.CustomSettings:Refresh()
	end
end

function Custom:Has(key, kind, id)
	for _, entry in ipairs(self:Entries(key)) do
		if entry.kind == kind and entry.id == id then
			return true
		end
	end
	return false
end

-- False if it's already there.
function Custom:Add(key, entry)
	if not KEYS[key] or self:Has(key, entry.kind, entry.id) then
		return false
	end
	local list = CMP.Copy(self:Entries(key))
	table.insert(list, CMP.Copy(entry))
	Save(key, list)
	return true
end

function Custom:Remove(key, index)
	local list = CMP.Copy(self:Entries(key))
	if list[index] then
		table.remove(list, index)
		Save(key, list)
	end
end

function Custom:SetField(key, index, field, value)
	local list = CMP.Copy(self:Entries(key))
	if list[index] then
		list[index][field] = value
		Save(key, list)
	end
end

-- Swap with the neighbour (delta -1 / +1) in the list; ties at the same place keep list order.
function Custom:Move(key, index, delta)
	local list = CMP.Copy(self:Entries(key))
	local other = index + delta
	if list[index] and list[other] then
		list[index], list[other] = list[other], list[index]
		Save(key, list)
	end
end

---------------------------------------------------------------------------
-- What an entry shows: name, icon, whether it's shown at all
---------------------------------------------------------------------------

local function SpellKnown(spellID)
	local any = false
	-- (not a list literal: a missing API would be a nil hole that ends ipairs early)
	local checks = { n = 3, C_SpellBook and C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown }
	for i = 1, checks.n do
		local check = checks[i]
		if type(check) == "function" then
			any = true
			local ok, known = pcall(check, spellID)
			if ok and Plain(known) and known then
				return true
			end
		end
	end
	return not any -- no way to ask: show it
end

local function SpellTexture(spellID)
	local ok, texture = Try(C_Spell and C_Spell.GetSpellTexture, spellID)
	if ok and texture then
		return texture
	end
	ok, texture = Try(GetSpellTexture, spellID)
	return ok and texture or nil
end

local function ItemTexture(itemID)
	local ok, texture = Try(C_Item and C_Item.GetItemIconByID, itemID)
	if ok and texture then
		return texture
	end
	ok, texture = Try(GetItemIcon, itemID)
	return ok and texture or nil
end

local function ItemCount(itemID)
	local ok, count = Try(C_Item and C_Item.GetItemCount, itemID, false, true)
	if not ok then
		ok, count = Try(GetItemCount, itemID, false, true)
	end
	return ok and Plain(count) and count or 0
end

local function IsEquipped(itemID)
	local ok, equipped = Try(C_Item and C_Item.IsEquippedItem, itemID)
	if not ok then
		ok, equipped = Try(IsEquippedItem, itemID)
	end
	return ok and Plain(equipped) and equipped == true
end

local function IsEquippable(itemID)
	local ok, equippable = Try(C_Item and C_Item.IsEquippableItem, itemID)
	if not ok then
		ok, equippable = Try(IsEquippableItem, itemID)
	end
	return ok and Plain(equippable) and equippable == true
end

local function HasUse(itemID)
	local ok, name = Try(C_Item and C_Item.GetItemSpell, itemID)
	if not ok then
		ok, name = Try(GetItemSpell, itemID)
	end
	return ok and name ~= nil
end

local function SlotItem(slot)
	local ok, itemID = Try(GetInventoryItemID, "player", slot)
	return ok and Plain(itemID) and itemID or nil
end

Custom.SLOT_NAMES = { [13] = "Trinket 1", [14] = "Trinket 2" }

function Custom:Name(entry)
	if entry.kind == "spell" or entry.kind == "aura" then
		local ok, name = Try(C_Spell and C_Spell.GetSpellName, entry.id)
		return ok and name or ("Spell " .. tostring(entry.id))
	elseif entry.kind == "item" then
		local ok, name = Try(C_Item and C_Item.GetItemNameByID, entry.id)
		if not (ok and name) then
			ok, name = Try(GetItemInfo, entry.id)
		end
		return ok and name or ("Item " .. tostring(entry.id))
	elseif entry.kind == "slot" then
		local base = self.SLOT_NAMES[entry.id] or ("Slot " .. tostring(entry.id))
		local itemID = SlotItem(entry.id)
		local name = itemID and self:Name({ kind = "item", id = itemID })
		return name and (base .. ": " .. name) or base
	end
	return "?"
end

function Custom:Texture(entry)
	local texture
	if entry.kind == "spell" then
		texture = SpellTexture(entry.id)
	elseif entry.kind == "aura" then
		local seen = self:SeenBuffs()[entry.id]
		texture = seen and seen.icon or SpellTexture(entry.id)
	elseif entry.kind == "item" then
		texture = ItemTexture(entry.id)
	elseif entry.kind == "slot" then
		local ok, slotTexture = Try(GetInventoryItemTexture, "player", entry.id)
		texture = ok and slotTexture or nil
	end
	return texture or QUESTION_MARK
end

-- Shown in the cooldown bar right now? (unknown spells, missing items and trinkets without
-- a use effect are hidden; "always" items stay)
function Custom:IsAvailable(entry)
	if entry.kind == "spell" then
		return SpellKnown(entry.id)
	elseif entry.kind == "aura" then
		return true -- shown while the buff is on you (see AuraState)
	elseif entry.kind == "item" then
		return entry.always == true or ItemCount(entry.id) > 0 or IsEquipped(entry.id)
	elseif entry.kind == "slot" then
		local itemID = SlotItem(entry.id)
		return itemID ~= nil and HasUse(itemID)
	end
	return false
end

-- Cooldown info in the shape Blizzard's items give it (Skin, Keybinds read it).
local function CooldownInfoFor(entry)
	if entry.kind == "spell" or entry.kind == "aura" then
		return { spellID = entry.id, isCustom = true }
	elseif entry.kind == "item" then
		return { itemID = entry.id, isCustom = true }
	elseif entry.kind == "slot" then
		return { equipSlot = entry.id, isCustom = true }
	end
	return { isCustom = true }
end

---------------------------------------------------------------------------
-- Icons in the bars
---------------------------------------------------------------------------

local framesByKey = {} -- key -> list of our icon frames (reused)
local shownByKey = {} -- key -> list of { frame, entry, index } shown now

local function GetCooldownInfo(self)
	return self.cooldownInfo
end

-- Built like Blizzard's item template (CooldownViewerEssentialItemTemplate), so the Skin
-- code styles it the same way: Icon + mask, frame art, Cooldown, ChargeCount.Current.
local function CreateIcon(info)
	local key = info.key
	local frame = CreateFrame("Frame", nil, info.frame)
	frame:SetSize(BASE_SIZE[key], BASE_SIZE[key])
	frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	frame.Icon:SetAllPoints()
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
	mask:SetAllPoints()
	frame.Icon:AddMaskTexture(mask)
	local overlay = frame:CreateTexture(nil, "OVERLAY")
	overlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
	local x, y = OVERLAY_INSET[key][1], OVERLAY_INSET[key][2]
	overlay:SetPoint("TOPLEFT", -x, y)
	overlay:SetPoint("BOTTOMRIGHT", x, -y)
	local cooldown = CreateFrame("Cooldown", nil, frame)
	cooldown:SetAllPoints()
	cooldown:SetSwipeTexture(NATIVE_SWIPE)
	cooldown:SetSwipeColor(0, 0, 0, 0.7)
	cooldown:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown")
	cooldown:SetDrawBling(false)
	if TIMER_FONT[key] then
		frame.cooldownFont = TIMER_FONT[key]
		pcall(cooldown.SetCountdownFont, cooldown, TIMER_FONT[key])
	end
	if info.buffs and cooldown.SetUseAuraDisplayTime then
		cooldown:SetUseAuraDisplayTime(true) -- like Blizzard's buff icons
	end
	frame.Cooldown = cooldown
	-- the count: ChargeCount.Current on cooldown icons, Applications.Applications on buffs
	-- (the names Blizzard's templates use; Media.lua styles both)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints()
	holder:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local count = holder:CreateFontString(nil, "OVERLAY", COUNT_FONT[key])
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	if info.buffs then
		holder.Applications = count
		frame.Applications = holder
	else
		holder.Current = count
		frame.ChargeCount = holder
	end
	frame.countText = count
	frame.GetCooldownInfo = GetCooldownInfo
	frame.isCustom = true
	frame:SetScript("OnEnter", function(self)
		CMP.Safe(Custom.ShowTooltip, Custom, self)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame:Hide()
	return frame
end

-- Hover tooltip, like Blizzard's icons (only when the viewer shows tooltips, see StyleIcon).
function Custom:ShowTooltip(frame)
	local entry = frame.entry
	if not entry then
		return
	end
	local tooltip = GameTooltip
	if GameTooltip_SetDefaultAnchor then
		GameTooltip_SetDefaultAnchor(tooltip, frame)
	else
		tooltip:SetOwner(frame, "ANCHOR_RIGHT")
	end
	local shown = false
	local aura = frame.auraState and frame.auraState.aura
	if aura and tooltip.SetUnitBuffByAuraInstanceID and not CMP.IsSecret(aura.auraInstanceID) and aura.auraInstanceID then
		local harmful = aura.isHarmful
		harmful = Plain(harmful) and harmful == true -- secret check first
		local method = harmful and tooltip.SetUnitDebuffByAuraInstanceID or tooltip.SetUnitBuffByAuraInstanceID
		shown = method ~= nil and (pcall(method, tooltip, "player", aura.auraInstanceID))
	end
	if not shown then
		if (entry.kind == "spell" or entry.kind == "aura") and tooltip.SetSpellByID then
			shown = (pcall(tooltip.SetSpellByID, tooltip, entry.id))
		elseif entry.kind == "item" and tooltip.SetItemByID then
			shown = (pcall(tooltip.SetItemByID, tooltip, entry.id))
		elseif entry.kind == "slot" and tooltip.SetInventoryItem then
			shown = (pcall(tooltip.SetInventoryItem, tooltip, "player", entry.id))
		end
	end
	if not shown or tooltip:NumLines() == 0 then
		tooltip:SetText(self:Name(entry), 1, 1, 1)
	end
	tooltip:Show()
end

local function SetCount(fontString, value)
	if value == nil or not pcall(fontString.SetText, fontString, value) then
		fontString:SetText("")
	end
end

local function ShowDuration(cooldown, duration)
	if duration == nil then
		return false
	end
	return (pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true))
end

-- Values may be hidden from addons: handed to the widget as they are, never compared.
local function ShowTimes(cooldown, start, duration, modRate)
	if start == nil or duration == nil then
		cooldown:Clear()
		return
	end
	if not pcall(cooldown.SetCooldown, cooldown, start, duration, modRate) then
		cooldown:Clear()
	end
end

local function UpdateSpell(frame, spellID)
	local cooldown = frame.Cooldown
	local shown = false
	local okCharges, charges = Try(C_Spell and C_Spell.GetSpellCharges, spellID)
	charges = okCharges and type(charges) == "table" and charges or nil
	if charges then
		-- Spells with charges: the time to the next charge (the plain cooldown stays at zero
		-- while a charge is left).
		if C_Spell.GetSpellChargeDuration then
			local ok, duration = pcall(C_Spell.GetSpellChargeDuration, spellID)
			shown = ok and ShowDuration(cooldown, duration)
		end
		if not shown then
			ShowTimes(cooldown, charges.cooldownStartTime, charges.cooldownDuration, charges.chargeModRate)
			shown = true
		end
	end
	if not shown and C_Spell and C_Spell.GetSpellCooldownDuration then
		local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID, true) -- no GCD
		shown = ok and ShowDuration(cooldown, duration)
	end
	if not shown then
		local ok, cd = Try(C_Spell and C_Spell.GetSpellCooldown, spellID)
		if ok and type(cd) == "table" then
			local gcd = cd.isOnGCD
			if Plain(gcd) and gcd then
				cooldown:Clear()
			else
				ShowTimes(cooldown, cd.startTime, cd.duration, cd.modRate)
			end
		else
			cooldown:Clear()
		end
	end
	if charges then
		local okMulti, multi = pcall(function() return charges.maxCharges > 1 end)
		SetCount(frame.countText, (not okMulti or multi) and charges.currentCharges or nil)
	else
		SetCount(frame.countText, nil)
	end
	frame.Icon:SetDesaturated(false)
end

local function ItemCooldown(itemID)
	if C_Item and C_Item.GetItemCooldown then
		return pcall(C_Item.GetItemCooldown, itemID)
	end
	return Try(GetItemCooldown, itemID)
end

local function UpdateItem(frame, entry)
	local itemID = entry.id
	local ok, start, duration = ItemCooldown(itemID)
	if ok then
		ShowTimes(frame.Cooldown, start, duration)
	else
		frame.Cooldown:Clear()
	end
	local count = ItemCount(itemID)
	if IsEquippable(itemID) then
		SetCount(frame.countText, nil)
	else
		SetCount(frame.countText, count)
	end
	frame.Icon:SetDesaturated(count == 0 and not IsEquipped(itemID))
end

local function UpdateSlot(frame, slot)
	local ok, start, duration = Try(GetInventoryItemCooldown, "player", slot)
	if ok then
		ShowTimes(frame.Cooldown, start, duration)
	else
		frame.Cooldown:Clear()
	end
	SetCount(frame.countText, nil)
	frame.Icon:SetDesaturated(false)
end

---------------------------------------------------------------------------
-- Buffs
---------------------------------------------------------------------------

local estimates = {} -- buff spellID -> { start, duration }: timed from your cast (combat)
local lastCasts = {} -- spellID -> GetTime() of your last cast of it
local wasOn = {} -- buff spellID -> true while we saw it on you

local function Saved(name)
	local db = CMP.db
	if not db then
		return {}
	end
	db[name] = db[name] or {}
	return db[name]
end

-- Buffs seen on you out of combat (for the + menu): spellID -> { name, icon, duration,
-- external = from another player, seen = time() }. The newest 60 are kept.
function Custom:SeenBuffs()
	return Saved("seenBuffs")
end

local MAX_SEEN = 60

function Custom:RecordBuffs()
	if InCombatLockdown() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		return
	end
	local seen = self:SeenBuffs()
	local now = time()
	-- buffs, and debuffs you put on yourself (an item's self-stun, ...); not enemies' debuffs
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		for index = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
			if not ok or aura == nil or CMP.IsSecret(aura) or type(aura) ~= "table" then
				break
			end
			local id = aura.spellId
			local own = aura.isFromPlayerOrPlayerPet
			local harmful = filter == "HARMFUL"
			if Plain(id) and type(id) == "number" and not (harmful and not (Plain(own) and own == true)) then
				seen[id] = {
					name = Plain(aura.name) and aura.name or nil,
					icon = Plain(aura.icon) and aura.icon or nil,
					duration = Plain(aura.duration) and aura.duration or nil,
					external = Plain(own) and own == false or nil,
					harmful = harmful or nil,
					seen = now,
				}
			end
		end
	end
	local count, oldestID, oldest = 0, nil, math.huge
	for id, info in pairs(seen) do
		count = count + 1
		if (info.seen or 0) < oldest then
			oldestID, oldest = id, info.seen or 0
		end
	end
	if count > MAX_SEEN and oldestID then
		seen[oldestID] = nil
	end
end

-- Learns which of your casts starts this buff: only out of combat, only when the buff is
-- your own and has just been applied (its start time is now), from a cast just before it.
local function LearnTrigger(id, aura, now)
	if InCombatLockdown() then
		return
	end
	local own, expiration, duration = aura.isFromPlayerOrPlayerPet, aura.expirationTime, aura.duration
	if not (Plain(own) and own == true and Plain(expiration) and Plain(duration)) then
		return
	end
	if type(expiration) ~= "number" or type(duration) ~= "number" or duration <= 0 then
		return
	end
	local applied = expiration - duration
	if now - applied > 1 then
		return -- already on for a while: not something we just watched start
	end
	local best, bestTime = nil, -math.huge
	for castID, castTime in pairs(lastCasts) do
		if castTime <= applied + 0.1 and castTime >= applied - 0.5 and castTime > bestTime then
			best, bestTime = castID, castTime
		end
	end
	if best then
		Saved("buffTriggers")[id] = best
	end
end

-- An aura on you by spell ID: ok, aura (maybe secret) or nil. The lookup by spell ID may
-- only cover buffs, so debuffs are also searched one by one.
local function FindPlayerAura(id)
	local ok, aura = Try(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, id)
	if ok and (CMP.IsSecret(aura) or aura ~= nil) then
		return ok, aura
	end
	local okUnit, unitAura = Try(C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID, "player", id)
	if okUnit and (CMP.IsSecret(unitAura) or unitAura ~= nil) then
		return okUnit, unitAura
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
			for index = 1, 40 do
				local okIndex, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
				if not okIndex or data == nil or CMP.IsSecret(data) or type(data) ~= "table" then
					break
				end
				local spellId = data.spellId
				if Plain(spellId) and spellId == id then
					return true, data
				end
			end
		end
	end
	return ok or okUnit, nil
end

-- { active, aura (readable table) | nil, estimate | nil }
function Custom:AuraState(entry)
	local id = entry.id
	local ok, aura = FindPlayerAura(id)
	local now = GetTime()
	local secret = ok and CMP.IsSecret(aura)
	if ok and not secret and type(aura) == "table" then
		local duration = aura.duration
		if Plain(duration) and type(duration) == "number" and duration > 0 then
			Saved("buffDurations")[id] = duration
		end
		if not wasOn[id] then
			wasOn[id] = true
			LearnTrigger(id, aura, now)
		end
		return { active = true, aura = aura }
	end
	local inCombat = InCombatLockdown()
	if not inCombat then
		-- out of combat a lookup that finds nothing means it's not on you
		if not secret then
			wasOn[id] = nil
		end
		local estimate = estimates[id]
		if estimate and now - estimate.start > 1 then
			estimates[id] = nil -- (kept for a moment: the buff can land just after the cast)
		end
		return { active = false }
	end
	-- in combat: hidden from addons, or gone; our timing from your cast decides
	local estimate = estimates[id]
	if estimate and now < estimate.start + estimate.duration then
		return { active = true, estimate = estimate }
	end
	estimates[id] = nil
	return { active = false }
end

-- Your cast of spellID: starts the buffs it is known to start (timed, for combat).
function Custom:OnCast(spellID)
	local now = GetTime()
	lastCasts[spellID] = now
	for castID, castTime in pairs(lastCasts) do
		if now - castTime > 5 then
			lastCasts[castID] = nil
		end
	end
	local triggers, durations = Saved("buffTriggers"), Saved("buffDurations")
	for _, entry in ipairs(self:Entries("BuffIcon")) do
		local id = entry.id
		local duration = durations[id]
		if entry.kind == "aura" and triggers[id] == spellID and duration then
			estimates[id] = { start = now, duration = duration }
			-- each one hides on time, not when the longest is done
			C_Timer.After(duration + 0.05, function()
				CMP.Safe(self.SyncAll, self)
			end)
		end
	end
end

function Custom:OnCombatEnd()
	wipe(estimates) -- out of combat buffs are read directly again
end

local function UpdateAura(frame, entry)
	local state = frame.auraState or {}
	local cooldown = frame.Cooldown
	frame.Icon:SetDesaturated(not state.active)
	local aura = state.aura
	if aura then
		if Plain(aura.icon) and aura.icon then
			frame.Icon:SetTexture(aura.icon)
		end
		local shown = false
		local instance = aura.auraInstanceID
		if C_UnitAuras.GetAuraDuration and (CMP.IsSecret(instance) or instance ~= nil) then
			local ok, duration = pcall(C_UnitAuras.GetAuraDuration, "player", instance)
			shown = ok and ShowDuration(cooldown, duration)
		end
		if not shown then
			local okStart, start, timed = pcall(function()
				return aura.expirationTime - aura.duration, aura.duration > 0
			end)
			if okStart and timed then
				ShowTimes(cooldown, start, aura.duration)
			else
				cooldown:Clear() -- no duration, or hidden values
			end
		end
		local okStacks, stacks = pcall(function() return aura.applications > 1 and aura.applications or nil end)
		SetCount(frame.countText, okStacks and stacks or nil)
	elseif state.estimate then
		ShowTimes(cooldown, state.estimate.start, state.estimate.duration)
		SetCount(frame.countText, nil)
	else
		cooldown:Clear()
		SetCount(frame.countText, nil)
	end
end

-- Tracked Buffs set to show inactive buffs (Edit Mode): ours stay too, grayed.
local function ShowsInactive(info)
	local hide = info.frame and info.frame.hideWhenInactive
	return Plain(hide) and hide == false
end

function Custom:UpdateCooldown(frame, entry)
	if entry.kind == "aura" then
		UpdateAura(frame, entry)
	elseif entry.kind == "spell" then
		UpdateSpell(frame, entry.id)
	elseif entry.kind == "item" then
		UpdateItem(frame, entry)
	elseif entry.kind == "slot" then
		UpdateSlot(frame, entry.id)
	end
end

local function SameShown(old, new)
	if #old ~= #new then
		return false
	end
	for i = 1, #new do
		local a, b = old[i], new[i]
		if a.frame ~= b.frame or a.entry.kind ~= b.entry.kind or a.entry.id ~= b.entry.id or a.entry.pos ~= b.entry.pos
			or a.active ~= b.active then
			return false
		end
	end
	return true
end

-- Brings the icons of one viewer in line with its entries. True if what's shown changed
-- (the row needs a new layout).
function Custom:Sync(info)
	local key = info.key
	if not KEYS[key] or not info.frame then
		return false
	end
	local frames = framesByKey[key] or {}
	framesByKey[key] = frames
	local shown = {}
	local index = 0
	for i, entry in ipairs(self:Entries(key)) do
		local available = self:IsAvailable(entry)
		local auraState
		if available and entry.kind == "aura" then
			auraState = self:AuraState(entry)
			available = auraState.active or ShowsInactive(info)
		end
		if available then
			index = index + 1
			local frame = frames[index]
			if not frame then
				frame = CreateIcon(info)
				frames[index] = frame
			end
			frame.entry = entry
			frame.entryIndex = i
			frame.cooldownInfo = CooldownInfoFor(entry)
			frame.auraState = auraState
			frame.Icon:SetTexture(self:Texture(entry))
			frame:Show()
			self:UpdateCooldown(frame, entry)
			shown[#shown + 1] = { frame = frame, entry = entry, index = i, active = auraState and auraState.active }
		end
	end
	for i = index + 1, #frames do
		frames[i]:Hide()
		frames[i].entry = nil
	end
	local changed = not SameShown(shownByKey[key] or {}, shown)
	shownByKey[key] = shown
	if changed then
		for _, item in ipairs(shown) do
			CMP.Safe(self.StyleIcon, self, info, item.frame)
		end
	end
	return changed
end

-- Edit Mode's "Show Timer", read from one of Blizzard's icons in the same viewer.
local function NativeHidesTimer(info)
	for item in pairs(CMP.Layout:Items(info.frame)) do
		local cooldown = item.Cooldown
		if cooldown and cooldown.GetHideCountdownNumbers then
			local ok, hide = pcall(cooldown.GetHideCountdownNumbers, cooldown)
			if ok and Plain(hide) then
				return hide == true
			end
		end
	end
	return nil
end

function Custom:StyleIcon(info, frame)
	local hide = NativeHidesTimer(info)
	if hide ~= nil then
		frame.Cooldown:SetHideCountdownNumbers(hide)
	end
	-- Blizzard's icons: hover for a tooltip when the viewer shows tooltips, never clicks
	local tooltips = info.frame.tooltipsShown
	frame:SetMouseClickEnabled(false)
	frame:SetMouseMotionEnabled(not (Plain(tooltips) and tooltips == false))
	CMP.Layout:ApplyItemScale(info, frame)
	CMP.Skin:ApplyItem(info, frame)
	CMP.Media:StyleItem(info, frame)
	CMP.Keybinds:ApplyItem(info, frame)
end

-- Our icons shown in this viewer: list of frames.
function Custom:Frames(info)
	local result = {}
	for _, item in ipairs(shownByKey[info.key] or {}) do
		result[#result + 1] = item.frame
	end
	return result
end

function Custom:HasShown(info)
	local shown = shownByKey[info.key]
	return shown ~= nil and #shown > 0
end

-- Where each icon goes among Blizzard's: sortMajor = layoutIndex of the icon it follows
-- (0 = first, huge = last), sortMinor = its place in the entry list.
-- appendOnly: all after Blizzard's, in list order (a viewer whose icons stay where
-- Blizzard put them: ours can't go between them).
function Custom:AssignOrder(info, appendOnly)
	local shown = shownByKey[info.key]
	if not shown or #shown == 0 then
		return
	end
	local bySpell = {}
	local last = 0
	for item in pairs(CMP.Layout:Items(info.frame)) do
		local index = item.layoutIndex
		if index and item:GetParent() == info.frame then
			last = math.max(last, index)
			local spellID = CMP:GetItemSpellID(item)
			if spellID and (not bySpell[spellID] or index < bySpell[spellID]) then
				bySpell[spellID] = index
			end
		end
	end
	for _, item in ipairs(shown) do
		local pos = item.entry.pos
		local major
		if appendOnly then
			major = last + 1
		elseif pos == "start" then
			major = 0
		elseif type(pos) == "number" and bySpell[pos] then
			major = bySpell[pos]
		else
			major = last + 1
		end
		item.frame.sortMajor = major
		item.frame.sortMinor = item.index
	end
end

function Custom:RefreshStyles(info)
	for _, item in ipairs(shownByKey[info.key] or {}) do
		CMP.Safe(self.StyleIcon, self, info, item.frame)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function Custom:UpdateAllCooldowns()
	for _, shown in pairs(shownByKey) do
		for _, item in ipairs(shown) do
			CMP.Safe(self.UpdateCooldown, self, item.frame, item.entry)
		end
	end
end

-- In combat a frame can become protected (something protected anchored to it); then
-- nothing changes until combat ends (CMP:CanTouch marks an update for then).
function Custom:CanTouch(info)
	if not InCombatLockdown() then
		return true
	end
	if not CMP:CanTouch(info.frame) then
		return false
	end
	for _, frame in ipairs(framesByKey[info.key] or {}) do
		if not CMP:CanTouch(frame) then
			return false
		end
	end
	return true
end

function Custom:SyncAll()
	for key in pairs(KEYS) do
		local info = CMP.byKey[key]
		if info and info.frame and self:CanTouch(info) and self:Sync(info) then
			CMP.Layout:Run(info)
		end
	end
end

local COOLDOWN_EVENTS = {
	"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
}
local CONTENT_EVENTS = {
	"BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE",
	"TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED", "GET_ITEM_INFO_RECEIVED",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
}

function Custom:Start()
	if self.events then
		return
	end
	-- Blizzard's "show tooltips" setting changes: ours follow
	for key in pairs(KEYS) do
		local info = CMP.byKey[key]
		if info and info.frame then
			CMP.HookMethod(info.frame, "SetTooltipsShown", function()
				CMP.Safe(self.RefreshStyles, self, info)
			end)
		end
	end
	local cooldownEvents = {}
	for _, event in ipairs(COOLDOWN_EVENTS) do
		cooldownEvents[event] = true
	end
	self.events = CreateFrame("Frame")
	for _, event in ipairs(COOLDOWN_EVENTS) do
		pcall(self.events.RegisterEvent, self.events, event)
	end
	for _, event in ipairs(CONTENT_EVENTS) do
		pcall(self.events.RegisterEvent, self.events, event)
	end
	pcall(self.events.RegisterUnitEvent, self.events, "UNIT_AURA", "player")
	pcall(self.events.RegisterUnitEvent, self.events, "UNIT_SPELLCAST_SUCCEEDED", "player")
	self.events:SetScript("OnEvent", function(_, event, _, _, spellID)
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if Plain(spellID) and type(spellID) == "number" then
				CMP.Safe(self.OnCast, self, spellID)
			end
		end
		if event == "UNIT_AURA" then
			CMP.Safe(self.RecordBuffs, self)
		elseif event == "PLAYER_REGEN_ENABLED" then
			self:OnCombatEnd()
		end
		if cooldownEvents[event] then
			CMP.Safe(self.UpdateAllCooldowns, self)
		elseif not self.syncPending then
			-- bursts of bag / talent events: once, next frame
			self.syncPending = true
			C_Timer.After(0, function()
				self.syncPending = false
				CMP.Safe(self.SyncAll, self)
			end)
		end
	end)
end
