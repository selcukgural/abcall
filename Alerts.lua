local _, ns = ...

-- Classic Era's AB team-wide channel shows in chat as "[Instance]", sent via
-- SendChatMessage's "INSTANCE_CHAT" type - not "BATTLEGROUND", confirmed from
-- an actual in-game screenshot of a teammate's message.
local CHAT_TYPE = "INSTANCE_CHAT"

local cooldowns = {} -- "kind:baseKey" -> GetTime() of last send

-- Per-kind message template and minimum cooldown floor. "count" (manual
-- incoming-alert buttons) has no floor of its own beyond ns.db.cooldown;
-- "auto" (automatic Sap alert) gets a longer floor so a repeatedly-sapped
-- player doesn't spam the same message over and over; "undefended" gets the
-- longest floor since it's a recurring area-awareness ping, not an emergency.
local KIND_TEMPLATE_KEY = {
	count = "template",
	safe = "safeTemplate",
	auto = "autoTemplate",
	undefended = "undefendedTemplate",
}
local KIND_MIN_COOLDOWN = {
	auto = 10,
	undefended = 30,
}

local function BuildMessage(kind, baseName, count)
	local template = ns.db[KIND_TEMPLATE_KEY[kind]]
	local text = template:gsub("{base}", baseName)
	if count then
		local countText = count >= 4 and (count .. "+") or tostring(count)
		text = text:gsub("{count}", countText)
	end
	return text
end

-- kind: "count" (default), "safe", or "auto". count may be nil for "safe"/"auto".
-- Returns true, "" on success, or false, remainingSeconds if still on cooldown.
function ns.SendAlert(baseKey, baseName, count, kind)
	kind = kind or "count"
	local db = ns.db
	local cooldownKey = kind .. ":" .. baseKey
	local cooldown = math.max(db.cooldown, KIND_MIN_COOLDOWN[kind] or 0)
	local now = GetTime()
	local last = cooldowns[cooldownKey]
	if last and (now - last) < cooldown then
		return false, cooldown - (now - last)
	end
	cooldowns[cooldownKey] = now

	local text = BuildMessage(kind, baseName, count)
	local sent = pcall(SendChatMessage, text, CHAT_TYPE)
	if not sent or db.echoLocal then
		DEFAULT_CHAT_FRAME:AddMessage("|cff2ecc71[AB Call]|r " .. text)
	end
	return true, 0
end

function ns.GetCooldownRemaining(baseKey, kind)
	kind = kind or "count"
	local cooldown = math.max(ns.db.cooldown, KIND_MIN_COOLDOWN[kind] or 0)
	local last = cooldowns[kind .. ":" .. baseKey]
	if not last then
		return 0
	end
	local remaining = cooldown - (GetTime() - last)
	return remaining > 0 and remaining or 0
end
