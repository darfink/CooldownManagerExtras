local _, ns = ...
local CMP = ns.CMP

-- Keybind text on cooldown icons. We read Blizzard's action bars (spells, macros and
-- items such as potions or trinkets) and the key bound to each button, and show it on the
-- icon of the same spell. Only public, non-secret APIs: GetActionInfo, GetMacroSpell,
-- GetBindingKey. Buttons of other action bar addons (Bartender, Dominos) use their own
-- binding names and aren't covered.

local Keybinds = {}
CMP.Keybinds = Keybinds

local bySpell, byItem = {}, {}

-- Binding command for an action slot of the extra action bars, and a priority (lower
-- wins) for when a spell sits on several buttons. The main bar pages (bar 1/2, forms,
-- stealth...), so its slots are read live from its buttons instead; see Rebuild.
local function BindingForSlot(slot)
	if slot >= 25 and slot <= 36 then
		return "MULTIACTIONBAR3BUTTON" .. (slot - 24), 2
	elseif slot >= 37 and slot <= 48 then
		return "MULTIACTIONBAR4BUTTON" .. (slot - 36), 2
	elseif slot >= 49 and slot <= 60 then
		return "MULTIACTIONBAR2BUTTON" .. (slot - 48), 2
	elseif slot >= 61 and slot <= 72 then
		return "MULTIACTIONBAR1BUTTON" .. (slot - 60), 2
	elseif slot >= 145 and slot <= 156 then
		return "MULTIACTIONBAR5BUTTON" .. (slot - 144), 2
	elseif slot >= 157 and slot <= 168 then
		return "MULTIACTIONBAR6BUTTON" .. (slot - 156), 2
	elseif slot >= 169 and slot <= 180 then
		return "MULTIACTIONBAR7BUTTON" .. (slot - 168), 2
	end
	return nil
end

local REPLACEMENTS = {
	{ "SHIFT%-", "S" },
	{ "CTRL%-", "C" },
	{ "ALT%-", "A" },
	{ "META%-", "M" },
	{ "MOUSEWHEELUP", "WU" },
	{ "MOUSEWHEELDOWN", "WD" },
	{ "MIDDLEBUTTON", "M3" },
	{ "BUTTON(%d+)", "M%1" },
	{ "NUMPADDECIMAL", "N." },
	{ "NUMPADPLUS", "N+" },
	{ "NUMPADMINUS", "N-" },
	{ "NUMPADMULTIPLY", "N*" },
	{ "NUMPADDIVIDE", "N/" },
	{ "NUMPAD", "N" },
	{ "SPACE", "Spc" },
	{ "BACKSPACE", "Bs" },
	{ "CAPSLOCK", "Caps" },
	{ "PAGEUP", "PU" },
	{ "PAGEDOWN", "PD" },
	{ "INSERT", "Ins" },
	{ "DELETE", "Del" },
	{ "HOME", "Hm" },
	{ "END", "End" },
}

local function Shorten(key)
	for _, r in ipairs(REPLACEMENTS) do
		key = key:gsub(r[1], r[2])
	end
	return key
end

local function Remember(map, id, text, priority)
	if CMP.IsSecret(id) or not id then
		return
	end
	local current = map[id]
	if not current or priority < current.priority then
		map[id] = { text = text, priority = priority }
	end
end

local function ItemSpell(itemID)
	if C_Item and C_Item.GetItemSpell then
		local _, spellID = C_Item.GetItemSpell(itemID)
		return spellID
	end
	return nil
end

local function ItemIDFromLink(link)
	if not link then
		return nil
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local itemID = C_Item.GetItemInfoInstant(link)
		if itemID then
			return itemID
		end
	end
	return tonumber(tostring(link):match("item:(%d+)"))
end

local function RememberItem(itemID, text, priority)
	if not itemID then
		return
	end
	Remember(byItem, itemID, text, priority)
	Remember(bySpell, ItemSpell(itemID), text, priority)
end

local function RememberSlot(slot, command, priority)
	local key = command and GetBindingKey(command)
	if not key then
		return
	end
	local ok, actionType, id = pcall(GetActionInfo, slot)
	if not ok or CMP.IsSecret(actionType) or CMP.IsSecret(id) or not actionType or not id then
		return
	end
	local text = Shorten(key)
	if actionType == "spell" then
		Remember(bySpell, id, text, priority)
		local base = FindBaseSpellByID and FindBaseSpellByID(id)
		if base and base ~= id then
			Remember(bySpell, base, text, priority)
		end
	elseif actionType == "macro" then
		local spellID = GetMacroSpell and GetMacroSpell(id)
		if spellID then
			Remember(bySpell, spellID, text, priority + 1)
		elseif GetMacroItem then
			-- /use macros: the macro reports the item it would use right now.
			local _, link = GetMacroItem(id)
			RememberItem(ItemIDFromLink(link), text, priority + 1)
		end
	elseif actionType == "item" then
		RememberItem(id, text, priority)
	end
end

function Keybinds:Rebuild()
	wipe(bySpell)
	wipe(byItem)
	-- Main bar: each button knows which slot it shows right now (page, form, stealth...).
	for i = 1, 12 do
		local button = _G["ActionButton" .. i]
		local slot = button and button.action
		if type(slot) == "number" and not CMP.IsSecret(slot) then
			RememberSlot(slot, "ACTIONBUTTON" .. i, 1)
		end
	end
	for slot = 25, 180 do
		local command, priority = BindingForSlot(slot)
		if command then
			RememberSlot(slot, command, priority)
		end
	end
end

function Keybinds:TextFor(item)
	local info = item.GetCooldownInfo and item:GetCooldownInfo()
	if not info then
		return nil
	end
	for _, field in ipairs({ "overrideSpellID", "spellID", "overrideTooltipSpellID" }) do
		local id = info[field]
		if not CMP.IsSecret(id) and id and bySpell[id] then
			return bySpell[id].text
		end
	end
	if info.itemID and byItem[info.itemID] then -- our custom item icons
		return byItem[info.itemID].text
	end
	if info.equipSlot then
		local itemID = GetInventoryItemID("player", info.equipSlot)
		if itemID and byItem[itemID] then
			return byItem[itemID].text
		end
	end
	return nil
end

local labels = setmetatable({}, { __mode = "k" })

local function Label(item)
	local label = labels[item]
	if not label then
		local holder = CreateFrame("Frame", nil, item)
		holder:SetAllPoints(item)
		local cooldown = item.Cooldown
		holder:SetFrameLevel((cooldown and cooldown:GetFrameLevel() or item:GetFrameLevel()) + 2)
		label = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		label.holder = holder
		labels[item] = label
	end
	return label
end

function Keybinds:ApplyItem(info, item)
	if info.kind ~= "icons" then
		return
	end
	local key = info.key
	if not CMP:Get(key, "keybinds") then
		if labels[item] then
			labels[item].holder:Hide()
		end
		return
	end
	local text = self:TextFor(item)
	local label = Label(item)
	if not text then
		label.holder:Hide()
		return
	end
	local point = CMP:Get(key, "keybindPoint")
	local x = point:find("LEFT", 1, true) and 2 or -2
	local y = point:find("TOP", 1, true) and -2 or 2
	label:ClearAllPoints()
	label:SetPoint(point, label.holder, point, x, y)
	label:SetJustifyH(point:find("LEFT", 1, true) and "LEFT" or "RIGHT")
	local size = CMP:Get(key, "keybindSize")
	local font = CMP.Media:Fetch("font", CMP:Get(key, "font")) or (NumberFontNormalSmall and NumberFontNormalSmall:GetFont()) or STANDARD_TEXT_FONT
	local outline = CMP:Get(key, "outline")
	outline = (outline == "default" or outline == nil) and "OUTLINE" or (outline == "NONE" and "" or outline)
	label:SetFont(font, size > 0 and size or 11, outline)
	label:SetText(text)
	label.holder:Show()
end

local pending = false
local function Schedule()
	if pending then
		return
	end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		Keybinds:Rebuild()
		CMP.Skin:RefreshAll()
	end)
end

function Keybinds:Start()
	if self.events then
		return
	end
	self.events = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "PLAYER_EQUIPMENT_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UPDATE_STEALTH", "BAG_UPDATE_DELAYED" }) do
		pcall(self.events.RegisterEvent, self.events, event)
	end
	self.events:SetScript("OnEvent", Schedule)
	self:Rebuild()
end
