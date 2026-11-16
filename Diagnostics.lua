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
