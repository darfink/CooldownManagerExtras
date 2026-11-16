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

-- At UI scales other than 1, Blizzard's icon size is a fraction of a pixel and a centered
-- frame can start half a pixel off; the game then rounds edges differently, so the bars and
-- the icons below them (and icons and their borders) end up a pixel apart.
for _, cfg in ipairs({ { ui = 0.64, prd = 1 }, { ui = 0.71, prd = 1.1 }, { ui = 0.53, prd = 0.9 } }) do
	T.test(("layout: rows and bars line up on whole pixels (UI scale %.2f, PRD scale %.1f)"):format(cfg.ui, cfg.prd), function(H, T)
		local CMP = H.CMP
		H.state(H.UIParent).scale = cfg.ui
		H.viewers.PRD:SetScale(cfg.prd)
		for _, key in ipairs({ "Essential", "Utility" }) do
			H.viewers[key].systemInfo.isInDefaultPosition = false
			for i = 1, (key == "Essential" and 7 or 8) do
				H.spells[100 * i] = { name = "S" .. i }
				H.viewers[key]:AddItem({ spellID = 100 * i })
			end
			CMP:Set(key, "style", "square")
			CMP:Set(key, "align", "center")
			CMP:Set(key, "spacingX", 0)
			CMP:Set(key, "sharedBorders", true)
		end
		CMP:Set("Utility", "attachTo", "Essential")
		CMP:Set("Utility", "matchWidth", "target")
		CMP:Set("PRD", "attachTo", "Essential")
		CMP:Set("PRD", "attachSide", "ABOVE")
		CMP:Set("PRD", "matchWidth", "widest")
		CMP:Set("PRD", "style", "square")
		H.flush()
		local function px(v, frame) return v * frame:GetEffectiveScale() / H.pixelFactor end
		local function whole(v) return math.abs(v - math.floor(v + 0.5)) < 0.01 end
		local l, _, w = CMP.Anchors:VisibleRect(H.viewers.PRD)
		local prdL, prdR = px(l, H.UIParent), px(l + w, H.UIParent)
		T.truthy(whole(prdL) and whole(prdR), ("PRD on whole pixels: %.3f %.3f"):format(prdL, prdR))
		for _, key in ipairs({ "Essential", "Utility" }) do
			local left, right = math.huge, -math.huge
			for _, it in ipairs(H.viewers[key].items) do
				local a, b = px(it:GetLeft(), it), px(it:GetRight(), it)
				T.truthy(whole(a) and whole(b), ("%s icon on whole pixels: %.3f %.3f"):format(key, a, b))
				left, right = math.min(left, a), math.max(right, b)
			end
			T.near(left, prdL, 0.01, key .. " starts where the bars start")
			T.near(right, prdR, 0.01, key .. " ends where the bars end")
		end
	end)
end

T.test("layout: rows matching the PRD's own (fractional) width line up with it on whole pixels", function(H, T)
	local CMP = H.CMP
	H.state(H.UIParent).scale = 0.71
	local prd = H.viewers.PRD
	prd:SetScale(1.1)
	prd.defaultBarWidth, prd.barWidthPercent = 200, 157 -- 314 units * 1.1 * 0.71: not whole pixels
	H.raw.SetWidth(prd, 314)
	for _, part in ipairs({ prd.HealthBarsContainer, prd.PowerBar, prd.AlternatePowerBar }) do H.raw.SetWidth(part, 314) end
	-- placed by Edit Mode, off the pixel grid
	prd.systemInfo = { anchorInfo = { point = "CENTER", relativeTo = H.UIParent, relativePoint = "CENTER", offsetX = 0.37, offsetY = -200.4 } }
	for _, key in ipairs({ "Essential", "Utility" }) do
		H.viewers[key].systemInfo.isInDefaultPosition = false
		for i = 1, (key == "Essential" and 7 or 8) do
			H.spells[100 * i] = { name = "S" .. i }
			H.viewers[key]:AddItem({ spellID = 100 * i })
		end
		CMP:Set(key, "style", "square")
		CMP:Set(key, "spacingX", 0)
		CMP:Set(key, "sharedBorders", true)
	end
	CMP:Set("Essential", "attachTo", "PRD")
	CMP:Set("Essential", "matchWidth", "target")
	CMP:Set("Utility", "attachTo", "Essential")
	CMP:Set("Utility", "matchWidth", "target")
	CMP:Set("PRD", "style", "square")
	H.flush()
	local function px(v, f) return v * f:GetEffectiveScale() / H.pixelFactor end
	local l, _, w = CMP.Anchors:VisibleRect(prd)
	local prdL, prdR = px(l, H.UIParent), px(l + w, H.UIParent)
	T.near(prdL, math.floor(prdL + 0.5), 0.01, "PRD left on a whole pixel")
	T.near(prdR, math.floor(prdR + 0.5), 0.01, "PRD right on a whole pixel")
	for _, key in ipairs({ "Essential", "Utility" }) do
		local a, b = math.huge, -math.huge
		for _, it in ipairs(H.viewers[key].items) do
			a, b = math.min(a, px(it:GetLeft(), it)), math.max(b, px(it:GetRight(), it))
		end
		T.near(a, prdL, 0.01, key .. " left = PRD left")
		T.near(b, prdR, 0.01, key .. " right = PRD right")
	end
	-- detached again: Blizzard's exact width and spot come back
	CMP:Set("Essential", "attachTo", "none")
	CMP:Set("Essential", "matchWidth", "off")
	H.flush()
	T.near(prd:GetWidth(), 314, 0.001, "Blizzard's width")
	local _, _, _, x = prd:GetPoint(1)
	T.near(x, 0.37 / 1.1, 0.001, "Edit Mode's spot")
end)
