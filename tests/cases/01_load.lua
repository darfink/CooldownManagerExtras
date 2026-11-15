-- Loading, initialisation and slash commands.
local T = ...

T.test("addon loads through the .toc and initialises with no Lua errors", function(H, T)
	local CMP = H.CMP
	T.truthy(CMP, "ns.CMP was not created")
	T.eq(#H.errors, 0)
	T.truthy(CMP.db, "saved variables table was not created")
	T.eq(CMP.activeLayout, "Modern", "active Edit Mode layout")
	T.eq(CMP.ready, true, "addon should be ready after PLAYER_ENTERING_WORLD")
	for _, key in ipairs({ "Essential", "Utility", "BuffIcon", "BuffBar", "PRD" }) do
		T.truthy(CMP.byKey[key].frame, key .. " frame was not bound")
	end
end)

T.test("loads in the .toc order and sees every file", function(H, T)
	local CMP = H.CMP
	for _, name in ipairs({ "Profiles", "Session", "Media", "Layout", "Skin", "Anchors", "Overlay", "Keybinds", "Timers",
		"Lockouts", "Mana", "Settings", "SpellMenu", "Options", "Diagnostics", "Masque" }) do
		T.truthy(CMP[name], "CMP." .. name .. " missing: its file did not load")
	end
	T.eq(_G.CooldownManagerPlus, CMP)
end)

T.test("a second boot with saved data keeps it and fills in missing tables", { saved = { version = 1, layouts = { Modern = { Essential = { style = "square" } } } } }, function(H, T)
	local CMP = H.CMP
	T.eq(CMP:Get("Essential", "style"), "square")
	T.eq(CMP:Get("Utility", "style"), "blizzard", "unset values fall back to defaults")
	for _, field in ipairs({ "spells", "ui", "profiles", "chars" }) do
		T.eq(type(CMP.db[field]), "table", "db." .. field)
	end
end)

T.test("slash command /cmp is registered", function(H, T)
	T.eq(_G.SLASH_COOLDOWNMANAGERPLUS1, "/cmp")
	T.eq(type(_G.SlashCmdList.COOLDOWNMANAGERPLUS), "function")
end)

T.test("/cmp help (and unknown words) print the command list", function(H, T)
	local slash = _G.SlashCmdList.COOLDOWNMANAGERPLUS
	slash("help")
	T.truthy(T.printed(H, "/cmp probe"), "help lists /cmp probe")
	T.truthy(T.printed(H, "/cmp blocked"), "help lists /cmp blocked")
	T.truthy(T.printed(H, "/cmp reset"), "help lists /cmp reset")
	H.output = {}
	slash("")
	T.truthy(T.printed(H, "Settings live in Edit Mode"))
end)

T.test("/cmp probe reports 'No active tracked auras' when nothing is tracked", function(H, T)
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("probe")
	T.truthy(T.printed(H, "Aura probe"))
	T.truthy(T.printed(H, "No active tracked auras"))
end)

T.test("/cmp probe lists an aura on a Tracked Buffs item, in and out of combat", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 17, linkedSpellID = 6788 })
	H.spells[6788] = { name = "Weakened Soul" }
	local aura = H.addAura("player", { spellId = 6788, isHarmful = true, duration = 15, expirationTime = H.now + 15 })
	H.setItemAura(item, aura)
	local slash = _G.SlashCmdList.COOLDOWNMANAGERPLUS
	slash("probe")
	T.truthy(T.printed(H, "Weakened Soul"), "names the linked spell")
	T.truthy(T.printed(H, "instance readable"), "reports readability")
	-- in combat the aura fields are secret; the probe must not raise
	H.inCombat = true
	H.output = {}
	H.setItemAura(item, H.secretFields(aura))
	slash("probe")
	T.truthy(T.printed(H, "Aura probe (in combat"), "header still printed")
end)

T.test("/cmp blocked lists recorded ADDON_ACTION_BLOCKED events and 'blocked clear' forgets them", function(H, T)
	local slash = _G.SlashCmdList.COOLDOWNMANAGERPLUS
	slash("blocked")
	T.truthy(T.printed(H, "No blocked actions recorded"))
	H.fireEvent("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "SetPoint()")
	H.fireEvent("ADDON_ACTION_FORBIDDEN", "CooldownManagerPlus", "ClearAllPoints()")
	T.eq(#H.CMP.db.blocked, 2)
	H.output = {}
	slash("blocked")
	T.truthy(T.printed(H, "2 blocked action(s)"))
	T.truthy(T.printed(H, "SomeOtherAddon"))
	T.truthy(T.printed(H, "FORBIDDEN"))
	slash("blocked clear")
	T.eq(#H.CMP.db.blocked, 0)
end)

T.test("blocked-action log keeps only the newest 50 entries", function(H, T)
	for i = 1, 60 do
		H.fireEvent("ADDON_ACTION_BLOCKED", "Addon" .. i, "Func")
	end
	T.eq(#H.CMP.db.blocked, 50)
	T.eq(H.CMP.db.blocked[50].addon, "Addon60")
	T.eq(H.CMP.db.blocked[1].addon, "Addon11")
end)

T.test("/cmp status prints one line per frame", function(H, T)
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("status")
	T.truthy(T.printed(H, "layout:"))
	T.truthy(T.printed(H, "Essential: frame=yes"))
	T.truthy(T.printed(H, "PRD: frame=yes"))
end)

T.test("/cmp reset clears the active layout's settings", function(H, T)
	local CMP = H.CMP
	CMP:Set("Essential", "style", "square")
	T.eq(CMP:Get("Essential", "style"), "square")
	_G.SlashCmdList.COOLDOWNMANAGERPLUS("reset")
	T.eq(CMP:Get("Essential", "style"), "blizzard")
end)
