-- Custom entries (Custom.lua, CustomSettings.lua): your own spells, items and trinket
-- slots in Essential / Utility, next to Blizzard's icons, and their tiles in Cooldown Settings.
local T = ...

local function populate(H, key, spells)
	local items = {}
	for i, spellID in ipairs(spells) do
		H.spells[spellID] = H.spells[spellID] or { name = "Spell " .. spellID }
		items[i] = H.viewers[key]:AddItem({ spellID = spellID })
	end
	return items
end

local function unmanaged(H, key)
	H.viewers[key].systemInfo.isInDefaultPosition = false
end

local function customFrames(H, key)
	return H.CMP.Custom:Frames(H.CMP.byKey[key])
end

-- left edges in placement order: Blizzard's items and ours, sorted by x
local function order(frames)
	table.sort(frames, function(a, b) return a:GetLeft() < b:GetLeft() end)
	return frames
end

T.test("custom: a spell added to Essential gets an icon after Blizzard's", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Essential")
	local items = populate(H, "Essential", { 100, 200, 300 })
	H.spells[900] = { name = "My Spell", texture = 12345 }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	H.flush()
	local custom = customFrames(H, "Essential")
	T.eq(#custom, 1)
	local icon = custom[1]
	T.truthy(icon:IsShown())
	T.eq(icon.Icon:GetTexture(), 12345)
	T.eq(icon:GetParent(), H.viewers.Essential, "in the viewer")
	T.eq(icon.layoutIndex, nil, "never in Blizzard's grid layout")
	local row = order({ items[1], items[2], items[3], icon })
	T.eq(row[4], icon, "last")
	T.near(icon:GetWidth() * icon:GetScale(), items[1]:GetWidth() * items[1]:GetScale(), 0.01, "same size")
end)

T.test("custom: 'after <spell>' and 'first' place the icon among Blizzard's", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Essential")
	local items = populate(H, "Essential", { 100, 200, 300 })
	H.spells[900] = { name = "A" }
	H.spells[901] = { name = "B" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900, pos = 100 })
	CMP.Custom:Add("Essential", { kind = "spell", id = 901, pos = "start" })
	H.flush()
	local byID = {}
	for _, frame in ipairs(customFrames(H, "Essential")) do byID[frame.entry.id] = frame end
	local row = order({ items[1], items[2], items[3], byID[900], byID[901] })
	T.eq(row[1], byID[901], "first")
	T.eq(row[2], items[1])
	T.eq(row[3], byID[900], "right after spell 100")
	T.eq(row[4], items[2])
end)

T.test("custom: in a viewer at its default place, ours continue Blizzard's grid without touching it", function(H, T)
	local CMP = H.CMP
	local items = populate(H, "Essential", { 100, 200 })
	local viewer = H.viewers.Essential
	local before = { items[1]:GetLeft(), items[2]:GetLeft() }
	local w, h = viewer:GetSize()
	H.spells[900] = { name = "A" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	H.flush()
	local icon = customFrames(H, "Essential")[1]
	T.eq(items[1]:GetLeft(), before[1])
	T.eq(items[2]:GetLeft(), before[2])
	local vw, vh = viewer:GetSize()
	T.eq(vw, w, "viewer size stays Blizzard's")
	T.eq(vh, h)
	T.truthy(icon:GetLeft() > items[2]:GetLeft(), "after the last one")
	T.eq(#H.violations, 0, "no Edit Mode override called")
end)

T.test("custom: unknown spells, items you don't have and trinkets without a use stay hidden", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Utility")
	populate(H, "Utility", { 100 })
	H.spells[900] = { name = "Not Known", known = false }
	H.items[5512] = { name = "Healthstone", count = 0, use = "Heal" }
	H.items[7000] = { name = "Potion", count = 0, use = "Drink" }
	H.items[8000] = { name = "Plain Trinket", equippable = true, equipped = true }
	H.inventory[13] = 8000
	CMP.Custom:Add("Utility", { kind = "spell", id = 900 })
	CMP.Custom:Add("Utility", { kind = "item", id = 5512 })
	CMP.Custom:Add("Utility", { kind = "item", id = 7000, always = true })
	CMP.Custom:Add("Utility", { kind = "slot", id = 13 })
	CMP.Custom:Add("Utility", { kind = "slot", id = 14 })
	H.flush()
	local shown = customFrames(H, "Utility")
	T.eq(#shown, 1, "only the 'always' potion")
	T.eq(shown[1].entry.id, 7000)
	T.truthy(shown[1].Icon:IsDesaturated(), "gray with none left")
	T.eq(tostring(shown[1].ChargeCount.Current:GetText()), "0")
	-- now you get a healthstone and an on-use trinket
	H.items[5512].count = 1
	H.items[8000].use = "Use"
	H.fireEvent("BAG_UPDATE_DELAYED")
	H.advance(0.1)
	H.flush()
	T.eq(#customFrames(H, "Utility"), 3)
end)

T.test("custom: the square style and fonts apply to our icons", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Essential")
	populate(H, "Essential", { 100 })
	H.spells[900] = { name = "A" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	CMP:Set("Essential", "style", "square")
	H.flush()
	local icon = customFrames(H, "Essential")[1]
	T.eq(icon.Icon:GetNumMaskTextures(), 0, "round mask removed")
	CMP:Set("Essential", "style", "blizzard")
	T.eq(icon.Icon:GetNumMaskTextures(), 1, "mask back")
end)

T.test("custom: spell cooldowns go through duration objects; hidden item cooldowns don't raise", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Essential")
	populate(H, "Essential", { 100 })
	H.spells[900] = { name = "A" }
	H.items[7000] = { name = "Potion", count = 3, use = "Drink" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	CMP.Custom:Add("Essential", { kind = "item", id = 7000 })
	H.flush()
	H.secretReturn(H.G.C_Item, "GetItemCooldown")
	H.secretReturn(H.G.C_Spell, "GetSpellCharges", "fields")
	H.inCombat = true
	H.fireEvent("SPELL_UPDATE_COOLDOWN")
	H.fireEvent("BAG_UPDATE_COOLDOWN")
	H.flush()
	T.eq(#customFrames(H, "Essential"), 2)
	H.inCombat = false
end)

T.test("custom: settings are kept per viewer and survive export / import", function(H, T)
	local CMP = H.CMP
	CMP.Custom:Add("Essential", { kind = "spell", id = 900, pos = 100 })
	CMP.Custom:Add("Utility", { kind = "slot", id = 13 })
	T.falsy(CMP.Custom:Add("Essential", { kind = "spell", id = 900 }), "no duplicates")
	local text = CMP.Share:Export()
	local ok, message = CMP.Share:Import(text, "Copy", true)
	T.truthy(ok, tostring(message))
	local frames = CMP.db.profiles.Copy.frames
	T.eq(frames.Essential.custom[1].id, 900)
	T.eq(frames.Essential.custom[1].pos, 100)
	T.eq(frames.Utility.custom[1].kind, "slot")
end)

---------------------------------------------------------------------------
-- Cooldown Settings window
---------------------------------------------------------------------------

local function settings(H, essential, utility)
	for _, id in ipairs(essential) do H.spells[id] = H.spells[id] or { name = "Spell " .. id } end
	for _, id in ipairs(utility or {}) do H.spells[id] = H.spells[id] or { name = "Spell " .. id } end
	local window, frames = H.makeCooldownSettings({
		{ category = H.G.Enum.CooldownViewerCategory.Essential, spells = essential },
		{ category = H.G.Enum.CooldownViewerCategory.Utility, spells = utility or {} },
	})
	H.CMP.CustomSettings:Start()
	window:RefreshLayout()
	return window, frames
end

-- our tiles in a section (frames with a Badge), shown
local function tiles(section)
	local result = {}
	for _, child in ipairs({ section.Container:GetChildren() }) do
		if child.Badge and child:IsShown() then result[#result + 1] = child end
	end
	return result
end
local function addTile(section)
	for _, tile in ipairs(tiles(section)) do
		if tile.isAdd then return tile end
	end
end
local function blizzardItem(section, spellID)
	for item in section.itemPool:EnumerateActive() do
		if item.spellID == spellID then return item end
	end
end
-- position in the section grid: row * 7 + column
local function slot(frame, section)
	local left, top = frame:GetLeft() - section.Container:GetLeft(), section.Container:GetTop() - frame:GetTop()
	return math.floor(top / 46 + 0.5) * 7 + math.floor(left / 46 + 0.5)
end

T.test("custom settings: a + tile follows Blizzard's icons in Essential and Utility", function(H, T)
	local _, frames = settings(H, { 100, 200 }, { 300 })
	local essential, utility = frames[1], frames[2]
	local add = addTile(essential)
	T.truthy(add, "+ tile in Essential")
	T.eq(slot(add, essential), 2, "right after Blizzard's two icons")
	T.truthy(addTile(utility), "+ tile in Utility")
	T.eq(add.layoutIndex, nil, "not in Blizzard's grid layout")
end)

T.test("custom settings: tiles sit at their bar position, and the section grows a row when needed", function(H, T)
	local CMP = H.CMP
	local _, frames = settings(H, { 100, 200, 300, 400, 500, 600 })
	local essential = frames[1]
	local height = essential:GetHeight()
	H.spells[900] = { name = "Mine" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900, pos = 200 })
	H.flush()
	local mine
	for _, tile in ipairs(tiles(essential)) do
		if tile.entry and tile.entry.id == 900 then mine = tile end
	end
	T.truthy(mine, "tile for the custom spell")
	T.eq(slot(mine, essential), 2, "right after spell 200")
	T.eq(slot(blizzardItem(essential, 300), essential), 3, "Blizzard's next icon moved along")
	T.eq(slot(addTile(essential), essential), 7, "+ wraps to the second row")
	T.truthy(essential:GetHeight() > height + 40, "section grew by a row")
	-- Blizzard rebuilds the window (e.g. after a drag): still in place
	CooldownViewerSettings:RefreshLayout()
	T.eq(slot(mine, essential), 2)
end)

T.test("custom settings: the + menu adds a trinket slot; the tile menu places and removes it", function(H, T)
	local CMP = H.CMP
	local _, frames = settings(H, { 100, 200 })
	local essential = frames[1]
	local add = addTile(essential)
	add:GetScript("OnMouseUp")(add, "LeftButton")
	local menu = H.lastMenu
	T.truthy(menu and menu:Find("Trinket 1"), "menu offers trinket slots")
	menu:Find("Trinket 1").fn()
	H.flush()
	T.eq(CMP.Custom:Entries("Essential")[1].kind, "slot")
	local tile
	for _, t in ipairs(tiles(essential)) do if t.entry then tile = t end end
	T.truthy(tile, "a tile for the slot")
	tile:GetScript("OnMouseUp")(tile, "RightButton")
	local after = H.lastMenu:Find("After Spell 100")
	T.truthy(after, "can be placed after Blizzard's spells")
	after.fn()
	T.eq(CMP.Custom:Entries("Essential")[1].pos, 100)
	for _, t in ipairs(tiles(essential)) do if t.entry then tile = t end end
	tile:GetScript("OnMouseUp")(tile, "RightButton")
	H.lastMenu:Find("Remove").fn()
	T.eq(#CMP.Custom:Entries("Essential"), 0)
end)

T.test("custom settings: typed spell names and IDs are added; unknown ones are reported", function(H, T)
	local CMP = H.CMP
	H.spells[900] = { name = "Mine" }
	CMP.CustomSettings:AddFromText("Essential", "spell", " 900 ")
	T.eq(CMP.Custom:Entries("Essential")[1].id, 900)
	CMP.CustomSettings:AddFromText("Essential", "spell", "12345678")
	T.eq(#CMP.Custom:Entries("Essential"), 1, "unknown spell not added")
end)

T.test("probe: /cme probe spell|item|slot|aura run without errors, also with hidden values", function(H, T)
	H.spells[900] = { name = "Mine" }
	local slash = _G.SlashCmdList.COOLDOWNMANAGEREXTRAS
	slash("probe spell 900")
	slash("probe item 7000")
	slash("probe slot 13")
	slash("probe aura 900")
	slash("probe nonsense")
	slash("probe aura")
	H.secretReturn(H.G.C_Spell, "GetSpellCooldown", "fields")
	H.secretReturn(H.G.C_Item, "GetItemCooldown")
	H.inCombat = true
	slash("probe spell 900")
	slash("probe item 7000")
	H.inCombat = false
	T.truthy(true)
end)

T.test("custom: at the viewer's default place, 'first' / 'after' can't overlap Blizzard's icons", function(H, T)
	local CMP = H.CMP
	local items = populate(H, "Essential", { 100, 200 })
	H.spells[900] = { name = "A" }
	H.spells[901] = { name = "B" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900, pos = 100 })
	CMP.Custom:Add("Essential", { kind = "spell", id = 901, pos = "start" })
	H.flush()
	local lefts = { [items[1]:GetLeft()] = true, [items[2]:GetLeft()] = true }
	for _, frame in ipairs(customFrames(H, "Essential")) do
		T.falsy(lefts[frame:GetLeft()], "no shared slot")
		T.truthy(frame:GetLeft() > items[2]:GetLeft(), "appended")
		lefts[frame:GetLeft()] = true
	end
end)

T.test("custom: spells with charges show the recharge, not the plain cooldown", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "Essential")
	populate(H, "Essential", { 100 })
	H.spells[900] = { name = "Charged", charges = { currentCharges = 1, maxCharges = 2, cooldownStartTime = H.now, cooldownDuration = 20 } }
	H.G.C_Spell.GetSpellChargeDuration = function(id) return { charge = id } end
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	H.flush()
	local icon = customFrames(H, "Essential")[1]
	T.eq(tostring(icon.ChargeCount.Current:GetText()), "1")
	H.G.C_Spell.GetSpellChargeDuration = nil
	H.fireEvent("SPELL_UPDATE_CHARGES")
	local _, duration = icon.Cooldown:GetCooldownTimes()
	T.eq(duration, 20000, "fallback: start / duration from the charge info")
end)

T.test("custom settings: a profile switch with the window open shows the new profile's tiles", function(H, T)
	local CMP = H.CMP
	local window, frames = settings(H, { 100 })
	window:Show()
	H.spells[900] = { name = "Mine" }
	CMP.Custom:Add("Essential", { kind = "spell", id = 900 })
	H.flush()
	T.eq(#tiles(frames[1]), 2, "custom + add")
	CMP.Profiles:Create("Empty", false)
	CMP.Profiles:SetCharacterProfile("Empty")
	H.flush()
	T.eq(#tiles(frames[1]), 1, "only the + tile")
end)

T.test("custom settings: bag items with a cooldown (from their tooltip) come first, with item tooltips", function(H, T)
	local bags = { [0] = { 7000, 4000, 7000 } }
	rawset(_G, "C_Container", {
		GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
		GetContainerItemID = function(bag, slot) return bags[bag] and bags[bag][slot] end,
	})
	rawset(_G, "ITEM_COOLDOWN_TOTAL", "(%s Cooldown)")
	rawset(_G, "C_TooltipInfo", { GetItemByID = function(id)
		if id == 7000 then return { lines = { { leftText = "Use: Restores health. (2 Min Cooldown)" } } } end
		return { lines = { { leftText = "Use: Eat." } } }
	end })
	H.items[7000] = { name = "Potion", count = 2, use = "Drink" }
	H.items[4000] = { name = "Bread", count = 5, use = "Eat" }
	local _, frames = settings(H, { 100 })
	local add = addTile(frames[1])
	add:GetScript("OnMouseUp")(add, "LeftButton")
	local bagMenu = H.lastMenu:Find("From Your Bags")
	T.truthy(bagMenu:Find("Potion"), "potion listed")
	T.truthy(bagMenu:Find("Without a Cooldown"):Find("Bread"), "bread in its own submenu")
	T.truthy(bagMenu:Find("Potion").tooltip, "item tooltip on hover")
	local count = 0
	for _, e in ipairs(bagMenu.entries) do if e.text and e.text:find("Potion", 1, true) then count = count + 1 end end
	T.eq(count, 1, "listed once")
end)

T.test("custom settings: the input box previews what it found", function(H, T)
	H.spells[900] = { name = "Mine" }
	local CS = H.CMP.CustomSettings
	T.truthy(CS:Preview("spell", "900"):find("Mine", 1, true))
	T.truthy(CS:Preview("spell", "nothing"):find("No match", 1, true))
end)

---------------------------------------------------------------------------
-- Buffs in Tracked Buffs
---------------------------------------------------------------------------

local function buffFrames(H)
	return customFrames(H, "BuffIcon")
end

T.test("custom buffs: a buff from another player shows while it is on you", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	H.spells[10060] = { name = "Power Infusion" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 10060 })
	H.flush()
	T.eq(#buffFrames(H), 0, "not on you: hidden")
	local aura = H.addAura("player", { spellId = 10060, name = "Power Infusion", icon = 555, isHelpful = true,
		duration = 15, expirationTime = H.now + 15, isFromPlayerOrPlayerPet = false })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	local icons = buffFrames(H)
	T.eq(#icons, 1, "shown")
	T.eq(icons[1].Icon:GetTexture(), 555, "the buff's own icon")
	T.falsy(icons[1].Icon:IsDesaturated())
	T.truthy(CMP.Custom:SeenBuffs()[10060].external, "remembered as from another player")
	H.removeAura("player", aura.auraInstanceID)
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	T.eq(#buffFrames(H), 0, "gone again")
end)

T.test("custom buffs: in combat (buff hidden), a buff you start is timed from your cast", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	local TRINKET_USE, BUFF = 500, 600
	H.spells[BUFF] = { name = "Cocoon" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = BUFF })
	-- once out of combat: cast, then the buff appears -> learned
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", TRINKET_USE)
	local aura = H.addAura("player", { spellId = BUFF, name = "Cocoon", isHelpful = true, duration = 12,
		expirationTime = H.now + 12, isFromPlayerOrPlayerPet = true })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	T.eq(CMP.db.buffTriggers[BUFF], TRINKET_USE, "trigger learned")
	T.eq(CMP.db.buffDurations[BUFF], 12, "duration learned")
	H.removeAura("player", aura.auraInstanceID)
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(20)
	H.flush()
	-- in combat the game hides it from lookups
	H.inCombat = true
	aura = H.addAura("player", { spellId = BUFF, isHelpful = true, hiddenFromLookup = true })
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid2", TRINKET_USE)
	H.advance(0.1)
	H.flush()
	local icons = buffFrames(H)
	T.eq(#icons, 1, "shown from the cast")
	local _, duration = icons[1].Cooldown:GetCooldownTimes()
	T.eq(duration, 12000, "for the learned duration")
	H.advance(12.5)
	H.flush()
	T.eq(#buffFrames(H), 0, "gone when the time is up")
	H.inCombat = false
end)

T.test("custom buffs: Tracked Buffs showing inactive buffs keeps ours, grayed", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	H.viewers.BuffIcon.hideWhenInactive = false
	H.spells[10060] = { name = "Power Infusion" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 10060 })
	H.flush()
	local icons = buffFrames(H)
	T.eq(#icons, 1)
	T.truthy(icons[1].Icon:IsDesaturated())
end)

T.test("custom buffs: the Tracked Buffs + menu lists buffs seen on you, from others apart", function(H, T)
	local CMP = H.CMP
	H.spells[10060] = { name = "Power Infusion" }
	H.spells[17] = { name = "Shield" }
	H.addAura("player", { spellId = 10060, name = "Power Infusion", isHelpful = true, duration = 15,
		expirationTime = H.now + 15, isFromPlayerOrPlayerPet = false })
	H.addAura("player", { spellId = 17, name = "Shield", isHelpful = true, duration = 15,
		expirationTime = H.now + 15, isFromPlayerOrPlayerPet = true })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	local _, frames = settings(H, { 100 })
	local window = CooldownViewerSettings
	-- a third section for Tracked Buffs
	local _, buffSections = H.makeCooldownSettings({ { category = H.G.Enum.CooldownViewerCategory.TrackedBuff, spells = { 100 } } })
	CMP.CustomSettings:Refresh()
	local add = addTile(buffSections[1])
	T.truthy(add, "+ tile in Tracked Buffs")
	add:GetScript("OnMouseUp")(add, "LeftButton")
	local menu = H.lastMenu
	T.truthy(menu:Find("From Others"):Find("Power Infusion"))
	T.truthy(menu:Find("Your Own"):Find("Shield"))
	T.truthy(menu:Find("On You Now"):Find("Power Infusion"))
	menu:Find("From Others"):Find("Power Infusion").fn()
	T.eq(CMP.Custom:Entries("BuffIcon")[1].kind, "aura")
	T.eq(CMP.Custom:Entries("BuffIcon")[1].id, 10060)
end)

-- learn: cast TRIGGER, own buff BUFF appears with duration d (out of combat), then it ends
local function learnBuff(H, trigger, buff, duration)
	H.spells[buff] = H.spells[buff] or { name = "Buff " .. buff }
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", trigger)
	local aura = H.addAura("player", { spellId = buff, isHelpful = true, duration = duration,
		expirationTime = H.now + duration, isFromPlayerOrPlayerPet = true })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	H.removeAura("player", aura.auraInstanceID)
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(30)
	H.flush()
end

T.test("custom buffs: a buff cast before the pull keeps its timer when combat hides it", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 600 })
	learnBuff(H, 500, 600, 20)
	-- cast out of combat, buff readable...
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 500)
	local aura = H.addAura("player", { spellId = 600, isHelpful = true, duration = 20,
		expirationTime = H.now + 20, isFromPlayerOrPlayerPet = true })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	-- ...then the pull hides it
	H.inCombat = true
	aura.hiddenFromLookup = true
	H.fireEvent("PLAYER_REGEN_DISABLED")
	H.advance(2)
	H.flush()
	T.eq(#buffFrames(H), 1, "still shown, timed from the cast")
	H.inCombat = false
end)

T.test("custom buffs: casting a buff on someone else never shows yours (no learned trigger)", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	H.spells[10060] = { name = "Power Infusion" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 10060 })
	-- received from another player once (duration learned, not tied to your casts)
	local aura = H.addAura("player", { spellId = 10060, isHelpful = true, duration = 15,
		expirationTime = H.now + 15, isFromPlayerOrPlayerPet = false })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	H.removeAura("player", aura.auraInstanceID)
	H.advance(30)
	H.flush()
	H.inCombat = true
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 10060) -- you cast it on an ally
	H.advance(0.1)
	H.flush()
	T.eq(#buffFrames(H), 0)
	T.eq(CMP.db.buffTriggers and CMP.db.buffTriggers[10060], nil)
	H.inCombat = false
end)

T.test("custom buffs: an already-running buff doesn't learn an unrelated cast as its trigger", function(H, T)
	local CMP = H.CMP
	H.spells[600] = { name = "Old Buff" }
	H.addAura("player", { spellId = 600, isHelpful = true, duration = 60,
		expirationTime = H.now + 50, isFromPlayerOrPlayerPet = true }) -- started 10 s ago
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 999)
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 600 })
	H.advance(0.1)
	H.flush()
	T.eq(CMP.db.buffTriggers and CMP.db.buffTriggers[600], nil)
end)

T.test("custom buffs: each timed buff hides on its own time; combat end clears the timing", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 600 })
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 601 })
	learnBuff(H, 500, 600, 6)
	learnBuff(H, 500, 601, 20)
	H.inCombat = true
	H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 500)
	H.advance(0.1)
	H.flush()
	T.eq(#buffFrames(H), 2)
	H.advance(7)
	H.flush()
	T.eq(#buffFrames(H), 1, "the short one is gone")
	H.inCombat = false
	H.fireEvent("PLAYER_REGEN_ENABLED")
	H.advance(0.1)
	H.flush()
	T.eq(#buffFrames(H), 0, "out of combat: read directly (not on you)")
end)

T.test("custom settings: buffs with the same name show their duration and spell ID", function(H, T)
	H.addAura("player", { spellId = 1301168, name = "Transformative Cocoon", isHelpful = true, duration = 5,
		expirationTime = H.now + 5, isFromPlayerOrPlayerPet = true })
	H.addAura("player", { spellId = 1316048, name = "Transformative Cocoon", isHelpful = true, duration = 0,
		expirationTime = 0, isFromPlayerOrPlayerPet = true })
	H.addAura("player", { spellId = 1301167, name = "Transformative Cocoon", isHarmful = true, duration = 5,
		expirationTime = H.now + 5, isFromPlayerOrPlayerPet = true })
	local _, sections = H.makeCooldownSettings({ { category = H.G.Enum.CooldownViewerCategory.TrackedBuff, spells = { 100 } } })
	H.CMP.CustomSettings:Start()
	H.CMP.CustomSettings:Refresh()
	local add = addTile(sections[1])
	add:GetScript("OnMouseUp")(add, "LeftButton")
	local now = H.lastMenu:Find("On You Now")
	T.truthy(now:Find("5 s, 1301168"), "duration and ID")
	T.truthy(now:Find("no timer, 1316048"))
	T.truthy(now:Find("debuff"), "the self-stun is listed, marked as a debuff")
	T.truthy(now:Find("5 s, 1301167"))
	T.eq(H.CMP.CustomSettings.FormatDuration(120), "2 min")
end)

T.test("custom buffs: a debuff you put on yourself shows and is remembered, even if the spell ID lookup skips debuffs", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	populate(H, "BuffIcon", { 100 })
	-- this client's lookup by spell ID only finds buffs
	local lookup = H.G.C_UnitAuras.GetPlayerAuraBySpellID
	H.G.C_UnitAuras.GetPlayerAuraBySpellID = function(id)
		local aura = lookup(id)
		if aura and aura.isHarmful then return nil end
		return aura
	end
	H.G.C_UnitAuras.GetUnitAuraBySpellID = function() return nil end
	H.spells[1301167] = { name = "Transformative Cocoon" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 1301167 })
	H.addAura("player", { spellId = 1301167, name = "Transformative Cocoon", isHarmful = true, duration = 5,
		expirationTime = H.now + 5, isFromPlayerOrPlayerPet = true })
	H.addAura("player", { spellId = 777, name = "Enemy Curse", isHarmful = true, duration = 5,
		expirationTime = H.now + 5, isFromPlayerOrPlayerPet = false })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	T.eq(#buffFrames(H), 1, "the self-stun shows")
	local seen = CMP.Custom:SeenBuffs()
	T.truthy(seen[1301167] and seen[1301167].harmful, "remembered as a debuff")
	T.eq(seen[777], nil, "enemies' debuffs are not remembered")
end)

T.test("custom buffs: they join Tracked Buffs' row instead of wrapping to a new one", function(H, T)
	local CMP = H.CMP
	unmanaged(H, "BuffIcon")
	local items = populate(H, "BuffIcon", { 100, 200, 300 })
	H.viewers.BuffIcon.stride = 3 -- Blizzard's stride: its own icon count
	H.spells[10060] = { name = "Power Infusion" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 10060 })
	H.addAura("player", { spellId = 10060, isHelpful = true, duration = 15, expirationTime = H.now + 15 })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	local icon = buffFrames(H)[1]
	T.near(icon:GetTop(), items[1]:GetTop(), 0.5, "same row")
	T.truthy(icon:GetLeft() > items[3]:GetLeft(), "after Blizzard's")
end)

T.test("custom buffs: same row also when the viewer keeps Blizzard's place", function(H, T)
	local CMP = H.CMP
	local items = populate(H, "BuffIcon", { 100, 200, 300 })
	H.viewers.BuffIcon.stride = 3
	H.spells[10060] = { name = "Power Infusion" }
	CMP.Custom:Add("BuffIcon", { kind = "aura", id = 10060 })
	H.addAura("player", { spellId = 10060, isHelpful = true, duration = 15, expirationTime = H.now + 15 })
	H.fireEvent("UNIT_AURA", "player", { isFullUpdate = true })
	H.advance(0.1)
	H.flush()
	local icon = buffFrames(H)[1]
	T.near(icon:GetTop(), items[1]:GetTop(), 0.5, "same row")
end)
