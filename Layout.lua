local _, ns = ...
local CMP = ns.CMP
local raw = CMP.raw

-- Places a viewer's items after Blizzard's own grid layout ran.
--
-- Blizzard still decides what is tracked, the order, the orientation, the icon limit per
-- row, the icon direction and the padding (all Edit Mode / Cooldown Settings options).
-- On top of that we add: alignment inside the row (start / center / end), collapsing the
-- gaps of inactive buffs, pixel snapping, and the "square" style's real padding.

local Layout = {}
CMP.Layout = Layout

local itemsByViewer = {} -- viewer -> { [item] = true }
local hookedItems = setmetatable({}, { __mode = "k" })
local busy = {}
local engineUsed = {} -- viewer -> true after we placed items, until restored

-- Base widths of item frames (their template size). Match Width can make a column one
-- pixel wider; sizes are always computed from the base width.
local baseWidth = setmetatable({}, { __mode = "k" })

local appliedWidth = setmetatable({}, { __mode = "k" }) -- item -> width we set (if not base)

local function BaseWidth(item)
	local base = baseWidth[item]
	if not base then
		base = item:GetWidth()
		if CMP.IsSecret(base) or not base or base <= 0 then
			return nil
		end
		baseWidth[item] = base
	end
	return base
end

-- Content bounds per frame key, UI units. Used for width matching.
Layout.content = {}

function Layout:Items(viewer)
	return itemsByViewer[viewer] or {}
end

-- A viewer in its default (managed) position is sized and placed by Blizzard's managed
-- frame container; changing its geometry would overflow those bounds. Geometry options
-- wait until the viewer has been moved once in Edit Mode.
function Layout:IsGeometryLocked(info)
	return info.frame ~= nil and CMP:IsManagedDefault(info.frame)
end

function Layout:IsEngineActive(info)
	local key = info.key
	if self:IsGeometryLocked(info) then
		return false
	end
	if self.fit[info.frame] then
		return true
	end
	if CMP.Custom:HasShown(info) then
		return true -- our own icons are placed by us
	end
	if CMP:Get(key, "align") ~= "native" then
		return true
	end
	if Layout:ClosesGaps(info) then
		return true
	end
	if info.kind == "icons" and (CMP:Get(key, "spacingX") >= 0 or CMP:Get(key, "spacingY") >= 0) then
		return true
	end
	if info.kind == "bars" then
		return CMP:Get(key, "matchWidth") ~= "off"
	end
	return CMP:IconStyle(info) ~= "blizzard" or CMP:Get(key, "iconSize") > 0
end

-- Buffs: whether inactive buffs give up their slot. Blizzard keeps an empty slot for each
-- tracked buff that isn't active. With Grow From set, active buffs are packed from that
-- point (a centered row of one buff is centered); with Default, "Close Gaps" decides.
function Layout:ClosesGaps(info)
	if not info.buffs then
		return false
	end
	return CMP:Get(info.key, "align") ~= "native" or CMP:Get(info.key, "collapse") == true
end

-- Exact icon size: pick an item scale that makes the icon a whole number of screen pixels.
function Layout:ApplyItemScale(info, item)
	if info.kind ~= "icons" then
		return
	end
	local viewer = info.frame
	local fit = self.fit[viewer]
	local size = fit and fit.size or (not self:IsGeometryLocked(info) and CMP:Get(info.key, "iconSize") or 0)
	if size <= 0 and self:IsEngineActive(info) then
		-- Edit Mode's Icon Size, rounded to whole screen pixels: at most UI scales Blizzard's
		-- size is fractional (49.93 px), and the game then rounds each edge differently, so
		-- borders and the icons next to them end up a pixel off.
		local base = BaseWidth(item)
		if base then
			size = base * (viewer.iconScale or 1) * viewer:GetEffectiveScale() / UIParent:GetEffectiveScale()
		end
	end
	local scale
	if size > 0 then
		local base = BaseWidth(item)
		if not base then
			return
		end
		local factor = PixelUtil.GetPixelToUIUnitFactor()
		local pixels = math.max(1, math.floor(size * UIParent:GetEffectiveScale() / factor + 0.5))
		scale = pixels * factor / (base * viewer:GetEffectiveScale())
	else
		scale = viewer.iconScale or 1
	end
	if math.abs(item:GetScale() - scale) > 0.0001 then
		raw.SetScale(item, scale)
	end
end

-- Alignment actually in effect ("start" | "center" | "end") and whether rows are horizontal.
function Layout:EffectiveAlign(info)
	local viewer = info.frame
	local horizontal = viewer.isHorizontal ~= false
	local align = CMP:Get(info.key, "align")
	if align == "native" or self:IsGeometryLocked(info) then
		if horizontal then
			align = viewer.layoutFramesGoingRight ~= false and "start" or "end"
		else
			align = viewer.layoutFramesGoingUp and "end" or "start"
		end
	end
	return align, horizontal
end

-- Can icons wrap into another row (an icon limit per row that the tracked icons reach)?
function Layout:CanWrap(info)
	if info.buffs or not info.frame.stride then
		return false -- buff viewers are always a single row or column
	end
	local count = 0
	for item in pairs(self:Items(info.frame)) do
		if item.layoutIndex and item.GetCooldownID and item:GetCooldownID() ~= nil then
			count = count + 1
		end
	end
	count = count + #CMP.Custom:Frames(info)
	return count >= info.frame.stride
end

function Layout:Hook(info)
	local viewer = info.frame
	itemsByViewer[viewer] = itemsByViewer[viewer] or {}

	CMP.HookMethod(viewer, "OnAcquireItemFrame", function(_, item)
		CMP.Safe(self.OnAcquire, self, info, item)
	end)
	CMP.HookMethod(viewer, "Layout", function()
		self:Run(info)
	end)
	CMP.HookMethod(viewer, "RefreshData", function()
		CMP.Safe(CMP.Skin.RefreshViewer, CMP.Skin, info)
	end)

	-- Items that already exist (we may load after the first layout).
	for _, child in ipairs({ viewer:GetChildren() }) do
		if child.SetViewerFrame and child.GetCooldownID then
			self:OnAcquire(info, child)
		end
	end
end

function Layout:OnAcquire(info, item)
	itemsByViewer[info.frame][item] = true
	if not hookedItems[item] then
		hookedItems[item] = true
		-- Buffs show and hide as auras come and go. Blizzard keeps their slot, so it doesn't
		-- re-run the layout; we need to when collapsing or centering.
		item:HookScript("OnShow", function() self:Run(info) end)
		item:HookScript("OnHide", function() self:Run(info) end)
	end
	-- A pooled icon may come back still widened from an earlier Match Width layout.
	self:SetItemExtraWidth(info, item, 0)
	self:ApplyItemScale(info, item)
	if info.kind == "bars" then
		CMP.Anchors:ApplyBarItemWidth(info, item)
	end
	CMP.Skin:ApplyItem(info, item)
	CMP.Media:StyleItem(info, item)
	CMP.Keybinds:ApplyItem(info, item)
end

-- In combat only frames that aren't protected may change. If anything here became
-- protected (e.g. something protected got anchored to it), wait for combat to end.
local function CanTouchViewer(viewer)
	if not InCombatLockdown() then
		return true
	end
	if not CMP:CanTouch(viewer) then
		return false
	end
	for item in pairs(itemsByViewer[viewer]) do
		if item.layoutIndex and not CMP:CanTouch(item) then
			return false
		end
	end
	local info = CMP.byFrame[viewer]
	return info == nil or CMP.Custom:CanTouch(info)
end

function Layout:Run(info)
	local viewer = info.frame
	if not viewer or info.kind == "prd" or busy[viewer] or not CMP.ready then
		return
	end
	if not CanTouchViewer(viewer) then
		return
	end
	busy[viewer] = true
	CMP.Safe(self.RunUnsafe, self, info)
	busy[viewer] = nil -- always cleared, even after an error
	CMP.Anchors:OnContentChanged(info)
end

-- Blizzard's round icon art leaves a transparent edge around each icon; Blizzard pulls
-- icons 4 units closer (2 per side) so they touch (see GetAdditionalPaddingOffset). We
-- treat the visible icon as the icon: rows we lay out have their frame on the visible
-- edges, so attaching with gap 0 or matching widths lines up with what you see.
local BLIZZARD_ICON_EDGE = 2 -- item units, per side
Layout.BLIZZARD_ICON_EDGE = BLIZZARD_ICON_EDGE

local function IconEdge(info)
	if info.kind == "icons" and CMP:IconStyle(info) == "blizzard" then
		return BLIZZARD_ICON_EDGE
	end
	return 0
end

-- Transparent edge (UI units) between a viewer's frame and its visible icons, for rows
-- Blizzard lays out itself (ours already sit on the visible edges).
function Layout:VisibleInset(info)
	if info.kind ~= "icons" or not info.frame or self:IsEngineActive(info) then
		return 0
	end
	return IconEdge(info) * (info.frame.iconScale or 1) * CMP.ToUI(info.frame)
end

-- Padding between icons in the item's own units, the way Place uses it.
local function ItemPadding(info, native)
	local viewer = info.frame
	local horizontal = viewer.isHorizontal ~= false
	local padding = (horizontal and viewer.childXPadding or viewer.childYPadding) or 0
	-- Blizzard pulls icons 4px closer because its round art has transparent edges. Square
	-- and Masque icons fill their frame, so negative padding would overlap them.
	if not native and info.kind == "icons" and CMP:IconStyle(info) ~= "blizzard" then
		padding = math.max(0, padding)
	end
	return padding
end

-- Shared borders: square icons with a border overlap their neighbour by the border width,
-- so two neighbours show one border line instead of two (like CSS border-collapse).
function Layout:SharedBorderPixels(info)
	if info.kind ~= "icons" or CMP:IconStyle(info) ~= "square" or not CMP:Get(info.key, "sharedBorders") then
		return 0
	end
	return math.max(0, CMP:Get(info.key, "borderSize") or 0)
end

-- Gaps between icons (along a row) and between rows, in the viewer's units, as distances
-- between item frames. Icon Gap / Row Gap are screen pixels between the visible icons
-- (-1 = Blizzard's Icon Padding). edge = transparent edge of Blizzard's icon art.
function Layout:Gaps(info, native, scale, edge)
	local padding = ItemPadding(info, native) * scale
	if native then
		return padding, padding
	end
	local px = CMP.PixelUnit(info.frame)
	local x, y = CMP:Get(info.key, "spacingX"), CMP:Get(info.key, "spacingY")
	local gap = x >= 0 and (x * px - 2 * edge) or padding
	local lineGap = y >= 0 and (y * px - 2 * edge) or gap
	local shared = self:SharedBorderPixels(info)
	if shared > 0 then
		-- Overlap when the icons would touch (or close to it).
		if gap <= px * 0.5 then
			gap = -shared * px
		end
		if lineGap <= px * 0.5 then
			lineGap = -shared * px
		end
	end
	return gap, lineGap
end

-- Items that get a slot in the grid (see Place).
local function CountSlots(info)
	local viewer = info.frame
	local count, first = 0, nil
	for item in pairs(itemsByViewer[viewer]) do
		if item.layoutIndex and item:GetParent() == viewer then
			local shown = item:IsShown()
			if CMP.IsSecret(shown) then
				return 0, nil
			end
			if shown or (item.GetCooldownID and item:GetCooldownID() ~= nil) then
				count = count + 1
				first = first or item
			end
		end
	end
	for _, frame in ipairs(CMP.Custom:Frames(info)) do
		count = count + 1
		first = first or frame
	end
	return count, first
end

-- Match Width for icon rows: the icon size (whole screen pixels) that makes a full row
-- exactly as wide as the reference. Place then spreads the leftover pixels over the gaps.
Layout.fit = {}

function Layout:ComputeFit(info)
	local viewer = info.frame
	self.fit[viewer] = nil
	if info.kind ~= "icons" or self:IsGeometryLocked(info) or viewer.isHorizontal == false then
		return
	end
	local width = CMP.Anchors:FitWidth(info)
	if not width or width <= 0 then
		return
	end
	local total, first = CountSlots(info)
	if total == 0 or not first then
		return
	end
	local stride = viewer.stride
	if not stride or stride < 1 or info.buffs then
		stride = total -- buff rows never wrap (our custom buffs widen the row)
	end
	local perLine = math.min(stride, total)
	local base = BaseWidth(first)
	if not base then
		return
	end
	local toUI = CMP.ToUI(viewer)
	local edgeUnits = IconEdge(info) -- item units
	local factor = PixelUtil.GetPixelToUIUnitFactor() / UIParent:GetEffectiveScale() -- UI units per pixel
	-- Gaps that don't depend on the icon size (Icon Gap in pixels, shared borders)...
	local fixedGap = nil
	if CMP:Get(info.key, "spacingX") >= 0 or (self:SharedBorderPixels(info) > 0 and ItemPadding(info, false) <= 0) then
		local gap = self:Gaps(info, false, 1, 0) -- viewer units, no edge
		fixedGap = gap * toUI
	end
	local size
	if fixedGap then
		-- visible row = N * (icon - 2 edge) + (N - 1) * visibleGap; solve for the icon.
		local visibleIcon = (width - (perLine - 1) * fixedGap) / perLine
		size = visibleIcon / (1 - 2 * edgeUnits / base)
	else
		-- ...or Blizzard's padding, which scales with the icons.
		local padding = ItemPadding(info, false)
		local scale = width / (toUI * (perLine * base + (perLine - 1) * padding - 2 * edgeUnits))
		size = base * scale * toUI
	end
	size = math.max(1, math.floor(size / factor)) * factor
	self.fit[viewer] = { width = width, size = size, perLine = perLine }
end

function Layout:RunUnsafe(info)
	local viewer = info.frame
	CMP.Custom:Sync(info)
	self:ComputeFit(info)
	if info.kind == "icons" then
		for item in pairs(itemsByViewer[viewer]) do
			if item.layoutIndex then
				self:ApplyItemScale(info, item)
			end
		end
		for _, frame in ipairs(CMP.Custom:Frames(info)) do
			self:ApplyItemScale(info, frame)
		end
	end
	if self:IsEngineActive(info) then
		engineUsed[viewer] = true
		self:Place(info, false)
	elseif engineUsed[viewer] then
		-- Switched off: put everything back exactly where Blizzard's grid would.
		engineUsed[viewer] = nil
		self:Place(info, true)
	else
		self:StoreNativeContent(info)
	end
	-- A viewer in its default place keeps Blizzard's layout: our icons continue its grid.
	if self:IsGeometryLocked(info) and CMP.Custom:HasShown(info) then
		self:Place(info, true, true)
	end
	-- Borders depend on the (possibly new) item scale.
	CMP.Skin:RefreshViewer(info)
end

function Layout:StoreNativeContent(info)
	local _, _, width, height = CMP.RectUI(info.frame)
	local inset = self:VisibleInset(info)
	self.content[info.key] = width and { width = width - 2 * inset, height = height - 2 * inset } or nil
end

-- extra: viewer units added to the item's width (0 = its normal width).
function Layout:SetItemExtraWidth(info, item, extra)
	if info.kind ~= "icons" then
		return
	end
	local base = BaseWidth(item)
	if not base then
		return
	end
	local width = base + extra / item:GetScale()
	-- Compare with what we set (never the live width, which can be secret in combat).
	local current = appliedWidth[item] or base
	if math.abs(current - width) > 0.001 then
		raw.SetWidth(item, width)
		appliedWidth[item] = width ~= base and width or nil
	end
end

-- Our custom icons carry sortMajor (the layoutIndex they follow) and sortMinor.
local function ByLayoutIndex(a, b)
	local am, bm = a.sortMajor or a.layoutIndex, b.sortMajor or b.layoutIndex
	if am ~= bm then
		return am < bm
	end
	return (a.sortMinor or 0) < (b.sortMinor or 0)
end

-- native = true reproduces Blizzard's GridLayout exactly (used to undo our changes).
-- customOnly = true (with native): only our custom icons are placed, after Blizzard's,
-- for viewers whose geometry stays Blizzard's.
function Layout:Place(info, native, customOnly)
	local viewer = info.frame
	local key = info.key
	local collapse = not native and self:ClosesGaps(info)
	local customs = CMP.Custom:Frames(info)

	-- slots: what the grid reserves room for. placed: what we position.
	local slots, placed = {}, {}
	for item in pairs(itemsByViewer[viewer]) do
		if item.layoutIndex and item:GetParent() == viewer then
			local shown = item:IsShown()
			if CMP.IsSecret(shown) then
				return -- can't reason about it; leave Blizzard's positions alone
			end
			local hasCooldown = item.GetCooldownID and item:GetCooldownID() ~= nil
			-- Blizzard pads the grid to at least two slots with empty items. Keep those
			-- only when reproducing the native layout.
			if (native and not customOnly) or shown or hasCooldown then
				slots[#slots + 1] = item
				if native or shown or not collapse then
					placed[#placed + 1] = item
				end
			end
		end
	end
	if #customs > 0 then
		CMP.Custom:AssignOrder(info, customOnly)
		for _, frame in ipairs(customs) do
			slots[#slots + 1] = frame
			placed[#placed + 1] = frame
		end
	end

	if #placed == 0 then
		self.content[key] = { width = 0, height = 0 }
		return
	end
	table.sort(slots, ByLayoutIndex)
	table.sort(placed, ByLayoutIndex)

	local first = placed[1]
	local scale = first:GetScale()
	-- Icons: their template width (a column may be 1 px wider, see below). Bars: as they are
	-- (Match Width sets the bar width).
	local itemWidth = info.kind == "icons" and BaseWidth(first) or first:GetWidth()
	local width, height = itemWidth * scale, first:GetHeight() * scale -- viewer units

	local horizontal = viewer.isHorizontal ~= false
	local stride = viewer.stride
	-- Buff rows are one row (or column): Blizzard's stride there is its own icon count, so
	-- our custom buffs would wrap into a row of their own.
	if not stride or stride < 1 or info.buffs then
		stride = #slots
	end
	-- Transparent edge of Blizzard's icon art (viewer units): items overhang the frame by
	-- this much, so the frame sits on the visible icon edges.
	local edge = native and 0 or IconEdge(info) * scale
	local gap, lineGap = self:Gaps(info, native, scale, edge)

	local goingRight = viewer.layoutFramesGoingRight ~= false
	local goingUp = viewer.layoutFramesGoingUp == true

	-- primary axis = along a row (horizontal) or a column (vertical)
	local primary = horizontal and width or height
	local secondary = horizontal and height or width
	local total = #slots
	local perLine = math.min(stride, total)
	local lines = math.ceil(total / stride)
	-- Width of each column. Normally all the same. With Match Width the row must come out
	-- exactly the reference width while icons stay whole pixels: the few leftover pixels
	-- make some columns 1 pixel wider, spread evenly, so the gaps stay exact.
	local columns = {}
	for k = 0, perLine - 1 do
		columns[k] = primary
	end
	local fit = not native and horizontal and self.fit[viewer]
	if fit then
		local px = CMP.PixelUnit(viewer)
		local target = fit.width / CMP.ToUI(viewer) + 2 * edge
		local leftover = math.floor((target - perLine * primary - (perLine - 1) * gap) / px + 0.5)
		leftover = math.max(0, math.min(leftover, perLine))
		for n = 1, leftover do
			local k = math.floor((n - 0.5) * perLine / leftover)
			columns[k] = columns[k] + px
		end
	end
	local function Span(count)
		local total = 0
		for k = 0, count - 1 do
			total = total + columns[k]
		end
		return total + math.max(0, count - 1) * gap
	end
	local extentPrimary = Span(perLine)
	local extentSecondary = lines * secondary + (lines - 1) * lineGap

	local align = native and "native" or CMP:Get(key, "align")
	if align == "native" then
		if horizontal then
			align = goingRight and "start" or "end"
		else
			align = goingUp and "end" or "start"
		end
	end
	-- Icon Direction decides the order: the first icon sits at the side it grows from.
	local reversed = (horizontal and not goingRight) or (not horizontal and goingUp)

	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	local count = #placed
	for line = 0, math.ceil(count / stride) - 1 do
		local firstIndex = line * stride + 1
		local inLine = math.min(stride, count - line * stride)
		local lineLength = Span(inLine)
		local offset = 0
		if align == "center" then
			offset = (extentPrimary - lineLength) / 2
		elseif align == "end" then
			offset = extentPrimary - lineLength
		end
		for k = 0, inLine - 1 do
			local item = placed[firstIndex + k]
			local slot = reversed and (inLine - 1 - k) or k
			local p = offset + Span(slot) + (slot > 0 and gap or 0)
			self:SetItemExtraWidth(info, item, horizontal and (columns[slot] - primary) or 0)
			local q = line * (secondary + lineGap)
			local x, y
			if horizontal then
				x, y = p - edge, -(q - edge)
			else
				x, y = q - edge, -(p - edge)
			end
			if not native then
				x, y = CMP.Snap(x, viewer), CMP.Snap(y, viewer)
			end
			if not customOnly or item.isCustom then
				raw.ClearAllPoints(item)
				raw.SetPoint(item, "TOPLEFT", viewer, "TOPLEFT", x / scale, y / scale)
			end
			local itemWidth = horizontal and columns[slot] or width
			minX, maxX = math.min(minX, x), math.max(maxX, x + itemWidth)
			minY, maxY = math.min(minY, y - height), math.max(maxY, y)
		end
	end

	-- Keep the frame at the size of the full grid, so its center (and the Edit Mode
	-- selection) stays put while buffs come and go.
	if customOnly then
		return -- the frame and its content size stay Blizzard's
	end
	local frameWidth = (horizontal and extentPrimary or extentSecondary) - 2 * edge
	local frameHeight = (horizontal and extentSecondary or extentPrimary) - 2 * edge
	if not CMP:IsManagedDefault(viewer) then
		raw.SetSize(viewer, math.max(frameWidth, 1), math.max(frameHeight, 1))
	end

	local toUI = CMP.ToUI(viewer)
	self.content[key] = { width = (maxX - minX - 2 * edge) * toUI, height = (maxY - minY - 2 * edge) * toUI }
end
