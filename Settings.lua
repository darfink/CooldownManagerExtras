local _, ns = ...
local CMP = ns.CMP

-- Settings shown in Edit Mode, in a panel attached right under Blizzard's own settings
-- dialog for each cooldown viewer and the Personal Resource Display (LibEditMode). Values
-- are stored per Edit Mode layout, like Blizzard's own settings.
--
-- Panel order follows how people set things up: where it grows, what it's attached to,
-- then the look (collapsed sections, so the panel stays short).

local Settings = {}
CMP.Settings = Settings

local LEM = CMP.LEM
local Type = LEM.SettingType

local function Option(text, value)
	return { text = text, value = value }
end

-- Settings that show, hide or relabel other settings. Only these rebuild the panel;
-- rebuilding on every change would drop an active slider drag.
local PRDBarSettings, BuffBarSettings, SpacingSettings
local STRUCTURAL = { align = true, sharedBorders = true, attachTo = true, style = true, barStyle = true, matchWidth = true, keybinds = true }

-- Settings that only apply because of the setting above them are indented under it, with a
-- thin blue guide line (our accent color) so they read as one group.
local INDENT = "  |TInterface\\Buttons\\WHITE8X8:18:2:0:0:8:8:0:8:0:8:79:163:255|t  "

local function Bind(info, field, setting)
	setting.default = CMP.defaults[field]
	setting.get = function(layoutName)
		return CMP:Get(info.key, field, layoutName)
	end
	setting.set = function(layoutName, value)
		CMP:Set(info.key, field, value, layoutName)
		CMP.Session:Touch(info.key)
		if STRUCTURAL[field] then
			CMP:RefreshDialog(info)
		end
	end
	return setting
end

-- Gap, offset and size sliders use Edit Mode's own units (what Edit Mode's position
-- numbers use). Border sizes are physical screen pixels.
local function Units(value)
	return ("%d"):format(value)
end

local function Pixels(value)
	return ("%d px"):format(value)
end

local function Any(...)
	local checks = { ... }
	return function(layoutName)
		for _, check in ipairs(checks) do
			if check(layoutName) then
				return true
			end
		end
		return false
	end
end

local function GeometryLocked(info)
	return function()
		return CMP.Layout:IsGeometryLocked(info)
	end
end

local function NotAttached(info)
	return function(layoutName)
		local target = CMP:Get(info.key, "attachTo", layoutName)
		return CMP.byKey[target] == nil or target == info.key
	end
end

local function NotSquare(info)
	return function(layoutName)
		return CMP:Get(info.key, "style", layoutName) ~= "square" or CMP.Masque:IsActive(info)
	end
end

local function StyleLocked(info)
	return function()
		return CMP.Layout:IsGeometryLocked(info) or CMP.Masque:IsActive(info)
	end
end

local function MatchOff(info)
	return function(layoutName)
		return CMP:Get(info.key, "matchWidth", layoutName) == "off"
	end
end

local LOCKED_NOTE = "\n\n|cffffd100Needs the frame to be moved once in Edit Mode first|r (frames in their default position are placed by Blizzard)."
local MASQUE_NOTE = "\n\nWhen Masque skins these icons (with Masque Blizzard Bars), Masque owns their look: change it in /masque. Layout, size, fonts and per-spell borders still work."
local SPELL_NOTE = "\n\nTip: right-click a spell in the Cooldown Settings window to give just that spell its own border."

-- A collapsible section. Returns a check that is true while the section is collapsed.
-- Only one section per frame is open at a time (opening one closes the others), so the
-- panel stays short enough to fit on the screen.
local sectionKeys = {} -- info.key -> { uiKey = true }
local rebuildPending

local function RebuildPanelSoon()
	if rebuildPending then
		return
	end
	rebuildPending = true
	C_Timer.After(0, function()
		rebuildPending = nil
		local extension = LEM.internal and LEM.internal.extension
		if extension and extension:IsShown() and extension.systemID then
			extension:Update(extension.systemID, extension.subSystemID) -- redraws the other headers' arrows
		end
	end)
end

local function Section(info, list, id, name, expandedByDefault)
	local uiKey = info.key .. "." .. id
	sectionKeys[info.key] = sectionKeys[info.key] or {}
	sectionKeys[info.key][uiKey] = expandedByDefault == true
	local function IsExpanded()
		local value = CMP.db.ui[uiKey]
		if value == nil then
			return expandedByDefault == true
		end
		return value
	end
	table.insert(list, {
		kind = Type.Expander,
		name = name,
		default = expandedByDefault == true,
		get = IsExpanded,
		set = function(_, expanded)
			CMP.db.ui[uiKey] = expanded and true or false
			if not expanded then
				return
			end
			local closed = false
			for other, otherDefault in pairs(sectionKeys[info.key]) do
				local open = CMP.db.ui[other]
				if open == nil then
					open = otherDefault
				end
				if other ~= uiKey and open then
					CMP.db.ui[other] = false
					closed = true
				end
			end
			if closed then
				RebuildPanelSoon()
			end
		end,
	})
	return function()
		return not IsExpanded()
	end
end

---------------------------------------------------------------------------

local function GrowthSettings(info, list)
	local noun = info.kind == "bars" and "bars" or "icons"
	table.insert(list, Bind(info, "align", {
		kind = Type.Dropdown,
		name = "Grow From",
		desc = "Where new " .. noun .. " appear when you track more, and which point of the frame stays put.\n\n"
			.. "Center: the row stays centered on its spot and grows to both sides.\n"
			.. "Left / Right (Top / Bottom): that edge stays put.\n"
			.. "Default: Blizzard's behavior (follows Icon Direction).\n\n"
			.. "In Edit Mode, arrows next to the frame show the direction." .. LOCKED_NOTE,
		disabled = GeometryLocked(info),
		values = function()
			local horizontal = info.frame and info.frame.isHorizontal ~= false
			local default
			if horizontal then
				default = info.frame.layoutFramesGoingRight ~= false and "Left" or "Right"
			else
				default = info.frame and info.frame.layoutFramesGoingUp and "Bottom" or "Top"
			end
			return {
				Option(("%s (%s)"):format(DEFAULT or "Default", default), "native"),
				Option(horizontal and "Left" or "Top", "start"),
				Option("Center", "center"),
				Option(horizontal and "Right" or "Bottom", "end"),
			}
		end,
	}))
	-- Changing it by hand keeps the frame where it is: the new fixed point is recorded first.
	local growSetting = list[#list]
	local baseSet = growSetting.set
	growSetting.set = function(layoutName, value)
		if (layoutName == nil or layoutName == CMP.activeLayout) and info.frame then
			CMP.Anchors:RecordPin(info, value)
		end
		baseSet(layoutName, value)
	end

	if info.buffs then
		-- Left / Center / Right always pack the active buffs from that point; only Default
		-- (Blizzard's layout) has a choice.
		table.insert(list, Bind(info, "collapse", {
			kind = Type.Checkbox,
			name = "Close Gaps",
			desc = "Blizzard leaves an empty slot for every tracked buff that isn't active. This closes those gaps so the active ones stay together.\n\nLeft, Center and Right always do this." .. LOCKED_NOTE,
			disabled = GeometryLocked(info),
			hidden = function(layoutName)
				return CMP:Get(info.key, "align", layoutName) ~= "native"
			end,
		}))
	end
end

local function AttachSettings(info, list)
	table.insert(list, Bind(info, "attachTo", {
		kind = Type.Dropdown,
		name = "Attach To",
		desc = "Keep this frame attached to another one. It follows that frame when it moves, resizes or hides.\n\n"
			.. "Easiest: in Edit Mode, drag this frame against another one until it snaps. That attaches it. Drag it away to detach.\n\n"
			.. "Arrow keys change the gap and offset while attached." .. LOCKED_NOTE,
		values = function()
			local values = { Option("Nothing (Edit Mode)", "none") }
			for _, other in ipairs(CMP.frameInfos) do
				if other ~= info and other.frame then
					table.insert(values, Option(CMP:GetName(other.key), other.key))
				end
			end
			return values
		end,
		disabled = function()
			return info.frame ~= nil and CMP:IsManagedDefault(info.frame)
		end,
	}))
	local attachSetting = list[#list]
	local baseSet = attachSetting.set
	attachSetting.set = function(layoutName, value)
		if value == "none" and (layoutName == nil or layoutName == CMP.activeLayout) and info.frame
			and CMP.Anchors:TargetInfo(info) then
			-- Detaching: keep growing from where the frame is now, not from an old spot.
			CMP.Anchors:RecordPin(info)
		end
		if CMP.byKey[value] and CMP.Anchors:WouldCycle(info.key, value) then
			CMP:Print(("Can't attach %s to %s: %s is already attached to it."):format(
				CMP:GetName(info.key), CMP:GetName(value), CMP:GetName(value)))
			return
		end
		baseSet(layoutName, value)
	end

	local hidden = NotAttached(info)
	-- Side and line-up in one choice, grouped by side: "Below, centered".
	local SIDES = {
		{ "BELOW", "Below", "left", "right" },
		{ "ABOVE", "Above", "left", "right" },
		{ "LEFT", "Left of it", "top", "bottom" },
		{ "RIGHT", "Right of it", "top", "bottom" },
	}
	table.insert(list, {
		kind = Type.Dropdown,
		name = INDENT .. "Position",
		desc = "Which side of the other frame this one sits on, and what lines up.\n\n"
			.. "Centered: stays centered on the other frame as either one changes size.\n"
			.. "Left / right (top / bottom) aligned: those edges line up.\n\n"
			.. "In Edit Mode a dot marks the point where the two frames meet.",
		default = "BELOW:CENTER",
		get = function(layoutName)
			return CMP:Get(info.key, "attachSide", layoutName) .. ":" .. CMP:Get(info.key, "attachAlign", layoutName)
		end,
		set = function(layoutName, value)
			local side, align = strsplit(":", value)
			CMP:SetQuiet(info.key, "attachSide", side, layoutName)
			CMP:Set(info.key, "attachAlign", align, layoutName)
			CMP.Session:Touch(info.key)
			CMP:RefreshDialog(info)
		end,
		generator = function(_, root, data)
			for i, entry in ipairs(SIDES) do
				if i > 1 then
					root:CreateDivider()
				end
				local side, sideText = entry[1], entry[2]
				for _, choice in ipairs({ { "CENTER", "centered" }, { "START", entry[3] .. "-aligned" }, { "END", entry[4] .. "-aligned" } }) do
					local value = side .. ":" .. choice[1]
					root:CreateRadio(("%s, %s"):format(sideText, choice[2]), function()
						return data.get(CMP.activeLayout) == value
					end, function()
						data.set(CMP.activeLayout, value)
					end)
				end
			end
		end,
		hidden = hidden,
	})
	table.insert(list, Bind(info, "attachGap", {
		kind = Type.Slider,
		name = INDENT .. "Gap",
		desc = "Space between the two frames. Negative values overlap them.",
		minValue = -20,
		maxValue = 60,
		valueStep = 1,
		formatter = Units,
		hidden = hidden,
	}))
	table.insert(list, Bind(info, "attachOffset", {
		kind = Type.Slider,
		name = INDENT .. "Offset",
		desc = "Slide this frame along the edge it's attached to.",
		minValue = -300,
		maxValue = 300,
		valueStep = 1,
		formatter = Units,
		hidden = hidden,
	}))
	table.insert(list, Bind(info, "whenHidden", {
		kind = Type.Dropdown,
		name = INDENT .. "If It Hides",
		desc = "What this frame does while the frame it's attached to is hidden (for example when that one only shows in combat).\n\n"
			.. "Keep Its Spot: stays where it is.\nTake Its Place: moves into the hidden frame's spot, so the stack closes up.",
		values = {
			Option("Keep Its Spot", "keep"),
			Option("Take Its Place", "fill"),
		},
		hidden = hidden,
	}))
end

local function MatchedWidth(info)
	return function(layoutName)
		return CMP:Get(info.key, "matchWidth", layoutName) ~= "off"
	end
end

local function IconSettings(info, list)
	local isBars = info.kind == "bars"
	local collapsed = Section(info, list, "icons", isBars and "Bar Icons" or "Icon Look", false)
	table.insert(list, Bind(info, "style", {
		kind = Type.Dropdown,
		name = "Icon Style",
		desc = "Blizzard: the normal rounded icons.\nSquare: no rounded corners or frame art, so icons line up edge to edge, with a crisp border." .. SPELL_NOTE .. LOCKED_NOTE .. MASQUE_NOTE,
		disabled = StyleLocked(info),
		values = function()
			if CMP.Masque:IsActive(info) then
				return { Option(CMP.Masque:Describe(info), CMP:Get(info.key, "style")) }
			end
			return {
				Option("Blizzard", "blizzard"),
				Option("Square", "square"),
			}
		end,
		hidden = collapsed,
	}))
	if not isBars then
	table.insert(list, Bind(info, "iconSize", {
		kind = Type.Slider,
		name = "Exact Size",
		desc = "Icon size in Edit Mode units, rounded so every icon covers whole screen pixels and rows line up exactly. Off uses Edit Mode's Icon Size.\n\nNot used while Match Width sizes the icons." .. LOCKED_NOTE,
		disabled = Any(GeometryLocked(info), MatchedWidth(info)),
		minValue = 0,
		maxValue = 96,
		valueStep = 1,
		formatter = function(value)
			return value == 0 and (OFF or "Off") or Units(value)
		end,
		hidden = collapsed,
	}))
	end
	local squareHidden = Any(collapsed, NotSquare(info))
	table.insert(list, Bind(info, "borderSize", {
		kind = Type.Slider,
		name = INDENT .. "Border",
		desc = "In screen pixels. 0 hides the border.",
		minValue = 0,
		maxValue = 6,
		valueStep = 1,
		formatter = Pixels,
		hidden = squareHidden,
	}))
	local colorSetting = Bind(info, "borderColor", {
		kind = Type.ColorPicker,
		name = INDENT .. "Color",
		hasOpacity = true,
		hidden = squareHidden,
	})
	local d = CMP.defaults.borderColor
	colorSetting.default = CreateColor(d.r, d.g, d.b, d.a)
	colorSetting.get = function(layoutName)
		local c = CMP:Get(info.key, "borderColor", layoutName)
		return CreateColor(c.r, c.g, c.b, c.a or 1)
	end
	colorSetting.set = function(layoutName, color)
		local r, g, b, a = color:GetRGBA()
		CMP:Set(info.key, "borderColor", { r = r, g = g, b = b, a = a }, layoutName)
		CMP.Session:Touch(info.key)
	end
	table.insert(list, colorSetting)
	table.insert(list, Bind(info, "zoom", {
		kind = Type.Slider,
		name = INDENT .. "Zoom",
		desc = "Crops the icon's own built-in edge.",
		minValue = 0,
		maxValue = 25,
		valueStep = 1,
		formatter = function(value)
			return ("%d%%"):format(value)
		end,
		hidden = squareHidden,
	}))
	table.insert(list, Bind(info, "sharedBorders", {
		kind = Type.Checkbox,
		name = "Shared Borders",
		desc = "Icons that touch share one border line instead of showing two side by side (like CSS border-collapse): they overlap by the border width.\n\nAlso between attached frames that both use Shared Borders (e.g. a row attached to a Square Personal Resource Display), with Gap 0.",
		hidden = squareHidden,
	}))
	if not isBars then
		SpacingSettings(info, list, collapsed)
	end
end

-- Personal Resource Display: bar frame art or a crisp square border.
local function ColorSetting(info, field, name, desc, hidden)
	local setting = Bind(info, field, {
		kind = Type.ColorPicker,
		name = name,
		desc = desc,
		hasOpacity = true,
		hidden = hidden,
	})
	local d = CMP.defaults[field]
	setting.default = CreateColor(d.r, d.g, d.b, d.a)
	setting.get = function(layoutName)
		local c = CMP:Get(info.key, field, layoutName)
		return CreateColor(c.r, c.g, c.b, c.a or 1)
	end
	setting.set = function(layoutName, color)
		local r, g, b, a = color:GetRGBA()
		CMP:Set(info.key, field, { r = r, g = g, b = b, a = a }, layoutName)
		CMP.Session:Touch(info.key)
	end
	return setting
end

PRDBarSettings = function(info, list)
	local collapsed = Section(info, list, "bars", "Bar Look", false)
	table.insert(list, Bind(info, "style", {
		kind = Type.Dropdown,
		name = "Bar Style",
		desc = "Blizzard: the normal bar frame.\nSquare: no frame art; a plain background and a crisp border inside each bar, so the bars are exactly as wide as they look (handy next to square icons).",
		values = {
			Option("Blizzard", "blizzard"),
			Option("Square", "square"),
		},
		hidden = collapsed,
	}))
	local notSquare = Any(collapsed, function(layoutName)
		return CMP:Get(info.key, "style", layoutName) ~= "square"
	end)
	table.insert(list, Bind(info, "borderSize", {
		kind = Type.Slider,
		name = INDENT .. "Border",
		desc = "In screen pixels. 0 hides the border.",
		minValue = 0,
		maxValue = 6,
		valueStep = 1,
		formatter = Pixels,
		hidden = notSquare,
	}))
	table.insert(list, ColorSetting(info, "borderColor", INDENT .. "Color", nil, notSquare))
	table.insert(list, ColorSetting(info, "barBackground", INDENT .. "Background", "Color behind the empty part of each bar.", notSquare))
	table.insert(list, Bind(info, "sharedBorders", {
		kind = Type.Checkbox,
		name = "Shared Borders",
		desc = "When a Square cooldown row with Shared Borders is attached to the bars with Gap 0, the two share one border line instead of showing two.",
		hidden = notSquare,
	}))
end

-- Tracked Bars: the bar next to the icon (the icon has its own section).
BuffBarSettings = function(info, list)
	local collapsed = Section(info, list, "bars", "Bar Look", false)
	table.insert(list, Bind(info, "barStyle", {
		kind = Type.Dropdown,
		name = "Bar Style",
		desc = "Blizzard: the normal bar frame (a dark background with a built-in edge and shadow).\nSquare: no frame art; a plain background and a crisp border inside the bar, so it's exactly as big as it looks (handy next to a square icon).",
		values = {
			Option("Blizzard", "blizzard"),
			Option("Square", "square"),
		},
		hidden = collapsed,
	}))
	local notSquare = Any(collapsed, function(layoutName)
		return CMP:Get(info.key, "barStyle", layoutName) ~= "square"
	end)
	table.insert(list, Bind(info, "barBorderSize", {
		kind = Type.Slider,
		name = INDENT .. "Border",
		desc = "In screen pixels. 0 hides the border.",
		minValue = 0,
		maxValue = 6,
		valueStep = 1,
		formatter = Pixels,
		hidden = notSquare,
	}))
	table.insert(list, ColorSetting(info, "barBorderColor", INDENT .. "Color", nil, notSquare))
	table.insert(list, ColorSetting(info, "barBackground", INDENT .. "Background", "Color behind the empty part of each bar.", notSquare))
end

-- Spacing between icons, in screen pixels between the visible icons.
SpacingSettings = function(info, list, collapsed)
	local function Spacing(value)
		return value < 0 and nil or ("%d px"):format(value)
	end
	table.insert(list, Bind(info, "spacingX", {
		kind = Type.Slider,
		name = "Icon Gap",
		desc = "Space between icons in a row, in screen pixels between the visible icons. Blizzard uses Edit Mode's Icon Padding." .. LOCKED_NOTE,
		minValue = -1,
		maxValue = 20,
		valueStep = 1,
		formatter = function(value)
			return Spacing(value) or "Blizzard"
		end,
		disabled = GeometryLocked(info),
		hidden = collapsed,
	}))
	if not info.buffs then
		table.insert(list, Bind(info, "spacingY", {
			kind = Type.Slider,
			name = "Row Gap",
			desc = "Space between rows, when icons wrap into more than one row." .. LOCKED_NOTE,
			minValue = -1,
			maxValue = 20,
			valueStep = 1,
			formatter = function(value)
				return Spacing(value) or "Same"
			end,
			disabled = GeometryLocked(info),
			hidden = collapsed,
		}))
	end
end

local function WidthSettings(info, list)
	local what = info.kind == "icons"
		and "Size the icons so a full row is exactly as wide as another cooldown row, so the edges line up (horizontal rows). The icons stay whole pixels; the small rest goes into the gaps."
		or "Make this frame exactly as wide as the cooldown icons, so the edges line up."
	table.insert(list, Bind(info, "matchWidth", {
		kind = Type.Dropdown,
		name = "Match Width",
		desc = what .. "\n\n"
			.. "Attached Frame: the frame it's attached to.\n"
			.. "Widest Row: the widest cooldown row attached in the same stack (or any, if none is attached).\n\nChains work: a row can match a frame that itself matches another one. A chain that leads back to this frame is ignored."
			.. (info.kind == "icons" and LOCKED_NOTE or ""),
		disabled = info.kind == "icons" and GeometryLocked(info) or nil,
		values = {
			Option(OFF or "Off", "off"),
			Option("Attached Frame", "target"),
			Option("Widest Row", "widest"),
		},
	}))
	table.insert(list, Bind(info, "widthAdjust", {
		kind = Type.Slider,
		name = INDENT .. "Adjust",
		desc = "Fine-tune the matched width, e.g. to line up with the bar's border art.",
		minValue = -40,
		maxValue = 40,
		valueStep = 1,
		formatter = Units,
		hidden = MatchOff(info),
	}))
end

local OUTLINES = {
	Option(DEFAULT or "Default", "default"),
	Option(NONE or "None", "NONE"),
	Option("Outline", "OUTLINE"),
	Option("Thick Outline", "THICKOUTLINE"),
}

local function MediaValues(kind)
	return function()
		local values = { Option(DEFAULT or "Default", "default") }
		for _, entry in ipairs(CMP.Media:List(kind)) do
			local text = entry.name
			if kind == "statusbar" then
				local preview = entry.atlas and "|A:%s:12:72|a  %s" or "|T%s:12:72|t  %s"
				text = preview:format(entry.path, entry.name)
			end
			table.insert(values, Option(text, entry.name))
		end
		return values
	end
end

local function TextSettings(info, list)
	local collapsed = Section(info, list, "text", "Text & Textures", false)
	local lsmNote = CMP.Media:LSM() and "" or "\n\nInstall SharedMedia (or any addon that ships LibSharedMedia) for more fonts."
	table.insert(list, Bind(info, "font", {
		kind = Type.Dropdown,
		name = "Font",
		desc = "Font for this frame's text. Default keeps Blizzard's." .. lsmNote,
		values = MediaValues("font"),
		height = 320,
		hidden = collapsed,
	}))
	table.insert(list, Bind(info, "outline", {
		kind = Type.Dropdown,
		name = "Outline",
		values = OUTLINES,
		hidden = collapsed,
	}))
	local function SizeSlider(field, name, desc)
		table.insert(list, Bind(info, field, {
			kind = Type.Slider,
			name = name,
			desc = desc,
			minValue = 0,
			maxValue = 40,
			valueStep = 1,
			formatter = function(value)
				return value == 0 and (DEFAULT or "Default") or Units(value)
			end,
			hidden = collapsed,
		}))
	end
	if info.kind == "icons" then
		if info.buffs then
			table.insert(list, Bind(info, "debuffTimers", {
				kind = Type.Checkbox,
				name = "Debuff Timers",
				desc = "Blizzard shows no timer for tracked debuffs on you (such as Weakened Soul): it only reads helpful auras. This adds the countdown.\n\nIf the game hides aura timers from addons (in some combat situations), the icon shows no timer, as without this.",
				hidden = collapsed,
			}))
		end
		SizeSlider("timerSize", "Timer Size", "Size of the cooldown countdown numbers.")
		SizeSlider("countSize", "Count Size", "Size of charge and stack counts.")
		table.insert(list, Bind(info, "keybinds", {
			kind = Type.Checkbox,
			name = "Show Keybinds",
			desc = "Show the key each spell is bound to on your action bars (spells, macros and items). Buttons of other action bar addons aren't covered.",
			hidden = collapsed,
		}))
		local keybindsOff = Any(collapsed, function(layoutName)
			return not CMP:Get(info.key, "keybinds", layoutName)
		end)
		SizeSlider("keybindSize", INDENT .. "Size", "Size of the keybind text.")
		list[#list].hidden = keybindsOff
		table.insert(list, Bind(info, "keybindPoint", {
			kind = Type.Dropdown,
			name = INDENT .. "Corner",
			values = {
				Option("Top Left", "TOPLEFT"),
				Option("Top Right", "TOPRIGHT"),
				Option("Bottom Left", "BOTTOMLEFT"),
				Option("Bottom Right", "BOTTOMRIGHT"),
			},
			hidden = keybindsOff,
		}))
	else
		SizeSlider("textSize", "Text Size")
		table.insert(list, Bind(info, "barTexture", {
			kind = Type.Dropdown,
			name = "Bar Texture",
			values = MediaValues("statusbar"),
			height = 320,
			hidden = collapsed,
		}))
	end
end

function Settings:Register()
	-- RefreshDialog re-runs LibEditMode's panel through EnableSystemSetting, which also
	-- clears that setting's "disabled" flag, so use one that is never disabled.
	for _, info in ipairs(CMP.frameInfos) do
		info.refreshName = INDENT .. "Offset" -- must match the registered name exactly
	end
	self:UpdateHeaderSoon()
	local cooldownSystem = Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
	local indices = Enum.EditModeCooldownViewerSystemIndices
	for _, info in ipairs(CMP.frameInfos) do
		local list = { { kind = Type.Divider, name = "Cooldown Manager Extras" } }
		info.header = list[1]
		if info.kind == "prd" then
			info.systemID = Enum.EditModeSystem and Enum.EditModeSystem.PersonalResourceDisplay
			AttachSettings(info, list)
			WidthSettings(info, list)
			PRDBarSettings(info, list)
			local collapsed = Section(info, list, "mana", "Mana", false)
			table.insert(list, Bind(info, "fsr", {
				kind = Type.Checkbox,
				name = "Five-Second Rule",
				desc = "After you spend mana, spirit-based mana regeneration pauses for 5 seconds. A spark runs across the mana bar during those 5 seconds, so you can see when regeneration resumes.",
				hidden = collapsed,
			}))
			TextSettings(info, list)
			if info.systemID then
				LEM:AddSystemSettings(info.systemID, list)
			end
		elseif cooldownSystem and indices and indices[info.subsystem] then
			info.systemID = cooldownSystem
			info.subSystemID = indices[info.subsystem]
			GrowthSettings(info, list)
			AttachSettings(info, list)
			WidthSettings(info, list)
			IconSettings(info, list)
			if info.kind == "bars" then
				BuffBarSettings(info, list)
			end
			TextSettings(info, list)
			LEM:AddSystemSettings(info.systemID, list, info.subSystemID)
		end
	end
	self:UpdateHeader()
	self:KeepPanelOnScreen()
end

-- Panel title: shows which profile is being edited, if any (instead of a label in the
-- world).

function Settings:UpdateHeader()
	local profile = CMP.Profiles:ActiveName()
	local name = profile and ("Cooldown Manager Extras  |cff4fa3ff(%s)|r"):format(profile) or "Cooldown Manager Extras"
	for _, info in ipairs(CMP.frameInfos) do
		if info.header then
			info.header.name = name
		end
	end
end

function Settings:UpdateHeaderSoon()
	-- Profiles resolve once the character is known; refresh the title on entering Edit Mode.
	LEM:RegisterCallback("enter", function()
		Settings:UpdateHeader()
	end)
end

-- Our panel sits under Blizzard's settings dialog. When that would run off the screen, it
-- moves next to the dialog (left if there's room, else right). Whichever side it ends up
-- on is kept as long as it fits there, so the panel doesn't jump around while you work;
-- each time Edit Mode opens it starts out below again. If it's taller than the room on
-- every side, it goes where there's the most room, at full size, and the mouse wheel
-- scrolls it up and down. The panel is our own copy of LibEditMode's frame, so moving it
-- touches nothing of Blizzard's.
local SIDES = { "below", "left", "right" }
local SCROLL_STEP = 60 -- screen pixels per wheel notch

function Settings:PlacePanel()
	local extension = LEM.internal and LEM.internal.extension
	local dialog = EditModeSystemSettingsDialog
	if not extension or not dialog or self.placing then
		return
	end
	local dialogTop, dialogBottom = dialog:GetTop(), dialog:GetBottom()
	local dialogLeft, dialogRight = dialog:GetLeft(), dialog:GetRight()
	if not dialogBottom or not dialogLeft or not dialogTop or not dialogRight then
		return
	end
	if extension:GetScale() ~= 1 then
		extension:SetScale(1) -- older versions shrank it
	end
	-- Everything in screen pixels.
	local ds, es = dialog:GetEffectiveScale(), extension:GetEffectiveScale()
	local height, width = extension:GetHeight() * es, extension:GetWidth() * es
	if height <= 0 or width <= 0 then
		return
	end
	local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale()
	-- Room on each side: { across, down } in screen pixels.
	local room = {
		below = { math.huge, dialogBottom * ds },
		left = { dialogLeft * ds, dialogTop * ds },
		right = { screenWidth - dialogRight * ds, dialogTop * ds },
	}
	local function Fits(side)
		return room[side][1] >= width and room[side][2] >= height
	end
	local side = self.panelSide
	if not side or not Fits(side) then
		side = nil
		for _, candidate in ipairs(SIDES) do
			if Fits(candidate) then
				side = candidate
				break
			end
		end
	end
	if not side then
		-- Too tall everywhere: the side (that's wide enough) with the most height.
		for _, candidate in ipairs(SIDES) do
			if room[candidate][1] >= width and (not side or room[candidate][2] > room[side][2]) then
				side = candidate
			end
		end
		side = side or "below"
	end
	-- How far it can scroll: the part that doesn't fit.
	local overflow = math.max(0, height - room[side][2])
	local scroll = math.max(0, math.min(self.panelScroll or 0, overflow))
	self.panelOverflow, self.panelScroll = overflow, scroll
	if side == self.panelSide and scroll == self.panelPlacedScroll and self.panelPlaced then
		return -- already there
	end
	self.panelSide, self.panelPlacedScroll, self.panelPlaced = side, scroll, true
	self.placing = true
	local y = scroll / es
	extension:ClearAllPoints()
	if side == "below" then
		extension:SetPoint("TOP", dialog, "BOTTOM", 0, y)
	elseif side == "left" then
		extension:SetPoint("TOPRIGHT", dialog, "TOPLEFT", 0, y)
	else
		extension:SetPoint("TOPLEFT", dialog, "TOPRIGHT", 0, y)
	end
	self.placing = nil
end

function Settings:ScrollPanel(delta)
	if (self.panelOverflow or 0) <= 0 then
		return
	end
	self.panelScroll = (self.panelScroll or 0) - delta * SCROLL_STEP
	self:PlacePanel()
end

-- Our panel's title area drags Blizzard's dialog (and our panel with it), like the
-- dialog's own title. StartMoving / StopMovingOrSizing are what the dialog itself uses.
function Settings:AddDragHandle(extension)
	local dialog = EditModeSystemSettingsDialog
	if extension.cmpHandle or not dialog then
		return
	end
	local handle = CreateFrame("Frame", nil, extension)
	handle:SetPoint("TOPLEFT", 0, 0)
	handle:SetPoint("TOPRIGHT", 0, 0)
	handle:SetHeight(34)
	handle:SetFrameLevel(extension:GetFrameLevel() + 20)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if dialog:IsMovable() then
			dialog:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		dialog:StopMovingOrSizing()
		Settings:PlacePanel()
	end)
	handle:SetScript("OnEnter", function()
		GameTooltip:SetOwner(handle, "ANCHOR_TOP")
		GameTooltip:SetText("Cooldown Manager Extras", 1, 1, 1)
		GameTooltip:AddLine("Drag to move the settings window. The - button in the corner of the window above hides this panel. When the panel is taller than the screen, scroll it with the mouse wheel.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	extension.cmpHandle = handle
end

-- A small +/- button in the top-left corner of Blizzard's settings dialog hides our whole
-- panel (for this Edit Mode session), for when you only want Blizzard's settings. It's our
-- own frame, anchored to the dialog, shown only while the dialog edits one of our frames.
function Settings:SetCollapsed(collapsed)
	self.collapsed = collapsed and true or false
	local extension = LEM.internal and LEM.internal.extension
	if extension then
		if self.collapsed then
			extension:Hide()
		elseif extension.systemID and self:DialogShowsOurs() then
			extension:Update(extension.systemID, extension.subSystemID)
		end
	end
	self:UpdateToggle()
end

function Settings:DialogShowsOurs()
	local dialog = EditModeSystemSettingsDialog
	local system = dialog and dialog:IsShown() and dialog.attachedToSystem
	return system ~= nil and CMP.byFrame[system] ~= nil
end

function Settings:UpdateToggle()
	local toggle = self.toggle
	if not toggle then
		return
	end
	toggle:SetShown(self:DialogShowsOurs())
	local texture = self.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"
	toggle:SetNormalTexture(texture)
	toggle:SetPushedTexture(self.collapsed and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
end

function Settings:CreateToggle()
	local dialog = EditModeSystemSettingsDialog
	if self.toggle or not dialog then
		return
	end
	local toggle = CreateFrame("Button", nil, UIParent)
	toggle:SetSize(18, 18)
	toggle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -14)
	toggle:SetFrameStrata(dialog:GetFrameStrata())
	toggle:SetFrameLevel(dialog:GetFrameLevel() + 20)
	toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	toggle:SetScript("OnClick", function()
		Settings:SetCollapsed(not Settings.collapsed)
		PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
	end)
	toggle:SetScript("OnEnter", function()
		GameTooltip:SetOwner(toggle, "ANCHOR_TOP")
		GameTooltip:SetText("Cooldown Manager Extras", 1, 1, 1)
		GameTooltip:AddLine(Settings.collapsed and "Show the extra settings panel." or "Hide the extra settings panel while you edit.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	toggle:Hide()
	self.toggle = toggle
	dialog:HookScript("OnShow", function() Settings:UpdateToggle() end)
	dialog:HookScript("OnHide", function() Settings:UpdateToggle() end)
	CMP.HookMethod(dialog, "AttachToSystemFrame", function() Settings:UpdateToggle() end)
end

function Settings:KeepPanelOnScreen()
	local extension = LEM.internal and LEM.internal.extension
	if self.panelHooked or not extension then
		return
	end
	self.panelHooked = true
	self:AddDragHandle(extension)
	-- Mouse wheel scrolls the panel when it's taller than the screen.
	extension:EnableMouseWheel(true)
	extension:SetScript("OnMouseWheel", function(_, delta)
		Settings:ScrollPanel(delta)
	end)
	self:CreateToggle()
	-- LibEditMode shows the panel whenever a frame is selected; keep it hidden while
	-- collapsed.
	hooksecurefunc(extension, "Update", function()
		if Settings.collapsed then
			extension:Hide()
		end
		Settings:UpdateToggle()
	end)
	hooksecurefunc(extension, "Layout", function()
		Settings:PlacePanel()
	end)
	-- Sizes can settle after LibEditMode's layout pass (Blizzard's dialog lays itself out
	-- a frame later, sections expand): re-check whenever either one changes size.
	extension:HookScript("OnSizeChanged", function()
		Settings:PlacePanel()
	end)
	if EditModeSystemSettingsDialog then
		EditModeSystemSettingsDialog:HookScript("OnSizeChanged", function()
			Settings:PlacePanel()
		end)
		EditModeSystemSettingsDialog:HookScript("OnShow", function()
			C_Timer.After(0, function()
				Settings:PlacePanel()
			end)
		end)
	end
	LEM:RegisterCallback("enter", function()
		Settings.panelSide = nil -- start out below each time Edit Mode opens
		Settings.panelScroll = 0
		if Settings.collapsed then
			Settings.collapsed = false -- and shown
			Settings:UpdateToggle()
		end
	end)
	-- Blizzard's dialog changes height when its own settings change, and can be dragged.
	if EditModeSystemSettingsDialog then
		CMP.HookMethod(EditModeSystemSettingsDialog, "UpdateSizeAndAnchors", function()
			Settings:PlacePanel()
		end)
		EditModeSystemSettingsDialog:HookScript("OnDragStop", function()
			Settings:PlacePanel()
		end)
	end
end
