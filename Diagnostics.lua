local _, ns = ...
local CMP = ns.CMP

-- Records "Interface action failed because of an AddOn" (ADDON_ACTION_BLOCKED /
-- ADDON_ACTION_FORBIDDEN). The game names the addon it blames and the protected function
-- that was refused. Kept in our saved variables (last 50), so it survives /reload:
--   /cme blocked        list them
--   /cme blocked clear  forget them
-- For the full story (which code tainted what), turn on the game's taint log:
--   /console taintLog 1   -> World of Warcraft/_forever_/Logs/taint.log after /reload

local Diagnostics = {}
CMP.Diagnostics = Diagnostics

local MAX = 50
local pending = {} -- before our saved variables load

local function Store()
	local db = _G.CooldownManagerExtrasDB
	if type(db) ~= "table" then
		return pending
	end
	db.blocked = db.blocked or {}
	for _, entry in ipairs(pending) do
		table.insert(db.blocked, entry)
	end
	wipe(pending)
	return db.blocked
end

local function Record(event, addon, func)
	local list = Store()
	local editing = EditModeManagerFrame and EditModeManagerFrame:IsShown()
	table.insert(list, {
		time = date("%Y-%m-%d %H:%M:%S"),
		event = event,
		addon = tostring(addon),
		func = tostring(func),
		combat = InCombatLockdown() and true or false,
		editMode = editing and true or false,
	})
	while #list > MAX do
		table.remove(list, 1)
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, addon, func)
	pcall(Record, event, addon, func)
end)

function Diagnostics:Print(clear)
	local list = Store()
	if clear then
		wipe(list)
		CMP:Print("Blocked-action log cleared.")
		return
	end
	if #list == 0 then
		CMP:Print("No blocked actions recorded.")
		return
	end
	CMP:Print(("%d blocked action(s), newest last:"):format(#list))
	for _, e in ipairs(list) do
		print(("  %s  %s  blamed: |cffffd100%s|r  function: %s%s%s"):format(e.time, e.event == "ADDON_ACTION_FORBIDDEN" and "FORBIDDEN" or "blocked",
			e.addon, e.func, e.combat and "  (combat)" or "", e.editMode and "  (Edit Mode)" or ""))
	end
end

-- /cme probe: what Blizzard's Tracked Buffs / Bars have for each active aura, and whether
-- addons may read it right now (in combat the game hides some auras from addons).
local function Show(value)
	if CMP.IsSecret(value) then -- first: testing a hidden value itself is an error
		return "|cffff6060secret|r"
	end
	if value == nil then
		return "-"
	end
	return tostring(value)
end

function Diagnostics:Probe()
	CMP:Print(("Aura probe (in combat: %s):"):format(InCombatLockdown() and "|cffffd100yes|r" or "no"))
	local any = false
	for _, info in ipairs(CMP.frameInfos) do
		if info.buffs and info.frame then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				local aura = item.GetAuraDataCached and item:GetAuraDataCached()
				if aura then
					any = true
					local ok, c = pcall(item.GetCooldownInfo, item)
					c = ok and type(c) == "table" and c or {}
					local instance = aura.auraInstanceID
					local readable = not CMP.IsSecret(instance) and instance ~= nil
					local timer = "-"
					if readable and C_UnitAuras and C_UnitAuras.GetAuraDuration then
						local unit = item.GetAuraDataUnit and item:GetAuraDataUnit()
						if CMP.IsSecret(unit) or not unit then
							unit = "player"
						end
						local durationOK = pcall(C_UnitAuras.GetAuraDuration, unit, instance)
						timer = durationOK and "|cff60ff60ok|r" or "|cffff6060refused|r"
					end
					local linked = c.linkedSpellID
					local name = not CMP.IsSecret(linked) and linked and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(linked)
					print(("  %s: spell %s linked %s (%s) on %s | instance readable: %s | duration: %s"):format(
						info.key, Show(c.spellID), Show(c.linkedSpellID), tostring(name or "?"),
						Show(item.GetAuraDataUnit and item:GetAuraDataUnit()),
						readable and "|cff60ff60yes|r" or "|cffff6060no|r", timer))
				end
			end
		end
	end
	if not any then
		print("  No active tracked auras.")
	end
end

-- /cme probe spell|item|slot|aura <id>: what addons may read about one cooldown or buff
-- right now, and whether our own cooldown widgets accept it. Run it in and out of combat:
-- it decides what custom entries (Custom.lua) can show.
local GOOD, BAD = "|cff60ff60ok|r", "|cffff6060refused|r"

local function Values(ok, ...)
	if not ok then
		return "|cffff6060error|r"
	end
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = Show((select(i, ...)))
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

local function Fields(value, names)
	if CMP.IsSecret(value) or type(value) ~= "table" then
		return Show(value)
	end
	local parts = {}
	for _, name in ipairs(names) do
		table.insert(parts, name .. "=" .. Show(value[name]))
	end
	return table.concat(parts, " ")
end

local testCooldown
local function TestWidget(method, ...)
	testCooldown = testCooldown or CreateFrame("Cooldown", nil, UIParent)
	local ok = pcall(testCooldown[method], testCooldown, ...)
	testCooldown:Clear()
	return ok and GOOD or BAD
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

function Diagnostics:ProbeOne(kind, arg)
	local id = tonumber(arg)
	if not id and kind == "spell" and arg ~= "" then
		local ok, info = Call(C_Spell and C_Spell.GetSpellInfo, arg)
		id = ok and type(info) == "table" and info.spellID or nil
	elseif not id and kind == "item" and arg ~= "" then
		local ok, itemID = Call(C_Item and C_Item.GetItemInfoInstant, arg)
		id = ok and type(itemID) == "number" and itemID or nil
	end
	if kind == "aura" and not id then
		-- no ID: list your buffs, to find the one to probe
		CMP:Print(("Your buffs and debuffs (in combat: %s):"):format(InCombatLockdown() and "|cffffd100yes|r" or "no"))
		local any = false
		for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
			local label = filter == "HELPFUL" and "|cff60ff60buff|r" or "|cffff6060debuff|r"
			for index = 1, 40 do
				local ok, data = Call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
				if not ok or data == nil then
					break
				end
				any = true
				print("  " .. label .. " " .. Fields(data, { "name", "spellId", "duration", "isFromPlayerOrPlayerPet" }))
			end
		end
		if not any then
			print("  none readable")
		end
		return
	end
	if not id or not (kind == "spell" or kind == "item" or kind == "slot" or kind == "aura") then
		CMP:Print("Usage: /cme probe spell <id or name> | item <id> | slot <13 or 14> | aura <spell id>")
		return
	end
	CMP:Print(("Probe %s %d (in combat: %s):"):format(kind, id, InCombatLockdown() and "|cffffd100yes|r" or "no"))
	if kind == "spell" then
		print("  name: " .. Values(Call(C_Spell and C_Spell.GetSpellName, id)))
		print("  known: " .. Values(Call(IsPlayerSpell, id)))
		local ok, cd = Call(C_Spell and C_Spell.GetSpellCooldown, id)
		print("  GetSpellCooldown: " .. (ok and Fields(cd, { "startTime", "duration", "isEnabled", "isOnGCD" }) or "error"))
		if ok and type(cd) == "table" and not CMP.IsSecret(cd) then
			print("    -> our cooldown widget: " .. TestWidget("SetCooldown", cd.startTime, cd.duration))
		end
		local okDuration, duration = Call(C_Spell and C_Spell.GetSpellCooldownDuration, id, true)
		print("  GetSpellCooldownDuration: " .. (okDuration and (duration ~= nil and "object" or "-") or "error")
			.. (okDuration and duration ~= nil and (" -> our cooldown widget: " .. TestWidget("SetCooldownFromDurationObject", duration, true)) or ""))
		local okCharges, charges = Call(C_Spell and C_Spell.GetSpellCharges, id)
		print("  GetSpellCharges: " .. (okCharges and Fields(charges, { "currentCharges", "maxCharges" }) or "error"))
	elseif kind == "item" then
		print("  name: " .. Values(Call(C_Item and C_Item.GetItemNameByID, id)))
		print("  count: " .. Values(Call(C_Item and C_Item.GetItemCount, id, false, true)))
		local fn = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
		local results = { Call(fn, id) }
		print("  GetItemCooldown (start, duration, enable): " .. Values(unpack(results)))
		if results[1] then
			print("    -> our cooldown widget: " .. TestWidget("SetCooldown", results[2], results[3]))
		end
	elseif kind == "slot" then
		print("  item: " .. Values(Call(GetInventoryItemID, "player", id)))
		local results = { Call(GetInventoryItemCooldown, "player", id) }
		print("  GetInventoryItemCooldown (start, duration, enable): " .. Values(unpack(results)))
		if results[1] then
			print("    -> our cooldown widget: " .. TestWidget("SetCooldown", results[2], results[3]))
		end
	elseif kind == "aura" then
		local ok, aura = Call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, id)
		if not ok then
			print("  GetPlayerAuraBySpellID: error")
		elseif aura == nil then
			print("  GetPlayerAuraBySpellID: nothing (not on you, or hidden from addons)")
		else
			print("  GetPlayerAuraBySpellID: " .. Fields(aura, { "spellId", "auraInstanceID", "duration", "expirationTime", "applications" }))
			local instance = not CMP.IsSecret(aura) and type(aura) == "table" and aura.auraInstanceID or nil
			if instance ~= nil and not CMP.IsSecret(instance) then
				local okDuration, duration = Call(C_UnitAuras.GetAuraDuration, "player", instance)
				print("  GetAuraDuration: " .. (okDuration and duration ~= nil and ("object -> our cooldown widget: " .. TestWidget("SetCooldownFromDurationObject", duration, true)) or "refused"))
			end
		end
		local readable, total = 0, 0
		for index = 1, 40 do
			local okIndex, data = Call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
			if not okIndex or data == nil then
				break
			end
			total = total + 1
			if not CMP.IsSecret(data) and type(data) == "table" and not CMP.IsSecret(data.spellId) then
				readable = readable + 1
			end
		end
		print(("  your buffs: %d listed, %d with a readable spell ID"):format(total, readable))
	end
end

---------------------------------------------------------------------------
-- /cme probe events: logs what the game tells addons when a buff is added to or removed
-- from you, so we can see what is left to work with in combat (procs from gear, buffs from
-- other players): the aura change event and lookups of your custom buffs.
-- Runs until /cme probe events again, or 40 events.
---------------------------------------------------------------------------

local AURA_FIELDS = { "spellId", "name", "icon", "auraInstanceID", "duration", "expirationTime", "isFromPlayerOrPlayerPet" }
local MAX_EVENTS = 40

local function Kind(value)
	if CMP.IsSecret(value) then
		return "|cffffd100secret|r"
	end
	return value == nil and "nil" or type(value)
end

function Diagnostics:ReportAuraEvent(updateInfo)
	local inCombat = InCombatLockdown() and "|cffffd100combat|r" or "no combat"
	if CMP.IsSecret(updateInfo) or type(updateInfo) ~= "table" then
		print(("[%s] UNIT_AURA: updateInfo %s"):format(inCombat, Kind(updateInfo)))
		return true
	end
	local added, removed = updateInfo.addedAuras, updateInfo.removedAuraInstanceIDs
	if not (added or removed or updateInfo.isFullUpdate) then
		return false -- only refreshed values: not interesting, not counted
	end
	print(("[%s] UNIT_AURA: full %s | added %s | removed %s"):format(inCombat, Show(updateInfo.isFullUpdate), Kind(added), Kind(removed)))
	if type(added) == "table" and not CMP.IsSecret(added) then
		for _, aura in ipairs(added) do
			print("  added: " .. Fields(aura, AURA_FIELDS))
			local instance = not CMP.IsSecret(aura) and type(aura) == "table" and aura.auraInstanceID or nil
			if instance ~= nil then
				local okData, data = Call(C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instance)
				print("    by instance: " .. (okData and Fields(data, { "spellId", "name", "duration" }) or "error"))
				local okDuration, duration = Call(C_UnitAuras and C_UnitAuras.GetAuraDuration, "player", instance)
				print("    duration object: " .. (okDuration and duration ~= nil
					and ("yes -> our cooldown widget: " .. TestWidget("SetCooldownFromDurationObject", duration, true)) or "no"))
				local icon = not CMP.IsSecret(aura) and aura.icon
				if icon ~= nil then
					self.testTexture = self.testTexture or UIParent:CreateTexture()
					print("    icon -> our texture: " .. (pcall(self.testTexture.SetTexture, self.testTexture, icon) and GOOD or BAD))
				end
			end
		end
	end
	if type(removed) == "table" and not CMP.IsSecret(removed) then
		for _, instance in ipairs(removed) do
			print("  removed instance: " .. Show(instance))
		end
	end
	-- can your custom buffs be found by spell ID right now?
	for _, entry in ipairs(CMP.Custom:Entries("BuffIcon")) do
		if entry.kind == "aura" then
			local okLookup, aura = Call(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, entry.id)
			print(("  custom %s (%d) by spell ID: %s"):format(tostring(CMP.Custom:Name(entry)), entry.id,
				okLookup and Kind(aura) or "error"))
		end
	end
	return true
end

function Diagnostics:ToggleEventProbe()
	local frame = self.eventProbe
	if frame and frame.on then
		frame:UnregisterAllEvents()
		frame.on = false
		CMP:Print("Event probe off.")
		return
	end
	if not frame then
		frame = CreateFrame("Frame")
		self.eventProbe = frame
		frame:SetScript("OnEvent", function(_, event, _, updateInfo)
			local ok, counted = CMP.Safe(self.ReportAuraEvent, self, updateInfo)
			if ok and counted then
				frame.count = frame.count + 1
				if frame.count >= MAX_EVENTS then
					self:ToggleEventProbe()
				end
			end
		end)
	end
	frame.count = 0
	frame.on = true
	pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", "player")
	-- (no combat log: registering for it is reserved for the Blizzard UI here)
	CMP:Print("Event probe on. Gain and lose buffs in and out of combat, e.g. a gear proc on a target dummy. /cme probe events stops it.")
end
