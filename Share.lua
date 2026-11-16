local _, ns = ...
local CMP = ns.CMP

-- Import / export: the settings in effect now (every frame) plus the per-spell styles, as
-- one line of text you can paste to a friend or another account. Importing makes a new
-- profile (see Profiles.lua); per-spell styles are merged in if you choose.
--
-- The text is our own small format, read back by a parser that only builds tables of
-- strings, numbers and booleans: nothing in it is ever run as code. Everything imported is
-- checked against our known settings; unknown or wrongly typed values are dropped.
-- With the game's compression available (C_EncodingUtil) the text is compressed and
-- base64 encoded; otherwise it's base64 only.

local Share = {}
CMP.Share = Share

local VERSION = 1
local PREFIX_PACKED, PREFIX_PLAIN = "!CMP1:", "!CMP0:"
local MAX_DEPTH = 12

---------------------------------------------------------------------------
-- Serializer: s<len>:<bytes>  n<number>;  T  F  t <key value>... e
---------------------------------------------------------------------------

local function Write(value, out, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
	elseif kind == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif kind == "table" then
		if depth > MAX_DEPTH then
			error("too deep")
		end
		out[#out + 1] = "t"
		for k, v in pairs(value) do
			local keyKind, valueKind = type(k), type(v)
			if (keyKind == "string" or keyKind == "number")
				and (valueKind == "string" or valueKind == "number" or valueKind == "boolean" or valueKind == "table") then
				Write(k, out, depth + 1)
				Write(v, out, depth + 1)
			end
		end
		out[#out + 1] = "e"
	end
end

local function Serialize(value)
	local out = {}
	Write(value, out, 0)
	return table.concat(out)
end

-- Returns value, next position; errors on anything malformed.
local function Read(text, pos, depth)
	local tag = text:sub(pos, pos)
	if tag == "s" then
		local colon = text:find(":", pos + 1, true)
		local length = colon and tonumber(text:sub(pos + 1, colon - 1))
		if not length or length < 0 or colon + length > #text then
			error("bad string")
		end
		return text:sub(colon + 1, colon + length), colon + length + 1
	elseif tag == "n" then
		local semicolon = text:find(";", pos + 1, true)
		local number = semicolon and tonumber(text:sub(pos + 1, semicolon - 1))
		if not number or number ~= number or number == math.huge or number == -math.huge then
			error("bad number")
		end
		return number, semicolon + 1
	elseif tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "t" then
		if depth > MAX_DEPTH then
			error("too deep")
		end
		local result = {}
		pos = pos + 1
		while text:sub(pos, pos) ~= "e" do
			if pos > #text then
				error("unterminated table")
			end
			local key, value
			key, pos = Read(text, pos, depth + 1)
			if type(key) == "table" or type(key) == "boolean" then
				error("bad key")
			end
			value, pos = Read(text, pos, depth + 1)
			result[key] = value
		end
		return result, pos + 1
	end
	error("bad data")
end

local function Deserialize(text)
	local value, pos = Read(text, 1, 0)
	if pos ~= #text + 1 then
		error("trailing data")
	end
	return value
end

---------------------------------------------------------------------------
-- Base64 (fallback when the game's encoder isn't there)
---------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE = {}
for i = 1, #ALPHABET do
	DECODE[ALPHABET:byte(i)] = i - 1
end

local function Encode64(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local chars = {}
		for j = 3, 0, -1 do
			local index = math.floor(n / 64 ^ j) % 64
			chars[#chars + 1] = ALPHABET:sub(index + 1, index + 1)
		end
		if not b then
			chars[3], chars[4] = "=", "="
		elseif not c then
			chars[4] = "="
		end
		out[#out + 1] = table.concat(chars)
	end
	return table.concat(out)
end

local function Decode64(data)
	data = data:gsub("[^%w%+/=]", "")
	if #data % 4 ~= 0 then
		error("bad base64")
	end
	local out = {}
	for i = 1, #data, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local byte = data:byte(i + j)
			local value = DECODE[byte]
			if byte == 61 then -- "="
				pad = pad + 1
				value = 0
			elseif not value then
				error("bad base64")
			end
			n = n * 64 + value
		end
		local bytes = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		out[#out + 1] = bytes:sub(1, 3 - pad)
	end
	return table.concat(out)
end

local function Codec()
	local util = C_EncodingUtil
	local method = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate
	if util and method and util.CompressString and util.DecompressString and util.EncodeBase64 and util.DecodeBase64 then
		return util, method
	end
	return nil
end

local function Pack(data)
	local util, method = Codec()
	if util then
		local ok, packed = pcall(function()
			return util.EncodeBase64(util.CompressString(data, method))
		end)
		if ok and type(packed) == "string" then
			return PREFIX_PACKED .. packed
		end
	end
	return PREFIX_PLAIN .. Encode64(data)
end

local function Unpack(text)
	text = strtrim(text or "")
	if text:sub(1, #PREFIX_PACKED) == PREFIX_PACKED then
		local util, method = Codec()
		if not util then
			error("this text was made with compression this game version can't read")
		end
		return util.DecompressString(util.DecodeBase64(text:sub(#PREFIX_PACKED + 1)), method)
	elseif text:sub(1, #PREFIX_PLAIN) == PREFIX_PLAIN then
		return Decode64(text:sub(#PREFIX_PLAIN + 1))
	end
	error("not a Cooldown Manager Extras export")
end

---------------------------------------------------------------------------
-- Checking imported settings
---------------------------------------------------------------------------

local function CleanColor(value)
	if type(value) ~= "table" then
		return nil
	end
	local color = {}
	for _, channel in ipairs({ "r", "g", "b", "a" }) do
		local v = value[channel]
		if type(v) == "number" then
			color[channel] = math.max(0, math.min(1, v))
		elseif channel ~= "a" then
			return nil
		end
	end
	return color
end

-- What each setting may hold. Anything else is dropped on import (the default applies).
local ANCHORS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local STYLES = { "blizzard", "square" }
local SCHEMA = {
	align = { "native", "start", "center", "end" },
	collapse = "boolean",
	attachTo = "frame", -- "none" or one of our frames
	attachSide = { "BELOW", "ABOVE", "LEFT", "RIGHT" },
	attachAlign = { "START", "CENTER", "END" },
	attachGap = { -20, 60 },
	attachOffset = { -300, 300 },
	pinX = { -100000, 100000 },
	pinY = { -100000, 100000 },
	pinPoint = ANCHORS,
	style = STYLES,
	iconSize = { 0, 96 },
	borderSize = { 0, 6 },
	borderColor = "color",
	zoom = { 0, 25 },
	spacingX = { -1, 20 },
	spacingY = { -1, 20 },
	sharedBorders = "boolean",
	barBackground = "color",
	barStyle = STYLES,
	barBorderSize = { 0, 6 },
	barBorderColor = "color",
	matchWidth = { "off", "target", "widest" },
	widthAdjust = { -40, 40 },
	font = "string",
	outline = { "default", "NONE", "OUTLINE", "THICKOUTLINE" },
	timerSize = { 0, 40 },
	countSize = { 0, 40 },
	textSize = { 0, 40 },
	barTexture = "string",
	keybinds = "boolean",
	keybindSize = { 0, 40 },
	keybindPoint = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
	whenHidden = { "keep", "fill" },
	debuffTimers = "boolean",
	fsr = "boolean",
	custom = "custom", -- Essential / Utility / Tracked Buffs: your own entries (Custom.lua)
	healthColorMode = { "default", "class", "custom" },
	healthColor = "color",
	healthTexture = "string",
	powerColors = "colormap", -- { [power token] = color }
	powerTexture = "string",
	costTexture = "string",
	costColorMode = { "default", "power", "custom" },
	costColor = "color",
}

-- { [power token] = value } with only valid tokens and values.
local function CleanMap(value, clean)
	if type(value) ~= "table" then
		return nil
	end
	local result, count = {}, 0
	for token, item in pairs(value) do
		if type(token) == "string" and token:match("^[%u_]+$") and #token <= 40 then
			local v = clean(item)
			if v ~= nil then
				result[token] = v
				count = count + 1
			end
		end
	end
	return count > 0 and result or nil
end

local CUSTOM_KINDS = { spell = true, item = true, slot = true, aura = true }

local function CleanCustom(value)
	if type(value) ~= "table" then
		return nil
	end
	local list = {}
	for _, entry in ipairs(value) do
		if type(entry) == "table" and CUSTOM_KINDS[entry.kind] and type(entry.id) == "number"
			and entry.id >= 1 and entry.id < 100000000 then
			local pos = entry.pos
			if not (pos == "start" or (type(pos) == "number" and pos >= 1 and pos < 100000000)) then
				pos = nil
			end
			table.insert(list, { kind = entry.kind, id = math.floor(entry.id), pos = pos, always = entry.always == true or nil })
			if #list >= 50 then
				break
			end
		end
	end
	return #list > 0 and list or nil
end

local function OneOf(list, value)
	for _, allowed in ipairs(list) do
		if value == allowed then
			return true
		end
	end
	return false
end

-- The value if it's allowed for this setting, else nil (false stays false).
local function CleanSetting(field, value)
	local rule = SCHEMA[field]
	if rule == nil then
		return nil
	elseif rule == "color" then
		return CleanColor(value)
	elseif rule == "custom" then
		return CleanCustom(value)
	elseif rule == "colormap" then
		return CleanMap(value, CleanColor)
	elseif rule == "stringmap" then
		return CleanMap(value, function(v) return type(v) == "string" and #v <= 200 and v or nil end)
	elseif rule == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		return nil
	elseif rule == "string" then
		return type(value) == "string" and #value <= 200 and value or nil
	elseif rule == "frame" then
		if type(value) ~= "string" then
			return nil
		end
		local named = value:match("^frame:([%a_][%w_]*)$") -- another Edit Mode frame, by name
		return (value == "none" or CMP.byKey[value] ~= nil or (named and #named <= 80)) and value or nil
	elseif type(rule[1]) == "number" then
		if type(value) ~= "number" then
			return nil
		end
		return math.max(rule[1], math.min(rule[2], value))
	end
	return OneOf(rule, value) and value or nil
end

local function CleanFrames(frames)
	local result, count = {}, 0
	if type(frames) ~= "table" then
		return result, count
	end
	for key, settings in pairs(frames) do
		if CMP.byKey[key] and type(settings) == "table" then
			local clean = {}
			for field, value in pairs(settings) do
				if type(field) == "string" then
					clean[field] = CleanSetting(field, value)
				end
			end
			if next(clean) then
				result[key] = clean
				count = count + 1
			end
		end
	end
	return result, count
end

-- Per-spell style fields and the kind each takes.
local SPELL_FIELDS = {
	color = "color",
	size = "number",
	cooldownOnly = "boolean",
	lockoutDebuff = "number",
}

local function CleanSpells(spells)
	local result, count = {}, 0
	if type(spells) ~= "table" then
		return result, count
	end
	for spellID, style in pairs(spells) do
		if type(spellID) == "number" and spellID > 0 and spellID == math.floor(spellID) and type(style) == "table" then
			local clean = {}
			for field, kind in pairs(SPELL_FIELDS) do
				local value = style[field]
				if kind == "color" then
					clean[field] = CleanColor(value)
				elseif type(value) == kind then
					clean[field] = value
				end
			end
			if next(clean) then
				result[spellID] = clean
				count = count + 1
			end
		end
	end
	return result, count
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- The settings in effect now, as text.
-- The current settings, with the gap of every attached frame written out (see Inspect).
function Share:ExportFrames()
	local frames = CMP.Profiles:Snapshot()
	for _, settings in pairs(frames) do
		if type(settings) == "table" and settings.attachTo and settings.attachTo ~= "none" and settings.attachGap == nil then
			settings.attachGap = CMP.defaults.attachGap
		end
	end
	return frames
end

function Share:Export()
	local data = {
		addon = "CooldownManagerExtras",
		version = VERSION,
		name = CMP.Profiles:ActiveName() or CMP.activeLayout,
		frames = Share:ExportFrames(),
		spells = CMP.Copy(CMP.db.spells or {}),
	}
	return Pack(Serialize(data))
end

-- What an export holds, without importing it: { name, frames, spells, frameCount,
-- spellCount }, or nil and an error message.
function Share:Read(text)
	local ok, data = pcall(function()
		return Deserialize(Unpack(text))
	end)
	if not ok then
		local message = tostring(data):gsub("^.-:%d+: ", "")
		return nil, "Can't read that: " .. message .. "."
	end
	if type(data) ~= "table" or data.addon ~= "CooldownManagerExtras" or type(data.version) ~= "number" then
		return nil, "That's not a Cooldown Manager Extras export."
	end
	if data.version > VERSION then
		return nil, "That export is from a newer version of Cooldown Manager Extras; update the addon first."
	end
	local frames, frameCount = CleanFrames(data.frames)
	-- Exports always write the gap of an attached frame; one without it is from 0.1/0.2,
	-- whose default gap was 2. 0.1 also had one Bar Texture for all PRD bars.
	CMP.MigrateFrames(frames, true)
	local spells, spellCount = CleanSpells(data.spells)
	return {
		name = type(data.name) == "string" and data.name:sub(1, 40) or nil,
		frames = frames,
		spells = spells,
		frameCount = frameCount,
		spellCount = spellCount,
	}
end

-- Imports as a new profile called `name`. withSpells: also set the per-spell styles in the
-- export (replacing those spells' current styles). Returns ok, message.
function Share:Import(text, name, withSpells)
	local data, err = self:Read(text)
	if not data then
		return false, err
	end
	name = strtrim(name or "")
	if name == "" then
		name = data.name or "Imported"
	end
	local ok, createErr = CMP.Profiles:Create(name, false)
	if not ok then
		return false, createErr
	end
	CMP.db.profiles[name].frames = data.frames
	local spellNote = ""
	if withSpells and data.spellCount > 0 then
		for spellID, style in pairs(data.spells) do
			CMP.db.spells[spellID] = style
		end
		CMP.Skin:RefreshAll()
		spellNote = (" and %d spell style(s)"):format(data.spellCount)
	end
	return true, ("Imported profile %s (%d frame(s))%s. Pick it above to use it."):format(name, data.frameCount, spellNote)
end

-- For tests.
Share.Serialize, Share.Deserialize = Serialize, Deserialize
Share.Encode64, Share.Decode64 = Encode64, Decode64
