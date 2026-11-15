local _, ns = ...
local CMP = ns.CMP
local raw = CMP.raw

-- Positions and widths.
--
-- attachTo = "none"  : Edit Mode places the frame. If Grow From isn't Default, we keep the
--                      matching point fixed (left edge, center or right edge), so the frame
--                      grows away from it when cooldowns are added. Dragging moves that point.
-- attachTo = <key>   : attached to another cooldown viewer or the Personal Resource Display,
--                      on a side, lined up by centers or an edge, with a gap. The attachment
--                      survives the target hiding (Edit Mode's own snaps break then).
--
-- Snapping a frame to another one in Edit Mode turns into an attachment automatically, and
-- arrow-key nudges change the attachment's gap/offset (or the fixed point), so the normal
-- Edit Mode workflow keeps working.

local Anchors = {}
CMP.Anchors = Anchors

local applied = {} -- key -> true while we control the position
local lastContentWidth = {}

local function PointsFor(side, align)
	if side == "BELOW" or side == "ABOVE" then
		local h = (align == "START" and "LEFT") or (align == "END" and "RIGHT") or ""
		if side == "BELOW" then
			return "TOP" .. h, "BOTTOM" .. h
		end
		return "BOTTOM" .. h, "TOP" .. h
	end
	local v = (align == "START" and "TOP") or (align == "END" and "BOTTOM") or ""
	if side == "RIGHT" then
		return (v ~= "" and v .. "LEFT" or "LEFT"), (v ~= "" and v .. "RIGHT" or "RIGHT")
	end
	return (v ~= "" and v .. "RIGHT" or "RIGHT"), (v ~= "" and v .. "LEFT" or "LEFT")
end

local function SplitPoint(point)
	local v = point:match("^TOP") or point:match("^BOTTOM") or ""
	local h = point:match("LEFT$") or point:match("RIGHT$") or ""
	return v, h
end

local H_ALIGN = { [""] = "CENTER", LEFT = "START", RIGHT = "END" }
local V_ALIGN = { [""] = "CENTER", TOP = "START", BOTTOM = "END" }

-- Turns an Edit Mode snap (point -> relativePoint) into side + align.
local function DeriveAttachment(point, relativePoint)
	local pv, ph = SplitPoint(point)
	local rv, rh = SplitPoint(relativePoint)
	if pv == "TOP" and rv == "BOTTOM" and ph == rh then
		return "BELOW", H_ALIGN[ph]
	elseif pv == "BOTTOM" and rv == "TOP" and ph == rh then
		return "ABOVE", H_ALIGN[ph]
	elseif ph == "LEFT" and rh == "RIGHT" and pv == rv then
		return "RIGHT", V_ALIGN[pv]
	elseif ph == "RIGHT" and rh == "LEFT" and pv == rv then
		return "LEFT", V_ALIGN[pv]
	end
	return nil
end

-- What you see of a frame can be smaller than the frame:
--  * Personal Resource Display: Blizzard doesn't shrink the frame when a bar is hidden
--    (e.g. Hide Health Bar), so it keeps empty space. We use the bars that are shown.
--  * Cooldown rows laid out by Blizzard: the transparent edge of the round icon art.
-- Returns insets (UI units) from the frame's edges to the visible part: top, bottom,
-- left, right. Gaps and edges are measured on the visible part, so gap 0 touches.
local PRD_PARTS = { "HealthBarsContainer", "PowerBar", "AlternatePowerBar", "ClassFrameContainer" }

function Anchors:VisibleInsets(info)
	if not info or not info.frame then
		return 0, 0, 0, 0
	end
	if info.kind == "prd" then
		local frame = info.frame
		local l, b, w, h = CMP.RectUI(frame)
		if not l then
			return 0, 0, 0, 0
		end
		local top, bottom
		for _, name in ipairs(PRD_PARTS) do
			local part = frame[name]
			local shown = part and part.IsShown and part:IsShown()
			-- The class resource container can stay shown while the class frame inside it
			-- hides itself (e.g. Arcane Charges outside Arcane); count what's inside.
			if name == "ClassFrameContainer" and not CMP.IsSecret(shown) and shown then
				local inner = frame.classFrame
				shown = inner ~= nil and inner.IsShown ~= nil and inner:IsShown()
			end
			if not CMP.IsSecret(shown) and shown then
				local pl, pb, pw, ph = CMP.RectUI(part)
				if pl and ph and ph > 0 then
					top = math.max(top or -math.huge, pb + ph)
					bottom = math.min(bottom or math.huge, pb)
				end
			end
		end
		if not top then
			return 0, 0, 0, 0
		end
		return (b + h) - top, bottom - b, 0, 0
	end
	local inset = CMP.Layout:VisibleInset(info)
	return inset, inset, inset, inset
end

-- A point ("TOP", "BOTTOMLEFT", ...) on the visible part, UI units.
function Anchors:VisiblePoint(frame, point)
	local l, b, w, h = self:VisibleRect(frame)
	if not l then
		return nil
	end
	local x = point:find("LEFT", 1, true) and l or (point:find("RIGHT", 1, true) and l + w or l + w / 2)
	local y = point:find("TOP", 1, true) and b + h or (point:find("BOTTOM", 1, true) and b or b + h / 2)
	return x, y
end

-- Visible rect (UI units): left, bottom, width, height.
function Anchors:VisibleRect(frame)
	local l, b, w, h = CMP.RectUI(frame)
	if not l then
		return nil
	end
	local top, bottom, left, right = self:VisibleInsets(CMP.byFrame[frame])
	return l + left, b + bottom, w - left - right, h - top - bottom
end

-- Shared borders between attached frames: when both frames draw a border of their own
-- (square icons or square bars) and share borders, they overlap by the thinner border, so
-- the seam shows one border line instead of two. UI units.
local function BorderPixels(info)
	if not info or not CMP:Get(info.key, "sharedBorders") then
		return 0
	end
	if info.kind == "prd" then
		return CMP:Get(info.key, "style") == "square" and CMP:Get(info.key, "borderSize") or 0
	end
	return CMP.Layout:SharedBorderPixels(info)
end

function Anchors:BorderOverlap(info, target)
	local overlap = math.min(BorderPixels(info), BorderPixels(target))
	if overlap <= 0 then
		return 0
	end
	return overlap * CMP.PixelUnit(UIParent)
end

-- Gap and offset between two frames for a side/align, UI units.
local function Measure(frame, target, side, align)
	local fl, fb, fw, fh = Anchors:VisibleRect(frame)
	local tl, tb, tw, th = Anchors:VisibleRect(target)
	if not fl or not tl then
		return nil
	end
	local fr, ft, tr, tt = fl + fw, fb + fh, tl + tw, tb + th
	local gap, offset
	if side == "BELOW" or side == "ABOVE" then
		gap = side == "BELOW" and (tb - ft) or (fb - tt)
		if align == "START" then
			offset = fl - tl
		elseif align == "END" then
			offset = fr - tr
		else
			offset = (fl + fw / 2) - (tl + tw / 2)
		end
	else
		gap = side == "RIGHT" and (fl - tr) or (tl - fr)
		if align == "START" then
			offset = ft - tt
		elseif align == "END" then
			offset = fb - tb
		else
			offset = (fb + fh / 2) - (tb + th / 2)
		end
	end
	gap = gap + Anchors:BorderOverlap(CMP.byFrame[frame], CMP.byFrame[target])
	return math.floor(gap + 0.5), math.floor(offset + 0.5)
end

-- Would attaching `key` to `targetKey` create a loop through our attachments?
function Anchors:WouldCycle(key, targetKey)
	local seen = {}
	local current = targetKey
	while current and CMP.byKey[current] do
		if current == key or seen[current] then
			return true
		end
		seen[current] = true
		local nextKey = CMP:Get(current, "attachTo")
		current = CMP.byKey[nextKey] and nextKey or nil
	end
	return false
end

-- Is `frame` (directly or through its anchors) positioned relative to `other`?
local function DependsOn(frame, other, depth)
	depth = depth or 0
	if depth > 20 then
		return true
	end
	for i = 1, frame:GetNumPoints() do
		local _, relativeTo = frame:GetPoint(i)
		if type(relativeTo) == "string" then
			relativeTo = _G[relativeTo]
		end
		if relativeTo == other then
			return true
		end
		if relativeTo and relativeTo ~= UIParent and relativeTo.GetNumPoints and DependsOn(relativeTo, other, depth + 1) then
			return true
		end
	end
	return false
end

function Anchors:TargetInfo(info)
	local target = CMP.byKey[CMP:Get(info.key, "attachTo")]
	if target and target ~= info and target.frame then
		return target
	end
	return nil
end

-- Grow From on a frame that isn't attached: the point that stays fixed, so the frame grows
-- away from it. nil = Blizzard default (Edit Mode's own anchor decides).
function Anchors:PinPoint(info, align)
	if info.kind == "prd" or not info.frame then
		return nil
	end
	align = align or CMP:Get(info.key, "align")
	if align == "native" then
		return nil
	end
	if info.frame.isHorizontal ~= false then
		return (align == "start" and "TOPLEFT") or (align == "end" and "TOPRIGHT") or "TOP"
	end
	return (align == "start" and "TOPLEFT") or (align == "end" and "BOTTOMLEFT") or "LEFT"
end

-- Stores where that point is right now (UI units).
function Anchors:RecordPin(info, align)
	local point = self:PinPoint(info, align)
	if not point then
		return nil
	end
	local x, y = CMP.PointUI(info.frame, point)
	if not x then
		return nil
	end
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	CMP:SetQuiet(info.key, "pinX", x)
	CMP:SetQuiet(info.key, "pinY", y)
	CMP:SetQuiet(info.key, "pinPoint", point)
	return x, y
end

-- Do we position this frame (attached, or pinned by Grow From)?
function Anchors:IsControlled(info)
	return self:TargetInfo(info) ~= nil or self:PinPoint(info) ~= nil
end

-- Puts the frame back where the Edit Mode layout says, without calling Blizzard Lua.
function Anchors:RestoreEditMode(info)
	local frame = info.frame
	local systemInfo = frame.systemInfo
	-- Managed defaults are placed by Blizzard's container; every other frame (default or
	-- moved) has its anchor in systemInfo, like Blizzard's ApplySystemAnchor uses.
	if not systemInfo or not systemInfo.anchorInfo or CMP:IsManagedDefault(frame) then
		return
	end
	if not CMP:CanTouch(frame) then
		return
	end
	local scale = frame:GetScale()
	local a, b = systemInfo.anchorInfo, systemInfo.anchorInfo2
	raw.ClearAllPoints(frame)
	raw.SetPoint(frame, a.point, a.relativeTo, a.relativePoint, a.offsetX / scale, a.offsetY / scale)
	if b then
		raw.SetPoint(frame, b.point, b.relativeTo, b.relativePoint, b.offsetX / scale, b.offsetY / scale)
	end
end

function Anchors:Apply(info)
	local frame = info.frame
	if not frame or not CMP.ready then
		return
	end
	local key = info.key
	local mode = CMP:Get(key, "attachTo")

	local attached = CMP.byKey[mode] ~= nil and mode ~= key
	local pinPoint = not attached and self:PinPoint(info)
	if (not attached and not pinPoint) or CMP:IsManagedDefault(frame) then
		if applied[key] then
			applied[key] = nil
			self:RestoreEditMode(info)
		end
		return
	end
	if not CMP:CanTouch(frame) then
		return
	end

	-- UI units -> the frame's own units (the Personal Resource Display has its own scale)
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()

	if pinPoint then
		local x, y = CMP:Get(key, "pinX"), CMP:Get(key, "pinY")
		if not x or not y or CMP:Get(key, "pinPoint") ~= pinPoint then
			x, y = self:RecordPin(info)
			if not x then
				return
			end
		end
		raw.ClearAllPoints(frame)
		raw.SetPoint(frame, pinPoint, UIParent, "BOTTOMLEFT", CMP.Snap(x * k, frame), CMP.Snap(y * k, frame))
		applied[key] = true
		return
	end

	local target = self:TargetInfo(info)
	if not target or self:WouldCycle(key, target.key) or DependsOn(target.frame, frame) then
		return
	end
	local side = CMP:Get(key, "attachSide")
	local point, relativePoint = PointsFor(side, CMP:Get(key, "attachAlign"))
	local gap, offset = CMP:Get(key, "attachGap"), CMP:Get(key, "attachOffset")
	-- "Take its place": while the target is hidden, sit where the target starts instead of
	-- next to it, so a stack closes up. Never in Edit Mode, where everything is shown.
	local targetShown = target.frame:IsShown()
	if CMP:Get(key, "whenHidden") == "fill" and not CMP.IsSecret(targetShown) and not targetShown then
		relativePoint = point
		gap = 0
	end
	local filling = relativePoint == point
	if not filling then
		gap = gap - self:BorderOverlap(info, target)
	end
	local x, y
	if side == "BELOW" then
		x, y = offset, -gap
	elseif side == "ABOVE" then
		x, y = offset, gap
	elseif side == "RIGHT" then
		x, y = gap, offset
	else
		x, y = -gap, offset
	end
	-- Measure on the visible parts of both frames (see VisibleInsets).
	local tTop, tBottom, tLeft, tRight = self:VisibleInsets(target)
	local fTop, fBottom, fLeft, fRight = self:VisibleInsets(info)
	if side == "BELOW" then
		y = y + (filling and -tTop or tBottom) + fTop
	elseif side == "ABOVE" then
		y = y - (filling and -tBottom or tTop) - fBottom
	elseif side == "RIGHT" then
		x = x - (filling and -tLeft or tRight) - fLeft
	else
		x = x + (filling and -tRight or tLeft) + fRight
	end
	-- Lining up along the edge: visible edges (or visible centers) line up.
	local align = CMP:Get(key, "attachAlign")
	if side == "BELOW" or side == "ABOVE" then
		if align == "START" then
			x = x + tLeft - fLeft
		elseif align == "END" then
			x = x - tRight + fRight
		else
			x = x + (tLeft - tRight) / 2 - (fLeft - fRight) / 2
		end
	else
		if align == "START" then
			y = y - tTop + fTop
		elseif align == "END" then
			y = y + tBottom - fBottom
		else
			y = y + (tBottom - tTop) / 2 - (fBottom - fTop) / 2
		end
	end
	raw.ClearAllPoints(frame)
	raw.SetPoint(frame, point, target.frame, relativePoint, CMP.Snap(x * k, frame), CMP.Snap(y * k, frame))
	applied[key] = true
end

-- A frame was shown or hidden: frames attached to it with "Take its place" move.
function Anchors:OnVisibilityChanged(info)
	if not CMP.ready then
		return
	end
	for _, other in ipairs(CMP.frameInfos) do
		if other.frame and CMP:Get(other.key, "attachTo") == info.key and CMP:Get(other.key, "whenHidden") == "fill" then
			CMP.Safe(self.Apply, self, other)
		end
	end
end

function Anchors:ApplyAll()
	for _, info in ipairs(CMP.frameInfos) do
		if info.frame then
			CMP.Safe(self.Apply, self, info)
		end
	end
	self:UpdateWidths()
end

-- Edit Mode drag and arrow keys.
function Anchors:OnUserMoved(info, how, keyName)
	if not CMP.ready then
		return
	end
	local key = info.key
	local mode = CMP:Get(key, "attachTo")

	if how == "drag" then
		local point, relativeTo, relativePoint = info.frame:GetPoint(1)
		if type(relativeTo) == "string" then
			relativeTo = _G[relativeTo]
		end
		local target = relativeTo and CMP.byFrame[relativeTo]
		if target and target ~= info and not self:WouldCycle(key, target.key) then
			local side, align = DeriveAttachment(point, relativePoint)
			if side then
				local gap, offset = Measure(info.frame, target.frame, side, align)
				if gap then
					CMP:SetQuiet(key, "attachTo", target.key)
					CMP:SetQuiet(key, "attachSide", side)
					CMP:SetQuiet(key, "attachAlign", align)
					CMP:SetQuiet(key, "attachGap", gap)
					CMP:SetQuiet(key, "attachOffset", offset)
					self:ApplyAll()
					self:UpdateWidths(true) -- the new target may change the matched width
					CMP:RefreshDialog(info)
					CMP.Overlay:Refresh()
					return
				end
			end
		end
		if mode ~= "none" then
			-- Dragged away from its target: detach.
			CMP:SetQuiet(key, "attachTo", "none")
			applied[key] = nil
		end
		if self:PinPoint(info) then
			-- Keep growing from the new spot.
			self:RecordPin(info)
			self:Apply(info)
		end
		self:UpdateWidths(true)
		CMP:RefreshDialog(info)
		CMP.Overlay:Refresh()
		return
	end

	-- nudge
	local step = IsShiftKeyDown() and 10 or 1
	local dx = (keyName == "LEFT" and -step) or (keyName == "RIGHT" and step) or 0
	local dy = (keyName == "DOWN" and -step) or (keyName == "UP" and step) or 0
	if dx == 0 and dy == 0 then
		return
	end
	if self:TargetInfo(info) then
		local side = CMP:Get(key, "attachSide")
		local gap, offset = CMP:Get(key, "attachGap"), CMP:Get(key, "attachOffset")
		if side == "BELOW" then
			offset, gap = offset + dx, gap - dy
		elseif side == "ABOVE" then
			offset, gap = offset + dx, gap + dy
		elseif side == "RIGHT" then
			gap, offset = gap + dx, offset + dy
		else
			gap, offset = gap - dx, offset + dy
		end
		CMP:SetQuiet(key, "attachGap", gap)
		CMP:SetQuiet(key, "attachOffset", offset)
	elseif self:PinPoint(info) then
		if not CMP:Get(key, "pinX") then
			self:RecordPin(info)
		end
		CMP:SetQuiet(key, "pinX", (CMP:Get(key, "pinX") or 0) + dx)
		CMP:SetQuiet(key, "pinY", (CMP:Get(key, "pinY") or 0) + dy)
	else
		return
	end
	self:Apply(info)
	CMP:RefreshDialog(info)
	CMP.Overlay:Refresh()
end

function Anchors:Hook(info)
	local frame = info.frame
	-- Blizzard re-applies saved positions on layout load and layout switches.
	CMP.HookMethod(frame, "ApplySystemAnchor", function()
		CMP.Safe(self.ApplyAll, self)
	end)
	-- Edit Mode breaks snaps when the target hides and re-anchors to the screen corner.
	CMP.HookMethod(frame, "BreakFrameSnap", function()
		if self:IsControlled(info) then
			CMP.Safe(self.Apply, self, info)
		end
	end)
	frame:HookScript("OnShow", function()
		CMP.Safe(self.OnVisibilityChanged, self, info)
	end)
	frame:HookScript("OnHide", function()
		CMP.Safe(self.OnVisibilityChanged, self, info)
	end)
	-- Edit Mode's "Reset To Default Position": drop our position override too, otherwise the
	-- attachment or Grow From pin would put the frame right back.
	CMP.HookMethod(frame, "ResetToDefaultPosition", function()
		CMP.Safe(self.OnResetPosition, self, info)
		CMP.Session:Touch(info.key)
	end)
	CMP.HookMethod(frame, "OnDragStop", function()
		CMP.Safe(self.OnUserMoved, self, info, "drag")
		CMP.Session:Touch(info.key)
	end)
	CMP.HookMethod(frame, "ProcessMovementKey", function(_, keyName)
		CMP.Safe(self.OnUserMoved, self, info, "nudge", keyName)
		CMP.Session:Touch(info.key)
	end)
	if info.kind == "prd" then
		-- The visible bars change: re-attach on the new visible edges.
		local function Reapply()
			CMP.Safe(self.ApplyAll, self)
		end
		for _, method in ipairs({ "SetHideHealth", "SetHidePower", "SetHideAltPower", "SetHideClassInfo",
			"SetBarPadding", "SetHealthBarHeight", "SetPowerBarHeight", "UpdateFrameHeight" }) do
			CMP.HookMethod(frame, method, Reapply)
		end
		for _, name in ipairs(PRD_PARTS) do
			local part = frame[name]
			if part and part.HookScript then
				part:HookScript("OnShow", Reapply)
				part:HookScript("OnHide", Reapply)
			end
		end
		-- The class frame is created later (SetupClassBar); hook it once it exists.
		local hookedClassFrame
		local function HookClassFrame()
			local inner = frame.classFrame
			if inner and inner ~= hookedClassFrame and inner.HookScript then
				hookedClassFrame = inner
				inner:HookScript("OnShow", Reapply)
				inner:HookScript("OnHide", Reapply)
			end
		end
		HookClassFrame()
		for _, method in ipairs({ "SetupClass", "SetupClassBar" }) do
			CMP.HookMethod(frame, method, function()
				HookClassFrame()
				Reapply()
			end)
		end
		CMP.HookMethod(frame, "UpdateBarWidth", function()
			CMP.Safe(self.UpdateWidths, self, true)
		end)
		CMP.HookMethod(frame, "UpdateSystemSetting", function()
			CMP.Safe(self.UpdateWidths, self, true)
		end)
	end
end

---------------------------------------------------------------------------
-- Width matching
---------------------------------------------------------------------------

-- Frames connected to `key` through attachments (either direction).
function Anchors:GroupOf(key)
	local group, queue = { [key] = true }, { key }
	while #queue > 0 do
		local current = table.remove(queue)
		for _, info in ipairs(CMP.frameInfos) do
			local other = info.key
			local target = CMP:Get(other, "attachTo")
			local linked = (other == current and CMP.byKey[target] and target)
				or (target == current and other)
			if linked and not group[linked] then
				group[linked] = true
				table.insert(queue, linked)
			end
		end
	end
	return group
end

function Anchors:ContentWidth(key)
	local content = CMP.Layout.content[key]
	if content then
		return content.width
	end
	local info = CMP.byKey[key]
	if not info or not info.frame then
		return 0
	end
	local _, _, width = CMP.RectUI(info.frame)
	return width or 0
end

-- Width matching follows chains: Utility can match Essential while Essential matches the
-- Personal Resource Display. Widths are resolved from the frames that keep their own width
-- ("natural" frames) along the chain, never from a matched frame's current size, so
-- frames can't keep resizing each other. A chain that loops back on itself is ignored.
local function IsNatural(key)
	return CMP:Get(key, "matchWidth") == "off"
end

local function IsRow(key)
	local info = CMP.byKey[key]
	return info ~= nil and info.kind == "icons" and info.frame ~= nil
end

-- Width the frame `key` gets (UI units). Returns nil, true when its chain loops.
function Anchors:ResolvedWidth(key, visiting)
	if visiting[key] then
		return nil, true
	end
	if IsNatural(key) then
		return self:ContentWidth(key)
	end
	visiting[key] = true
	local reference, loops = self:ReferenceFor(key, visiting)
	visiting[key] = nil
	if loops then
		return nil, true
	end
	if not reference then
		return self:ContentWidth(key) -- nothing to match: its own width
	end
	return reference + CMP:Get(key, "widthAdjust")
end

-- Width `key` should match before its adjustment, or nil. Second value: the chain loops.
function Anchors:ReferenceFor(key, visiting)
	local mode = CMP:Get(key, "matchWidth")
	if mode == "target" then
		local target = self:TargetInfo(CMP.byKey[key])
		if not target then
			return nil
		end
		return self:ResolvedWidth(target.key, visiting)
	elseif mode == "widest" then
		-- Rows whose chain comes back here are skipped. If every candidate loops, that's a
		-- loop for this frame too: falling back to a matched row's current width would
		-- let the rows grow each other step by step.
		local function Widest(candidates)
			local best, looped
			for candidate in pairs(candidates) do
				if candidate ~= key and IsRow(candidate) then
					local width, loops = self:ResolvedWidth(candidate, visiting)
					looped = looped or loops
					if width and width > (best or 0) then
						best = width
					end
				end
			end
			return best, looped
		end
		local best, looped = Widest(self:GroupOf(key))
		if not best then
			local all = {}
			for _, other in ipairs(CMP.frameInfos) do
				all[other.key] = true
			end
			local anyLooped
			best, anyLooped = Widest(all)
			looped = looped or anyLooped
		end
		if not best and looped then
			return nil, true
		end
		return best
	end
	return nil
end

-- Width (UI units) a frame should match, or nil when matching is off or loops.
function Anchors:ReferenceWidth(info)
	if IsNatural(info.key) then
		return nil
	end
	local reference, loops = self:ReferenceFor(info.key, { [info.key] = true })
	if loops then
		return nil
	end
	return reference
end

-- True when Match Width on `key` can't work because the chain comes back to it.
function Anchors:MatchLoops(key)
	if IsNatural(key) then
		return false
	end
	local _, loops = self:ReferenceFor(key, { [key] = true })
	return loops == true
end

-- Match Width for icon rows (UI units), or nil.
function Anchors:FitWidth(info)
	local reference = self:ReferenceWidth(info)
	if not reference then
		return nil
	end
	return reference + CMP:Get(info.key, "widthAdjust")
end

local prdMatched = false

function Anchors:ApplyPRDWidth(info)
	local frame = info.frame
	local reference = self:ReferenceWidth(info)
	local width
	if reference then
		width = (reference + CMP:Get(info.key, "widthAdjust")) * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
		prdMatched = true
	elseif prdMatched then
		-- Same formula as Blizzard's UpdateBarWidth (Edit Mode's Bar Width setting).
		width = (frame.defaultBarWidth or 200) * (frame.barWidthPercent or 100) / 100
		prdMatched = false
	else
		return
	end
	if not CMP:CanTouch(frame) then
		return
	end
	width = math.max(10, CMP.Snap(width, frame))
	if math.abs(frame:GetWidth() - width) < 0.01 then
		return
	end
	raw.SetWidth(frame, width)
	for _, part in ipairs({ frame.HealthBarsContainer, frame.PowerBar, frame.AlternatePowerBar, frame.ClassFrameContainer }) do
		raw.SetWidth(part, width)
	end
end

function Anchors:BarItemWidth(info)
	local viewer = info.frame
	local reference = self:ReferenceWidth(info)
	if reference then
		return (reference + CMP:Get(info.key, "widthAdjust")) * UIParent:GetEffectiveScale()
	end
	return nil, (viewer.baseBarWidth or 220) * (viewer.barWidthScale or 1)
end

-- Returns true when the width changed.
function Anchors:ApplyBarItemWidth(info, item)
	local uiWidth, nativeWidth = self:BarItemWidth(info)
	local width = nativeWidth
	if uiWidth then
		width = CMP.Snap(uiWidth / item:GetEffectiveScale(), item)
	end
	local current = item:GetWidth()
	if CMP.IsSecret(current) then -- hidden in combat: leave it for after
		return false
	end
	if width and math.abs(current - width) >= 0.01 and CMP:CanTouch(item) then
		raw.SetWidth(item, width)
		return true
	end
	return false
end

function Anchors:ApplyBarWidths(info)
	local changed = false
	for item in pairs(CMP.Layout:Items(info.frame)) do
		if item.layoutIndex and self:ApplyBarItemWidth(info, item) then
			changed = true
		end
	end
	if changed then
		CMP.Layout:Run(info)
	end
end

-- Re-apply every matched width. Each one resolves from natural widths on its own, so the
-- order doesn't matter.
function Anchors:UpdateWidths(includeRows)
	if not CMP.ready then
		return
	end
	if includeRows and (self.propagating or 0) <= 2 then
		self.propagating = (self.propagating or 0) + 1
		for _, other in ipairs(CMP.frameInfos) do
			if other.kind == "icons" and other.frame and not IsNatural(other.key) then
				CMP.Layout:Run(other)
			end
		end
		self.propagating = self.propagating - 1
	end
	local prd = CMP.byKey.PRD
	if prd.frame then
		CMP.Safe(self.ApplyPRDWidth, self, prd)
	end
	local bars = CMP.byKey.BuffBar
	if bars.frame then
		CMP.Safe(self.ApplyBarWidths, self, bars)
	end
end

function Anchors:OnContentChanged(info)
	if info.kind ~= "icons" then
		return
	end
	local width = self:ContentWidth(info.key)
	if lastContentWidth[info.key] and math.abs(lastContentWidth[info.key] - width) < 0.01 then
		return
	end
	lastContentWidth[info.key] = width
	-- Only natural widths feed the chains (see ResolvedWidth), so a matched frame
	-- changing size never needs to tell anyone.
	if not IsNatural(info.key) then
		return
	end
	self:UpdateWidths(true)
end

function Anchors:OnResetPosition(info)
	local key = info.key
	CMP:SetQuiet(key, "attachTo", "none")
	CMP:SetQuiet(key, "pinX", false)
	CMP:SetQuiet(key, "pinY", false)
	CMP:SetQuiet(key, "pinPoint", false)
	applied[key] = nil
	self:RestoreEditMode(info)
	-- With Grow From set, the new default spot becomes the fixed point.
	self:ApplyAll()
	CMP:Update()
	CMP:RefreshDialog(info)
end
