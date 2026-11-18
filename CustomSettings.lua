local _, ns = ...
local CMP = ns.CMP

-- Custom entries in Blizzard's Cooldown Settings window. Each one gets a tile inside the
-- Essential, Utility or Tracked Buffs section, between Blizzard's own icons at the place it has in the
-- bar, plus a "+" tile to add more (menu, or drop a spell or item on it). Right-click a
-- custom tile for its options.
--
-- Blizzard's sections are grid layouts over the icons they own. We never add our tiles to
-- that layout (no layoutIndex): after Blizzard's grid ran, we place its icons and our tiles
-- again in one grid and set the section's height. Blizzard's drag-to-reorder works from
-- where its icons are on screen, so it keeps working.

local CustomSettings = {}
CMP.CustomSettings = CustomSettings

local Custom = CMP.Custom

local ADD_TINT = { 0.55, 0.78, 1 }
local BADGE_COLOR = { 0.31, 0.64, 1, 1 } -- the add-on's blue
local LAST = math.huge

local tilesByKey = {} -- key -> list of tiles (the last one in use is the "+" tile)
local hookedContainers = setmetatable({}, { __mode = "k" })

local function Try(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

local function CategoryKey(categoryFrame)
	local enum = Enum and Enum.CooldownViewerCategory
	local ok, object = Try(categoryFrame.GetCategoryObject, categoryFrame)
	if not enum or not ok or not object or not object.GetCategory then
		return nil
	end
	local category = object:GetCategory()
	if category == enum.Essential then
		return "Essential"
	elseif category == enum.Utility then
		return "Utility"
	elseif category == enum.TrackedBuff then
		return "BuffIcon"
	end
	return nil
end

local function BlizzardItems(categoryFrame)
	local items = {}
	local pool = categoryFrame.itemPool
	if pool and pool.EnumerateActive then
		for item in pool:EnumerateActive() do
			if item.layoutIndex then
				items[#items + 1] = item
			end
		end
	end
	table.sort(items, function(a, b) return a.layoutIndex < b.layoutIndex end)
	return items
end

local function IsEmptyCategoryItem(item)
	local ok, empty = Try(item.IsEmptyCategory, item)
	return ok and empty == true
end

---------------------------------------------------------------------------
-- Menus and input
---------------------------------------------------------------------------

local function IconMarkup(texture)
	return ("|T%s:16:16:0:0:64:64:4:60:4:60|t "):format(tostring(texture))
end

local function Trim(text)
	return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

local function SpellName(spellID)
	local ok, name = Try(C_Spell and C_Spell.GetSpellName, spellID)
	return ok and name or nil
end

local function ReportAdd(added, entry)
	if not added then
		CMP:Print(Custom:Name(entry), "is already there.")
	end
end

function CustomSettings:AddSpell(key, spellID)
	if FindBaseSpellByID then
		local ok, base = pcall(FindBaseSpellByID, spellID)
		if ok and type(base) == "number" then
			spellID = base
		end
	end
	local entry = { kind = "spell", id = spellID }
	ReportAdd(Custom:Add(key, entry), entry)
end

-- Why a buff can't show (nil when it can).
function CustomSettings:BuffProblem(spellID)
	local status = Custom:BuffStatus(spellID)
	if status == "notyours" then
		return "Not started by a spell you know or an item you carry, so it can't be shown: in combat the game hides buffs, and only a buff you cast yourself can be timed. (Buffs from other players, passive procs and random effects can't.)"
	elseif status == "unlearned" then
		return "Duration not known yet: cast it once out of combat."
	end
	return nil
end

function CustomSettings:AddAura(key, spellID)
	local entry = { kind = "aura", id = spellID }
	local added = Custom:Add(key, entry)
	ReportAdd(added, entry)
	local problem = added and self:BuffProblem(spellID)
	if problem then
		CMP:Print(problem)
	end
end

function CustomSettings:AddItem(key, itemID)
	local equippable = false
	local ok, value = Try(C_Item and C_Item.IsEquippableItem, itemID)
	if ok then
		equippable = value == true
	end
	-- consumables (potions, ...) stay visible with none left; gear only while you have it
	local entry = { kind = "item", id = itemID, always = not equippable or nil }
	ReportAdd(Custom:Add(key, entry), entry)
end

-- Text from the input box (an ID, a link or a name) -> spell or item ID, or nil.
function CustomSettings:Resolve(kind, text)
	text = Trim(text)
	if text == "" then
		return nil
	end
	if kind == "spell" or kind == "aura" then
		local id = tonumber(text) or tonumber(text:match("spell:(%d+)"))
		if not id then
			local ok, info = Try(C_Spell and C_Spell.GetSpellInfo, text)
			id = ok and type(info) == "table" and info.spellID or nil
		end
		return id and SpellName(id) and id or nil
	end
	local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
	if not id then
		local ok, itemID = Try(C_Item and C_Item.GetItemInfoInstant, text)
		id = ok and type(itemID) == "number" and itemID or nil
	end
	return id
end

function CustomSettings:AddFromText(key, kind, text)
	if Trim(text) == "" then
		return
	end
	local id = self:Resolve(kind, text)
	if not id then
		local spellLike = kind ~= "item"
		CMP:Print(spellLike and "No spell found for" or "No item found for", Trim(text)
			.. (spellLike and ". Give its spell ID or exact name." or ". Give its item ID, or drop the item on the + tile."))
		return
	end
	if kind == "spell" then
		self:AddSpell(key, id)
	elseif kind == "aura" then
		self:AddAura(key, id)
	else
		self:AddItem(key, id)
	end
end

-- "<icon> Name" for the input box preview.
function CustomSettings:Preview(kind, text)
	local id = self:Resolve(kind, text)
	if not id then
		return Trim(text) == "" and " " or "|cff808080No match yet|r"
	end
	local entry = { kind = kind == "aura" and "spell" or kind, id = id }
	return IconMarkup(Custom:Texture(entry)) .. Custom:Name(entry) .. (" |cff808080(%d)|r"):format(id)
end

local function DialogText(dialog)
	if dialog.GetTextFontString then
		return dialog:GetTextFontString()
	end
	return dialog.Text or dialog.text
end

local function EditBoxOf(dialog)
	if dialog.GetEditBox then
		return dialog:GetEditBox()
	end
	return dialog.editBox or dialog.EditBox
end

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs.CME_ADD_CUSTOM then
		return
	end
	StaticPopupDialogs.CME_ADD_CUSTOM = {
		text = "%s",
		button1 = ADD or "Add",
		button2 = CANCEL or "Cancel",
		hasEditBox = 1,
		editBoxWidth = 260,
		OnShow = function(dialog)
			local box = EditBoxOf(dialog)
			if box then
				box:SetText("")
				box:SetFocus()
			end
		end,
		EditBoxOnTextChanged = function(box, data)
			local dialog = box:GetParent()
			data = data or (dialog and dialog.data)
			local fontString = dialog and DialogText(dialog)
			if not data or not fontString then
				return
			end
			fontString:SetText(data.prompt .. "\n\n" .. CustomSettings:Preview(data.kind, box:GetText()))
			if dialog.Resize then
				pcall(dialog.Resize, dialog, "CME_ADD_CUSTOM")
			elseif StaticPopup_Resize then
				pcall(StaticPopup_Resize, dialog, "CME_ADD_CUSTOM")
			end
		end,
		OnAccept = function(dialog, data)
			local box = EditBoxOf(dialog)
			if box and data then
				CustomSettings:AddFromText(data.key, data.kind, box:GetText())
			end
		end,
		EditBoxOnEnterPressed = function(box, data)
			local dialog = box:GetParent()
			data = data or (dialog and dialog.data)
			if data then
				CustomSettings:AddFromText(data.key, data.kind, box:GetText())
			end
			if dialog then
				dialog:Hide()
			end
		end,
		EditBoxOnEscapePressed = function(box)
			box:GetParent():Hide()
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 1,
		preferredIndex = 3,
	}
end

function CustomSettings:Prompt(key, kind)
	DefinePopup()
	if not StaticPopup_Show then
		return
	end
	local text = (kind == "spell" and "Add a spell to %s.\nSpell ID or name:")
		or (kind == "aura" and "Add a buff to %s.\nThe buff's spell ID or name:")
		or "Add an item to %s.\nItem ID or name:"
	text = text:format(CMP:GetName(key))
	StaticPopup_Show("CME_ADD_CUSTOM", text, nil, { key = key, kind = kind, prompt = text })
end

-- Whether an item has a cooldown, from the game's own data, no lists of IDs: its tooltip
-- shows "(<time> Cooldown)" (the game's localized ITEM_COOLDOWN_TOTAL text), or its use
-- spell has a base cooldown, or it is on cooldown right now.
local cooldownPattern
local function CooldownPattern()
	if cooldownPattern == nil then
		local text = type(ITEM_COOLDOWN_TOTAL) == "string" and ITEM_COOLDOWN_TOTAL or nil
		cooldownPattern = text and ("^" .. text:gsub("[%(%)%.%-%+%[%]%^%$%*%?]", "%%%0"):gsub("%%s", ".+") .. "$") or false
	end
	return cooldownPattern or nil
end

local function TooltipHasCooldown(itemID)
	local pattern = CooldownPattern()
	local ok, data = Try(C_TooltipInfo and C_TooltipInfo.GetItemByID, itemID)
	if not pattern or not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return false
	end
	for _, line in ipairs(data.lines) do
		for _, text in ipairs({ line.leftText, line.rightText }) do
			if type(text) == "string" and not CMP.IsSecret(text) then
				-- the cooldown is often at the end of the "Use:" line
				local tail = text:match("(%b())%s*$")
				if text:match(pattern) or (tail and tail:match(pattern)) then
					return true
				end
			end
		end
	end
	return false
end

local function HasCooldown(itemID, useSpellID)
	if TooltipHasCooldown(itemID) then
		return true
	end
	if type(useSpellID) == "number" then
		local ok, base = Try(GetSpellBaseCooldown, useSpellID)
		if ok and type(base) == "number" and not CMP.IsSecret(base) and base > 1500 then
			return true
		end
	end
	local fn = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
	local ok, _, duration = Try(fn, itemID)
	return ok and type(duration) == "number" and not CMP.IsSecret(duration) and duration > 1.5
end

-- Usable items in your bags (potions, healthstones, on-use items), once each:
-- { id, name, texture, cooldown = true|false }, those with a cooldown first.
local function BagItems()
	local result, seen = {}, {}
	local container = C_Container
	if not container or not container.GetContainerNumSlots or not container.GetContainerItemID then
		return result
	end
	for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
		local okSlots, slots = pcall(container.GetContainerNumSlots, bag)
		for slot = 1, okSlots and slots or 0 do
			local ok, itemID = pcall(container.GetContainerItemID, bag, slot)
			if ok and type(itemID) == "number" and not seen[itemID] then
				seen[itemID] = true
				local okSpell, spellName, spellID = Try(C_Item and C_Item.GetItemSpell, itemID)
				if okSpell and spellName then
					local entry = { kind = "item", id = itemID }
					table.insert(result, { id = itemID, name = Custom:Name(entry), texture = Custom:Texture(entry),
						cooldown = HasCooldown(itemID, spellID) })
				end
			end
		end
	end
	table.sort(result, function(a, b)
		if a.cooldown ~= b.cooldown then
			return a.cooldown
		end
		return a.name < b.name
	end)
	return result
end

local function ItemTooltip(button, itemID)
	if button.SetTooltip then
		button:SetTooltip(function(tooltip)
			if tooltip.SetItemByID then
				pcall(tooltip.SetItemByID, tooltip, itemID)
			end
		end)
	end
end

local function SpellTooltip(button, spellID)
	if button.SetTooltip then
		button:SetTooltip(function(tooltip)
			if tooltip.SetSpellByID then
				pcall(tooltip.SetSpellByID, tooltip, spellID)
			end
		end)
	end
end

-- "12 s", "2 min", or "no timer" (auras without a duration)
local function FormatDuration(seconds)
	if type(seconds) ~= "number" or seconds <= 0 then
		return "no timer"
	elseif seconds < 90 then
		return ("%d s"):format(math.floor(seconds + 0.5))
	elseif seconds < 5400 then
		return ("%d min"):format(math.floor(seconds / 60 + 0.5))
	end
	return ("%d h"):format(math.floor(seconds / 3600 + 0.5))
end
CustomSettings.FormatDuration = FormatDuration

-- Several buffs can share a name (an item can put two on you, e.g. the effect and a
-- second stage): the label shows each one's duration and spell ID to tell them apart, and
-- the spell or item that starts it.
function CustomSettings:AddBuffButton(parent, key, buff)
	local label = IconMarkup(buff.icon or Custom:Texture({ kind = "aura", id = buff.id })) .. buff.name
		.. (buff.harmful and " |cffff6060debuff|r" or "")
		.. (" |cff808080%s, %d|r"):format(FormatDuration(buff.duration), buff.id)
	local button = parent:CreateButton(label, function()
		self:AddAura(key, buff.id)
	end)
	button:SetEnabled(not Custom:Has(key, "aura", buff.id))
	SpellTooltip(button, buff.id)
end

-- Only buffs your own casts start: the ones that can be timed in combat.
function CustomSettings:OpenBuffMenu(tile, key)
	MenuUtil.CreateContextMenu(tile, function(_, root)
		root:CreateTitle("Add to " .. CMP:GetName(key))
		local list = {}
		for id, info in pairs(Custom:SeenBuffs()) do
			if Custom:BuffStatus(id) == "ok" then
				table.insert(list, { id = id, name = info.name or tostring(id), icon = info.icon,
					duration = info.duration, harmful = info.harmful, seen = info.seen or 0 })
			end
		end
		table.sort(list, function(a, b) return a.seen > b.seen end)
		local started = root:CreateButton("Started by Your Spells and Items")
		if started.SetTooltip then
			started:SetTooltip(function(tooltip)
				tooltip:SetText("Started by Your Spells and Items", 1, 1, 1)
				tooltip:AddLine("Buffs you have started yourself, out of combat. In combat the game hides buffs from add-ons, so these are timed from your cast.\n\nNot listed: buffs from other players and passive procs. They can't be shown in combat.", nil, nil, nil, true)
			end)
		end
		for _, buff in ipairs(list) do
			self:AddBuffButton(started, key, buff)
		end
		if #list == 0 then
			started:CreateButton("None yet: use a trinket, potion or spell once out of combat"):SetEnabled(false)
		end
		root:CreateButton("Buff by Spell ID or Name...", function() self:Prompt(key, "aura") end)
		root:CreateDivider()
		root:CreateTitle("Or drop a spell or item on the + tile")
	end)
end

function CustomSettings:OpenAddMenu(tile, key)
	if not MenuUtil or not MenuUtil.CreateContextMenu then
		return
	end
	if key == "BuffIcon" then
		return self:OpenBuffMenu(tile, key)
	end
	MenuUtil.CreateContextMenu(tile, function(_, root)
		root:CreateTitle("Add to " .. CMP:GetName(key))
		root:CreateButton("Spell...", function() self:Prompt(key, "spell") end)
		root:CreateButton("Item...", function() self:Prompt(key, "item") end)
		local trinkets = root:CreateButton("Trinket Slot")
		for _, slot in ipairs({ 13, 14 }) do
			local entry = { kind = "slot", id = slot }
			local button = trinkets:CreateButton(IconMarkup(Custom:Texture(entry)) .. Custom:Name(entry), function()
				Custom:Add(key, entry)
			end)
			button:SetEnabled(not Custom:Has(key, "slot", slot))
			if button.SetTooltip then
				button:SetTooltip(function(tooltip)
					if tooltip.SetInventoryItem then
						pcall(tooltip.SetInventoryItem, tooltip, "player", slot)
					end
				end)
			end
		end
		local bags = root:CreateButton("From Your Bags")
		local items = BagItems()
		local others
		for _, item in ipairs(items) do
			-- items without a cooldown (food, ...) go into their own submenu
			local parent = bags
			if not item.cooldown then
				others = others or bags:CreateButton("Without a Cooldown")
				parent = others
			end
			local button = parent:CreateButton(IconMarkup(item.texture) .. item.name, function()
				self:AddItem(key, item.id)
			end)
			button:SetEnabled(not Custom:Has(key, "item", item.id))
			ItemTooltip(button, item.id)
		end
		if #items == 0 then
			bags:CreateButton("No usable items in your bags"):SetEnabled(false)
		end
		root:CreateDivider()
		root:CreateTitle("Or drop a spell or item on the + tile")
	end)
end

-- Blizzard's spells in this section, in order: { id, name }.
local function SectionSpells(categoryFrame)
	local result = {}
	if not categoryFrame then
		return result
	end
	for _, item in ipairs(BlizzardItems(categoryFrame)) do
		if not IsEmptyCategoryItem(item) then
			local spellID = CMP:GetItemSpellID(item)
			if spellID then
				table.insert(result, { id = spellID, name = SpellName(spellID) or tostring(spellID) })
			end
		end
	end
	return result
end

function CustomSettings:OpenEntryMenu(tile, key, index)
	if not MenuUtil or not MenuUtil.CreateContextMenu then
		return
	end
	local categoryFrame = tile:GetParent() and tile:GetParent():GetParent()
	MenuUtil.CreateContextMenu(tile, function(_, root)
		local entry = Custom:Entries(key)[index]
		if not entry then
			return
		end
		root:CreateTitle(Custom:Name(entry))
		local function IsPos(pos)
			return function()
				local current = Custom:Entries(key)[index]
				return current ~= nil and current.pos == pos
			end
		end
		local function SetPos(pos)
			return function()
				Custom:SetField(key, index, "pos", pos)
			end
		end
		local place = root:CreateButton("Place")
		place:CreateRadio("First", IsPos("start"), SetPos("start"))
		place:CreateRadio("Last", IsPos(nil), SetPos(nil))
		local spells = SectionSpells(categoryFrame)
		if #spells > 0 then
			place:CreateDivider()
			for _, spell in ipairs(spells) do
				place:CreateRadio("After " .. spell.name, IsPos(spell.id), SetPos(spell.id))
			end
		end
		local count = #Custom:Entries(key)
		root:CreateButton("Move Earlier", function() Custom:Move(key, index, -1) end):SetEnabled(index > 1)
		root:CreateButton("Move Later", function() Custom:Move(key, index, 1) end):SetEnabled(index < count)
		if entry.kind == "item" then
			root:CreateCheckbox("Show With None Left", function()
				local current = Custom:Entries(key)[index]
				return current ~= nil and current.always == true
			end, function()
				local current = Custom:Entries(key)[index]
				Custom:SetField(key, index, "always", not (current and current.always) or nil)
			end)
		end
		if entry.kind == "spell" or entry.kind == "aura" then
			root:CreateDivider()
			CMP.SpellMenu:AddStyleEntries(root, entry.id, true)
		end
		root:CreateDivider()
		root:CreateButton(REMOVE or "Remove", function() Custom:Remove(key, index) end)
	end)
end

-- A spell or item held on the cursor (dragged from the spellbook, bags or character pane).
function CustomSettings:AcceptCursor(key)
	if not GetCursorInfo then
		return false
	end
	local kind, a, _, c, d = GetCursorInfo()
	if kind == "spell" then
		local spellID = type(c) == "number" and c or d
		if type(spellID) == "number" then
			ClearCursor()
			if key == "BuffIcon" then
				self:AddAura(key, spellID) -- a spell's buff usually has the spell's ID
			else
				self:AddSpell(key, spellID)
			end
			return true
		end
	elseif kind == "item" and type(a) == "number" then
		ClearCursor()
		if key == "BuffIcon" then
			-- an item's buff: its use spell (trinkets, potions)
			local ok, _, spellID = Try(C_Item and C_Item.GetItemSpell, a)
			if ok and type(spellID) == "number" then
				self:AddAura(key, spellID)
			else
				CMP:Print("That item has no use effect to track.")
			end
		else
			self:AddItem(key, a)
		end
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

local function ShowTooltip(tile)
	local tooltip = GameTooltip
	tooltip:SetOwner(tile, "ANCHOR_RIGHT")
	local entry = tile.entry
	if tile.isAdd then
		if tile.key == "BuffIcon" then
			tooltip:SetText("Add Custom Buff", 1, 1, 1)
			tooltip:AddLine("A buff your own spell or item starts (trinkets, potions, spells). Click for a menu, or drop a spell or item here.", nil, nil, nil, true)
		else
			tooltip:SetText("Add Custom Spell or Item", 1, 1, 1)
			tooltip:AddLine("Click for a menu, or drop a spell or item here.", nil, nil, nil, true)
		end
		tooltip:AddLine("Cooldown Manager Extras", 0.31, 0.64, 1)
	elseif entry then
		local shown = false
		if (entry.kind == "spell" or entry.kind == "aura") and tooltip.SetSpellByID then
			shown = (pcall(tooltip.SetSpellByID, tooltip, entry.id))
		elseif entry.kind == "item" and tooltip.SetItemByID then
			shown = (pcall(tooltip.SetItemByID, tooltip, entry.id))
		elseif entry.kind == "slot" and tooltip.SetInventoryItem then
			shown = (pcall(tooltip.SetInventoryItem, tooltip, "player", entry.id))
		end
		if not shown or tooltip:NumLines() == 0 then
			tooltip:SetText(Custom:Name(entry), 1, 1, 1)
		end
		local problem = entry.kind == "aura" and CustomSettings:BuffProblem(entry.id)
		if problem then
			tooltip:AddLine(problem, 1, 0.38, 0.38, true)
		end
		tooltip:AddLine("Custom (Cooldown Manager Extras). Right-click for options.", 0.31, 0.64, 1, true)
	end
	tooltip:Show()
end

local function CreateTile()
	local tile = CreateFrame("Frame", nil, UIParent)
	tile:SetSize(38, 38)
	tile.Icon = tile:CreateTexture(nil, "ARTWORK")
	tile.Icon:SetAllPoints()
	tile.Highlight = tile:CreateTexture(nil, "HIGHLIGHT")
	tile.Highlight:SetAllPoints()
	tile.Highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	tile.Highlight:SetBlendMode("ADD")
	-- a small corner mark tells our tiles from Blizzard's
	tile.Badge = tile:CreateTexture(nil, "OVERLAY")
	tile.Badge:SetSize(6, 6)
	tile.Badge:SetPoint("TOPRIGHT", -2, -2)
	tile.Badge:SetColorTexture(unpack(BADGE_COLOR))
	tile:EnableMouse(true)
	tile:SetScript("OnEnter", ShowTooltip)
	tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tile:SetScript("OnReceiveDrag", function(self)
		CustomSettings:AcceptCursor(self.key)
	end)
	tile:SetScript("OnMouseUp", function(self, button)
		if CustomSettings:AcceptCursor(self.key) then
			return
		end
		if self.isAdd then
			CustomSettings:OpenAddMenu(self, self.key)
		elseif button == "RightButton" or button == "LeftButton" then
			CustomSettings:OpenEntryMenu(self, self.key, self.entryIndex)
		end
	end)
	return tile
end

local function SetupTile(tile, key, entry, index)
	tile.key = key
	tile.entry = entry
	tile.entryIndex = index
	tile.isAdd = entry == nil
	if tile.isAdd then
		tile.Icon:SetAtlas("cdm-empty")
		tile.Icon:SetVertexColor(unpack(ADD_TINT))
		tile.Icon:SetDesaturated(false)
		tile.Badge:Hide()
	else
		tile.Icon:SetTexture(Custom:Texture(entry))
		tile.Icon:SetVertexColor(1, 1, 1)
		-- like Blizzard's unlearned spells: gray when it wouldn't show in the bar now
		tile.Icon:SetDesaturated(not Custom:IsAvailable(entry))
		tile.Badge:Show()
	end
end

local function HideTiles(key)
	for _, tile in ipairs(tilesByKey[key] or {}) do
		tile:Hide()
	end
end

-- Blizzard's icons and our tiles in one grid, in bar order.
function CustomSettings:PlaceTiles(categoryFrame, key)
	local container = categoryFrame.Container
	if not container then
		return
	end
	local items = BlizzardItems(categoryFrame)
	local bySpell, list = {}, {}
	for _, item in ipairs(items) do
		list[#list + 1] = { frame = item, major = item.layoutIndex, minor = 0 }
		if not IsEmptyCategoryItem(item) then
			local spellID = CMP:GetItemSpellID(item)
			if spellID and not bySpell[spellID] then
				bySpell[spellID] = item.layoutIndex
			end
		end
	end
	local tiles = tilesByKey[key] or {}
	tilesByKey[key] = tiles
	local entries = Custom:Entries(key)
	for i = 1, #entries + 1 do
		local tile = tiles[i]
		if not tile then
			tile = CreateTile()
			tiles[i] = tile
		end
		local entry = entries[i]
		SetupTile(tile, key, entry, i)
		tile:SetParent(container)
		tile:SetFrameLevel(container:GetFrameLevel() + 2)
		local major
		if not entry then
			major = LAST -- "+" always last
		elseif entry.pos == "start" then
			major = -1
		elseif type(entry.pos) == "number" and bySpell[entry.pos] then
			major = bySpell[entry.pos]
		else
			major = LAST
		end
		list[#list + 1] = { frame = tile, major = major, minor = entry and i or LAST }
		tile:Show()
	end
	for i = #entries + 2, #tiles do
		tiles[i]:Hide()
	end
	table.sort(list, function(a, b)
		if a.major ~= b.major then
			return a.major < b.major
		end
		return a.minor < b.minor
	end)

	local stride = container.stride or 7
	local padX, padY = container.childXPadding or 8, container.childYPadding or 8
	local size = items[1] and items[1]:GetWidth() or 38
	if CMP.IsSecret(size) or not size or size <= 0 then
		size = 38
	end
	for n, entry in ipairs(list) do
		local slot = n - 1
		local column, row = slot % stride, math.floor(slot / stride)
		entry.frame:ClearAllPoints()
		entry.frame:SetPoint("TOPLEFT", container, "TOPLEFT", column * (size + padX), -row * (size + padY))
	end
	local rows = math.max(1, math.ceil(#list / stride))
	container:SetHeight(rows * size + (rows - 1) * padY)
end

-- Runs right after Blizzard's grid placed its icons. The section (a resize layout) calls
-- the grid's Layout and then measures it, so the height we set here is what it uses.
local function AfterGridLayout(categoryFrame)
	local key = CategoryKey(categoryFrame)
	if not key then
		-- a pooled section now showing something else: our tiles leave it
		for _, tiles in pairs(tilesByKey) do
			for _, tile in ipairs(tiles) do
				if tile:GetParent() == categoryFrame.Container then
					tile:Hide()
				end
			end
		end
		return
	end
	CMP.Safe(CustomSettings.PlaceTiles, CustomSettings, categoryFrame, key)
end

function CustomSettings:HookCategory(categoryFrame)
	local container = categoryFrame.Container
	if container and not hookedContainers[container] and container.Layout then
		hookedContainers[container] = true
		hooksecurefunc(container, "Layout", function(self)
			AfterGridLayout(self:GetParent())
		end)
	end
end

-- After Blizzard rebuilt the window, and after our own changes.
function CustomSettings:Refresh()
	local settings = CooldownViewerSettings
	if not settings or not settings.categoryPool or not settings.categoryPool.EnumerateActive then
		return
	end
	local seen = {}
	for categoryFrame in settings.categoryPool:EnumerateActive() do
		local key = CategoryKey(categoryFrame)
		if key then
			seen[key] = true
		end
		self:HookCategory(categoryFrame)
		AfterGridLayout(categoryFrame)
		if key and categoryFrame.Layout then
			-- re-measure the section (runs the grid again, and our placement after it)
			pcall(categoryFrame.Layout, categoryFrame)
		end
	end
	for key in pairs(tilesByKey) do
		if not seen[key] then
			HideTiles(key)
		end
	end
end

function CustomSettings:Start()
	local settings = CooldownViewerSettings
	if self.started or not settings or type(settings.RefreshLayout) ~= "function" then
		return
	end
	self.started = true
	hooksecurefunc(settings, "RefreshLayout", function()
		CMP.Safe(self.Refresh, self)
	end)
	if settings.IsShown and settings:IsShown() then
		CMP.Safe(self.Refresh, self)
	end
end
