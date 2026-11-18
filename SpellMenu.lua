local _, ns = ...
local CMP = ns.CMP

-- Per-spell styling, added to the right-click menu of spells in Blizzard's Cooldown
-- Settings window (the same menu that holds Blizzard's alerts).
--  * Square style: the color and size of that spell's border.
--  * Blizzard style: the color tints Blizzard's own icon frame.

local SpellMenu = {}
CMP.SpellMenu = SpellMenu

local PRESETS = {
	{ text = "Black", color = { r = 0, g = 0, b = 0, a = 1 } },
	{ text = "White", color = { r = 1, g = 1, b = 1, a = 1 } },
	{ text = "Red", color = { r = 0.90, g = 0.15, b = 0.15, a = 1 } },
	{ text = "Orange", color = { r = 1.00, g = 0.50, b = 0.05, a = 1 } },
	{ text = "Gold", color = { r = 1.00, g = 0.82, b = 0.10, a = 1 } },
	{ text = "Green", color = { r = 0.20, g = 0.85, b = 0.30, a = 1 } },
	{ text = "Blue", color = { r = 0.25, g = 0.55, b = 1.00, a = 1 } },
	{ text = "Purple", color = { r = 0.70, g = 0.35, b = 1.00, a = 1 } },
}

local SIZES = { 1, 2, 3, 4 }

local function Swatch(color)
	return ("|TInterface\\Buttons\\WHITE8X8:12:12:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(
		math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
end

local function SameColor(a, b)
	return a and b and math.abs(a.r - b.r) < 0.01 and math.abs(a.g - b.g) < 0.01 and math.abs(a.b - b.b) < 0.01
end

local function CurrentStyle(spellID)
	return CMP:GetSpellStyle(spellID) or {}
end

local function OpenColorPicker(spellID)
	local previous = CurrentStyle(spellID).color
	local start = previous or { r = 1, g = 1, b = 1, a = 1 }
	local function apply()
		local r, g, b = ColorPickerFrame:GetColorRGB()
		local a = ColorPickerFrame:GetColorAlpha()
		CMP:SetSpellStyle(spellID, "color", { r = r, g = g, b = b, a = a })
	end
	CMP:OpenColorPicker({
		r = start.r,
		g = start.g,
		b = start.b,
		opacity = start.a or 1,
		hasOpacity = true,
		swatchFunc = apply,
		opacityFunc = apply,
		cancelFunc = function()
			CMP:SetSpellStyle(spellID, "color", previous)
		end,
	})
end

local function AddMenu(owner, rootDescription)
	if owner.IsEmptyCategory and owner:IsEmptyCategory() then
		return
	end
	local spellID = CMP:GetItemSpellID(owner)
	if not spellID then
		return
	end

	rootDescription:CreateDivider()
	rootDescription:CreateTitle("Cooldown Manager Extras")
	SpellMenu:AddStyleEntries(rootDescription, spellID)
end

-- Border color / size / reset entries for one spell, added to any menu description.
-- bordersOnly: just the border entries (our custom icons, which have no buff or lockout).
function SpellMenu:AddStyleEntries(rootDescription, spellID, bordersOnly)
	local colorMenu = rootDescription:CreateButton("Border Color")
	colorMenu:CreateRadio(DEFAULT or "Default", function()
		return CurrentStyle(spellID).color == nil
	end, function()
		CMP:SetSpellStyle(spellID, "color", nil)
	end)
	for _, preset in ipairs(PRESETS) do
		colorMenu:CreateRadio(Swatch(preset.color) .. " " .. preset.text, function()
			return SameColor(CurrentStyle(spellID).color, preset.color)
		end, function()
			CMP:SetSpellStyle(spellID, "color", preset.color)
		end)
	end
	colorMenu:CreateDivider()
	colorMenu:CreateButton("Custom...", function()
		OpenColorPicker(spellID)
	end)

	local sizeMenu = rootDescription:CreateButton("Border Size")
	sizeMenu:CreateRadio(DEFAULT or "Default", function()
		return CurrentStyle(spellID).size == nil
	end, function()
		CMP:SetSpellStyle(spellID, "size", nil)
	end)
	for _, size in ipairs(SIZES) do
		sizeMenu:CreateRadio(("%d px"):format(size), function()
			return CurrentStyle(spellID).size == size
		end, function()
			CMP:SetSpellStyle(spellID, "size", size)
		end)
	end

	if bordersOnly then
		local resetBorder = rootDescription:CreateButton("Reset Border", function()
			CMP:SetSpellStyle(spellID, "color", nil)
			CMP:SetSpellStyle(spellID, "size", nil)
		end)
		local style = CMP:GetSpellStyle(spellID)
		resetBorder:SetEnabled(style ~= nil and (style.color ~= nil or style.size ~= nil))
		return
	end

	-- Spells that put a buff on you show the buff's duration on their cooldown icon.
	local cooldownOnly = rootDescription:CreateCheckbox("Show cooldown, not buff duration", function()
		return CurrentStyle(spellID).cooldownOnly == true
	end, function()
		CMP:SetSpellStyle(spellID, "cooldownOnly", not CurrentStyle(spellID).cooldownOnly or nil)
	end)
	if cooldownOnly.SetTooltip then
		cooldownOnly:SetTooltip(function(tooltip)
			tooltip:SetText("Show cooldown, not buff duration", 1, 1, 1)
			tooltip:AddLine("In Essential and Utility Cooldowns, show when you can cast this spell again instead of how long its buff lasts. Tracked Buffs still show the buff.", nil, nil, nil, true)
		end)
	end

	-- Lockout debuffs (Power Word: Shield / Weakened Soul): pick from the debuffs Tracked
	-- Buffs has shown you.
	local lockoutMenu = rootDescription:CreateButton("Gray Out During")
	lockoutMenu:CreateRadio(OFF or "Off", function()
		return CurrentStyle(spellID).lockoutDebuff == nil
	end, function()
		CMP:SetSpellStyle(spellID, "lockoutDebuff", nil)
	end)
	local debuffs = {}
	for id in pairs(CMP.Timers:KnownDebuffs()) do
		table.insert(debuffs, { id = id, name = CMP.Lockouts:DebuffName(id) })
	end
	table.sort(debuffs, function(a, b) return a.name < b.name end)
	for _, debuff in ipairs(debuffs) do
		lockoutMenu:CreateRadio(debuff.name, function()
			return CurrentStyle(spellID).lockoutDebuff == debuff.id
		end, function()
			CMP:SetSpellStyle(spellID, "lockoutDebuff", debuff.id)
		end)
	end
	if #debuffs == 0 then
		local none = lockoutMenu:CreateButton("No debuffs seen yet")
		none:SetEnabled(false)
	end
	if lockoutMenu.SetTooltip then
		lockoutMenu:SetTooltip(function(tooltip)
			tooltip:SetText("Gray Out During", 1, 1, 1)
			tooltip:AddLine("Show this spell as unusable while a debuff is on whoever it would land on (your friendly target for helpful spells, else you). Example: Power Word: Shield during Weakened Soul.", nil, nil, nil, true)
			tooltip:AddLine("The list holds debuffs that Tracked Buffs has shown on you out of combat. Track the debuff there to add it (it also needs to stay tracked to work in combat).", nil, nil, nil, true)
		end)
	end

	local reset = rootDescription:CreateButton("Reset Spell Style", function()
		CMP:ClearSpellStyle(spellID)
	end)
	reset:SetEnabled(CMP:GetSpellStyle(spellID) ~= nil)
end

function SpellMenu:Register()
	if Menu and Menu.ModifyMenu then
		Menu.ModifyMenu("MENU_COOLDOWN_SETTINGS_ITEM", function(owner, rootDescription)
			CMP.Safe(AddMenu, owner, rootDescription)
		end)
	end
end
