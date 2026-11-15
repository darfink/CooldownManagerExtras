local _, ns = ...
local CMP = ns.CMP

-- Ties our settings to Edit Mode's Save / Revert buttons, so changing one of our settings
-- behaves like changing one of Blizzard's:
--  * Save and Revert All Changes light up when one of our settings changed.
--  * Save keeps the changes. Revert All Changes, the dialog's Revert Changes (that frame
--    only) and "Exit" in Blizzard's unsaved-changes prompt put them back.
--
-- Our settings are written right away (so nothing is lost on a crash or /reload); this
-- module keeps a copy of what they were when Edit Mode opened or was last saved, and
-- restores it on revert.
--
-- One difference we can't remove without risking taint: Blizzard's "You have unsaved
-- changes" prompt on exit only knows Blizzard's own changes. Writing to Blizzard's flag
-- would taint Edit Mode, so when only our settings changed, Edit Mode closes without the
-- prompt and our changes are kept, as if saved.
--
-- Taint: only hooksecurefunc / HookScript, and only C widget methods (SetEnabled) on
-- Blizzard's buttons. We never write to Blizzard's tables.

local Session = {}
CMP.Session = Session

local snapshot -- copy of the settings when editing started or was last saved
local source -- { kind = "profile" | "layout", name = ... } the settings the copy belongs to
local dirty = {} -- frame key -> true when it differs from the copy
local Equal

-- Derived from the frame's position when Grow From changes or the frame is dragged.
-- Moving a frame is already one of Blizzard's own changes (its buttons light up for that),
-- so these alone don't count as ours. Reverting always restores them, though.
local DERIVED = { pinX = true, pinY = true, pinPoint = true }

local function Effective(settings, k)
	local v = settings[k]
	if v == nil then
		v = CMP.defaults[k]
	end
	return v
end

-- Same settings, counting a missing value as its default.
local function SameSettings(a, b)
	a, b = a or {}, b or {}
	for _, t in ipairs({ a, b }) do
		for k in pairs(t) do
			if not DERIVED[k] and not Equal(Effective(a, k), Effective(b, k)) then
				return false
			end
		end
	end
	return true
end

function Equal(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not Equal(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function CurrentSource()
	local profile = CMP.Profiles:ActiveName()
	if profile then
		return "profile", profile
	end
	return "layout", CMP.activeLayout
end

local function StoreOf(kind, name, create)
	local db = CMP.db
	if not db or not name then
		return nil
	end
	if kind == "profile" then
		local profile = db.profiles[name]
		if not profile and create then
			profile = { frames = {} }
			db.profiles[name] = profile
		end
		if profile and not profile.frames and create then
			profile.frames = {}
		end
		return profile and profile.frames
	end
	local layout = db.layouts[name]
	if not layout and create then
		layout = {}
		db.layouts[name] = layout
	end
	return layout
end

local function IsEditing()
	return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

-- Start (or restart) tracking from the current settings.
function Session:Begin()
	wipe(dirty)
	local kind, name = CurrentSource()
	if not CMP.db or not name then
		snapshot, source = nil, nil
	else
		source = { kind = kind, name = name }
		snapshot = CMP.Copy(StoreOf(kind, name) or {})
	end
	self:UpdateButtons()
end

function Session:End()
	snapshot, source = nil, nil
	wipe(dirty)
end

-- After a layout or profile switch: track the new settings. Deferred one frame, so a
-- revert that belongs to the switch (Blizzard's prompt) still restores the old ones first.
function Session:Rebase()
	if not snapshot then
		return
	end
	C_Timer.After(0, function()
		if snapshot and IsEditing() then
			self:Begin()
		end
	end)
end

-- A user-facing change to frame `key` (setting, drag, nudge, reset position).
function Session:Touch(key)
	if not snapshot or not key then
		return
	end
	local kind, name = CurrentSource()
	if kind ~= source.kind or name ~= source.name then
		return
	end
	local store = StoreOf(kind, name)
	dirty[key] = not SameSettings(store and store[key], snapshot[key]) or nil
	self:UpdateButtons()
end

function Session:IsDirty(key)
	if key then
		return dirty[key] == true
	end
	return next(dirty) ~= nil
end

-- Revert one frame's settings (key) or all of them (nil) to the copy.
function Session:Revert(key)
	if not snapshot then
		return
	end
	local store = StoreOf(source.kind, source.name, true)
	if not store then
		return
	end
	if key then
		store[key] = CMP.Copy(snapshot[key])
		dirty[key] = nil
	else
		wipe(store)
		for k, v in pairs(snapshot) do
			store[k] = CMP.Copy(v)
		end
		wipe(dirty)
	end
	CMP:Update()
	for _, info in ipairs(CMP.frameInfos) do
		if not key or info.key == key then
			CMP:RefreshDialog(info)
		end
	end
	self:UpdateButtons()
end

function Session:OnNewLayout()
	local layout = CMP.activeLayout and CMP.db and CMP.db.layouts[CMP.activeLayout]
	CMP.pendingNewLayout = CMP.Copy(layout or {})
	if snapshot and source.kind == "layout" then
		self:Revert()
	end
end

-- Save / Revert buttons: lit while Blizzard or we have unsaved changes.
function Session:UpdateButtons()
	local manager = EditModeManagerFrame
	if not manager or not manager:IsShown() then
		return
	end
	local ours = next(dirty) ~= nil
	local enabled = ours or manager.hasActiveChanges == true
	if manager.SaveChangesButton then
		manager.SaveChangesButton:SetEnabled(enabled)
	end
	if manager.RevertAllChangesButton then
		manager.RevertAllChangesButton:SetEnabled(enabled)
	end

	local dialog = EditModeSystemSettingsDialog
	local system = dialog and dialog.attachedToSystem
	local info = system and CMP.byFrame[system]
	local button = dialog and dialog.Buttons and dialog.Buttons.RevertChangesButton
	if info and button then
		button:SetEnabled(system.hasActiveChanges == true or dirty[info.key] == true)
	end
end

function Session:Init()
	local manager = EditModeManagerFrame
	if self.initialized or not manager then
		return
	end
	self.initialized = true

	-- Blizzard resets the buttons whenever its own state changes; put ours back on top.
	CMP.HookMethod(manager, "SetHasActiveChanges", function()
		if next(dirty) then
			Session:UpdateButtons()
		end
	end)
	-- Every real save goes through SaveLayouts (Save button, "Save and exit", new layout).
	CMP.HookMethod(manager, "SaveLayouts", function()
		if Session.revertedThisFrame then
			Session:OnNewLayout()
		elseif snapshot then
			Session:Begin()
		end
	end)
	-- The dialog's "Revert Changes": that frame only.
	CMP.HookMethod(manager, "RevertSystemChanges", function(_, systemFrame)
		local info = CMP.byFrame[systemFrame]
		if info then
			Session:Revert(info.key)
		end
	end)
	if manager.RevertAllChangesButton then
		manager.RevertAllChangesButton:HookScript("OnClick", function()
			Session:Revert()
		end)
	end
	-- Blizzard's unsaved-changes prompt: "Exit" / "Switch layout" without saving.
	local prompt = EditModeUnsavedChangesDialog
	if prompt and prompt.ProceedButton then
		prompt.ProceedButton:HookScript("OnClick", function()
			Session:Revert()
		end)
	end
	if EditModeSystemSettingsDialog then
		CMP.HookMethod(EditModeSystemSettingsDialog, "UpdateButtons", function()
			Session:UpdateButtons()
		end)
	end

	-- Real enter / exit only. Edit Mode also hides temporarily (e.g. Quick Keybind Mode)
	-- without leaving; LibEditMode's enter/exit callbacks fire for those too.
	CMP.HookMethod(manager, "EnterEditMode", function()
		Session:Begin()
	end)
	CMP.HookMethod(manager, "ExitEditMode", function()
		-- Deferred: "Exit" in Blizzard's prompt closes Edit Mode before its click hook runs.
		C_Timer.After(0, function()
			if not IsEditing() then
				Session:End()
			end
		end)
	end)

	-- New layouts (Save on a preset layout, copy, import) go through MakeNewLayout, which
	-- reverts the current layout's unsaved changes and saves the new one with them. Do the
	-- same with ours: the new layout gets the current settings, the old one goes back to
	-- its saved state.
	CMP.HookMethod(manager, "RevertAllChanges", function()
		Session.revertedThisFrame = true
		C_Timer.After(0, function()
			Session.revertedThisFrame = nil
		end)
	end)
	CMP.HookMethod(manager, "ImportLayout", function()
		CMP.pendingNewLayout = nil -- imported layouts start from defaults
	end)
end
