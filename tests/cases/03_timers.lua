-- Debuff timers on Tracked Buffs (Timers.lua) and "show cooldown, not buff duration".
local T = ...

local PWS, WEAKENED = 17, 6788 -- Power Word: Shield tracks Weakened Soul
local CHAR = "Tester-Realm"

local function overlay(item, H)
	for _, child in ipairs({ item:GetChildren() }) do
		if child:GetObjectType() == "Cooldown" and child ~= item.Cooldown then return child end
	end
end

local function newItem(H)
	H.spells[WEAKENED] = { name = "Weakened Soul" }
	return H.viewers.BuffIcon:AddItem({ spellID = PWS, linkedSpellID = WEAKENED })
end

-- Weakened Soul on you, readable (out of combat), cached by Blizzard's item
local function applyDebuff(H, item, duration)
	duration = duration or 15
	local aura = H.addAura("player", { spellId = WEAKENED, isHarmful = true, isHelpful = false, duration = duration,
		expirationTime = H.now + duration, name = "Weakened Soul" })
	H.setItemAura(item, aura, "player")
	return aura
end
local function clearDebuff(H, item, aura)
	if aura then H.removeAura("player", aura.auraInstanceID) end
	H.setItemAura(item, nil)
end
-- The same debuff in combat: Blizzard's item still caches it, but every field is secret and
-- lookups by spell ID find nothing.
local function applyHiddenDebuff(H, item)
	local aura = H.secretFields({ auraInstanceID = 900, spellId = WEAKENED, isHarmful = true, isHelpful = false,
		duration = 15, expirationTime = H.now + 15 })
	H.setItemAura(item, aura, "player")
	return aura
end
local function auraEvent(H)
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.flush()
end

T.test("timers: out of combat, a harmful aura on a Tracked Buffs item gets a timer", function(H, T)
	local item = newItem(H)
	applyDebuff(H, item)
	auraEvent(H)
	local cd = overlay(item, H)
	T.truthy(cd, "an overlay Cooldown frame was created on the item")
	T.truthy(cd:IsShown(), "overlay is shown")
	T.truthy(H.state(cd).durationObject, "the overlay got the aura's duration object")
	T.eq(H.state(cd).durationObject.instance, H.state(cd).durationObject.instance)
	T.eq(H.state(cd).reverse, true, "aura timers count like auras (reverse)")
	T.eq(item.Cooldown:GetAlpha(), 0, "Blizzard's own (empty) swipe is hidden by alpha only")
end)

T.test("timers: the duration is learned into the character's saved data", function(H, T)
	local item = newItem(H)
	applyDebuff(H, item, 15)
	auraEvent(H)
	local char = H.CMP.db.chars[CHAR]
	T.truthy(char, "character entry " .. CHAR .. " created")
	T.eq(char.debuffDurations[WEAKENED], 15)
	T.eq(H.CMP.Timers:KnownDebuffs()[WEAKENED], 15)
end)

T.test("timers: a changed duration (talent) replaces the learned one", function(H, T)
	local item = newItem(H)
	local aura = applyDebuff(H, item, 15)
	auraEvent(H)
	clearDebuff(H, item, aura)
	auraEvent(H)
	applyDebuff(H, item, 12)
	auraEvent(H)
	T.eq(H.CMP.db.chars[CHAR].debuffDurations[WEAKENED], 12)
end)

T.test("timers: a helpful aura gets no overlay and Blizzard's timer stays", function(H, T)
	H.spells[PWS] = { name = "Power Word: Shield" }
	local item = H.viewers.BuffIcon:AddItem({ spellID = PWS })
	local aura = H.addAura("player", { spellId = PWS, isHarmful = false, isHelpful = true, duration = 15, expirationTime = H.now + 15 })
	H.setItemAura(item, aura)
	auraEvent(H)
	local cd = overlay(item, H)
	T.falsy(cd and cd:IsShown(), "no overlay for a buff")
	T.eq(item.Cooldown:GetAlpha(), 1)
	T.eq(H.CMP.db.chars[CHAR] and H.CMP.db.chars[CHAR].debuffDurations and H.CMP.db.chars[CHAR].debuffDurations[PWS], nil)
end)

T.test("timers: the debuff is found by spell ID when Blizzard cached nothing", function(H, T)
	local item = newItem(H)
	H.addAura("player", { spellId = WEAKENED, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
	-- Blizzard's item has no cached aura but is shown; our lookup by linked spell finds it
	H.setItemAura(item, nil)
	auraEvent(H)
	local cd = overlay(item, H)
	T.truthy(cd and cd:IsShown())
end)

T.test("timers: the overlay goes away when the debuff ends", function(H, T)
	local item = newItem(H)
	local aura = applyDebuff(H, item)
	auraEvent(H)
	T.truthy(overlay(item, H):IsShown())
	clearDebuff(H, item, aura)
	auraEvent(H)
	T.falsy(overlay(item, H):IsShown(), "overlay hidden")
	T.eq(item.Cooldown:GetAlpha(), 1, "Blizzard's swipe is back")
end)

T.test("timers: the 'debuff timers' setting turns them off", function(H, T)
	local item = newItem(H)
	applyDebuff(H, item)
	H.CMP:Set("BuffIcon", "debuffTimers", false)
	auraEvent(H)
	T.falsy(overlay(item, H) and overlay(item, H):IsShown())
	H.CMP:Set("BuffIcon", "debuffTimers", true)
	auraEvent(H)
	T.truthy(overlay(item, H) and overlay(item, H):IsShown())
end)

T.test("timers: in combat, a debuff that appears after being absent gets an estimated timer of the learned duration", function(H, T)
	local item = newItem(H)
	-- 1. out of combat: seen, learned (15 s)
	local aura = applyDebuff(H, item, 15)
	auraEvent(H)
	T.eq(H.CMP.db.chars[CHAR].debuffDurations[WEAKENED], 15)
	-- 2. it ends; we see it absent
	clearDebuff(H, item, aura)
	auraEvent(H)
	T.falsy(overlay(item, H):IsShown())
	-- 3. later, in combat, it comes back: every aura field is secret
	H.advance(60)
	H.inCombat = true
	applyHiddenDebuff(H, item)
	auraEvent(H)
	local cd = overlay(item, H)
	T.truthy(cd:IsShown(), "estimated timer shown")
	local state = H.state(cd).cd
	T.truthy(state, "plain SetCooldown(start, duration) was used, not a duration object")
	T.near(state.start, H.now, 1e-6, "starts when it appeared")
	T.eq(state.duration, 15, "learned duration")
	T.eq(item.Cooldown:GetAlpha(), 0)
	-- 4. it falls off in combat: back to Blizzard's display
	H.setItemAura(item, nil)
	auraEvent(H)
	T.falsy(cd:IsShown())
	T.eq(item.Cooldown:GetAlpha(), 1)
end)

T.test("timers: the estimate keeps its start across refreshes", function(H, T)
	local item = newItem(H)
	local aura = applyDebuff(H, item, 15)
	auraEvent(H)
	clearDebuff(H, item, aura)
	auraEvent(H)
	H.advance(30)
	H.inCombat = true
	applyHiddenDebuff(H, item)
	auraEvent(H)
	local start = H.state(overlay(item, H)).cd.start
	H.advance(5)
	auraEvent(H)
	T.eq(H.state(overlay(item, H)).cd.start, start, "same start after 5 s")
	T.truthy(overlay(item, H):IsShown())
end)

-- An estimate running in combat, last updated just now.
local function estimateRunning(H)
	local item = newItem(H)
	local aura = applyDebuff(H, item, 15)
	auraEvent(H)
	clearDebuff(H, item, aura)
	auraEvent(H)
	H.advance(30)
	H.inCombat = true
	applyHiddenDebuff(H, item)
	auraEvent(H)
	local start = H.state(overlay(item, H)).cd.start
	H.advance(5)
	auraEvent(H) -- present again: "last seen" is now
	return item, start
end

-- In-game regression: hits on the shield update the auras all the time, so the debuff had
-- always been "seen" a moment ago. Removed early and put on again right away, it used to
-- count as the old one: that timer ran out early, and then nothing was shown at all.
T.test("timers: removed early and put on again right away = a new debuff, timed from now", function(H, T)
	local item = estimateRunning(H)
	H.advance(0.2)
	auraEvent(H) -- a hit on the shield
	H.setItemAura(item, nil)
	auraEvent(H)
	H.advance(0.2)
	applyHiddenDebuff(H, item)
	auraEvent(H)
	local state = H.state(overlay(item, H)).cd
	T.near(state.start, H.now, 1e-6, "timed from the new debuff")
	H.advance(11)
	auraEvent(H)
	T.truthy(overlay(item, H):IsShown(), "still timed after the old one would have ended")
end)

T.test("timers: /cmp timers reports without raising", function(H, T)
	estimateRunning(H)
	H.CMP.Timers:Report()
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("timers")
	T.truthy(true)
end)

T.test("timers: gone for a second and back = a new debuff, timed from now", function(H, T)
	local item, start = estimateRunning(H)
	H.setItemAura(item, nil)
	auraEvent(H)
	H.advance(1)
	applyHiddenDebuff(H, item)
	auraEvent(H)
	local state = H.state(overlay(item, H)).cd
	T.ne(state.start, start)
	T.near(state.start, H.now, 1e-6)
end)

T.test("timers: the estimate ends with the learned duration even if the aura data lingers", function(H, T)
	local item = newItem(H)
	local aura = applyDebuff(H, item, 15)
	auraEvent(H)
	clearDebuff(H, item, aura)
	auraEvent(H)
	H.advance(30)
	H.inCombat = true
	applyHiddenDebuff(H, item)
	auraEvent(H)
	H.advance(16)
	auraEvent(H)
	-- the estimated debuff has expired and we did not see it vanish and return, so no new timer
	T.falsy(overlay(item, H):IsShown())
end)

T.test("timers: a debuff already present at load gets no estimate in combat", {
	combat = true,
	saved = { version = 1, chars = { [CHAR] = { groups = {}, debuffDurations = { [WEAKENED] = 15 } } } },
	setup = function(H)
		local item = newItem(H)
		applyHiddenDebuff(H, item)
		H.preexistingItem = item
	end,
}, function(H, T)
	local item = H.preexistingItem
	T.eq(H.inCombat, true)
	T.eq(H.CMP.db.chars[CHAR].debuffDurations[WEAKENED], 15, "learned duration survived the reload")
	auraEvent(H)
	local cd = overlay(item, H)
	T.falsy(cd and cd:IsShown(), "we do not know when it began, so no timer")
	T.eq(item.Cooldown:GetAlpha(), 1)
	-- once it has been seen absent and then present, it is timed
	H.setItemAura(item, nil)
	auraEvent(H)
	applyHiddenDebuff(H, item)
	auraEvent(H)
	cd = overlay(item, H)
	T.truthy(cd and cd:IsShown(), "timed from when it reappeared")
	T.eq(H.state(cd).cd.duration, 15)
end)

T.test("timers: a debuff never read out of combat has no learned duration, so no estimate", function(H, T)
	local item = newItem(H)
	H.inCombat = true
	H.advance(10)
	auraEvent(H)
	applyHiddenDebuff(H, item)
	auraEvent(H)
	T.falsy(overlay(item, H) and overlay(item, H):IsShown())
end)

T.test("timers: the learned duration survives /reload (saved variables)", function(H, T)
	local item = newItem(H)
	applyDebuff(H, item, 15)
	auraEvent(H)
	local saved = H.CMP.db
	-- a new session loading the same saved variables
	local Harness = require("harness")
	H.uninstall()
	local H2 = Harness.boot(H.root, { saved = saved })
	T.eq(H2.CMP.Timers:KnownDebuffs()[WEAKENED], 15)
	H2.uninstall()
	-- leave a valid environment installed for the runner's own cleanup
	H.install()
end)

---------------------------------------------------------------------------
-- "Show cooldown, not buff duration" (Essential / Utility)
---------------------------------------------------------------------------

T.test("cooldown-only: the icon shows the spell's cooldown instead of the buff duration", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = PWS })
	local CMP = H.CMP
	T.falsy(overlay(item, H) and overlay(item, H):IsShown(), "off by default")
	CMP:SetSpellStyle(PWS, "cooldownOnly", true)
	local cd = overlay(item, H)
	T.truthy(cd and cd:IsShown(), "overlay shown after enabling")
	T.eq(H.state(cd).durationObject.spellCooldown, PWS)
	T.eq(item.Cooldown:GetAlpha(), 0)
	T.eq(H.state(cd).reverse, false, "cooldowns do not reverse")
	CMP:ClearSpellStyle(PWS)
	T.falsy(cd:IsShown())
	T.eq(item.Cooldown:GetAlpha(), 1)
end)

T.test("cooldown-only: if the game refuses the duration object, Blizzard's display returns", function(H, T)
	local item = H.viewers.Essential:AddItem({ spellID = PWS })
	_G.C_Spell.GetSpellCooldownDuration = function() error("hidden from addons") end
	H.CMP:SetSpellStyle(PWS, "cooldownOnly", true)
	local cd = overlay(item, H)
	T.falsy(cd and cd:IsShown())
	T.eq(item.Cooldown:GetAlpha(), 1)
end)
