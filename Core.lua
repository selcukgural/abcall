local ADDON, ns = ...

local defaults = {
	point = { "CENTER", nil, "CENTER", 0, 150 },
	locked = false,
	scale = 1,
	theme = "classic",
	cooldown = 4,
	echoLocal = true,
	template = "[{base}] {count} incoming!",
	safeTemplate = "[{base}] Clear, safe now!",
	autoTemplate = "[{base}] I'm Sapped! Possible stealthed enemy nearby!",
	autoSapAlert = true,
	undefendedTemplate = "[{base}] is undefended! Need defenders!",
	undefendedAlert = false,
	-- Persisted (not just in-memory) so a mid-match /reload doesn't lose
	-- track of who owns what - matchInstanceID lets us tell "still the same
	-- match, just reloaded" apart from "actually a new match" (see
	-- CheckZoneStatus below).
	baseOwner = {},
	basePending = {},
}

local function ApplyDefaults(src, dst)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = ApplyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local function IsInArathiBasin()
	local name, instanceType = GetInstanceInfo()
	return instanceType == "pvp" and name == "Arathi Basin"
end

-- Finds the nearest AB base to the player, if any base is within `radius`
-- (normalized map units). Returns baseKey, baseName, or nil if too far from
-- every base or not currently on the AB map at all (e.g. not in the BG).
local function FindNearestBase(radius)
	local pos = C_Map.GetPlayerMapPosition(ns.AB_MAP_ID, "player")
	if not pos then
		return nil
	end
	local nearestKey, nearestName, nearestDist
	for _, base in ipairs(ns.BASES) do
		local coord = ns.BASE_COORDS[base.key]
		local dx, dy = pos.x - coord.x, pos.y - coord.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= radius and (not nearestDist or dist < nearestDist) then
			nearestDist = dist
			nearestKey = base.key
			nearestName = base.name
		end
	end
	return nearestKey, nearestName
end
ns.FindNearestBase = FindNearestBase

local PROXIMITY_RADIUS = 0.035

-- Optional, off by default: warns the team if one of the bases they own has
-- had nobody from the raid nearby for a while - the classic AB failure mode
-- where everyone pushes one side and a held base quietly gets capped because
-- no chat message ever announces "nobody's here". This is the one extra bit
-- of periodic work this addon does (scanning raid member positions every few
-- seconds instead of only reacting to events), hence it being opt-in with a
-- "small performance cost" note in Settings.
local DEFEND_RADIUS = 0.05
local UNDEFENDED_CHECK_INTERVAL = 8
local UNDEFENDED_STREAK_THRESHOLD = 3
local undefendedStreak = {}

local function GetGroupUnits()
	if IsInRaid() then
		local units = {}
		for i = 1, GetNumGroupMembers() do
			units[i] = "raid" .. i
		end
		return units
	end
	return { "player" }
end

local function IsBaseDefended(coord, units)
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local pos = C_Map.GetPlayerMapPosition(ns.AB_MAP_ID, unit)
			if pos then
				local dx, dy = pos.x - coord.x, pos.y - coord.y
				if math.sqrt(dx * dx + dy * dy) <= DEFEND_RADIUS then
					return true
				end
			end
		end
	end
	return false
end

local function CheckUndefendedBases()
	if not (ns.db and ns.db.undefendedAlert and IsInArathiBasin()) then
		return
	end
	local myFaction = UnitFactionGroup("player")
	local units = GetGroupUnits()
	for _, base in ipairs(ns.BASES) do
		if ns.db.baseOwner[base.key] == myFaction then
			if IsBaseDefended(ns.BASE_COORDS[base.key], units) then
				undefendedStreak[base.key] = 0
			else
				local streak = (undefendedStreak[base.key] or 0) + 1
				undefendedStreak[base.key] = streak
				if streak == UNDEFENDED_STREAK_THRESHOLD then
					ns.SendAlert(base.key, base.name, nil, "undefended")
				end
			end
		else
			undefendedStreak[base.key] = 0
		end
	end
end
C_Timer.NewTicker(UNDEFENDED_CHECK_INTERVAL, CheckUndefendedBases)

-- ns.db.baseOwner: which faction currently owns each base (baseKey ->
-- "Alliance"/"Horde"), nil = neutral/unknown. Learned purely from the
-- standard BG system chat messages Blizzard broadcasts to everyone when a
-- node changes hands.
--
-- ns.db.basePending: a base currently mid-capture and not yet confirmed
-- (baseKey -> "Alliance"/"Horde", the faction about to take it), nil = no
-- capture in progress. Confirmed from real in-game screenshots that
-- capturing a base isn't instant - there's a message the moment someone
-- starts the capture, and only ~1 minute later (if unopposed) does the "has
-- taken" message that actually flips ns.db.baseOwner arrive:
--   "Pickelickle-PyrewoodVillage claims the blacksmith! If left
--    unchallenged, the Alliance will control it in 1 minute!"
--   "The Alliance has taken the lumber mill!"                  (confirmed)
--   "<Name> has assaulted the lumber mill!"    (attacking an owned base)
--   "<Name> has defended the southern farm!"   (assault repelled)
-- ns.db.basePending drives an intermediate "claiming, not secured yet" color
-- distinct from the full owned color, matching the real 1-minute window.
--
-- Both are persisted in ABCallDB (not plain runtime tables) so a
-- mid-match /reload doesn't lose track of who owns what - see
-- CheckZoneStatus for how a genuinely new match still resets them.

-- All text matching below is done against a single lowercased copy of the
-- message, since Blizzard's own wording isn't consistent about capitalizing
-- "the Alliance"/"the Horde" mid-sentence vs. at the start of one.
local function MatchBaseKey(lowerMsg)
	for _, base in ipairs(ns.BASES) do
		if lowerMsg:find(ns.BASE_KEYWORDS[base.key], 1, true) then
			return base.key
		end
	end
	return nil
end

local function ExtractFaction(lowerMsg)
	if lowerMsg:find("the alliance", 1, true) then
		return "Alliance"
	elseif lowerMsg:find("the horde", 1, true) then
		return "Horde"
	end
	return nil
end

local function HandleBGSystemMessage(msg)
	local lowerMsg = msg:lower()
	local baseKey = MatchBaseKey(lowerMsg)
	if not baseKey then
		return
	end

	if lowerMsg:find("has taken", 1, true) then
		-- Confirmed - the ~1 minute capture window has elapsed unopposed.
		local faction = ExtractFaction(lowerMsg)
		if faction then
			ns.db.baseOwner[baseKey] = faction
		end
		ns.db.basePending[baseKey] = nil
	elseif lowerMsg:find("claims the", 1, true) or lowerMsg:find("will control it", 1, true) then
		-- Capture just started (from neutral, or contesting an owned base) -
		-- the message states who'll end up with it if left unopposed.
		local faction = ExtractFaction(lowerMsg)
		if faction then
			ns.db.basePending[baseKey] = faction
		end
	elseif lowerMsg:find("has assaulted", 1, true) then
		-- Attacking an already-owned base; this wording doesn't name the
		-- attacker's faction, so infer it as whichever faction doesn't
		-- already own the base.
		local owner = ns.db.baseOwner[baseKey]
		if owner == "Alliance" then
			ns.db.basePending[baseKey] = "Horde"
		elseif owner == "Horde" then
			ns.db.basePending[baseKey] = "Alliance"
		end
	elseif lowerMsg:find("has defended", 1, true) then
		-- Assault repelled - no owner change, capture no longer in progress.
		ns.db.basePending[baseKey] = nil
	end

	ns.RefreshOwnership()
end

-- Manual fallback for when the tracked state might be stale - most notably
-- after a long disconnect, where messages announcing a capture could have
-- been missed entirely while offline and there's no live API to re-query
-- current ownership. Shift+left-click on a base cycles
-- neutral -> mine -> enemy -> neutral, same order the label color implies.
function ns.CycleBaseOwnership(baseKey, baseName)
	local myFaction = UnitFactionGroup("player")
	local enemyFaction = (myFaction == "Alliance") and "Horde" or "Alliance"
	local owner = ns.db.baseOwner[baseKey]
	local label
	if owner == myFaction then
		ns.db.baseOwner[baseKey] = enemyFaction
		label = enemyFaction
	elseif owner == enemyFaction then
		ns.db.baseOwner[baseKey] = nil
		label = "Neutral"
	else
		ns.db.baseOwner[baseKey] = myFaction
		label = myFaction
	end
	ns.db.basePending[baseKey] = nil
	ns.RefreshOwnership()
	DEFAULT_CHAT_FRAME:AddMessage("|cff2ecc71[AB Call]|r " .. baseName .. " manually set to: " .. label)
end

local function HasSap()
	for i = 1, 40 do
		local name = UnitAura("player", i, "HARMFUL")
		if not name then
			return false
		end
		if name == "Sap" then
			return true
		end
	end
	return false
end

local wasSapped = false
local function CheckSapStatus()
	if not ns.db then
		return
	end
	local sapped = HasSap()
	if sapped and not wasSapped and ns.db.autoSapAlert then
		local baseKey, baseName = FindNearestBase(PROXIMITY_RADIUS)
		-- Only alert for a base that's actually ours - getting sapped near an
		-- enemy or contested node isn't "our base is under threat".
		if baseKey and ns.db.baseOwner[baseKey] == UnitFactionGroup("player") then
			ns.SendAlert(baseKey, baseName, nil, "auto")
		end
	end
	wasSapped = sapped
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
eventFrame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")

-- A /reload doesn't leave the battleground - GetInstanceInfo()'s instanceID
-- stays the same for the whole server-side match, so comparing it (rather
-- than a plain "just entered AB" flag that a reload would reset to false) is
-- what lets a mid-match reload keep the ownership data instead of wiping it.
-- A genuinely new match gets a different instanceID and still resets.
local function CheckZoneStatus()
	local inAB = IsInArathiBasin()
	if ns.mainFrame then
		ns.mainFrame:SetShown(inAB)
	end
	if inAB then
		local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
		if ns.db.matchInstanceID ~= instanceID then
			ns.db.matchInstanceID = instanceID
			ns.db.baseOwner = {}
			ns.db.basePending = {}
			wipe(undefendedStreak)
			ns.RefreshOwnership()
		end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then
			return
		end
		ABCallDB = ApplyDefaults(defaults, ABCallDB)
		ns.db = ABCallDB
		ns.CreateMainFrame()
	elseif event == "UNIT_AURA" then
		CheckSapStatus()
	elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
		or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
		or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
		HandleBGSystemMessage(arg1)
	elseif ns.mainFrame then
		CheckZoneStatus()
	end
end)

local function PrintHelp()
	print("|cff2ecc71AB Call|r commands: /ac (toggle), /ac lock, /ac unlock, /ac reset")
end

SLASH_ABCALL1 = "/ac"
SLASH_ABCALL2 = "/abc"
SlashCmdList["ABCALL"] = function(msg)
	msg = strtrim(msg or ""):lower()

	if not ns.mainFrame then
		return
	end

	if msg == "lock" then
		ns.db.locked = true
		print("|cff2ecc71AB Call|r: locked.")
	elseif msg == "unlock" then
		ns.db.locked = false
		print("|cff2ecc71AB Call|r: unlocked, drag the title bar to move it.")
	elseif msg == "reset" then
		ns.ResetPosition()
		print("|cff2ecc71AB Call|r: position reset.")
	elseif msg == "" then
		ns.mainFrame:SetShown(not ns.mainFrame:IsShown())
	else
		PrintHelp()
	end
end
