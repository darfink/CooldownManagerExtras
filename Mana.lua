local _, ns = ...
local CMP = ns.CMP

-- Five-second rule on the Personal Resource Display's mana bar. After you spend mana,
-- spirit-based mana regeneration pauses for 5 seconds (only "while casting" regen
-- continues). A spark sweeps across the mana bar during those 5 seconds, the classic
-- "5SR" indicator.
--
-- Uses only your own spell casts (UNIT_SPELLCAST_SUCCEEDED) and each spell's static mana
-- cost (C_Spell.GetSpellPowerCost). It never reads your current mana, which can be secret
-- in instances on Forever.

local Mana = {}
CMP.Mana = Mana

local DURATION = 5
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local spark
local startTime
local channeling = false -- mana channels keep the timer at its start until they end

local function CostsMana(spellID)
	if CMP.IsSecret(spellID) or not spellID or not C_Spell or not C_Spell.GetSpellPowerCost then
		return false
	end
	local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
	if not ok or type(costs) ~= "table" then
		return false
	end
	for _, cost in ipairs(costs) do
		if cost.type == MANA then
			for _, field in ipairs({ "cost", "costPerSec", "minCost" }) do
				local amount = cost[field]
				if not CMP.IsSecret(amount) and amount and amount > 0 then
					return true
				end
			end
		end
	end
	return false
end

-- The bar showing mana right now: the main power bar, or the extra mana bar (druid forms).
local function ManaBar()
	local frame = CMP.byKey.PRD.frame
	if not frame then
		return nil
	end
	local powerType = UnitPowerType("player")
	if not CMP.IsSecret(powerType) and powerType == MANA and frame.PowerBar and frame.PowerBar:IsVisible() then
		return frame.PowerBar
	end
	local alt = frame.AlternatePowerBar
	if alt and alt:IsVisible() then
		return alt
	end
	return nil
end

local function Hide()
	startTime = nil
	if spark then
		spark:Hide()
	end
end

local function EnsureSpark()
	if spark then
		return spark
	end
	spark = CreateFrame("Frame", nil, UIParent)
	spark:SetFrameStrata("MEDIUM")
	local texture = spark:CreateTexture(nil, "OVERLAY")
	texture:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	texture:SetBlendMode("ADD")
	texture:SetAllPoints()
	spark:Hide()
	spark:SetScript("OnUpdate", function()
		local bar = ManaBar()
		if channeling then
			startTime = GetTime()
		end
		local elapsed = startTime and (GetTime() - startTime)
		if not bar or not elapsed or elapsed >= DURATION or not CMP:Get("PRD", "fsr") then
			Hide()
			return
		end
		local width, height = bar:GetWidth(), bar:GetHeight()
		spark:SetParent(bar)
		spark:SetFrameLevel(bar:GetFrameLevel() + 5)
		spark:SetSize(12, height * 2.2)
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar, "LEFT", width * elapsed / DURATION, 0)
	end)
	return spark
end

function Mana:Start()
	if self.events then
		return
	end
	self.events = CreateFrame("Frame")
	self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	self.events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	self.events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	self.events:SetScript("OnEvent", function(_, event, _, _, spellID)
		if not CMP:Get("PRD", "fsr") then
			channeling = false
			return
		end
		if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
			-- The 5 seconds count from the last mana spent: the end of the channel.
			if channeling then
				channeling = false
				startTime = GetTime()
				EnsureSpark():Show()
			end
			return
		end
		if CostsMana(spellID) then
			channeling = event == "UNIT_SPELLCAST_CHANNEL_START" or channeling
			startTime = GetTime()
			EnsureSpark():Show()
		end
	end)
end
