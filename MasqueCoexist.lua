local _, ns = ...
local CMP = ns.CMP

-- Coexisting with Masque.
--
-- We never register anything with Masque. If another addon (normally "Masque Blizzard
-- Bars") has Masque skin a cooldown viewer's icons, Masque owns the icon look and we step
-- back: no square style, default border, zoom, mask or overlay changes for that viewer.
-- Layout, anchoring, exact size, width matching, fonts and per-spell borders keep working.
--
-- We never register buttons or callbacks with Masque: its group callbacks hold one function
-- per event, so registering ours would replace the skinning addon's own. Instead we
-- post-hook (hooksecurefunc) __FireCB on the Masque Blizzard Bars groups for our viewers.
-- Masque calls it after every option change (enable/disable, skin, colors, reset), so we
-- refresh exactly when something changed, with no polling.

local Coexist = {}
CMP.Masque = Coexist

-- Masque Blizzard Bars: Masque:Group("Blizzard Action Bars", title, <viewer global name>)
-- gives the group ID "Blizzard Action Bars_<viewer global name>".
local MBB_ADDON = "MasqueBlizzBars"
local MBB_GROUP_PREFIX = "Blizzard Action Bars_"

local function IsLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	return IsAddOnLoaded and IsAddOnLoaded(name) or false
end

function Coexist:API()
	return LibStub and LibStub("Masque", true) or nil
end

local function KnownGroup(api, info)
	if not IsLoaded(MBB_ADDON) or not api.GetGroupByID then
		return nil
	end
	local ok, group = pcall(api.GetGroupByID, api, MBB_GROUP_PREFIX .. info.global)
	return ok and type(group) == "table" and group or nil
end

local function AnyItemRegistered(info)
	for item in pairs(CMP.Layout:Items(info.frame)) do
		if item.layoutIndex and rawget(item, "_MSQ_CFG") ~= nil then
			return true
		end
	end
	return false
end

-- Is Masque skinning this viewer's icons right now? Returns active, skinName.
function Coexist:Skinning(info)
	if info.kind == "prd" or not info.frame then
		return false
	end
	local api = self:API()
	if not api then
		return false
	end
	local group = KnownGroup(api, info)
	if group and type(group.db) == "table" then
		return not group.db.Disabled, group.db.SkinID
	end
	-- Some other addon put these icons into Masque: assume it's active.
	if AnyItemRegistered(info) then
		return true, nil
	end
	return false
end

function Coexist:IsActive(info)
	return (self:Skinning(info))
end

function Coexist:Describe(info)
	local active, skin = self:Skinning(info)
	if not active then
		return nil
	end
	return skin and ("Masque (%s)"):format(skin) or "Masque"
end

-- React to changes made in Masque's options (event-driven, no polling).
local hookedGroups = setmetatable({}, { __mode = "k" })
local refreshQueued = false

local function OnMasqueChanged()
	if refreshQueued then
		return
	end
	refreshQueued = true
	-- Masque finishes re-skinning in the same call; refresh on the next frame.
	C_Timer.After(0, function()
		refreshQueued = false
		CMP:Update()
		for _, info in ipairs(CMP.frameInfos) do
			CMP:RefreshDialog(info)
		end
	end)
end

function Coexist:Start()
	local api = self:API()
	if not api then
		return
	end
	for _, info in ipairs(CMP.frameInfos) do
		local group = info.frame and KnownGroup(api, info)
		if group and not hookedGroups[group] and type(group.__FireCB) == "function" then
			hookedGroups[group] = true
			hooksecurefunc(group, "__FireCB", OnMasqueChanged)
		end
	end
end
