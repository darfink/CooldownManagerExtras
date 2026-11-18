-- Edit Mode settings: registration, the section accordion, panel placement and scrolling.
local T = ...

local CooldownViewer = 12
local PRDSystem = 14
local INDICES = { Essential = 1, Utility = 2, BuffIcon = 3, BuffBar = 4 }

local function names(list)
	local out = {}
	for _, setting in ipairs(list) do out[#out + 1] = setting.name end
	return out
end
local function hasName(list, wanted)
	for _, setting in ipairs(list) do
		if setting.name and setting.name:sub(-#wanted) == wanted then return true end
	end
	return false
end

T.test("Settings:Register adds settings for each cooldown viewer and the PRD", function(H, T)
	local lib = H.ns.LibEditMode
	for key, index in pairs(INDICES) do
		local list = lib.subSystemSettings[CooldownViewer] and lib.subSystemSettings[CooldownViewer][index]
		T.truthy(list and #list > 5, key .. " has registered settings")
		T.eq(list[1].name, "Cooldown Manager Extras", key .. " starts with our header divider")
		for _, want in ipairs({ "Grow From", "Attach To", "Font" }) do
			T.truthy(hasName(list, want), key .. " lists '" .. want .. "'")
		end
		local info = H.CMP.byKey[key]
		T.eq(info.systemID, CooldownViewer)
		T.eq(info.subSystemID, index)
	end
	local prd = lib.systemSettings[PRDSystem]
	T.truthy(prd and #prd > 5, "PRD has registered settings")
	T.truthy(hasName(prd, "Five-Second Rule"))
	T.truthy(hasName(prd, "Attach To"))
end)

T.test("Tracked Bars (not Essential) get bar settings", function(H, T)
	local lib = H.ns.LibEditMode
	T.truthy(hasName(lib.subSystemSettings[CooldownViewer][INDICES.BuffBar], "Bar Style"))
	T.falsy(hasName(lib.subSystemSettings[CooldownViewer][INDICES.Essential], "Bar Style"))
	T.truthy(hasName(lib.subSystemSettings[CooldownViewer][INDICES.BuffIcon], "Close Gaps"))
	T.falsy(hasName(lib.subSystemSettings[CooldownViewer][INDICES.Essential], "Close Gaps"))
end)

T.test("every registered setting has a working getter, and set(default) does not raise", function(H, T)
	local lib = H.ns.LibEditMode
	local Type = lib.SettingType
	local count = 0
	local function check(list, label)
		for _, setting in ipairs(list) do
			if setting.kind ~= Type.Divider then
				T.eq(type(setting.get), "function", label .. " / " .. tostring(setting.name) .. " get")
				T.eq(type(setting.set), "function", label .. " / " .. tostring(setting.name) .. " set")
				setting.get("Modern")
				if setting.kind ~= Type.ColorPicker and setting.kind ~= Type.Expander then
					setting.set("Modern", setting.default, false)
				end
				count = count + 1
			end
		end
	end
	for key, index in pairs(INDICES) do
		check(lib.subSystemSettings[CooldownViewer][index], key)
	end
	check(lib.systemSettings[PRDSystem], "PRD")
	T.truthy(count > 50, "checked a good number of settings, got " .. count)
end)

T.test("selecting a viewer in Edit Mode builds our panel with that viewer's settings", function(H, T)
	H.enterEditMode()
	H.select("Essential")
	local ext = H.extension()
	T.truthy(ext:IsShown())
	T.eq(ext.systemID, CooldownViewer)
	T.eq(ext.subSystemID, INDICES.Essential)
	T.truthy(H.widget("Grow From"))
	T.falsy(H.widget("Bar Style"))
	H.select("BuffBar")
	T.eq(ext.subSystemID, INDICES.BuffBar)
	T.truthy(H.widget("Bar Style"))
	T.eq(H.CMP.selected, H.viewers.BuffBar, "CMP tracks the selected frame")
end)

T.test("selecting the Personal Resource Display shows its settings", function(H, T)
	H.enterEditMode()
	H.select(H.viewers.PRD)
	local ext = H.extension()
	T.eq(ext.systemID, PRDSystem)
	T.truthy(H.widget("Five-Second Rule"))
end)

---------------------------------------------------------------------------
-- Section accordion
---------------------------------------------------------------------------

local function expanded(H, key, id)
	local value = H.CMP.db.ui[key .. "." .. id]
	return value == true
end

T.test("sections start collapsed", function(H, T)
	H.enterEditMode()
	H.select("BuffBar")
	T.falsy(H.widget("Icon Style"):IsShown(), "Icon content hidden")
	T.falsy(H.widget("Bar Style"):IsShown(), "Bar content hidden")
	T.falsy(H.widget("Font"):IsShown(), "Text content hidden")
end)

T.test("expanding a section shows its settings", function(H, T)
	H.enterEditMode()
	H.select("BuffBar")
	H.clickExpander("Bar")
	T.truthy(expanded(H, "BuffBar", "bars"))
	T.truthy(H.widget("Bar Style"):IsShown())
	T.falsy(H.widget("Icon Style"):IsShown())
end)

T.test("expanding one section collapses the others for that frame", function(H, T)
	local CMP = H.CMP
	H.enterEditMode()
	H.select("BuffBar")
	H.clickExpander("Icon")
	T.truthy(expanded(H, "BuffBar", "icons"))
	H.clickExpander("Bar")
	T.truthy(expanded(H, "BuffBar", "bars"), "Bar is open")
	T.eq(CMP.db.ui["BuffBar.icons"], false, "Icon was closed")
	T.falsy(expanded(H, "BuffBar", "text"))
	-- the panel was rebuilt: only the open section's settings show
	T.truthy(H.widget("Bar Style"):IsShown())
	T.falsy(H.widget("Icon Style"):IsShown())
	H.clickExpander("Text")
	T.truthy(expanded(H, "BuffBar", "text"))
	T.eq(CMP.db.ui["BuffBar.bars"], false)
	T.eq(CMP.db.ui["BuffBar.icons"], false)
	T.truthy(H.widget("Font"):IsShown())
	T.falsy(H.widget("Bar Style"):IsShown())
end)

T.test("the accordion is per frame: opening a section on one frame leaves another's alone", function(H, T)
	local CMP = H.CMP
	H.enterEditMode()
	H.select("Essential")
	H.clickExpander("Text")
	T.truthy(expanded(H, "Essential", "text"))
	H.select("BuffBar")
	H.clickExpander("Bar")
	H.clickExpander("Icon")
	T.truthy(expanded(H, "Essential", "text"), "Essential's open section is untouched")
	T.truthy(expanded(H, "BuffBar", "icons"))
	T.falsy(expanded(H, "BuffBar", "bars"))
end)

T.test("collapsing the open section leaves every section closed", function(H, T)
	H.enterEditMode()
	H.select("BuffBar")
	H.clickExpander("Bar")
	H.clickExpander("Bar")
	T.falsy(expanded(H, "BuffBar", "bars"))
	T.falsy(H.widget("Bar Style"):IsShown())
end)

T.test("accordion state survives re-selecting the frame", function(H, T)
	H.enterEditMode()
	H.select("BuffBar")
	H.clickExpander("Bar")
	H.select("Essential")
	H.select("BuffBar")
	T.truthy(H.widget("Bar Style"):IsShown())
	T.truthy(expanded(H, "BuffBar", "bars"))
end)

T.test("panel rebuild after a section change settles (no rebuild loop)", function(H, T)
	local ext
	H.enterEditMode()
	H.select("BuffBar")
	ext = H.extension()
	local updates = 0
	hooksecurefunc(ext, "Update", function() updates = updates + 1 end)
	H.clickExpander("Icon")
	updates = 0
	local widget = H.widget("Bar")
	widget:GetScript("OnMouseUp")(widget)
	-- run the timers by hand to see how many rebuilds one click causes
	local drained, rounds = H.flush(50)
	T.truthy(drained, "timers kept re-queuing for 50 rounds: the panel rebuild loops")
	T.truthy(updates <= 2, "one click rebuilt the panel " .. updates .. " times")
	T.eq(H.pendingTimers(), 0)
end)

T.test("rapid clicks on different sections coalesce into a bounded number of rebuilds", function(H, T)
	H.enterEditMode()
	H.select("BuffBar")
	local updates = 0
	hooksecurefunc(H.extension(), "Update", function() updates = updates + 1 end)
	-- three clicks inside one frame: the headers are only redrawn by the deferred rebuild
	for _, name in ipairs({ "Icon", "Bar", "Text" }) do
		local w = H.widget(name)
		w:GetScript("OnMouseUp")(w)
	end
	local drained = H.flush(50)
	T.truthy(drained, "rebuild loops")
	T.truthy(updates <= 2, "too many rebuilds: " .. updates)
	-- last click wins
	T.truthy(expanded(H, "BuffBar", "text"))
	T.falsy(expanded(H, "BuffBar", "bars"))
	T.falsy(expanded(H, "BuffBar", "icons"))
end)

T.test("a saved state with several sections open converges to one when the panel is built", function(H, T)
	-- older versions allowed several open sections; building the panel must settle on one
	H.CMP.db.ui["BuffBar.icons"] = true
	H.CMP.db.ui["BuffBar.bars"] = true
	H.CMP.db.ui["BuffBar.text"] = true
	H.enterEditMode()
	H.select("BuffBar")
	local drained = H.flush(50)
	T.truthy(drained, "rebuild loops")
	local open = 0
	for _, id in ipairs({ "icons", "bars", "text" }) do
		if H.CMP.db.ui["BuffBar." .. id] then open = open + 1 end
	end
	T.eq(open, 1, "sections left open")
end)

---------------------------------------------------------------------------
-- Panel placement (Settings:PlacePanel)
---------------------------------------------------------------------------

-- Screen: 1920 x 1080 UI units; pixel-perfect scale, so 1 unit = 1 pixel.
local function setup(H, dialog, panel)
	H.enterEditMode()
	H.select("Essential")
	H.placeDialog(dialog.left, dialog.top, dialog.width, dialog.height)
	local ext = H.extension()
	ext:SetSize(panel.width, panel.height)
	H.CMP.Settings.panelSide = nil
	H.CMP.Settings.panelScroll = 0
	H.CMP.Settings.panelPlaced = false
	return ext
end
local function anchor(ext)
	local point, rel, relPoint, x, y = ext:GetPoint(1)
	return point, rel, relPoint, x, y
end

T.test("PlacePanel: below the dialog when there is room", function(H, T)
	local ext = setup(H, { left = 800, top = 900, width = 380, height = 300 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	local point, rel, relPoint, x, y = anchor(ext)
	T.eq(H.CMP.Settings.panelSide, "below")
	T.eq(point, "TOP")
	T.eq(rel, _G.EditModeSystemSettingsDialog)
	T.eq(relPoint, "BOTTOM")
	T.eq(y, 0)
end)

T.test("PlacePanel: moves to the left of the dialog when below does not fit", function(H, T)
	-- dialog bottom at 300: only 300 px below, panel needs 500; room on the left is wide and tall
	local ext = setup(H, { left = 800, top = 700, width = 380, height = 400 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	local point, rel, relPoint = anchor(ext)
	T.eq(H.CMP.Settings.panelSide, "left")
	T.eq(point, "TOPRIGHT")
	T.eq(relPoint, "TOPLEFT")
	T.eq(rel, _G.EditModeSystemSettingsDialog)
end)

T.test("PlacePanel: moves to the right when neither below nor left fit", function(H, T)
	-- dialog hugging the left edge: no room on the left; below is too short
	local ext = setup(H, { left = 50, top = 700, width = 380, height = 400 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	local point, _, relPoint = anchor(ext)
	T.eq(H.CMP.Settings.panelSide, "right")
	T.eq(point, "TOPLEFT")
	T.eq(relPoint, "TOPRIGHT")
end)

T.test("PlacePanel: keeps the side it chose while it still fits (no jumping)", function(H, T)
	local ext = setup(H, { left = 800, top = 700, width = 380, height = 400 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	T.eq(H.CMP.Settings.panelSide, "left")
	-- now there would be room below, but left still fits
	H.placeDialog(800, 1000, 380, 300)
	H.CMP.Settings:PlacePanel()
	T.eq(H.CMP.Settings.panelSide, "left")
	-- entering Edit Mode again starts below
	H.exitEditMode()
	H.enterEditMode()
	T.eq(H.CMP.Settings.panelSide, nil)
	H.CMP.Settings:PlacePanel()
	T.eq(H.CMP.Settings.panelSide, "below")
end)

T.test("PlacePanel: a panel that fits needs no scrolling", function(H, T)
	setup(H, { left = 800, top = 900, width = 380, height = 300 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	T.eq(H.CMP.Settings.panelOverflow, 0)
	H.wheel(-1)
	T.eq(H.CMP.Settings.panelScroll, 0, "wheel does nothing when nothing overflows")
end)

T.test("PlacePanel: taller than every side picks the side with the most room and scrolls", function(H, T)
	-- panel 1500 tall on a 1080 screen. below: 300 px; left: 700 px; right: 700 px; left wins (first of equals)
	local ext = setup(H, { left = 800, top = 700, width = 380, height = 400 }, { width = 370, height = 1500 })
	H.CMP.Settings:PlacePanel()
	T.truthy(H.CMP.Settings.panelOverflow > 0)
	T.eq(H.CMP.Settings.panelSide, "left")
	local es = ext:GetEffectiveScale()
	T.near(H.CMP.Settings.panelOverflow, 1500 * es - 700 * es, 1e-6, "overflow in screen pixels")
end)

T.test("PlacePanel: mouse wheel scrolls in steps and clamps to [0, overflow]", function(H, T)
	local ext = setup(H, { left = 800, top = 700, width = 380, height = 400 }, { width = 370, height = 1500 })
	local Settings = H.CMP.Settings
	Settings:PlacePanel()
	local es = ext:GetEffectiveScale()
	local overflow = Settings.panelOverflow
	T.truthy(overflow > 60, "overflow is more than one notch (" .. overflow .. ")")
	T.eq(Settings.panelScroll, 0)
	-- scrolling up at the top stays at 0
	H.wheel(1)
	T.eq(Settings.panelScroll, 0, "clamped at the top")
	-- one notch down
	H.wheel(-1)
	T.eq(Settings.panelScroll, 60)
	local _, _, _, _, y = ext:GetPoint(1)
	T.near(y, 60 / es, 1e-6, "the anchor moves by the scroll amount (in the panel's own units)")
	-- many notches down clamp at overflow
	for _ = 1, 100 do H.wheel(-1) end
	T.near(Settings.panelScroll, overflow, 1e-6, "clamped at the bottom")
	_, _, _, _, y = ext:GetPoint(1)
	T.near(y, overflow / es, 1e-6)
	-- and back up
	for _ = 1, 100 do H.wheel(1) end
	T.eq(Settings.panelScroll, 0)
	_, _, _, _, y = ext:GetPoint(1)
	T.eq(y, 0)
end)

T.test("PlacePanel: scroll position is re-clamped when the room grows", function(H, T)
	local ext = setup(H, { left = 800, top = 700, width = 380, height = 400 }, { width = 370, height = 1500 })
	local Settings = H.CMP.Settings
	Settings:PlacePanel()
	for _ = 1, 100 do H.wheel(-1) end
	local before = Settings.panelScroll
	T.truthy(before > 0)
	-- the panel shrinks (a section collapsed): the old scroll offset no longer fits
	ext:SetSize(370, 900)
	Settings:PlacePanel()
	T.truthy(Settings.panelScroll < before)
	T.truthy(Settings.panelScroll >= 0)
	T.near(Settings.panelScroll, Settings.panelOverflow, 1e-6)
	-- and it shrinks to something that fits: scroll resets to 0
	ext:SetSize(370, 400)
	Settings:PlacePanel()
	T.eq(Settings.panelScroll, 0)
	T.eq(Settings.panelOverflow, 0)
end)

T.test("PlacePanel: re-runs when the panel's Layout or the dialog's size changes", function(H, T)
	local ext = setup(H, { left = 800, top = 900, width = 380, height = 300 }, { width = 370, height = 500 })
	H.CMP.Settings:PlacePanel()
	T.eq(H.CMP.Settings.panelSide, "below")
	-- the panel grows (e.g. a section opened) and no longer fits below: Layout hook re-places it
	ext:SetSize(370, 900)
	ext:Layout()
	T.eq(H.CMP.Settings.panelSide, "left")
	-- the dialog grows tall: OnSizeChanged hook re-places it
	H.placeDialog(800, 900, 380, 300)
	H.flush()
	T.eq(H.CMP.Settings.panelSide, "left", "still fits on the left")
end)

T.test("PlacePanel: does nothing while the dialog has no position", function(H, T)
	H.enterEditMode()
	H.select("Essential")
	H.raw.ClearAllPoints(_G.EditModeSystemSettingsDialog)
	H.CMP.Settings:PlacePanel() -- must not raise
end)

T.test("panel collapse toggle hides and restores our panel", function(H, T)
	H.enterEditMode()
	H.select("Essential")
	local Settings = H.CMP.Settings
	T.truthy(Settings.toggle:IsShown(), "toggle button shows while the dialog edits one of our frames")
	Settings.toggle:GetScript("OnClick")(Settings.toggle)
	T.truthy(Settings.collapsed)
	T.falsy(H.extension():IsShown())
	Settings.toggle:GetScript("OnClick")(Settings.toggle)
	T.falsy(Settings.collapsed)
	T.truthy(H.extension():IsShown())
end)

local function hexPicker(H)
	local function scripted()
		local o = { hooks = {} }
		function o:HookScript(name, fn) self.hooks[name] = self.hooks[name] or {} table.insert(self.hooks[name], fn) end
		function o:Run(name, ...) for _, fn in ipairs(self.hooks[name] or {}) do fn(self, ...) end end
		return o
	end
	local frame = scripted()
	local picker = { rgb = { 1, 1, 1 } }
	local box = scripted()
	local okay = scripted()
	frame.Content = { HexBox = box, ColorPicker = picker }
	frame.Footer = { OkayButton = okay }
	function picker:SetColorRGB(r, g, b)
		self.rgb = { r, g, b }
		if frame.info and frame.info.swatchFunc then frame.info.swatchFunc() end
	end
	function frame:GetColorRGB() return picker.rgb[1], picker.rgb[2], picker.rgb[3] end
	function frame:GetColorAlpha() return 1 end
	function frame:SetupColorPickerAndShow(info) self.info = info end
	function box:GetText() return self.text end
	function box:SetText(text) self.text = text end
	function box:OnEnterPressed()
		local t = self.text
		while #t < 6 do t = t .. t end
		self.text = t:sub(1, 6)
		picker:SetColorRGB(_G.CreateColorFromRGBAHexString(self.text .. "ff"):GetRGB())
	end
	_G.ColorPickerFrame = frame
	_G.CreateColorFromRGBAHexString = function(hex)
		local n = function(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
		return H.G.CreateColor(n(1), n(3), n(5), n(7))
	end
	return frame, box, okay
end

T.test("settings: a typed hex color applies without Enter", function(H, T)
	local frame, box, okay = hexPicker(H)
	local got
	H.CMP:OpenColorPicker({ r = 1, g = 1, b = 1, swatchFunc = function() got = { frame:GetColorRGB() } end })
	box.text = "057a"
	box:Run("OnTextChanged", true)
	T.falsy(got, "four digits: not yet")
	box.text = "057aff"
	box:Run("OnTextChanged", true)
	T.near(got[3], 1, 0.001)
	T.near(got[2], 0x7a / 255, 0.001, "six digits apply at once")
	got = nil
	box.text = "fff"
	okay:Run("PreClick")
	T.near(got[1], 1, 0.001, "a short value applies on Okay, like Enter")
	-- another add-on's picker is left alone
	got = nil
	frame:SetupColorPickerAndShow({ swatchFunc = function() got = true end })
	box.text = "123456"
	box:Run("OnTextChanged", true)
	T.falsy(got, "not ours")
end)
