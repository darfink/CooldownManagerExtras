local _, ns = ...
local CMP = ns.CMP

-- Profiles: named, account-wide sets of all Cooldown Manager Extras settings, so a setup can
-- be shared between characters and talent groups.
--
-- Without a profile (the default), settings belong to the current Edit Mode layout, like
-- Blizzard's own. A character can instead use a profile, and each talent group can use its
-- own profile; switching talents then switches the profile (Blizzard's Cooldown Manager
-- switches its tracked spells on the same events).
--
-- db.profiles[name] = { frames = { [frameKey] = settings } }
-- db.chars[character] = { profile = name|nil, groups = { [talentGroup] = name|nil } }
-- Per-spell borders are stored by spell ID and shared by every profile.

local Profiles = {}
CMP.Profiles = Profiles

local function CharacterKey()
	local name, realm = UnitFullName("player")
	realm = realm or GetRealmName()
	if not name then
		return nil
	end
	return name .. "-" .. (realm or "")
end

function Profiles:Char(create)
	local db = CMP.db
	local key = CharacterKey()
	if not db or not key then
		return nil
	end
	local char = db.chars[key]
	if not char and create then
		char = { groups = {} }
		db.chars[key] = char
	end
	return char
end

function Profiles:TalentGroup()
	local info = C_SpecializationInfo
	if info and info.GetActiveSpecGroup then
		local ok, group = pcall(info.GetActiveSpecGroup)
		if ok and type(group) == "number" then
			return group
		end
	end
	return 1
end

function Profiles:NumTalentGroups()
	local info = C_SpecializationInfo
	local fn = (info and info.GetNumSpecGroups) or GetNumSpecGroups
	if fn then
		local ok, count = pcall(fn)
		if ok and type(count) == "number" and count > 0 then
			return count
		end
	end
	return 2
end

local function Exists(name)
	return name and CMP.db.profiles[name] ~= nil
end

-- Profile in use right now, or nil for "settings of the Edit Mode layout".
function Profiles:ActiveName()
	local char = CMP.db and self:Char()
	if not char then
		return nil
	end
	local byGroup = char.groups and char.groups[self:TalentGroup()]
	if Exists(byGroup) then
		return byGroup
	end
	if Exists(char.profile) then
		return char.profile
	end
	return nil
end

function Profiles:List()
	local names = {}
	for name in pairs(CMP.db.profiles) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

-- Settings currently in effect, copied, so a new profile starts from what you see.
function Profiles:Snapshot()
	local store = CMP:Store(nil, false)
	return CMP.Copy(store or {})
end

function Profiles:Create(name, fromCurrent)
	name = name and strtrim(name) or ""
	if name == "" then
		return false, "Enter a name."
	end
	if CMP.db.profiles[name] then
		return false, ("A profile named %s already exists."):format(name)
	end
	CMP.db.profiles[name] = { frames = fromCurrent and self:Snapshot() or {} }
	return true
end

function Profiles:Delete(name)
	if not CMP.db.profiles[name] then
		return
	end
	CMP.db.profiles[name] = nil
	for _, char in pairs(CMP.db.chars) do
		if char.profile == name then
			char.profile = nil
		end
		for group, profile in pairs(char.groups or {}) do
			if profile == name then
				char.groups[group] = nil
			end
		end
	end
	self:Changed()
end

-- name = nil: use the Edit Mode layout's settings.
function Profiles:SetCharacterProfile(name)
	local char = self:Char(true)
	char.profile = Exists(name) and name or nil
	self:Changed()
end

-- name = nil: same as the character's choice.
function Profiles:SetGroupProfile(group, name)
	local char = self:Char(true)
	char.groups = char.groups or {}
	char.groups[group] = Exists(name) and name or nil
	self:Changed()
end

function Profiles:Changed()
	local active = self:ActiveName()
	if active ~= self.lastActive then
		self.lastActive = active
		CMP.Session:Rebase()
		CMP.Settings:UpdateHeader()
		CMP:Update()
		for _, info in ipairs(CMP.frameInfos) do
			CMP:RefreshDialog(info)
		end
	end
	if self.OnChanged then
		self.OnChanged()
	end
end

function Profiles:OnTalentGroupChanged()
	local before = self.lastActive
	self:Changed()
	local after = self:ActiveName()
	if after ~= before then
		CMP:Print(("Talents switched: using %s."):format(after and ("profile " .. after) or "this Edit Mode layout's settings"))
	end
end
