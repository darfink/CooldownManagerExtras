local _, ns = ...
local CMP = ns.CMP

-- "Gray out during <debuff>" (per spell, Essential / Utility): shows a spell as unusable
-- while a lockout debuff is on whoever it would land on, e.g. Power Word: Shield while
-- that unit has Weakened Soul. You pick the debuff per spell in the right-click menu,
-- from the debuffs Tracked Buffs has shown you (see Timers:KnownDebuffs), so no spell is
-- built in.
--
-- "Whoever it would land on": a helpful spell with a range goes on your friendly target,
-- else on you (self-cast); every other spell only on you.
--
-- The gray is Blizzard's own "not usable" look (desaturated, darkened). We re-apply it
-- right after Blizzard repaints the icon (range, mana, cooldown), and when the debuff
-- goes, Blizzard's repaint puts its own look back.
--
-- Taint: hooksecurefunc on the icon's repaint methods, and only C methods
-- (SetDesaturated / SetVertexColor) on its texture.

local Lockouts = {}
CMP.Lockouts = Lockouts

local GRAY = { 0.4, 0.4, 0.4, 1 } -- Blizzard's "not usable" icon color

local grayed = setmetatable({}, { __mode = "k" }) -- item -> true while we gray it
local hooked = setmetatable({}, { __mode = "k" })
-- item -> Blizzard's own look as it last painted it: { desaturated = ..., color = { r, g, b, a } }.
-- Restored with the texture's own setters; calling Blizzard's repaint from here would read
-- cooldown values that are hidden from addons in combat.
local native = setmetatable({}, { __mode = "k" })

local function Plain(value)
	return not CMP.IsSecret(value) and value ~= nil -- secret check first
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, id)
		if ok and type(name) == "string" then
			return name
		end
	end
	return nil
end

local function SpellAsks(api, spellID)
	local fn = C_Spell and C_Spell[api]
	if not fn then
		return false
	end
	local ok, result = pcall(fn, spellID)
	return ok and Plain(result) and result == true
end

-- { debuff = spellID, unit = "help" | "player" } for a spell with a lockout debuff set.
function Lockouts:RuleFor(spellID)
	local style = spellID and CMP:GetSpellStyle(spellID)
	local debuff = style and style.lockoutDebuff
	if not debuff then
		return nil
	end
	local onOthers = SpellAsks("IsSpellHelpful", spellID) and SpellAsks("SpellHasRange", spellID)
	return { debuff = debuff, unit = onOthers and "help" or "player" }
end

function Lockouts:DebuffName(debuff)
	return SpellName(debuff) or ("Spell %d"):format(debuff)
end

local function UnitFor(rule)
	if rule.unit == "help" and UnitExists("target") and UnitCanAssist("player", "target") then
		return "target"
	end
	return "player"
end

-- In combat the game hides most auras from addons, so looking the debuff up by spell ID
-- finds nothing. Blizzard's own Tracked Buffs / Bars still find it, though: an item that
-- tracks the debuff (Weakened Soul is tracked through Power Word: Shield) keeps the aura
-- and which unit it's on ("player" first, then "target" if you cast it there).
local function TrackedHas(unit, spellID)
	for _, info in ipairs(CMP.frameInfos) do
		if info.buffs and info.frame then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				local ok, cooldownInfo = pcall(item.GetCooldownInfo, item)
				local linked = ok and type(cooldownInfo) == "table" and cooldownInfo.linkedSpellID
				local own = ok and type(cooldownInfo) == "table" and cooldownInfo.spellID
				local match = (Plain(linked) and linked == spellID) or (Plain(own) and own == spellID)
				if match and item.GetAuraDataCached and item:GetAuraDataCached() ~= nil then
					local auraUnit = item.GetAuraDataUnit and item:GetAuraDataUnit()
					if Plain(auraUnit) and auraUnit == unit then
						return true
					end
				end
			end
		end
	end
	return false
end

-- True only when we can tell for sure; hidden (secret) aura data counts as "no".
local function HasDebuff(unit, spellID)
	if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
		local ok, found = pcall(function()
			local aura = C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)
			return type(aura) == "table" and not CMP.IsSecret(aura)
		end)
		if ok and found == true then
			return true
		end
	end
	local ok, found = pcall(TrackedHas, unit, spellID)
	return ok and found == true
end

function Lockouts:IsLocked(spellID)
	local rule = self:RuleFor(spellID)
	return rule ~= nil and HasDebuff(UnitFor(rule), rule.debuff)
end

local function IconOf(item)
	return item.Icon and item.Icon.SetDesaturated and item.Icon or nil
end

-- Remember what Blizzard painted (only while it's Blizzard's paint, not our gray).
local function Capture(item, what)
	local icon = IconOf(item)
	if not icon then
		return
	end
	local saved = native[item] or {}
	native[item] = saved
	if what ~= "color" then
		local ok, desaturated = pcall(icon.IsDesaturated, icon)
		saved.desaturated = ok and desaturated or nil
	end
	if what ~= "desaturation" then
		local ok, r, g, b, a = pcall(icon.GetVertexColor, icon)
		saved.color = ok and { r, g, b, a } or nil
	end
end

local function Restore(item, icon)
	local saved = native[item] or {}
	if saved.desaturated == nil or not pcall(icon.SetDesaturated, icon, saved.desaturated) then
		icon:SetDesaturated(false)
	end
	if not saved.color or not pcall(icon.SetVertexColor, icon, unpack(saved.color, 1, 4)) then
		icon:SetVertexColor(1, 1, 1, 1)
	end
end

function Lockouts:Paint(item)
	local icon = IconOf(item)
	if not icon then
		return
	end
	if self:IsLocked(CMP:GetItemSpellID(item)) then
		if not grayed[item] then
			Capture(item)
		end
		grayed[item] = true
		icon:SetDesaturated(true)
		icon:SetVertexColor(unpack(GRAY))
	elseif grayed[item] then
		grayed[item] = nil
		Restore(item, icon) -- Blizzard's look from its last repaint (cooldown, range, mana)
	end
end

function Lockouts:UpdateItem(info, item)
	if info.kind ~= "icons" or info.buffs then
		return
	end
	if not hooked[item] and item.RefreshIconColor then
		hooked[item] = true
		-- Blizzard just painted: remember that, then gray again if needed.
		local function Repainted(what)
			Capture(item, what)
			if grayed[item] or Lockouts:IsLocked(CMP:GetItemSpellID(item)) then
				CMP.Safe(Lockouts.Paint, Lockouts, item)
			end
		end
		CMP.HookMethod(item, "RefreshIconColor", function() Repainted("color") end)
		CMP.HookMethod(item, "RefreshIconDesaturation", function() Repainted("desaturation") end)
	end
	self:Paint(item)
end

function Lockouts:UpdateAll()
	for _, info in ipairs(CMP.frameInfos) do
		if info.kind == "icons" and not info.buffs and info.frame then
			for item in pairs(CMP.Layout:Items(info.frame)) do
				CMP.Safe(self.UpdateItem, self, info, item)
			end
		end
	end
end

local pending
function Lockouts:Start()
	if self.events then
		return
	end
	self.events = CreateFrame("Frame")
	pcall(self.events.RegisterUnitEvent, self.events, "UNIT_AURA", "player", "target")
	pcall(self.events.RegisterEvent, self.events, "PLAYER_TARGET_CHANGED")
	self.events:SetScript("OnEvent", function()
		if pending then
			return
		end
		pending = true
		C_Timer.After(0, function()
			pending = nil
			Lockouts:UpdateAll()
		end)
	end)
	self:UpdateAll()
end
