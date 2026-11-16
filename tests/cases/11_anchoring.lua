-- Drop zones, Shift to move without attaching, other Edit Mode frames as targets, the
-- attachment gap default, and Edit Mode's Revert (Anchors.lua, Overlay.lua, EditSession.lua).
local T = ...

local function setup(H)
	for _, key in ipairs({ "Essential", "Utility" }) do
		H.viewers[key].systemInfo.isInDefaultPosition = false
		for i = 1, 3 do
			H.spells[100 * i] = { name = "S" .. i }
			H.viewers[key]:AddItem({ spellID = 100 * i })
		end
	end
	H.flush()
end

-- visible rect (UI units)
local function rect(H, key)
	return H.CMP.Anchors:VisibleRect(H.viewers[key])
end

-- drag Utility so its top sits `gap` below Essential, left edges `dx` apart
local function dropBelowEssential(H, gap, dx, during)
	local el, eb = rect(H, "Essential")
	H.drag(H.viewers.Utility, el + (dx or 0), eb - (gap or 0), during)
end

T.test("anchoring: dropping next to a frame attaches there, touching", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	dropBelowEssential(H, 10, 0) -- 10 units below, left edges lined up
	T.eq(CMP:Get("Utility", "attachTo"), "Essential")
	T.eq(CMP:Get("Utility", "attachSide"), "BELOW")
	T.eq(CMP:Get("Utility", "attachAlign"), "START", "left edges were closest")
	T.eq(CMP:Get("Utility", "attachGap"), 0, "touching")
	local _, eb = rect(H, "Essential")
	local ul, ub, uw, uh = rect(H, "Utility")
	T.near(ub + uh, eb, 0.6, "Utility's top on Essential's bottom")
end)

T.test("anchoring: while dragging, the overlay previews where it will attach", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	local text
	dropBelowEssential(H, 8, 0, function()
		T.truthy(CMP.Anchors.dragging, "drag tracked")
		CMP.Overlay:Draw()
		text = CMP.Overlay.preview
	end)
	T.truthy(text and text:find("Attach below Essential Cooldowns", 1, true), tostring(text))
	T.falsy(CMP.Anchors.dragging, "drag over")
end)

T.test("anchoring: holding Shift moves the frame without attaching (and detaches it)", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	dropBelowEssential(H, 5)
	T.eq(CMP:Get("Utility", "attachTo"), "Essential")
	H.shiftDown = true
	local preview
	dropBelowEssential(H, 5, 0, function()
		CMP.Overlay:Draw()
		preview = CMP.Overlay.preview
	end)
	H.shiftDown = false
	T.eq(CMP:Get("Utility", "attachTo"), "none", "detached, not re-attached")
	T.truthy(preview and preview:find("Shift", 1, true), "the preview says so")
end)

T.test("anchoring: dragging into empty space detaches, with a short note", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	dropBelowEssential(H, 0)
	H.drag(H.viewers.Utility, 50, 900)
	T.eq(CMP:Get("Utility", "attachTo"), "none")
	T.eq(CMP.Overlay.flash and CMP.Overlay.flash.text, "Detached")
end)

T.test("anchoring: other Edit Mode frames are targets (dropdown, drop zones, export)", function(H, T)
	local CMP = H.CMP
	setup(H)
	local key = "frame:MainActionBar"
	local found = false
	for _, info in ipairs(CMP.Anchors:ExternalTargets()) do
		found = found or info.key == key
	end
	T.truthy(found, "the action bar is offered")
	T.eq(CMP:GetName(key), "Action Bar 1")
	CMP:Set("Essential", "attachTo", key)
	CMP:Set("Essential", "attachSide", "ABOVE")
	local _, ab, _, ah = CMP.Anchors:VisibleRect(H.actionBar)
	local _, eb = rect(H, "Essential")
	T.near(eb, ab + ah, 0.6, "sits on top of the action bar")
	-- drop zone on it too
	H.enterEditMode()
	local al, _, aw = CMP.Anchors:VisibleRect(H.actionBar)
	local _, _, uw, uh = rect(H, "Utility")
	H.drag(H.viewers.Utility, al + aw + 4, ab + ah)
	T.eq(CMP:Get("Utility", "attachTo"), key, "dropped right of the action bar")
	T.eq(CMP:Get("Utility", "attachSide"), "RIGHT")
	-- export / import keep it
	local ok = CMP.Share:Import(CMP.Share:Export(), "Copy", true)
	T.truthy(ok)
	T.eq(CMP.db.profiles.Copy.frames.Essential.attachTo, key)
end)

T.test("anchoring: gap is 0 by default; older attachments keep their gap of 2", function(H, T)
	local CMP = H.CMP
	T.eq(CMP.defaults.attachGap, 0)
	local frames = { Utility = { attachTo = "Essential" }, BuffIcon = { attachTo = "none" } }
	CMP.MigrateFrames(frames, true)
	T.eq(frames.Utility.attachGap, 2, "0.1/0.2 default kept")
	T.eq(frames.BuffIcon.attachGap, nil, "not attached: untouched")
	-- exports write the gap, so an import can tell old from new
	CMP:Set("Utility", "attachTo", "Essential")
	local data = CMP.Share:ExportFrames()
	T.eq(data.Utility.attachGap, 0)
	T.eq(CMP.db.version, 2, "saved data marked as migrated")
end)

T.test("anchoring: Edit Mode's Revert All Changes undoes an attachment made by dragging", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	T.eq(CMP:Get("Utility", "attachTo"), "none")
	dropBelowEssential(H, 0)
	T.eq(CMP:Get("Utility", "attachTo"), "Essential")
	H.fireScript(H.editModeManager.RevertAllChangesButton, "OnClick", "LeftButton", false)
	H.flush()
	T.eq(CMP:Get("Utility", "attachTo"), "none", "reverted")
end)

T.test("anchoring: a frame dropped on top of another (overlapping) doesn't attach", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	local el, eb, ew, eh = rect(H, "Essential")
	-- Utility's top well inside Essential (overlapping by more than a few units)
	H.drag(H.viewers.Utility, el, eb + eh / 2 + 15)
	T.eq(CMP:Get("Utility", "attachTo"), "none")
end)

T.test("anchoring: re-dropping on the same side keeps the gap, and the preview shows it", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	dropBelowEssential(H, 2, 0)
	CMP:Set("Utility", "attachGap", 12)
	local _, eb = rect(H, "Essential")
	local previewTop
	dropBelowEssential(H, 14, 0, function()
		local candidate = CMP.Anchors:DropCandidate(CMP.byKey.Utility)
		local _, bottom, _, height = CMP.Anchors:CandidateRect(CMP.byKey.Utility, candidate)
		previewTop = bottom + height
	end)
	T.eq(CMP:Get("Utility", "attachGap"), 12, "gap kept")
	T.near(previewTop, eb - 12, 0.6, "the preview showed the same gap")
end)

T.test("anchoring: can't attach to a frame that is anchored to this one", function(H, T)
	local CMP = H.CMP
	setup(H)
	-- the action bar is anchored to Essential
	H.raw.ClearAllPoints(H.actionBar)
	H.raw.SetPoint(H.actionBar, "TOP", H.viewers.Essential, "BOTTOM", 0, -100)
	T.falsy(CMP.Anchors:CanAttach(CMP.byKey.Essential, CMP.Anchors:External("frame:MainActionBar")))
	T.truthy(CMP.Anchors:CanAttach(CMP.byKey.Utility, CMP.Anchors:External("frame:MainActionBar")))
end)

T.test("anchoring: Match Width follows another Edit Mode frame when it resizes", function(H, T)
	local CMP = H.CMP
	setup(H)
	CMP:Set("PRD", "attachTo", "frame:MainActionBar")
	CMP:Set("PRD", "matchWidth", "target")
	H.flush()
	local _, _, w1 = CMP.Anchors:VisibleRect(H.viewers.PRD)
	T.near(w1, 500, 1, "as wide as the bar")
	H.actionBar:SetWidth(700)
	H.fireScript(H.actionBar, "OnSizeChanged", 700, 40)
	H.advance(0.1)
	H.flush()
	local _, _, w2 = CMP.Anchors:VisibleRect(H.viewers.PRD)
	T.near(w2, 700, 1, "followed the resize")
end)

T.test("anchoring: leaving Edit Mode mid-drag clears the drag", function(H, T)
	local CMP = H.CMP
	setup(H)
	H.enterEditMode()
	H.viewers.Utility:OnDragStart()
	T.truthy(CMP.Anchors.dragging)
	H.exitEditMode()
	T.falsy(CMP.Anchors.dragging)
end)
