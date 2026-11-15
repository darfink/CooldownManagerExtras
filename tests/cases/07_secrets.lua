-- Secret values: in combat the client hides aura / cooldown values from addons. Refreshing with
-- secret fields must never raise (CMP.Safe would swallow it, but the harness records it).
local T = ...

local PWS, WEAKENED = 17, 6788

-- Items in every viewer; the buff items carry an aura.
local function populate(H)
	H.spells[WEAKENED] = { name = "Weakened Soul" }
	H.spells[PWS] = { name = "Power Word: Shield", helpful = true }
	local items = {}
	items.essential = H.viewers.Essential:AddItem({ spellID = PWS })
	items.utility = H.viewers.Utility:AddItem({ spellID = 100 })
	items.buff = H.viewers.BuffIcon:AddItem({ spellID = PWS, linkedSpellID = WEAKENED })
	items.bar = H.viewers.BuffBar:AddItem({ spellID = 200, linkedSpellID = WEAKENED })
	return items
end

-- Every refresh path the addon has.
local function refreshEverything(H)
	local CMP = H.CMP
	CMP:Update()
	CMP.Skin:RefreshAll()
	CMP.Timers:UpdateAll()
	CMP.Lockouts:UpdateAll()
	CMP.Keybinds:Rebuild()
	for _, key in ipairs({ "Essential", "Utility", "BuffIcon", "BuffBar" }) do
		H.viewers[key]:Layout()
		H.viewers[key]:RefreshData()
	end
	H.fireEvent("UNIT_AURA", "player", {})
	H.fireEvent("SPELL_UPDATE_COOLDOWN")
	H.fireEvent("PLAYER_TARGET_CHANGED")
	H.flush()
	H.advance(1)
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("probe")
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("status")
end

local function secretAura(H)
	return H.secretFields({ auraInstanceID = 900, spellId = WEAKENED, isHarmful = true, isHelpful = false,
		duration = 15, expirationTime = H.now + 15, name = "Weakened Soul", applications = 1 })
end

T.test("secrets: the helper really makes values that raise on use", function(H, T)
	local s = H.secret(5)
	T.truthy(_G.issecretvalue(s))
	T.eq(type(s), "number", "type() still reports the underlying type")
	T.errors(function() return s + 1 end, "secret")
	T.errors(function() return s < 3 end)
	T.errors(function() return s .. "x" end, "secret")
	T.errors(function() return #s end, "secret")
	T.falsy(_G.issecretvalue(5))
end)

T.test("secrets: refresh with a secret aura (every field secret) raises nothing", function(H, T)
	local items = populate(H)
	H.inCombat = true
	H.setItemAura(items.buff, secretAura(H), "player")
	H.setItemAura(items.bar, secretAura(H), "player")
	refreshEverything(H)
end)

T.test("secrets: ... also after the debuff duration was learned", function(H, T)
	local items = populate(H)
	local aura = H.addAura("player", { spellId = WEAKENED, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
	H.setItemAura(items.buff, aura, "player")
	refreshEverything(H)
	T.eq(H.CMP.Timers:KnownDebuffs()[WEAKENED], 15)
	H.removeAura("player", aura.auraInstanceID)
	H.setItemAura(items.buff, nil)
	refreshEverything(H)
	H.advance(60)
	H.inCombat = true
	H.setItemAura(items.buff, secretAura(H), "player")
	refreshEverything(H)
end)

T.test("secrets: the aura's unit is secret", function(H, T)
	local items = populate(H)
	H.inCombat = true
	H.setItemAura(items.buff, secretAura(H), H.secret("player"))
	refreshEverything(H)
end)

T.test("secrets: only the instance ID is secret (flags readable)", function(H, T)
	local items = populate(H)
	H.inCombat = true
	local aura = { auraInstanceID = H.secret(900), spellId = WEAKENED, isHarmful = true, isHelpful = false, duration = 15, expirationTime = H.now + 15 }
	H.setItemAura(items.buff, aura, "player")
	refreshEverything(H)
end)

T.test("secrets: only the harmful flags are secret (instance readable): the game is asked", function(H, T)
	local items = populate(H)
	H.inCombat = true
	local a = H.addAura("player", { spellId = WEAKENED, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
	local aura = { auraInstanceID = a.auraInstanceID, spellId = WEAKENED, isHarmful = H.secret(true), isHelpful = H.secret(false) }
	H.setItemAura(items.buff, aura, "player")
	refreshEverything(H)
	-- IsAuraFilteredOutByInstanceID said "not filtered out by HARMFUL": a timer is shown
	local shown
	for _, child in ipairs({ items.buff:GetChildren() }) do
		if child:GetObjectType() == "Cooldown" and child ~= items.buff.Cooldown and child:IsShown() then shown = true end
	end
	T.truthy(shown, "harmful by the game's own answer: timer shown")
end)

T.test("secrets: secret cooldown info (spell IDs hidden) on every item", function(H, T)
	local items = populate(H)
	for _, item in pairs(items) do
		item.cooldownInfo = H.secretFields(item.cooldownInfo)
	end
	H.inCombat = true
	refreshEverything(H)
	T.eq(H.CMP:GetItemSpellID(items.essential), nil, "no spell ID readable")
end)

T.test("secrets: lockout rule with secret cooldown info does not gray anything", function(H, T)
	local items = populate(H)
	H.CMP:SetSpellStyle(PWS, "lockoutDebuff", WEAKENED)
	H.addAura("player", { spellId = WEAKENED, isHarmful = true })
	items.essential.cooldownInfo = H.secretFields(items.essential.cooldownInfo)
	refreshEverything(H)
	T.falsy(items.essential.Icon:IsDesaturated())
end)

T.test("secrets: IsShown() is secret on the items", function(H, T)
	local items = populate(H)
	for _, item in pairs(items) do H.secretReturn(item, "IsShown") end
	H.inCombat = true
	H.CMP:Set("BuffIcon", "align", "center") -- activates our layout engine
	refreshEverything(H)
end)

T.test("secrets: icon item size and the viewers' rectangles are secret", function(H, T)
	local items = populate(H)
	for _, key in ipairs({ "essential", "utility", "buff" }) do
		H.secretReturn(items[key], "GetWidth")
		H.secretReturn(items[key], "GetHeight")
	end
	for _, key in ipairs({ "Essential", "Utility", "BuffIcon", "BuffBar" }) do
		H.secretReturn(H.viewers[key], "GetRect")
	end
	H.inCombat = true
	H.CMP:Set("Essential", "align", "center")
	H.CMP:Set("Essential", "style", "square")
	refreshEverything(H)
end)

T.test("secrets: a Tracked Bars item whose width is secret (combat) does not raise", function(H, T)
	local items = populate(H)
	H.secretReturn(items.bar, "GetWidth")
	H.inCombat = true
	H.CMP:Set("BuffBar", "barStyle", "square")
	refreshEverything(H)
end)

T.test("secrets: every aura API answers with secrets (full combat)", function(H, T)
	local items = populate(H)
	H.addAura("player", { spellId = WEAKENED, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
	H.inCombat = true
	for _, name in ipairs({ "GetPlayerAuraBySpellID", "GetUnitAuraBySpellID", "GetAuraDataByAuraInstanceID" }) do
		H.secretReturn(_G.C_UnitAuras, name, "fields")
	end
	H.secretReturn(_G.C_UnitAuras, "IsAuraFilteredOutByInstanceID", "whole")
	H.CMP:SetSpellStyle(PWS, "lockoutDebuff", WEAKENED)
	H.setItemAura(items.buff, secretAura(H), "player")
	refreshEverything(H)
end)

T.test("secrets: C_Spell results are secret (cooldown durations, names, power costs)", function(H, T)
	local items = populate(H)
	H.inCombat = true
	H.CMP:SetSpellStyle(PWS, "cooldownOnly", true)
	H.CMP:SetSpellStyle(PWS, "lockoutDebuff", WEAKENED)
	for _, name in ipairs({ "GetSpellName", "IsSpellHelpful", "SpellHasRange", "GetSpellCooldownDuration" }) do
		H.secretReturn(_G.C_Spell, name, "whole")
	end
	refreshEverything(H)
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", PWS)
	H.flush()
end)

T.test("secrets: a secret ADDON_ACTION_BLOCKED payload is recorded without raising", function(H, T)
	H.fireEvent("ADDON_ACTION_BLOCKED", H.secret("X"), H.secret("Y"))
	H.flush()
end)
