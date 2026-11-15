-- "Gray out during <debuff>" (Lockouts.lua).
local T = ...

local PWS, WEAKENED = 17, 6788

local function setup(H, opts)
	opts = opts or {}
	H.spells[PWS] = { name = "Power Word: Shield", helpful = opts.helpful ~= false, hasRange = opts.hasRange }
	H.spells[WEAKENED] = { name = "Weakened Soul" }
	local item = H.viewers.Essential:AddItem({ spellID = PWS })
	if opts.lockout ~= false then
		H.CMP:SetSpellStyle(PWS, "lockoutDebuff", WEAKENED)
	end
	return item
end
local function aura(H, unit)
	return H.addAura(unit or "player", { spellId = WEAKENED, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
end
local function tick(H, unit)
	H.fireEvent("UNIT_AURA", unit or "player", {})
	H.flush()
end
local function isGray(item)
	local r, g, b, a = item.Icon:GetVertexColor()
	return item.Icon:IsDesaturated() and math.abs(r - 0.4) < 1e-6 and math.abs(g - 0.4) < 1e-6 and math.abs(b - 0.4) < 1e-6 and a == 1
end
local function isNormal(item)
	local r, g, b = item.Icon:GetVertexColor()
	return not item.Icon:IsDesaturated() and r == 1 and g == 1 and b == 1
end

T.test("lockouts: a spell with a lockout debuff is grayed while the debuff is present", function(H, T)
	local item = setup(H)
	T.truthy(isNormal(item), "starts normal")
	local a = aura(H)
	tick(H)
	T.eq(item.Icon:IsDesaturated(), true, "SetDesaturated(true)")
	local r, g, b, alpha = item.Icon:GetVertexColor()
	T.near(r, 0.4); T.near(g, 0.4); T.near(b, 0.4); T.eq(alpha, 1)
end)

T.test("lockouts: ... and restored after the debuff goes", function(H, T)
	local item = setup(H)
	local a = aura(H)
	tick(H)
	T.truthy(isGray(item))
	H.removeAura("player", a.auraInstanceID)
	tick(H)
	T.eq(item.Icon:IsDesaturated(), false)
	T.truthy(isNormal(item), "Blizzard's own repaint look is back")
end)

T.test("lockouts: not grayed without the debuff, or without a lockout rule", function(H, T)
	local item = setup(H)
	tick(H)
	T.truthy(isNormal(item), "rule set, no debuff")
	local item2 = H.viewers.Utility:AddItem({ spellID = 100 })
	aura(H)
	tick(H)
	T.truthy(isNormal(item2), "no rule for that spell")
	T.truthy(isGray(item))
end)

T.test("lockouts: setting the rule applies at once, clearing it restores", function(H, T)
	local item = setup(H, { lockout = false })
	aura(H)
	tick(H)
	T.truthy(isNormal(item))
	H.CMP:SetSpellStyle(PWS, "lockoutDebuff", WEAKENED)
	T.truthy(isGray(item), "grayed immediately (Skin:RefreshAll)")
	H.CMP:SetSpellStyle(PWS, "lockoutDebuff", nil)
	T.truthy(isNormal(item), "restored immediately")
end)

T.test("lockouts: Blizzard repainting the icon does not undo the gray", function(H, T)
	local item = setup(H)
	aura(H)
	tick(H)
	T.truthy(isGray(item))
	item:RefreshIconColor()
	item:RefreshIconDesaturation()
	T.truthy(isGray(item), "hook re-applied the gray after Blizzard's repaint")
	item.spellOutOfRange = true -- Blizzard paints range red
	item:RefreshIconColor()
	T.truthy(isGray(item))
end)

T.test("lockouts: when the debuff goes, Blizzard's latest look (here: not enough mana) comes back", function(H, T)
	local item = setup(H)
	local a = aura(H)
	tick(H)
	T.truthy(isGray(item))
	-- while grayed, Blizzard repaints: the spell is now unusable for lack of mana
	H.spells[PWS].usable, H.spells[PWS].notEnoughMana = false, true
	item:RefreshIconColor()
	T.truthy(isGray(item), "still gray while locked")
	H.removeAura("player", a.auraInstanceID)
	tick(H)
	local r, g, b = item.Icon:GetVertexColor()
	T.near(r, 0.5); T.near(g, 0.5); T.near(b, 1, 1e-6, "blue-ish 'not enough mana' tint")
end)

T.test("lockouts: Blizzard's cooldown desaturation is kept across a lockout", function(H, T)
	local item = setup(H)
	item.cooldownDesaturated = true
	item:RefreshIconDesaturation() -- spell is on cooldown
	T.eq(item.Icon:IsDesaturated(), true)
	local a = aura(H)
	tick(H)
	T.truthy(isGray(item))
	item.cooldownDesaturated = false
	item:RefreshIconDesaturation() -- cooldown ended while locked
	T.truthy(isGray(item))
	H.removeAura("player", a.auraInstanceID)
	tick(H)
	T.eq(item.Icon:IsDesaturated(), false, "restored to Blizzard's latest (not on cooldown)")
end)

T.test("lockouts: a helpful ranged spell checks the friendly target, not you", function(H, T)
	local item = setup(H, { hasRange = true })
	H.units.target = { friendly = true }
	aura(H, "player") -- Weakened Soul on you, but PW:S would land on the target
	tick(H)
	T.truthy(isNormal(item), "your own debuff does not gray a spell aimed at the target")
	local a = aura(H, "target")
	tick(H, "target")
	T.truthy(isGray(item), "target's debuff grays it")
	H.units.target = nil -- target cleared: spell is self-cast again
	H.fireEvent("PLAYER_TARGET_CHANGED")
	H.flush()
	T.truthy(isGray(item), "now your own debuff counts")
end)

T.test("lockouts: in combat, a debuff Blizzard's Tracked Buffs still sees grays the spell", function(H, T)
	local item = setup(H)
	local tracked = H.viewers.BuffIcon:AddItem({ spellID = PWS, linkedSpellID = WEAKENED })
	H.inCombat = true
	-- nothing readable by spell ID in combat...
	H.setItemAura(tracked, H.secretFields({ auraInstanceID = 900, spellId = WEAKENED, isHarmful = true }), "player")
	tick(H)
	T.truthy(isGray(item), "found through Blizzard's tracked item")
	H.setItemAura(tracked, nil)
	tick(H)
	T.truthy(isNormal(item))
end)

T.test("lockouts: secret aura data is never read as 'present'", function(H, T)
	local item = setup(H)
	local a = aura(H)
	H.secretReturn(_G.C_UnitAuras, "GetUnitAuraBySpellID", "whole")
	tick(H)
	T.truthy(isNormal(item), "a secret answer counts as 'no'")
end)
