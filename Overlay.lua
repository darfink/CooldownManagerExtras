local _, ns = ...
local CMP = ns.CMP

-- Edit Mode visuals. Drawn only while Edit Mode is open, on our own frame (never on
-- Blizzard's), with the mouse disabled so it never gets in the way. Pictures, not text,
-- built to read on top of Edit Mode's blue tint:
--  * Growth: a small dark badge just inside the edge of each cooldown viewer, at the point
--    that stays put (left end, middle or right end), with white arrows pointing where new
--    icons appear:  [|>>]  [<|>]  [<<|]. A second badge at the bottom shows where extra
--    rows go. Blue outline = set by Cooldown Manager Extras; Blizzard's default is shown
--    (grey) only on the selected frame.
--  * Attachment: white = attached by Cooldown Manager Extras, gold = a plain Edit Mode snap.
--    A seam marks the shared edge and a dot the point where the frames meet (center,
--    left or right edge = what lines up). A line connects the two when there's a gap.
-- Lines have a dark outline so they read on any background.

local Overlay = {}
CMP.Overlay = Overlay

local COLOR_PLUS = { 0.31, 0.64, 1.00 } -- our accent (badge outline, labels)
local COLOR_ATTACH = { 1.00, 1.00, 1.00 } -- our attachments: white reads on the blue tint
local COLOR_NATIVE = { 1.00, 0.82, 0.00 }
local COLOR_ARROW = { 1.00, 1.00, 1.00 }
local COLOR_ARROW_NATIVE = { 0.80, 0.80, 0.80 }
local COLOR_BADGE = { 0.04, 0.05, 0.08 }
local COLOR_BADGE_EDGE_NATIVE = { 0.55, 0.55, 0.55 }
local WHITE = "Interface\\Buttons\\WHITE8X8"

local frame
local lines, dots, rects = {}, {}, {}
local lineCount, dotCount, rectCount = 0, 0, 0
local label

local SHADOW = { 0, 0, 0 }

local function Line(x1, y1, x2, y2, color, thickness, alpha, sublevel)
	lineCount = lineCount + 1
	local line = lines[lineCount]
	if not line then
		line = frame:CreateLine(nil, "OVERLAY")
		lines[lineCount] = line
	end
	line:SetDrawLayer("OVERLAY", sublevel or 2)
	line:SetThickness(thickness or 2)
	line:SetColorTexture(color[1], color[2], color[3], alpha or 1)
	line:SetStartPoint("BOTTOMLEFT", UIParent, x1, y1)
	line:SetEndPoint("BOTTOMLEFT", UIParent, x2, y2)
	line:Show()
end

local function RawDot(x, y, color, alpha, size, sublevel)
	dotCount = dotCount + 1
	local dot = dots[dotCount]
	if not dot then
		dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetTexture(WHITE)
		dots[dotCount] = dot
	end
	dot:SetDrawLayer("OVERLAY", sublevel)
	size = size or 6
	dot:SetSize(size, size)
	dot:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	dot:Show()
end

-- Line / dot with a dark outline underneath.
local function Stroke(x1, y1, x2, y2, color, thickness, alpha)
	thickness = thickness or 2
	Line(x1, y1, x2, y2, SHADOW, thickness + 2, (alpha or 1) * 0.7, 1)
	Line(x1, y1, x2, y2, color, thickness, alpha, 3)
end

local function Dot(x, y, color, alpha, size)
	size = size or 6
	RawDot(x, y, SHADOW, (alpha or 1) * 0.7, size + 2, 5)
	RawDot(x, y, color, alpha, size, 6)
end

-- Filled rectangle (UI units), drawn under the lines.
local function Rect(left, bottom, width, height, color, alpha)
	rectCount = rectCount + 1
	local rect = rects[rectCount]
	if not rect then
		rect = frame:CreateTexture(nil, "ARTWORK")
		rect:SetTexture(WHITE)
		rects[rectCount] = rect
	end
	rect:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	rect:ClearAllPoints()
	rect:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
	rect:SetSize(math.max(width, 1), math.max(height, 1))
	rect:Show()
end

-- Dark badge with a 1-unit outline, centered on (x, y).
local function Badge(x, y, width, height, edge, alpha)
	local l, b = x - width / 2, y - height / 2
	Rect(l - 1, b - 1, width + 2, height + 2, edge, alpha)
	Rect(l, b, width, height, COLOR_BADGE, alpha * 0.9)
end

-- Arrowhead with its tip at (x, y) pointing in direction (dx, dy), unit vector.
local function Arrowhead(x, y, dx, dy, color, alpha, size)
	size = size or 7
	local bx, by = x - dx * size, y - dy * size
	local px, py = -dy * size * 0.8, dx * size * 0.8
	Stroke(x, y, bx + px, by + py, color, 2, alpha)
	Stroke(x, y, bx - px, by - py, color, 2, alpha)
end

local function IsSystemFrame(f)
	return type(f) == "table" and (f.system ~= nil or CMP.byFrame[f] ~= nil)
end

function Overlay:DrawConnector(systemFrame, selected)
	local point, relativeTo, relativePoint = systemFrame:GetPoint(1)
	if type(relativeTo) == "string" then
		relativeTo = _G[relativeTo]
	end
	if not point or not relativeTo or relativeTo == UIParent or not IsSystemFrame(relativeTo) then
		return
	end
	if not relativeTo:IsVisible() then
		return
	end
	-- Drawn on the visible edges, where the frames actually meet (see Anchors:VisibleRect).
	local x1, y1 = CMP.Anchors:VisiblePoint(systemFrame, point)
	local x2, y2 = CMP.Anchors:VisiblePoint(relativeTo, relativePoint)
	if not x1 or not x2 then
		return
	end
	local info = CMP.byFrame[systemFrame]
	local ours = info and CMP.Anchors:TargetInfo(info) ~= nil
	local color = ours and COLOR_ATTACH or COLOR_NATIVE
	local alpha = selected and 1 or 0.6

	-- Seam along the shared edge, over the part where both frames overlap.
	local l1, b1, w1, h1 = CMP.Anchors:VisibleRect(systemFrame)
	local l2, b2, w2, h2 = CMP.Anchors:VisibleRect(relativeTo)
	if l1 and l2 then
		local horizontalSeam = relativePoint:find("TOP", 1, true) or relativePoint:find("BOTTOM", 1, true)
		if horizontalSeam then
			local from, to = math.max(l1, l2), math.min(l1 + w1, l2 + w2)
			if to - from > 4 then
				Stroke(from, y2, to, y2, color, selected and 2 or 1, alpha * 0.8)
			end
		else
			local from, to = math.max(b1, b2), math.min(b1 + h1, b2 + h2)
			if to - from > 4 then
				Stroke(x2, from, x2, to, color, selected and 2 or 1, alpha * 0.8)
			end
		end
	end

	if math.abs(x1 - x2) + math.abs(y1 - y2) > 1.5 then
		Stroke(x1, y1, x2, y2, color, selected and 2 or 1.5, alpha)
		Dot(x1, y1, color, alpha, 5)
	end
	Dot(x2, y2, color, alpha, selected and 8 or 6)
end

-- Growth badge. Horizontal rows: on the top edge; columns: on the left edge.
function Overlay:DrawGrowth(info, selected)
	local viewer = info.frame
	if info.kind == "prd" or not viewer:IsVisible() then
		return
	end
	local left, bottom, width, height = CMP.RectUI(viewer)
	if not left or width < 12 or height < 12 then
		return
	end
	local align, horizontal = CMP.Layout:EffectiveAlign(info)
	local ours = CMP:Get(info.key, "align") ~= "native" and not CMP.Layout:IsGeometryLocked(info)
	if not ours and not selected then
		return -- Blizzard's default needs no badge on every frame
	end
	local alpha = selected and 1 or 0.85
	local edgeColor = ours and COLOR_PLUS or COLOR_BADGE_EDGE_NATIVE
	local arrow = ours and COLOR_ARROW or COLOR_ARROW_NATIVE
	local long, short = selected and 46 or 40, selected and 16 or 14
	local right, top = left + width, bottom + height

	-- Along = the growth axis. P(a, c) maps "along, across" to screen x, y. For columns
	-- "along" runs downward from the top (start = top).
	local function P(a, c)
		if horizontal then
			return a, c
		end
		return c, a
	end
	-- Just inside the edge, so it never sits on the seam between two stacked frames.
	local inset = short / 2 + 3
	local from, to, edge
	if horizontal then
		from, to, edge = left + 3, right - 3, top - inset
	else
		from, to, edge = top - 3, bottom + 3, left + inset
	end
	local dir = to > from and 1 or -1
	local half = long / 2
	local center
	if align == "start" then
		center = from + dir * half
	elseif align == "end" then
		center = to - dir * half
	else
		center = (from + to) / 2
	end
	local bx, by = P(center, edge)
	if horizontal then
		Badge(bx, by, long, short, edgeColor, alpha)
	else
		Badge(bx, by, short, long, edgeColor, alpha)
	end

	-- Inside the badge: a pin where the frame stays put, arrows where it grows.
	local pinHalf = short / 2 - 3
	local function Pin(a)
		local x1, y1 = P(a, edge - pinHalf)
		local x2, y2 = P(a, edge + pinHalf)
		Stroke(x1, y1, x2, y2, arrow, 2, alpha)
	end
	local function Arrow(a1, a2)
		local x1, y1 = P(a1, edge)
		local x2, y2 = P(a2, edge)
		Stroke(x1, y1, x2, y2, arrow, 2, alpha)
		local d = a2 > a1 and 1 or -1
		local dx, dy = P(d, 0)
		Arrowhead(x2, y2, dx, dy, arrow, alpha, 5)
	end
	local pad = 5
	local s, e = center - dir * (half - pad), center + dir * (half - pad)
	if align == "start" then
		Pin(s)
		Arrow(s + dir * 3, e)
	elseif align == "end" then
		Pin(e)
		Arrow(e - dir * 3, s)
	else
		Pin(center)
		Arrow(center + dir * 3, e)
		Arrow(center - dir * 3, s)
	end

	-- Extra rows (or columns) appear once a row is full: a small badge with an arrow.
	if CMP.Layout:CanWrap(info) then
		local size = short
		if horizontal then
			local wx, wy = left + width / 2, bottom + short / 2 + 3
			Badge(wx, wy, size, size, edgeColor, alpha)
			Stroke(wx, wy + 4, wx, wy - 4, arrow, 2, alpha)
			Arrowhead(wx, wy - 4, 0, -1, arrow, alpha, 4)
		else
			local wx, wy = right - short / 2 - 3, bottom + height / 2
			Badge(wx, wy, size, size, edgeColor, alpha)
			Stroke(wx - 4, wy, wx + 4, wy, arrow, 2, alpha)
			Arrowhead(wx + 4, wy, 1, 0, arrow, alpha, 4)
		end
	end
end

-- Text only where a picture can't explain it: a frame in Blizzard's default position
-- needs to be moved once before Grow From and attaching work.
function Overlay:Describe(systemFrame)
	local info = CMP.byFrame[systemFrame]
	if info and not CMP.Anchors:TargetInfo(info) and CMP:IsManagedDefault(systemFrame) then
		return "Move this frame once to use Grow From and attaching"
	end
	return nil
end

function Overlay:DrawLabel(selected)
	if not selected or not selected:IsVisible() then
		label:Hide()
		return
	end
	local text = self:Describe(selected)
	if not text then
		label:Hide()
		return
	end
	label.text:SetText(text)
	label:SetSize(label.text:GetStringWidth() + 12, label.text:GetStringHeight() + 6)
	label:ClearAllPoints()
	label:SetPoint("BOTTOMLEFT", selected, "TOPLEFT", 0, 4)
	label:Show()
end

function Overlay:Draw()
	lineCount, dotCount, rectCount = 0, 0, 0
	local selected = CMP.selected

	local systems = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	if systems then
		for _, systemFrame in ipairs(systems) do
			if systemFrame:IsVisible() then
				CMP.Safe(self.DrawConnector, self, systemFrame, systemFrame == selected)
			end
		end
	end
	for _, info in ipairs(CMP.frameInfos) do
		if info.frame then
			local isSelected = info.frame == selected
			CMP.Safe(self.DrawGrowth, self, info, isSelected)
		end
	end
	CMP.Safe(self.DrawLabel, self, selected)

	for i = lineCount + 1, #lines do
		lines[i]:Hide()
	end
	for i = dotCount + 1, #dots do
		dots[i]:Hide()
	end
	for i = rectCount + 1, #rects do
		rects[i]:Hide()
	end
end

function Overlay:Refresh()
	if frame and frame:IsShown() then
		self:Draw()
	end
end

function Overlay:Init()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(1000)
	frame:EnableMouse(false)
	frame:Hide()

	label = CreateFrame("Frame", nil, frame)
	label:SetFrameLevel(1001)
	local background = label:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.75)
	label.text = label:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label.text:SetPoint("CENTER")
	label.text:SetTextColor(COLOR_PLUS[1], COLOR_PLUS[2], COLOR_PLUS[3])
	label:Hide()

	-- Redraw continuously while Edit Mode is open, so lines follow drags.
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 0.03 then
			elapsed = 0
			Overlay:Draw()
		end
	end)

	CMP.LEM:RegisterCallback("enter", function()
		frame:Show()
		Overlay:Draw()
	end)
	CMP.LEM:RegisterCallback("exit", function()
		frame:Hide()
	end)
end
