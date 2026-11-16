-- Offline mock of the parts of the WoW client API that Cooldown Manager Plus (and the bundled
-- LibEditMode) call. Written by reading what the addon calls; it is not a general emulator.
--
-- Rules of this file:
--  * Unknown globals fail loudly (and are recorded in H.errors) so API gaps are visible.
--    Globals the addon probes on purpose ("if IsAddOnLoaded then") are listed in OPTIONAL.
--  * Every Lua error that WoW would route to the error handler (event/script handlers,
--    hooks, timers, CMP.Safe) is recorded in H.errors. The runner fails a test that ends with
--    errors in the list unless it opted out.
--  * Frames are tables with a metatable whose __index is the widget's method table, like the
--    client's (Core.lua does getmetatable(CreateFrame("Frame")).__index). Private state lives in
--    a side table so addon-set fields never collide with it.

local M = {}

local PRISTINE = {}
for k in pairs(_G) do
	PRISTINE[k] = true
end

local OPTIONAL = {
	-- probed by the addon with `x and x(...)` / `if x then`
	CooldownManagerPlusDB = true,
	CallErrorHandler = false, -- defined below (modern retail has it)
	IsAddOnLoaded = true, -- removed from the modern client, only a fallback in the addon
	GetNumSpecGroups = true,
	C_EncodingUtil = true, -- Share.lua falls back to plain base64 without it
	GetActionInfo = false,
	GetMacroSpell = false,
	GetMacroItem = false,
	FindBaseSpellByID = false,
	issecretvalue = false,
	Settings = false,
	Menu = false,
	EDIT_MODE_GAMEPAD_SYSTEM_MAP = true, -- LibEditMode probes the three layout maps
	-- frames the addon looks up by name (_G[info.global]); nil until Blizzard's addon made them
	EssentialCooldownViewer = true, UtilityCooldownViewer = true, BuffIconCooldownViewer = true,
	BuffBarCooldownViewer = true, PersonalResourceDisplayFrame = true,
}
local OPTIONAL_PATTERNS = { "^ActionButton%d+$" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

function M.new(opts)
	opts = opts or {}
	local H = { errors = {}, output = {}, calls = {} }
	local realG = _G
	local S = {} -- object -> private state (strong: frames live as long as the client)
	local secrets = setmetatable({}, { __mode = "k" }) -- secret wrapper -> real type
	local rawType = type
	local pack = function(...) return { n = select("#", ...), ... } end

	local function st(obj) return S[obj] end
	H.state = st

	local function fmtErr(err)
		return rawType(err) == "string" and err or tostring(err)
	end

	local function record(err, where)
		local msg = fmtErr(err)
		if where then
			msg = msg .. "\n  (in " .. where .. ")"
		end
		table.insert(H.errors, msg)
	end
	H.recordError = record

	local function handler(err)
		local tb = debug.traceback(fmtErr(err), 2)
		record(tb)
		return tb
	end
	H.handler = handler

	-- run fn like the client runs a script/hook: errors are reported, execution carries on
	local function protected(where, fn, ...)
		return xpcall(fn, function(err)
			if not fmtErr(err):find("mock: unknown global", 1, true) then -- already recorded at the source
				record(debug.traceback(fmtErr(err), 2), where)
			end
			return err
		end, ...)
	end
	H.protected = protected

	---------------------------------------------------------------------------
	-- Secret values
	---------------------------------------------------------------------------
	-- A secret is a userdata that errors on every operation the client forbids (arithmetic,
	-- ordering comparisons, concatenation, length, indexing, calling). Truthiness and == cannot
	-- be trapped in Lua 5.1; the addon's rule is to test IsSecret first anyway. `type()` is
	-- replaced so a secret number still reports "number", like the client.
	local secretMT = {}
	local function deny(what)
		return function() error("attempt to " .. what .. " a secret value", 2) end
	end
	secretMT.__index = deny("index")
	secretMT.__newindex = deny("modify")
	secretMT.__call = deny("call")
	secretMT.__len = deny("get length of")
	secretMT.__concat = deny("concatenate")
	secretMT.__unm = deny("negate")
	for _, e in ipairs({ "add", "sub", "mul", "div", "mod", "pow", "lt", "le" }) do
		secretMT["__" .. e] = deny("do arithmetic or ordering on")
	end
	secretMT.__tostring = deny("convert to string")

	function H.secret(value)
		if secrets[value] then
			return value
		end
		-- userdata (not a table) so that # and .. are trapped too
		local s = newproxy(true)
		local mt = getmetatable(s)
		for k, v in pairs(secretMT) do mt[k] = v end
		secrets[s] = rawType(value)
		return s
	end
	function H.isSecret(value)
		return secrets[value] ~= nil
	end
	-- Copy of `tbl` where the listed fields (or all fields when none listed) are secret.
	function H.secretFields(tbl, ...)
		local names = { ... }
		local out = {}
		for k, v in pairs(tbl) do
			out[k] = v
		end
		if #names == 0 then
			for k, v in pairs(tbl) do
				out[k] = H.secret(v)
			end
		else
			for _, k in ipairs(names) do
				if out[k] ~= nil then
					out[k] = H.secret(out[k])
				end
			end
		end
		return out
	end
	-- Make every result of `owner[name]` secret ("fields": a table result gets secret fields).
	function H.secretReturn(owner, name, mode)
		local orig = owner[name]
		owner[name] = function(...)
			local r = pack(orig(...))
			for i = 1, r.n do
				local v = r[i]
				if v ~= nil then
					if mode == "fields" and rawType(v) == "table" then
						r[i] = H.secretFields(v)
					else
						r[i] = H.secret(v)
					end
				end
			end
			return unpack(r, 1, r.n)
		end
		return orig
	end

	---------------------------------------------------------------------------
	-- Time and timers
	---------------------------------------------------------------------------
	H.now = 1000
	H.timers = {}
	local timerSeq = 0
	local function addTimer(delay, fn)
		timerSeq = timerSeq + 1
		local t = { due = H.now + (delay or 0), seq = timerSeq, fn = fn }
		table.insert(H.timers, t)
		return t
	end
	local function runDue()
		local ran = 0
		while true do
			local best
			for i, t in ipairs(H.timers) do
				if t.due <= H.now and not t.cancelled and (not best or t.due < H.timers[best].due
					or (t.due == H.timers[best].due and t.seq < H.timers[best].seq)) then
					best = i
				end
			end
			if not best then
				break
			end
			local t = table.remove(H.timers, best)
			ran = ran + 1
			protected("C_Timer callback", t.fn, t)
			if t.ticker and not t.cancelled and (t.iterations == nil or t.iterations > 1) then
				if t.iterations then t.iterations = t.iterations - 1 end
				t.due = H.now + t.interval
				timerSeq = timerSeq + 1
				t.seq = timerSeq
				table.insert(H.timers, t)
			end
		end
		return ran
	end
	-- Advance the clock by `seconds`, running every timer that comes due on the way.
	function H.advance(seconds)
		local target = H.now + (seconds or 0)
		while true do
			local nextDue
			for _, t in ipairs(H.timers) do
				if not t.cancelled and t.due <= target and (not nextDue or t.due < nextDue) then
					nextDue = t.due
				end
			end
			if not nextDue then
				break
			end
			if nextDue > H.now then
				H.now = nextDue
			end
			runDue()
		end
		H.now = target
		runDue()
	end
	-- Run zero-delay timers (and anything they queue) until none are left. Returns
	-- drained?, rounds. `drained == false` means something kept re-queuing itself.
	function H.flush(maxRounds)
		maxRounds = maxRounds or 100
		for round = 1, maxRounds do
			if runDue() == 0 then
				return true, round - 1
			end
		end
		return false, maxRounds
	end
	function H.pendingTimers()
		local n = 0
		for _, t in ipairs(H.timers) do
			if not t.cancelled then n = n + 1 end
		end
		return n
	end

	---------------------------------------------------------------------------
	-- Globals table (strict)
	---------------------------------------------------------------------------
	local G = {}
	H.G = G

	local function pairsList(tbl)
		local keys = {}
		for k in pairs(tbl) do keys[#keys + 1] = k end
		return keys
	end

	---------------------------------------------------------------------------
	-- Widget classes
	---------------------------------------------------------------------------
	local classes = {}
	local function class(name, parent)
		local t = {}
		if parent then
			setmetatable(t, { __index = classes[parent] })
		end
		classes[name] = t
		return t
	end
	local MT = setmetatable({}, { __index = function(t, name)
		local mt = { __index = classes[name], __name = name }
		rawset(t, name, mt)
		return mt
	end })

	local function props(cls, names)
		for _, n in ipairs(names) do
			cls["Set" .. n] = function(self, v) S[self]["p_" .. n] = v end
			cls["Get" .. n] = function(self) return S[self]["p_" .. n] end
		end
	end
	local function noops(cls, names)
		for _, n in ipairs(names) do
			cls[n] = function() end
		end
	end

	local Region = class("Region")
	local Frame = class("Frame", "Region")
	local Button = class("Button", "Frame")
	local CheckButton = class("CheckButton", "Button")
	local DropdownButton = class("DropdownButton", "Button")
	local Cooldown = class("Cooldown", "Frame")
	local StatusBar = class("StatusBar", "Frame")
	local EditBox = class("EditBox", "Frame")
	local Slider = class("Slider", "Frame")
	local GameTooltip = class("GameTooltip", "Frame")
	local Texture = class("Texture", "Region")
	local MaskTexture = class("MaskTexture", "Texture")
	local Line = class("Line", "Texture")
	local FontString = class("FontString", "Region")
	local AnimationGroup = class("AnimationGroup")
	local Animation = class("Animation")
	class("ScrollFrame", "Frame")
	class("Model", "Frame")
	class("ColorSelect", "Frame")

	local newObject, UIParent

	---------------------------------------------------------------------------
	-- Region: parenting, anchors, geometry
	---------------------------------------------------------------------------
	local function isFrameType(obj)
		local c = classes
		return getmetatable(obj) and (MT[S[obj].type].__index == c.Frame or S[obj].isFrame)
	end

	local function detach(obj)
		local s = S[obj]
		local p = s.parent
		if p then
			local list = s.isFrame and S[p].children or S[p].regions
			for i, o in ipairs(list) do
				if o == obj then table.remove(list, i) break end
			end
		end
	end
	local function attach(obj, parent)
		local s = S[obj]
		s.parent = parent
		if parent then
			table.insert(s.isFrame and S[parent].children or S[parent].regions, obj)
		end
	end

	function Region:GetParent() return S[self].parent end
	function Region:SetParent(parent)
		detach(self)
		attach(self, parent)
	end
	function Region:GetName() return S[self].name end
	function Region:GetObjectType() return S[self].type end
	function Region:IsObjectType(t) return S[self].type == t end
	function Region:GetDebugName() return S[self].name or ("<" .. S[self].type .. ">") end

	local function resolveRel(self, rel)
		if rawType(rel) == "string" then
			rel = rawget(realG, rel) or G[rel]
			if not rel then error("SetPoint: unknown relative frame name") end
		end
		return rel
	end

	function Region:SetPoint(point, rel, relPoint, x, y)
		local s = S[self]
		if rawType(rel) == "number" or rel == nil and rawType(relPoint) == "number" then
			-- SetPoint(point, x, y)
			x, y = rel, relPoint
			rel, relPoint = nil, nil
		elseif rawType(rel) ~= "table" and rawType(rel) ~= "string" and rel ~= nil then
			error("SetPoint: bad relativeTo")
		end
		if rawType(relPoint) == "number" then
			x, y, relPoint = relPoint, x, nil
		end
		rel = resolveRel(self, rel)
		local anchor = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
		for i, a in ipairs(s.points) do
			if a.point == point then
				s.points[i] = anchor
				return
			end
		end
		table.insert(s.points, anchor)
	end
	function Region:ClearAllPoints() S[self].points = {} S[self].allPoints = nil end
	function Region:GetNumPoints() return #S[self].points end
	function Region:GetPoint(i)
		local a = S[self].points[i or 1]
		if not a then return nil end
		return a.point, a.rel or S[self].parent, a.relPoint, a.x, a.y
	end
	function Region:SetAllPoints(rel)
		local s = S[self]
		s.points = {}
		rel = rel or s.parent
		s.points[1] = { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 }
		s.points[2] = { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 }
		s.allPoints = true
	end

	local HX = { LEFT = 0, CENTER = 0.5, RIGHT = 1, TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
	local VY = { BOTTOM = 0, CENTER = 0.5, TOP = 1, TOPLEFT = 1, TOPRIGHT = 1, LEFT = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

	local function effScale(obj)
		local scale = 1
		local o, guard = obj, 0
		while o and guard < 64 do
			local s = S[o]
			if s.isFrame or o == obj and false then
				scale = scale * (s.scale or 1)
			elseif o == obj then
				-- region: scale of its parent only
			end
			o = s.parent
			guard = guard + 1
		end
		return scale
	end
	H.effectiveScale = effScale

	-- Absolute (screen) rectangle: left, bottom, width, height; nil when not anchored.
	local function absRect(obj, depth)
		depth = (depth or 0) + 1
		if depth > 40 then return nil end
		local s = S[obj]
		if s.root then
			local es = effScale(obj)
			return 0, 0, s.size.w * es, s.size.h * es
		end
		if #s.points == 0 then return nil end
		local es = effScale(obj)
		local xs, ys = {}, {}
		for _, a in ipairs(s.points) do
			local rel = a.rel or s.parent or UIParent
			local rl, rb, rw, rh = absRect(rel, depth)
			if not rl then return nil end
			local ax = rl + (HX[a.relPoint] or 0.5) * rw + a.x * es
			local ay = rb + (VY[a.relPoint] or 0.5) * rh + a.y * es
			xs[#xs + 1] = { f = HX[a.point], v = ax }
			ys[#ys + 1] = { f = VY[a.point], v = ay }
		end
		local function solve(list, size)
			local first = list[1]
			for i = 2, #list do
				if list[i].f ~= first.f then
					local w = (list[i].v - first.v) / (list[i].f - first.f)
					return first.v - first.f * w, w
				end
			end
			return first.v - first.f * size, size
		end
		local l, w = solve(xs, s.size.w * es)
		local b, h = solve(ys, s.size.h * es)
		return l, b, w, h
	end
	H.absRect = absRect

	local function ownRect(self)
		local l, b, w, h = absRect(self)
		if not l then return nil end
		local es = effScale(self)
		if S[self].root then es = S[self].scale end
		return l / es, b / es, w / es, h / es
	end
	function Region:GetRect()
		local l, b, w, h = ownRect(self)
		if not l then return nil end
		return l, b, w, h
	end
	function Region:GetLeft() local l = ownRect(self) return l end
	function Region:GetBottom() local _, b = ownRect(self) return b end
	function Region:GetRight() local l, _, w = ownRect(self) return l and l + w end
	function Region:GetTop() local _, b, _, h = ownRect(self) return b and b + h end
	function Region:GetCenter() local l, b, w, h = ownRect(self) if not l then return nil end return l + w / 2, b + h / 2 end
	function Region:GetWidth()
		local s = S[self]
		local l, _, w = ownRect(self)
		if l and (s.size.w == 0 or #s.points > 1) then return w end
		return s.size.w
	end
	function Region:GetHeight()
		local s = S[self]
		local l, _, _, h = ownRect(self)
		if l and (s.size.h == 0 or #s.points > 1) then return h end
		return s.size.h
	end
	function Region:GetSize() return self:GetWidth(), self:GetHeight() end

	local function sizeChanged(self, w, h)
		local s = S[self]
		local ow, oh = s.size.w, s.size.h
		if w then s.size.w = w end
		if h then s.size.h = h end
		if (s.size.w ~= ow or s.size.h ~= oh) and s.isFrame then
			H.fireScript(self, "OnSizeChanged", s.size.w, s.size.h)
		end
	end
	function Region:SetSize(w, h) sizeChanged(self, w, h) end
	function Region:SetWidth(w) sizeChanged(self, w, nil) end
	function Region:SetHeight(h) sizeChanged(self, nil, h) end
	function Region:SetScale(scale) S[self].scale = scale end
	function Region:GetScale() return S[self].scale or 1 end
	function Region:GetEffectiveScale()
		return effScale(self)
	end
	function Region:SetAlpha(a) S[self].alpha = a end
	function Region:GetAlpha() return S[self].alpha end
	function Region:GetEffectiveAlpha()
		local a, o = 1, self
		while o do a = a * (S[o].alpha or 1) o = S[o].parent end
		return a
	end

	local function parentVisible(obj)
		local p = S[obj].parent
		while p do
			if not S[p].shown then return false end
			p = S[p].parent
		end
		return true
	end
	local function propagateVisibility(obj, visible)
		local s = S[obj]
		if s.isFrame then
			H.fireScript(obj, visible and "OnShow" or "OnHide")
			for _, child in ipairs({ unpack(s.children) }) do
				if S[child].shown then
					propagateVisibility(child, visible)
				end
			end
		end
	end
	function Region:Show()
		local s = S[self]
		if s.shown then return end
		s.shown = true
		if parentVisible(self) then propagateVisibility(self, true) end
	end
	function Region:Hide()
		local s = S[self]
		if not s.shown then return end
		s.shown = false
		if parentVisible(self) then propagateVisibility(self, false) end
	end
	function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
	function Region:IsShown() return S[self].shown end
	function Region:IsVisible() return S[self].shown and parentVisible(self) end
	function Region:IsProtected() return S[self].protected == true, false end
	function Region:SetDrawLayer(layer, sub) S[self].layer, S[self].sublayer = layer, sub end
	function Region:GetDrawLayer() return S[self].layer, S[self].sublayer end
	function Region:SetIgnoreParentScale() end
	function Region:IsDragging() return false end
	function Region:SetTexelSnappingBias() end
	function Region:SetSnapToPixelGrid() end
	function Region:CreateAnimationGroup(name)
		local g = newObject("AnimationGroup", nil, name)
		S[g].target = self
		S[self].animGroups = S[self].animGroups or {}
		table.insert(S[self].animGroups, g)
		return g
	end

	---------------------------------------------------------------------------
	-- Frame
	---------------------------------------------------------------------------
	function H.fireScript(frame, name, ...)
		local s = S[frame]
		local main = s.scripts[name]
		if main then protected(name .. " script", main, frame, ...) end
		local hooks = s.hooks[name]
		if hooks then
			for _, fn in ipairs({ unpack(hooks) }) do
				protected(name .. " hook", fn, frame, ...)
			end
		end
	end
	function Frame:SetScript(name, fn) S[self].scripts[name] = fn end
	function Frame:GetScript(name) return S[self].scripts[name] end
	function Frame:HasScript(name) return true end
	function Frame:HookScript(name, fn)
		local s = S[self]
		s.hooks[name] = s.hooks[name] or {}
		table.insert(s.hooks[name], fn)
	end

	function Frame:SetFrameLevel(level) S[self].level = level end
	function Frame:GetFrameLevel() return S[self].level end
	function Frame:SetFrameStrata(strata) S[self].strata = strata end
	function Frame:GetFrameStrata() return S[self].strata end
	function Frame:Raise() end
	function Frame:Lower() end
	function Frame:SetID(id) S[self].id = id end
	function Frame:GetID() return S[self].id or 0 end
	function Frame:GetChildren()
		return unpack(S[self].children)
	end
	function Frame:GetNumChildren() return #S[self].children end
	function Frame:GetRegions() return unpack(S[self].regions) end
	function Frame:GetNumRegions() return #S[self].regions end
	function Frame:CreateTexture(name, layer, template, sublevel)
		local t = newObject("Texture", self, name)
		S[t].layer, S[t].sublayer = layer or "ARTWORK", sublevel or 0
		return t
	end
	function Frame:CreateMaskTexture(name)
		return newObject("MaskTexture", self, name)
	end
	function Frame:CreateLine(name, layer)
		local t = newObject("Line", self, name)
		S[t].layer = layer or "ARTWORK"
		return t
	end
	function Frame:CreateFontString(name, layer, template)
		local fs = newObject("FontString", self, name)
		S[fs].layer = layer or "ARTWORK"
		local font = M.FONTS[template or ""] or M.FONTS.default
		S[fs].font = { font[1], font[2], font[3] }
		return fs
	end

	function Frame:RegisterEvent(event)
		S[self].events[event] = true
		S[self].unitFilter[event] = nil
	end
	function Frame:RegisterUnitEvent(event, ...)
		S[self].events[event] = true
		S[self].unitFilter[event] = { ... }
	end
	function Frame:UnregisterEvent(event) S[self].events[event] = nil end
	function Frame:UnregisterAllEvents() S[self].events = {} end
	function Frame:IsEventRegistered(event) return S[self].events[event] == true end

	function Frame:EnableMouse(v) S[self].mouse = v end
	function Frame:IsMouseEnabled() return S[self].mouse == true end
	function Frame:EnableMouseWheel(v) S[self].wheel = v end
	function Frame:IsMouseWheelEnabled() return S[self].wheel == true end
	function Frame:EnableKeyboard(v) S[self].keyboard = v end
	function Frame:RegisterForDrag(...) S[self].drag = { ... } end
	function Frame:SetMovable(v) S[self].movable = v end
	function Frame:IsMovable() return S[self].movable == true end
	function Frame:StartMoving() S[self].moving = true end
	function Frame:StopMovingOrSizing() S[self].moving = nil end
	function Frame:SetClampedToScreen(v) S[self].clamped = v end
	function Frame:SetToplevel() end
	function Frame:SetPropagateMouseMotion() end
	function Frame:SetPropagateKeyboardInput() end
	function Frame:SetHitRectInsets() end
	function Frame:SetFixedFrameStrata() end
	function Frame:SetFixedFrameLevel() end
	function Frame:SetDontSavePosition() end
	function Frame:SetUserPlaced() end
	function Frame:SetResizable() end
	function Frame:SetAttribute(k, v) S[self].attrs = S[self].attrs or {} S[self].attrs[k] = v end
	function Frame:GetAttribute(k) return S[self].attrs and S[self].attrs[k] end
	function Frame:SetBackdrop() end
	function Frame:SetBackdropColor() end
	function Frame:SetBackdropBorderColor() end
	function Frame:SetIgnoreParentAlpha() end

	-- Layout frames (ResizeLayoutFrame / VerticalLayoutFrame): Layout is a no-op here; tests
	-- set sizes directly when they care.
	function H.layoutMethods(frame)
		frame.Layout = function() end
		frame.MarkDirty = function() end
	end

	---------------------------------------------------------------------------
	-- Button / CheckButton / DropdownButton
	---------------------------------------------------------------------------
	function Button:SetText(text) S[self].text = text end
	function Button:GetText() return S[self].text end
	function Button:SetEnabled(v) S[self].enabled = v ~= false end
	function Button:IsEnabled() return S[self].enabled ~= false end
	function Button:Enable() S[self].enabled = true end
	function Button:Disable() S[self].enabled = false end
	function Button:Click()
		local s = S[self]
		if s.enabled == false then return end
		H.fireScript(self, "OnClick", "LeftButton", false)
	end
	function Button:RegisterForClicks() end
	local function texSetter(key)
		return function(self, path, mode) S[self][key] = path end
	end
	Button.SetNormalTexture = texSetter("normalTexture")
	Button.SetPushedTexture = texSetter("pushedTexture")
	Button.SetHighlightTexture = texSetter("highlightTexture")
	Button.SetDisabledTexture = texSetter("disabledTexture")
	Button.SetNormalAtlas = texSetter("normalAtlas")
	Button.SetPushedAtlas = texSetter("pushedAtlas")
	Button.SetHighlightAtlas = texSetter("highlightAtlas")
	function Button:GetNormalTexture() return S[self].normalTexture end
	function Button:SetNormalFontObject() end
	function Button:SetHighlightFontObject() end
	function Button:SetDisabledFontObject() end
	function Button:GetFontString() return S[self].fontString end
	function Button:SetOnClickHandler(fn) S[self].onClickHandler = fn end
	function CheckButton:SetChecked(v) S[self].checked = not not v end
	function CheckButton:GetChecked() return S[self].checked == true end

	-- DropdownButton (Menu system): the generator is stored and run when a test opens the menu.
	function DropdownButton:SetupMenu(generator) S[self].menuGenerator = generator end
	function DropdownButton:GenerateMenu() end
	function DropdownButton:CloseMenu() end
	function DropdownButton:IsMenuOpen() return false end

	-- A rootDescription that records what the generator creates.
	local function newDescription(kind, text, ...)
		local d = { kind = kind, text = text, args = { ... }, children = {} }
		local mt = {}
		mt.__index = function(_, method)
			local k = method:match("^Create(.+)$")
			if k then
				return function(self, text2, ...)
					local child = newDescription(k:lower(), text2, ...)
					table.insert(d.children, child)
					return child
				end
			end
			if method == "SetScrollMode" then
				return function(self, h) d.scrollMode = h end
			end
			if method == "SetTooltip" then
				return function(self, fn) d.tooltip = fn end
			end
			if method == "SetEnabled" or method == "SetOnEnter" or method == "SetOnLeave" or method == "AddInitializer" or method == "SetResponder" then
				return function() end
			end
			error("mock menu description: unknown method " .. tostring(method))
		end
		local proxy = setmetatable(d, mt)
		return proxy
	end
	-- Build the menu of a DropdownButton; returns the root description (kind/text/children).
	function H.openMenu(dropdown)
		local gen = S[dropdown].menuGenerator
		if not gen then return nil end
		local root = newDescription("root")
		gen(dropdown, root)
		return root
	end

	---------------------------------------------------------------------------
	-- Cooldown
	---------------------------------------------------------------------------
	function Cooldown:SetCooldown(start, duration, modRate)
		local s = S[self]
		if rawType(start) ~= "number" or rawType(duration) ~= "number" then
			error("Usage: Cooldown:SetCooldown(start, duration [, modRate])", 2)
		end
		if duration > 0 then
			s.cd = { start = start, duration = duration, modRate = modRate }
			s.durationObject = nil
			self:Show()
		else
			s.cd, s.durationObject = nil, nil
			self:Hide()
		end
	end
	function Cooldown:SetCooldownFromDurationObject(obj, clearIfZero)
		local s = S[self]
		if rawType(obj) ~= "table" then
			error("Usage: Cooldown:SetCooldownFromDurationObject(duration [, clearIfZero])", 2)
		end
		s.durationObject = obj
		s.cd = nil
		s.fromDurationCalls = (s.fromDurationCalls or 0) + 1
		self:Show()
	end
	function Cooldown:Clear()
		S[self].cd, S[self].durationObject = nil, nil
	end
	function Cooldown:GetCooldownTimes()
		local cd = S[self].cd
		if not cd then return 0, 0 end
		return cd.start * 1000, cd.duration * 1000
	end
	function Cooldown:GetCooldownDuration() local cd = S[self].cd return cd and cd.duration * 1000 or 0 end
	function Cooldown:SetReverse(v) S[self].reverse = v end
	function Cooldown:GetReverse() return S[self].reverse == true end
	function Cooldown:SetUseAuraDisplayTime(v) S[self].auraDisplayTime = v end
	function Cooldown:SetSwipeTexture(path) S[self].swipeTexture = path end
	function Cooldown:SetSwipeColor(r, g, b, a) S[self].swipeColor = { r, g, b, a } end
	function Cooldown:SetDrawEdge(v) S[self].drawEdge = v end
	function Cooldown:SetDrawBling(v) S[self].drawBling = v end
	function Cooldown:SetDrawSwipe(v) S[self].drawSwipe = v end
	function Cooldown:SetEdgeTexture(path) S[self].edgeTexture = path end
	function Cooldown:SetHideCountdownNumbers(v) S[self].hideNumbers = v end
	function Cooldown:GetHideCountdownNumbers() return S[self].hideNumbers == true end
	function Cooldown:SetCountdownFont(font) S[self].countdownFont = font end
	function Cooldown:SetCountdownAbbrevThreshold() end
	function Cooldown:SetBlingTexture() end
	function Cooldown:GetCountdownFontString()
		local s = S[self]
		if not s.countdown then
			s.countdown = self:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		end
		return s.countdown
	end

	---------------------------------------------------------------------------
	-- StatusBar
	---------------------------------------------------------------------------
	local function isAtlas(name) return H.atlases[name] ~= nil end
	function StatusBar:SetStatusBarTexture(path)
		local s = S[self]
		if not s.barTexture then
			s.barTexture = newObject("Texture", self)
		end
		local tex = s.barTexture
		if isAtlas(path) then
			tex:SetAtlas(path)
		else
			tex:SetTexture(path)
		end
	end
	function StatusBar:GetStatusBarTexture() return S[self].barTexture end
	function StatusBar:SetMinMaxValues(a, b) S[self].min, S[self].max = a, b end
	function StatusBar:GetMinMaxValues() return S[self].min or 0, S[self].max or 1 end
	function StatusBar:SetValue(v) S[self].value = v end
	function StatusBar:GetValue() return S[self].value or 0 end
	function StatusBar:SetStatusBarColor(r, g, b, a) S[self].barColor = { r, g, b, a } end
	function StatusBar:SetOrientation() end
	function StatusBar:SetReverseFill() end
	function StatusBar:SetFillStyle() end

	---------------------------------------------------------------------------
	-- EditBox / Slider / GameTooltip
	---------------------------------------------------------------------------
	function EditBox:SetText(t) S[self].text = tostring(t or "") end
	function EditBox:GetText() return S[self].text or "" end
	function EditBox:SetAutoFocus() end
	function EditBox:SetJustifyH() end
	function EditBox:SetCursorPosition() end
	function EditBox:HighlightText() end
	function EditBox:ClearFocus() end
	function EditBox:SetFocus() end
	function EditBox:SetMaxLetters() end
	function EditBox:SetNumeric() end
	function EditBox:SetFontObject() end
	function EditBox:SetMultiLine() end
	function EditBox:GetNumber() return tonumber(S[self].text) or 0 end
	function EditBox:SetEnabled(v) S[self].enabled = v end

	function Slider:SetMinMaxValues(a, b) S[self].min, S[self].max = a, b end
	function Slider:GetMinMaxValues() return S[self].min or 0, S[self].max or 1 end
	function Slider:SetValue(v) S[self].value = v end
	function Slider:GetValue() return S[self].value or 0 end
	function Slider:SetValueStep() end
	function Slider:SetObeyStepOnDrag() end
	function Slider:SetEnabled(v) S[self].enabled = v end

	function GameTooltip:SetOwner(owner, anchor) S[self].owner = owner end
	function GameTooltip:SetText(t) S[self].text = t end
	function GameTooltip:AddLine(t) S[self].lines = S[self].lines or {} table.insert(S[self].lines, t) end
	function GameTooltip:AddDoubleLine() end
	function GameTooltip:ClearLines() S[self].lines = nil end
	function GameTooltip:SetSpellByID() end
	function GameTooltip:NumLines() return S[self].lines and #S[self].lines or 0 end

	---------------------------------------------------------------------------
	-- Texture / MaskTexture / Line / FontString
	---------------------------------------------------------------------------
	function Texture:SetTexture(path)
		local s = S[self]
		s.texture, s.atlas, s.color = path, nil, nil
	end
	function Texture:GetTexture() return S[self].texture end
	function Texture:SetAtlas(name, useAtlasSize)
		-- the real client takes a secret atlas from addons (SecretArguments = AllowedWhenTainted)
		if not H.isSecret(name) and not isAtlas(name) then
			-- the client logs an error for an unknown atlas; here it is a recorded failure
			record("SetAtlas: unknown atlas '" .. tostring(name) .. "'", "Texture:SetAtlas")
		end
		local s = S[self]
		s.atlas, s.texture, s.color = name, nil, nil
	end
	function Texture:GetAtlas() return S[self].atlas end
	function Texture:SetColorTexture(r, g, b, a)
		local s = S[self]
		s.color, s.texture, s.atlas = { r, g, b, a or 1 }, nil, nil
	end
	function Texture:SetTexCoord(...) S[self].texCoord = { ... } end
	function Texture:GetTexCoord() return unpack(S[self].texCoord or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
	function Texture:SetVertexColor(r, g, b, a) S[self].vertexColor = { r, g, b, a or 1 } end
	function Texture:GetVertexColor()
		local c = S[self].vertexColor or { 1, 1, 1, 1 }
		return c[1], c[2], c[3], c[4]
	end
	function Texture:SetDesaturated(v) S[self].desaturated = not not v end
	function Texture:IsDesaturated() return S[self].desaturated == true end
	function Texture:SetBlendMode(m) S[self].blend = m end
	function Texture:GetBlendMode() return S[self].blend or "BLEND" end
	function Texture:SetRotation() end
	function Texture:SetHorizTile() end
	function Texture:SetVertTile() end
	function Texture:SetTextureSliceMargins() end
	function Texture:SetGradient() end
	function Texture:AddMaskTexture(mask)
		local s = S[self]
		s.masks = s.masks or {}
		for _, m in ipairs(s.masks) do if m == mask then return end end
		table.insert(s.masks, mask)
	end
	function Texture:RemoveMaskTexture(mask)
		local s = S[self]
		for i, m in ipairs(s.masks or {}) do
			if m == mask then table.remove(s.masks, i) return end
		end
	end
	function Texture:GetNumMaskTextures() return #(S[self].masks or {}) end
	function Texture:GetMaskTexture(i) return (S[self].masks or {})[i] end
	function Line:SetStartPoint(point, rel, x, y) S[self].startPoint = { point, rel, x, y } end
	function Line:SetEndPoint(point, rel, x, y) S[self].endPoint = { point, rel, x, y } end
	function Line:SetThickness(t) S[self].thickness = t end

	function FontString:SetText(t) S[self].text = t end
	function FontString:GetText() return S[self].text end
	function FontString:SetFormattedText(fmt, ...) S[self].text = fmt:format(...) end
	function FontString:SetFont(path, height, flags)
		S[self].font = { path, height, flags or "" }
		return true
	end
	function FontString:GetFont()
		local f = S[self].font
		return f[1], f[2], f[3]
	end
	function FontString:SetFontObject(obj)
		local f = obj and obj.font
		if f then S[self].font = { f[1], f[2], f[3] } end
	end
	function FontString:SetTextColor(r, g, b, a) S[self].textColor = { r, g, b, a } end
	function FontString:SetJustifyH(v) S[self].justifyH = v end
	function FontString:SetJustifyV(v) S[self].justifyV = v end
	function FontString:SetWordWrap() end
	function FontString:SetMaxLines() end
	function FontString:SetNonSpaceWrap() end
	function FontString:SetShadowColor() end
	function FontString:SetShadowOffset() end
	function FontString:GetStringWidth() return #(S[self].text or "") * 6 end
	function FontString:GetStringHeight() return 12 end
	function FontString:GetJustifyH() return S[self].justifyH or "CENTER" end

	---------------------------------------------------------------------------
	-- Animations
	---------------------------------------------------------------------------
	function AnimationGroup:CreateAnimation(kind, name)
		local a = newObject("Animation", nil, name)
		S[a].kind, S[a].group = kind, self
		S[self].animations = S[self].animations or {}
		table.insert(S[self].animations, a)
		return a
	end
	function AnimationGroup:Play() S[self].playing = true S[self].plays = (S[self].plays or 0) + 1 end
	function AnimationGroup:Restart() self:Play() end
	function AnimationGroup:Stop() S[self].playing = false end
	function AnimationGroup:Pause() end
	function AnimationGroup:IsPlaying() return S[self].playing == true end
	function AnimationGroup:SetLooping() end
	function AnimationGroup:SetToFinalAlpha() end
	function AnimationGroup:GetParent() return S[self].target end
	function AnimationGroup:SetScript(n, fn) S[self].scripts[n] = fn end
	function AnimationGroup:HookScript(n, fn) S[self].hooks[n] = S[self].hooks[n] or {} table.insert(S[self].hooks[n], fn) end
	function AnimationGroup:GetScript(n) return S[self].scripts[n] end
	function Animation:SetScript(n, fn) S[self].scripts[n] = fn end
	function Animation:HookScript(n, fn) S[self].hooks[n] = S[self].hooks[n] or {} table.insert(S[self].hooks[n], fn) end
	function Animation:GetScript(n) return S[self].scripts[n] end
	props(Animation, { "FromAlpha", "ToAlpha", "Duration", "Order", "StartDelay", "EndDelay", "Target", "ChildKey", "Smoothing" })
	noops(Animation, { "SetTarget", "SetOffset", "SetScale", "SetFromScale", "SetToScale", "SetOrigin", "SetDegrees" })
	function Animation:GetParent() return S[self].group end

	---------------------------------------------------------------------------
	-- Object creation
	---------------------------------------------------------------------------
	local FRAME_TYPES = { Frame = true, Button = true, CheckButton = true, DropdownButton = true, Cooldown = true,
		StatusBar = true, EditBox = true, Slider = true, GameTooltip = true, ScrollFrame = true, Model = true, ColorSelect = true }
	H.templates = {}

	function newObject(typeName, parent, name)
		if not classes[typeName] then
			error("mock: unknown widget type " .. tostring(typeName), 3)
		end
		local obj = setmetatable({}, MT[typeName])
		local isFrame = FRAME_TYPES[typeName] == true
		S[obj] = {
			type = typeName, isFrame = isFrame, name = name, parent = nil, children = {}, regions = {},
			points = {}, size = { w = 0, h = 0 }, scale = 1, alpha = 1, shown = true,
			scripts = {}, hooks = {}, events = {}, unitFilter = {}, level = 1, strata = "MEDIUM",
		}
		if isFrame then
			S[obj].level = parent and S[parent] and ((S[parent].level or 1) + 1) or 1
			H.allFrames[#H.allFrames + 1] = obj
		end
		if name then
			G[name] = obj
			if H.installed then rawset(_G, name, obj) end
		end
		attach(obj, parent)
		return obj
	end
	H.allFrames = {} -- frames are never garbage collected in the client
	H.newObject = newObject

	local function applyTemplate(frame, template)
		for t in tostring(template or ""):gmatch("[^,%s]+") do
			local fn = H.templates[t]
			if fn then
				fn(frame)
			elseif not H.ignoredTemplates[t] then
				error("mock: unknown frame template '" .. t .. "' (add it to tests/mock/wow.lua)", 3)
			end
		end
	end
	H.ignoredTemplates = { CooldownFrameTemplate = true, DialogBorderTranslucentTemplate = true,
		UIPanelCloseButton = true, InputBoxTemplate = true, BackdropTemplate = true,
		UIPanelButtonTemplate = true, UICheckButtonTemplate = true }
	H.applyTemplate = applyTemplate

	local function CreateFrame(typeName, name, parent, template)
		if not FRAME_TYPES[typeName] then
			error("CreateFrame: unknown frame type '" .. tostring(typeName) .. "'", 2)
		end
		local frame = newObject(typeName, parent, name)
		applyTemplate(frame, template)
		return frame
	end

	---------------------------------------------------------------------------
	-- Events
	---------------------------------------------------------------------------
	-- Deliver a game event to every frame registered for it (UNIT_AURA etc. honour the unit
	-- filter given to RegisterUnitEvent), in frame creation order.
	function H.fireEvent(event, ...)
		local args = { ... }
		local targets = {}
		for _, frame in ipairs(H.allFrames) do
			local s = S[frame]
			if s and s.events[event] then
				local filter = s.unitFilter[event]
				local ok = true
				if filter then
					ok = false
					for _, unit in ipairs(filter) do
						if unit == args[1] then ok = true end
					end
				end
				if ok then targets[#targets + 1] = frame end
			end
		end
		for _, frame in ipairs(targets) do
			H.fireScript(frame, "OnEvent", event, unpack(args))
		end
		return #targets
	end

	---------------------------------------------------------------------------
	-- Pools, mixins, small utilities
	---------------------------------------------------------------------------
	local Pool = {}
	Pool.__index = Pool
	function Pool:Acquire()
		local obj = table.remove(self.inactive)
		local new = false
		if not obj then
			obj = self.creationFunc(self)
			new = true
		end
		self.active[obj] = true
		return obj, new
	end
	function Pool:Release(obj)
		if self.active[obj] then
			self.active[obj] = nil
			table.insert(self.inactive, obj)
			if self.resetter then self.resetter(self, obj) end
		end
	end
	function Pool:ReleaseAll()
		for obj in pairs(self.active) do
			self:Release(obj)
		end
	end
	function Pool:GetNumActive()
		local n = 0
		for _ in pairs(self.active) do n = n + 1 end
		return n
	end
	function Pool:EnumerateActive() return pairs(self.active) end
	function G.CreateUnsecuredObjectPool(creationFunc, resetter)
		return setmetatable({ creationFunc = creationFunc, resetter = resetter, active = {}, inactive = {} }, Pool)
	end

	function G.Mixin(obj, ...)
		for i = 1, select("#", ...) do
			for k, v in pairs((select(i, ...))) do
				obj[k] = v
			end
		end
		return obj
	end
	function G.CreateFromMixins(...) return G.Mixin({}, ...) end
	local function copyTable(t, seen)
		if rawType(t) ~= "table" then return t end
		local out = {}
		for k, v in pairs(t) do out[k] = copyTable(v) end
		return out
	end
	G.CopyTable = copyTable
	function G.GenerateClosure(fn, ...)
		local bound = pack(...)
		return function(...)
			local args = {}
			for i = 1, bound.n do args[i] = bound[i] end
			local extra = pack(...)
			for i = 1, extra.n do args[bound.n + i] = extra[i] end
			return fn(unpack(args, 1, bound.n + extra.n))
		end
	end
	function G.wipe(t) for k in pairs(t) do t[k] = nil end return t end
	table.wipe = G.wipe
	G.strtrim = function(s, chars)
		chars = chars or "%s"
		return (s:gsub("^[" .. chars .. "]+", ""):gsub("[" .. chars .. "]+$", ""))
	end
	G.strsplit = function(delim, str, pieces)
		local out, pos = {}, 1
		while true do
			if pieces and #out == pieces - 1 then break end
			local a, b = str:find(delim, pos, true)
			if not a then break end
			out[#out + 1] = str:sub(pos, a - 1)
			pos = b + 1
		end
		out[#out + 1] = str:sub(pos)
		return unpack(out)
	end
	G.date = os.date
	G.format = string.format
	G.strjoin = function(d, ...) return table.concat({ ... }, d) end
	G.tinsert = table.insert
	G.tremove = table.remove
	G.floor = math.floor
	G.max = math.max
	G.min = math.min
	G.abs = math.abs
	G.type = function(v)
		local real = secrets[v]
		if real then return real end
		return rawType(v)
	end

	function G.securecallfunction(fn, ...) return protected("securecallfunction", fn, ...) end
	function G.hooksecurefunc(a, b, c)
		local target, name, hook
		if rawType(a) == "string" then
			target, name, hook = G, a, b
		else
			target, name, hook = a, b, c
		end
		local orig = target[name]
		if rawType(orig) ~= "function" then
			error("hooksecurefunc: '" .. tostring(name) .. "' is not a function", 2)
		end
		local wrapper = function(...)
			local r = pack(orig(...))
			protected("hooksecurefunc(" .. tostring(name) .. ")", hook, ...)
			return unpack(r, 1, r.n)
		end
		if target == G then G[name] = wrapper else target[name] = wrapper end
	end
	G.geterrorhandler = function() return handler end
	G.seterrorhandler = function() end
	G.CallErrorHandler = function(err) return handler(err) end
	G.GetTime = function() return H.now end
	G.GetServerTime = function() return math.floor(H.now) end
	G.InCombatLockdown = function() return H.inCombat == true end
	G.PlaySound = function() end
	G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(H.output, table.concat(parts, " "))
	end
	G.issecretvalue = function(v) return secrets[v] ~= nil end
	G.issecrettable = function(v) return secrets[v] ~= nil end
	G.canaccessvalue = function(v) return secrets[v] == nil end
	G.debugstack = debug.traceback

	-- LibStub (small, enough for LibStub("Name", true) probes and NewLibrary)
	local libs, minors = {}, {}
	G.LibStub = setmetatable({
		NewLibrary = function(_, major, minor)
			if minors[major] and minors[major] >= minor then return nil end
			local old = minors[major]
			libs[major] = libs[major] or {}
			minors[major] = minor
			return libs[major], old
		end,
		GetLibrary = function(_, major, silent)
			if not libs[major] and not silent then error("Cannot find a library instance of " .. major, 2) end
			return libs[major], minors[major]
		end,
	}, { __call = function(self, major, silent) return self:GetLibrary(major, silent) end })
	function H.registerLib(name, lib, minor) libs[name], minors[name] = lib, minor or 1 end

	-- Colors and fonts
	local ColorMixin = {}
	ColorMixin.__index = ColorMixin
	function ColorMixin:GetRGB() return self.r, self.g, self.b end
	function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
	function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
	G.CreateColor = function(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, ColorMixin) end
	G.WHITE_FONT_COLOR = G.CreateColor(1, 1, 1)
	G.DISABLED_FONT_COLOR = G.CreateColor(0.5, 0.5, 0.5)
	G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	G.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
	G.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	for name, f in pairs(M.FONTS) do
		if name ~= "default" then
			G[name] = { font = f, GetFont = function() return f[1], f[2], f[3] end }
		end
	end
	G.DEFAULT, G.NONE, G.OFF, G.DELETE, G.HEADER_COLON = "Default", "None", "Off", "Delete", ":"
	G.RESET_TO_DEFAULT = "Reset To Default"
	G.HUD_EDIT_MODE_RESET_POSITION = "Reset Position"
	G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
	G.DefaultTooltipMixin = { OnLeave = function() end, OnEnter = function() end }
	G.EDIT_MODE_MODERN_SYSTEM_MAP = {}
	G.EDIT_MODE_CLASSIC_SYSTEM_MAP = {}

	-- Enum
	G.Enum = {
		EditModeSystem = { CooldownViewer = 12, PersonalResourceDisplay = 14 },
		EditModeCooldownViewerSystemIndices = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 },
		EditModeSettingDisplayType = { Dropdown = 0, Slider = 1, Checkbox = 2 },
		PowerType = { Mana = 0 },
		CooldownViewerIconDirection = { Left = 0, Right = 1 },
	}

	-- Pixel perfect scale: 1 UI unit == 1 physical pixel at the chosen resolution.
	H.screen = { w = 1920, h = 1080 }
	H.pixelFactor = 768 / H.screen.h
	G.PixelUtil = {
		GetPixelToUIUnitFactor = function() return H.pixelFactor end,
	}

	-- Slider helpers used by LibEditMode's slider widget
	G.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
	G.CreateMinimalSliderFormatter = function(side, fmt) return { side = side, format = fmt } end

	---------------------------------------------------------------------------
	-- Templates the addon and LibEditMode instantiate
	---------------------------------------------------------------------------
	local T = H.templates
	T.ResizeLayoutFrame = function(f) H.layoutMethods(f) end
	T.VerticalLayoutFrame = function(f) H.layoutMethods(f) end
	T.EditModeSystemSettingsDialogButtonTemplate = function(f)
		f.SetOnClickHandler = function(self, fn) S[self].onClickHandler = fn end
	end
	T.EditModeSystemSettingsDialogExtraButtonTemplate = T.EditModeSystemSettingsDialogButtonTemplate
	T.EditModeSettingCheckboxTemplate = function(f)
		f.Label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
		f.Button = CreateFrame("CheckButton", nil, f)
	end
	T.EditModeSettingSliderTemplate = function(f)
		f.Label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
		local holder = CreateFrame("Frame", nil, f)
		holder.Slider = CreateFrame("Slider", nil, holder)
		holder.MinText = holder:CreateFontString()
		holder.MaxText = holder:CreateFontString()
		holder.RightText = holder:CreateFontString()
		holder.Init = function(self, value, min, max, steps, formatters)
			self.Slider:SetMinMaxValues(min, max)
			self.Slider:SetValue(value)
		end
		holder.SetValue = function(self, v) self.Slider:SetValue(v) end
		holder.SetEnabled = function(self, v) S[self].enabled = v end
		holder.SetWidth = Region.SetWidth
		f.Slider = holder
		f.OnLoad = function() end
	end
	T.WowStyle1DropdownTemplate = function() end
	T.InputScrollFrameTemplate = function(f)
		f.EditBox = CreateFrame("EditBox", nil, f)
		f.CharCount = CreateFrame("Frame", nil, f)
	end
	T.ColorSwatchTemplate = function(f)
		f.SetColorRGB = function(self, r, g, b) S[self].rgb = { r, g, b } end
	end

	---------------------------------------------------------------------------
	-- C_* namespaces and misc API
	---------------------------------------------------------------------------
	H.atlases = { ["UI-HUD-CoolDownManager-Bar"] = true, ["UI-HUD-CoolDownManager-Bar-BG"] = true,
		["UI-HUD-CoolDownManager-Mask"] = true, ["UI-HUD-CoolDownManager-IconOverlay"] = true,
		["UI-CooldownManager-OORshadow"] = true, ["UI-HUD-ActionBar-GCD-Flipbook"] = true,
		["UI-HUD-CoolDownManager-Bar-Pip"] = true }
	G.C_Texture = { GetAtlasInfo = function(name) if H.atlases[name] then return { width = 64, height = 16 } end end }

	G.C_Timer = {
		After = function(delay, fn) addTimer(delay, fn) end,
		NewTimer = function(delay, fn) local t = addTimer(delay, fn) t.Cancel = function() t.cancelled = true end return t end,
		NewTicker = function(interval, fn, iterations)
			local t = addTimer(interval, fn)
			t.ticker, t.interval, t.iterations = true, interval, iterations
			t.Cancel = function() t.cancelled = true end
			return t
		end,
	}

	-- character and addons
	H.player = { name = "Tester", realm = "Realm", talentGroup = 1 }
	G.UnitFullName = function(unit) if unit == "player" then return H.player.name, H.player.realm end end
	G.GetRealmName = function() return H.player.realm end
	G.UnitExists = function(unit) return H.units[unit] ~= nil end
	G.UnitCanAssist = function(_, unit) return H.units[unit] ~= nil and H.units[unit].friendly == true end
	G.UnitPowerType = function() return 0, "MANA" end
	H.units = { player = { friendly = true } }
	G.C_SpecializationInfo = {
		GetActiveSpecGroup = function() return H.player.talentGroup end,
		GetNumSpecGroups = function() return 2 end,
	}
	H.loadedAddons = { Blizzard_CooldownViewer = true, Blizzard_EditMode = true }
	G.C_AddOns = { IsAddOnLoaded = function(name) return H.loadedAddons[name] == true end }
	G.C_EditMode = { GetLayouts = function() return { activeLayout = H.activeLayoutIndex, layouts = H.layouts } end }
	H.layouts = {}
	H.activeLayoutIndex = 1 -- 1 = "Modern"

	-- spells
	H.spells = {}
	G.C_Spell = {
		GetSpellName = function(id) local s = H.spells[id] return s and s.name end,
		IsSpellHelpful = function(id) local s = H.spells[id] return s and s.helpful == true or false end,
		SpellHasRange = function(id) local s = H.spells[id] return s and s.hasRange == true or false end,
		IsSpellUsable = function(id)
			local s = H.spells[id]
			if s and s.usable == false then return false, s.notEnoughMana == true end
			return true, false
		end,
		GetSpellPowerCost = function(id) local s = H.spells[id] return s and s.powerCost or nil end,
		GetSpellCooldownDuration = function(id)
			return { spellCooldown = id }
		end,
	}
	G.C_Item = { GetItemSpell = function() return nil end, GetItemInfoInstant = function() return nil end }
	G.FindBaseSpellByID = function(id) return id end
	G.GetBindingKey = function() return nil end
	G.GetActionInfo = function() return nil end
	G.GetInventoryItemID = function() return nil end
	G.IsAltKeyDown = function() return false end
	G.IsShiftKeyDown = function() return false end

	-- auras: H.auras[unit][instanceID] = aura table
	H.auras = { player = {}, target = {} }
	local nextInstance = 500
	function H.addAura(unit, aura)
		nextInstance = nextInstance + 1
		aura.auraInstanceID = aura.auraInstanceID or nextInstance
		H.auras[unit] = H.auras[unit] or {}
		H.auras[unit][aura.auraInstanceID] = aura
		return aura
	end
	function H.removeAura(unit, instanceID)
		H.auras[unit][instanceID] = nil
	end
	local function bySpell(unit, spellID)
		for _, aura in pairs(H.auras[unit] or {}) do
			if aura.spellId == spellID and not aura.hiddenFromLookup then return aura end
		end
	end
	G.C_UnitAuras = {
		GetPlayerAuraBySpellID = function(id) return bySpell("player", id) end,
		GetUnitAuraBySpellID = function(unit, id) return bySpell(unit, id) end,
		GetAuraDataByAuraInstanceID = function(unit, instance)
			if secrets[instance] then error("secret aura instance") end
			return H.auras[unit] and H.auras[unit][instance]
		end,
		GetAuraDuration = function(unit, instance)
			if secrets[instance] then error("bad argument: secret aura instance") end
			local aura = H.auras[unit] and H.auras[unit][instance]
			if not aura then return nil end
			return { auraDuration = true, unit = unit, instance = instance }
		end,
		IsAuraFilteredOutByInstanceID = function(unit, instance, filter)
			if secrets[instance] then error("secret aura instance") end
			local aura = H.auras[unit] and H.auras[unit][instance]
			if not aura then return true end
			if filter == "HARMFUL" then return not aura.isHarmful end
			return false
		end,
		GetRefreshCarryOverDuration = function() return 0 end,
	}

	-- Menu / Settings (Blizzard's)
	H.menuModifiers = {}
	G.Menu = { ModifyMenu = function(tag, fn) H.menuModifiers[tag] = fn end }
	H.settingsCategories = {}
	G.Settings = {
		RegisterCanvasLayoutCategory = function(panel, name)
			local c = { panel = panel, name = name, GetID = function() return name end }
			table.insert(H.settingsCategories, c)
			return c
		end,
		RegisterAddOnCategory = function() end,
		OpenToCategory = function(id) H.openedCategory = id end,
	}

	-- Slash commands
	G.SlashCmdList = {}

	-- Color picker
	G.ColorPickerFrame = {
		rgb = { 1, 1, 1 }, alpha = 1,
		SetupColorPickerAndShow = function(self, info) self.info = info end,
		GetColorRGB = function(self) return self.rgb[1], self.rgb[2], self.rgb[3] end,
		GetColorAlpha = function(self) return self.alpha end,
		SetColorRGB = function(self, r, g, b) self.rgb = { r, g, b } end,
	}

	---------------------------------------------------------------------------
	-- EventRegistry
	---------------------------------------------------------------------------
	local registry = { callbacks = {} }
	G.EventRegistry = {
		RegisterCallback = function(_, event, fn, owner)
			registry.callbacks[event] = registry.callbacks[event] or {}
			table.insert(registry.callbacks[event], { fn = fn, owner = owner })
		end,
		RegisterFrameEventAndCallback = function(_, event, fn, owner)
			registry.callbacks[event] = registry.callbacks[event] or {}
			table.insert(registry.callbacks[event], { fn = fn, owner = owner })
		end,
		TriggerEvent = function(_, event, ...)
			for _, cb in ipairs(registry.callbacks[event] or {}) do
				protected("EventRegistry " .. event, cb.fn, cb.owner, ...)
			end
		end,
	}
	H.registry = registry

	---------------------------------------------------------------------------
	-- Root frame
	---------------------------------------------------------------------------
	UIParent = newObject("Frame", nil, "UIParent")
	S[UIParent].root = true
	S[UIParent].size = { w = H.screen.w, h = H.screen.h }
	S[UIParent].scale = H.pixelFactor
	H.UIParent = UIParent
	G.CreateFrame = CreateFrame
	G.UIParent = UIParent
	G.WorldFrame = newObject("Frame", nil, "WorldFrame")
	S[G.WorldFrame].root = true
	S[G.WorldFrame].size = { w = H.screen.w, h = H.screen.h }
	G.GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
	G.SettingsTooltip = CreateFrame("GameTooltip", "SettingsTooltip", UIParent)

	-- Make GetFrameLevel on the root and children consistent
	S[UIParent].level = 0

	---------------------------------------------------------------------------
	-- Install: replace the global table contents; strict on unknown globals.
	---------------------------------------------------------------------------
	local seenMissing = {}
	function H.install()
		for k in pairs(_G) do
			if not PRISTINE[k] then rawset(_G, k, nil) end
		end
		for k, v in pairs(G) do
			rawset(_G, k, v)
		end
		rawset(_G, "_G", _G)
		-- the type() replacement is used by the addon only; harness code keeps rawType
		setmetatable(_G, {
			__index = function(_, key)
				if OPTIONAL[key] == true then return nil end
				for _, pattern in ipairs(OPTIONAL_PATTERNS) do
					if rawType(key) == "string" and key:find(pattern) then return nil end
				end
				if seenMissing[key] then error("mock: unknown global '" .. tostring(key) .. "'", 2) end
				seenMissing[key] = true
				record("unknown global '" .. tostring(key) .. "' (add it to tests/mock/wow.lua)\n" .. debug.traceback("", 2))
				error("mock: unknown global '" .. tostring(key) .. "'", 2)
			end,
		})
		H.installed = true
	end
	function H.uninstall()
		setmetatable(_G, nil)
		for k in pairs(_G) do
			if not PRISTINE[k] then rawset(_G, k, nil) end
		end
		H.installed = false
	end

	H.G = G
	return H
end

M.FONTS = {
	default = { "Fonts\\FRIZQT__.TTF", 12, "" },
	GameFontHighlightMedium = { "Fonts\\FRIZQT__.TTF", 14, "" },
	GameFontHighlightHugeOutline = { "Fonts\\FRIZQT__.TTF", 20, "OUTLINE" },
	GameFontHighlightOutline = { "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" },
	NumberFontNormal = { "Fonts\\ARIALN.TTF", 14, "OUTLINE" },
	NumberFontNormalSmall = { "Fonts\\ARIALN.TTF", 12, "OUTLINE" },
}

return M
