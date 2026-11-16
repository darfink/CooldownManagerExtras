local _, ns = ...
local CMP = ns.CMP

-- Options -> AddOns -> Cooldown Manager Extras. Only things that don't belong to one frame
-- in Edit Mode: profiles, and sharing them (import / export, Share.lua). Built from Blizzard's own templates so it looks native.

local Options = {}
CMP.Options = Options

local USE_LAYOUT = "\0layout" -- dropdown value: no profile, Edit Mode layout settings
local SAME_AS_CHARACTER = "\0char"

local function Label(parent, text, template)
	local fontString = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
	fontString:SetText(text)
	fontString:SetJustifyH("LEFT")
	return fontString
end

local function Dropdown(parent, width)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width or 240)
	return dropdown
end

local function Button(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(width or 160, 22)
	button:SetScript("OnClick", onClick)
	return button
end

function Options:Build()
	if self.panel or not Settings or not Settings.RegisterCanvasLayoutCategory then
		return
	end
	local Profiles = CMP.Profiles
	local panel = CreateFrame("Frame")
	panel:Hide()
	self.panel = panel

	local title = Label(panel, "Cooldown Manager Extras", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	local intro = Label(panel, "Most settings live in Edit Mode: open it and select a cooldown viewer or the Personal Resource Display. Per-spell borders: right-click a spell in the Cooldown Settings window.", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", -16, 0)
	intro:SetWordWrap(true)

	local header = Label(panel, "Profiles", "GameFontNormal")
	header:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
	local explain = Label(panel, "A profile is a saved set of all these settings, shared by your characters. Without one, settings belong to the current Edit Mode layout. Each talent group can use its own profile; switching talents switches it.", "GameFontHighlightSmall")
	explain:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	explain:SetPoint("RIGHT", -16, 0)
	explain:SetWordWrap(true)

	local rows = {}
	local function Row(labelText, anchor)
		local label = Label(panel, labelText)
		label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
		label:SetWidth(180)
		return label
	end

	-- This character
	local charLabel = Row("This character uses", explain)
	local charDropdown = Dropdown(panel)
	charDropdown:SetPoint("LEFT", charLabel, "RIGHT", 8, 0)
	charDropdown:SetupMenu(function(_, root)
		local char = Profiles:Char()
		local current = char and char.profile or USE_LAYOUT
		root:CreateRadio("Edit Mode layout settings", function() return current == USE_LAYOUT end, function()
			Profiles:SetCharacterProfile(nil)
		end)
		for _, name in ipairs(Profiles:List()) do
			root:CreateRadio(name, function() return current == name end, function()
				Profiles:SetCharacterProfile(name)
			end)
		end
	end)
	table.insert(rows, charDropdown)

	-- Talent groups
	local anchor = charLabel
	for group = 1, Profiles:NumTalentGroups() do
		local label = Row(group == 1 and "Primary talents" or ("Talent group %d"):format(group), anchor)
		if group == 2 then
			label:SetText("Secondary talents")
		end
		local dropdown = Dropdown(panel)
		dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
		dropdown:SetupMenu(function(_, root)
			local char = Profiles:Char()
			local current = char and char.groups and char.groups[group] or SAME_AS_CHARACTER
			root:CreateRadio("Same as character", function() return current == SAME_AS_CHARACTER end, function()
				Profiles:SetGroupProfile(group, nil)
			end)
			for _, name in ipairs(Profiles:List()) do
				root:CreateRadio(name, function() return current == name end, function()
					Profiles:SetGroupProfile(group, name)
				end)
			end
		end)
		table.insert(rows, dropdown)
		anchor = label
	end

	-- In use now
	local active = Label(panel, "", "GameFontHighlightSmall")
	active:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)

	-- New profile
	local newLabel = Row("New profile", active)
	local nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	nameBox:SetSize(180, 20)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	nameBox:SetPoint("LEFT", newLabel, "RIGHT", 14, 0)
	local status = Label(panel, "", "GameFontHighlightSmall")
	local createButton = Button(panel, "Create from current", 160, function()
		local name = nameBox:GetText()
		local ok, err = Profiles:Create(name, true)
		if ok then
			nameBox:SetText("")
			nameBox:ClearFocus()
			status:SetText(("Created %s. Pick it above to use it."):format(strtrim(name)))
		else
			status:SetText(err)
		end
		Options:Refresh()
	end)
	createButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	nameBox:SetScript("OnEnterPressed", function() createButton:Click() end)
	nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

	-- Delete profile (click twice; no popup)
	local deleteLabel = Row("Delete profile", newLabel)
	local deleteChoice
	local deleteDropdown = Dropdown(panel, 180)
	deleteDropdown:SetPoint("LEFT", deleteLabel, "RIGHT", 8, 0)
	deleteDropdown:SetupMenu(function(_, root)
		for _, name in ipairs(Profiles:List()) do
			root:CreateRadio(name, function() return deleteChoice == name end, function()
				deleteChoice = name
				Options:DisarmDelete()
			end)
		end
	end)
	table.insert(rows, deleteDropdown)
	local armedFor -- profile the next click deletes; tied to the name, never to "whatever is selected"
	local armToken = 0
	local deleteButton
	function Options:DisarmDelete()
		armedFor = nil
		armToken = armToken + 1
		if deleteButton then
			deleteButton:SetText(DELETE or "Delete")
		end
	end
	deleteButton = Button(panel, DELETE or "Delete", 160, function()
		if not deleteChoice or not CMP.db.profiles[deleteChoice] then
			status:SetText("Pick a profile to delete.")
			return
		end
		if armedFor ~= deleteChoice then
			Options:DisarmDelete()
			armedFor = deleteChoice
			local token = armToken
			deleteButton:SetText(("Click again: delete %s"):format(deleteChoice))
			C_Timer.After(3, function()
				if armToken == token then
					Options:DisarmDelete()
				end
			end)
			return
		end
		Options:DisarmDelete()
		Profiles:Delete(deleteChoice)
		status:SetText(("Deleted %s."):format(deleteChoice))
		deleteChoice = nil
		Options:Refresh()
	end)
	deleteButton:SetPoint("LEFT", deleteDropdown, "RIGHT", 8, 0)

	status:SetPoint("TOPLEFT", deleteLabel, "BOTTOMLEFT", 0, -16)

	-- Share: export the settings in effect now as text; import text as a new profile.
	local shareHeader = Label(panel, "Share", "GameFontNormal")
	shareHeader:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -20)
	local shareExplain = Label(panel, "Export puts the settings in use now (every frame, plus per-spell styles) in the box below: copy it with Ctrl+C. To import, paste an export into the box, name the new profile, and click Import.", "GameFontHighlightSmall")
	shareExplain:SetPoint("TOPLEFT", shareHeader, "BOTTOMLEFT", 0, -6)
	shareExplain:SetPoint("RIGHT", -16, 0)
	shareExplain:SetWordWrap(true)

	local box = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
	box:SetPoint("TOPLEFT", shareExplain, "BOTTOMLEFT", 6, -14)
	box:SetPoint("RIGHT", -24, 0)
	box:SetHeight(90)
	if box.CharCount then
		box.CharCount:Hide()
	end
	local editBox = box.EditBox
	editBox:SetMaxLetters(0)
	editBox:SetFontObject("GameFontHighlightSmall")
	editBox:SetWidth(520)
	box:HookScript("OnSizeChanged", function(_, width)
		editBox:SetWidth(math.max(100, width - 18))
	end)

	local shareStatus = Label(panel, "", "GameFontHighlightSmall")
	local exportButton = Button(panel, "Export", 120, function()
		local ok, text = pcall(CMP.Share.Export, CMP.Share)
		if not ok then
			shareStatus:SetText("Export failed: " .. tostring(text))
			return
		end
		editBox:SetText(text)
		editBox:SetFocus()
		editBox:HighlightText()
		shareStatus:SetText("Copied into the box: press Ctrl+C to copy it.")
	end)
	exportButton:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -12)

	local importName = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	importName:SetSize(160, 20)
	importName:SetAutoFocus(false)
	importName:SetMaxLetters(40)
	importName:SetPoint("LEFT", exportButton, "RIGHT", 24, 0)
	local importNameLabel = Label(panel, "Profile name", "GameFontHighlightSmall")
	importNameLabel:SetPoint("BOTTOMLEFT", importName, "TOPLEFT", -4, 2)

	local withSpells = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	withSpells:SetSize(24, 24)
	withSpells:SetChecked(true)
	local withSpellsLabel = Label(panel, "Also per-spell styles", "GameFontHighlightSmall")

	local importButton = Button(panel, "Import", 120, function()
		local ok, message = CMP.Share:Import(editBox:GetText(), importName:GetText(), withSpells:GetChecked())
		shareStatus:SetText(message)
		if ok then
			editBox:SetText("")
			importName:SetText("")
			Options:Refresh()
		end
	end)
	importButton:SetPoint("LEFT", importName, "RIGHT", 8, 0)
	withSpells:SetPoint("LEFT", importButton, "RIGHT", 12, 0)
	withSpellsLabel:SetPoint("LEFT", withSpells, "RIGHT", 2, 0)
	withSpells:SetScript("OnEnter", function()
		GameTooltip:SetOwner(withSpells, "ANCHOR_TOP")
		GameTooltip:SetText("Also per-spell styles", 1, 1, 1)
		GameTooltip:AddLine("Per-spell styles (borders, cooldown display, gray-out) are shared by all profiles. Importing them replaces your styles for the spells in the export; other spells keep theirs.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	withSpells:SetScript("OnLeave", function() GameTooltip:Hide() end)
	shareStatus:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", 0, -10)
	shareStatus:SetPoint("RIGHT", -16, 0)
	shareStatus:SetWordWrap(true)

	-- Pasting shows what the export holds, and suggests its profile name.
	editBox:HookScript("OnTextChanged", function(_, userInput)
		if not userInput then
			return
		end
		local text = editBox:GetText()
		if strtrim(text) == "" then
			shareStatus:SetText("")
			return
		end
		local data, err = CMP.Share:Read(text)
		if not data then
			shareStatus:SetText(err)
			return
		end
		if strtrim(importName:GetText()) == "" and data.name then
			importName:SetText(data.name)
		end
		shareStatus:SetText(("Export of %s: %d frame(s), %d spell style(s). Click Import to add it as a profile."):format(
			data.name or "unnamed settings", data.frameCount, data.spellCount))
	end)

	function Options:Refresh()
		local name = Profiles:ActiveName()
		active:SetText(("In use now: |cffffffff%s|r"):format(name and ("profile " .. name) or ("settings of Edit Mode layout " .. tostring(CMP.activeLayout or "?"))))
		for _, dropdown in ipairs(rows) do
			dropdown:GenerateMenu()
		end
	end
	panel:SetScript("OnShow", function() Options:Refresh() end)
	panel:SetScript("OnHide", function() Options:DisarmDelete() end)
	Profiles.OnChanged = function()
		if panel:IsShown() then
			Options:Refresh()
		end
	end

	self.category = Settings.RegisterCanvasLayoutCategory(panel, "Cooldown Manager Extras")
	Settings.RegisterAddOnCategory(self.category)
end

function Options:Open()
	if self.category and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	end
end
