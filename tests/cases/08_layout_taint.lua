-- Layout / anchoring behaviour and the addon's "never call Edit Mode's overridden methods" rule.
local T = ...

local function populate(H)
	local items = {}
	for _, key in ipairs({ "Essential", "Utility", "BuffIcon", "BuffBar" }) do
		items[key] = {}
		for i = 1, 4 do
			items[key][i] = H.viewers[key]:AddItem({ spellID = 100 * i })
		end
	end
	return items
end

T.test("taint: changing every kind of setting never calls the viewers' Edit Mode SetPoint/SetScale/SetSize overrides", function(H, T)
	local CMP = H.CMP
	populate(H)
	-- unmanaged (moved once in Edit Mode) so the geometry options are live
	for _, key in ipairs({ "Essential", "Utility", "BuffIcon" }) do
		H.viewers[key].systemInfo.isInDefaultPosition = false
	end
	CMP:Set("Essential", "align", "center")
	CMP:Set("Essential", "iconSize", 40)
	CMP:Set("Essential", "style", "square")
	CMP:Set("Essential", "spacingX", 4)
	CMP:Set("Essential", "sharedBorders", true)
	CMP:Set("Utility", "attachTo", "Essential")
	CMP:Set("Utility", "attachSide", "BELOW")
	CMP:Set("BuffIcon", "align", "end")
	CMP:Set("BuffBar", "matchWidth", "target")
	CMP:Set("BuffBar", "attachTo", "Utility")
	CMP:Set("PRD", "style", "square")
	CMP:Set("PRD", "attachTo", "Utility")
	H.flush()
	H.advance(1)
	CMP:Update()
	H.viewers.BuffIcon.items[1]:Hide()
	H.viewers.BuffIcon.items[1]:Show()
	T.eq(#H.violations, 0, "addon called an Edit Mode override: " .. (H.violations[1] and (H.violations[1].method .. H.violations[1].trace) or ""))
end)

T.test("layout: 'center' alignment centers a short row inside a full-width one", function(H, T)
	local CMP = H.CMP
	local items = populate(H)
	H.viewers.BuffIcon.systemInfo.isInDefaultPosition = false
	CMP:Set("BuffIcon", "align", "center")
	-- hide two of the four buffs: the remaining two are packed and centered on the frame
	items.BuffIcon[1]:Hide()
	items.BuffIcon[2]:Hide()
	H.flush()
	local viewer = H.viewers.BuffIcon
	local vl, _, vw = viewer:GetRect()
	local l3 = items.BuffIcon[3]:GetLeft()
	local l4, _, w4 = items.BuffIcon[4]:GetRect()
	local left, right = l3, l4 + w4
	T.near((left + right) / 2, vl + vw / 2, 1.5, "the two shown buffs are centered on the viewer")
end)

T.test("layout: default (managed) viewers keep their geometry untouched", function(H, T)
	local items = populate(H)
	local viewer = H.viewers.Essential
	T.eq(viewer.systemInfo.isInDefaultPosition, true)
	local w, h = viewer:GetSize()
	H.CMP:Set("Essential", "align", "center")
	H.CMP:Set("Essential", "iconSize", 60)
	H.flush()
	T.eq(select(1, viewer:GetSize()), w)
	T.eq(select(2, viewer:GetSize()), h)
	T.eq(#H.violations, 0)
end)

T.test("taint: in combat nothing protected is touched and the update is deferred when something is protected", function(H, T)
	local CMP = H.CMP
	populate(H)
	H.viewers.Essential.systemInfo.isInDefaultPosition = false
	H.state(H.viewers.Essential).protected = true
	H.inCombat = true
	CMP:Set("Essential", "align", "center")
	T.eq(CMP.pendingAfterCombat, true, "waits for the end of combat")
	H.inCombat = false
	H.fireEvent("PLAYER_REGEN_ENABLED")
	T.eq(CMP.pendingAfterCombat, false)
end)

T.test("share: export then import round-trips the settings into a new profile", function(H, T)
	local CMP = H.CMP
	CMP:Set("Essential", "style", "square")
	CMP:Set("Utility", "iconSize", 33)
	local ok, text = pcall(CMP.Share.Export, CMP.Share)
	T.truthy(ok, tostring(text))
	T.eq(type(text), "string")
	local imported, message = CMP.Share:Import(text, "Copy", true)
	T.truthy(imported, tostring(message))
	T.truthy(CMP.db.profiles.Copy, "profile created")
	T.eq(CMP.db.profiles.Copy.frames.Essential.style, "square")
	T.eq(CMP.db.profiles.Copy.frames.Utility.iconSize, 33)
	local bad, why = CMP.Share:Import("not an export", "Nope", true)
	T.falsy(bad)
end)
