local _, ns = ...

local PANEL_WIDTH = 236
local TITLE_HEIGHT = 24
local ROW_HEIGHT = 26
local PADDING = 8
local MIN_SCALE = 0.7
local MAX_SCALE = 1.6

local SLOT_HEIGHT = ROW_HEIGHT + 2

local function Tint(tex, color, alpha)
	tex:SetVertexColor(color[1], color[2], color[3], alpha)
end

-- Vertical offset (from the panel's TOPLEFT) for the row occupying the given
-- 1-based slot in the current display order.
local function RowY(slotIndex)
	return -(TITLE_HEIGHT + PADDING + (slotIndex - 1) * SLOT_HEIGHT)
end

-- Recolors every row's label per current ownership status and re-sorts them:
-- bases owned by (or being claimed by) the player's own faction float to the
-- top ("mine"), everything else sinks to the bottom ("other"), with a
-- divider line shown between the two groups when both are non-empty. A base
-- mid-capture (ns.db.basePending set, not yet confirmed by a "has taken"
-- message) shows a muted variant of the color instead of the full one.
-- Called once after the rows are built, and again from Core.lua any time
-- ns.db.baseOwner/ns.db.basePending changes.
function ns.RefreshOwnership()
	local rowsByKey = ns.rowsByKey
	if not rowsByKey then
		return
	end

	local myFaction = UnitFactionGroup("player")
	local mineKeys, otherKeys = {}, {}
	for _, base in ipairs(ns.BASES) do
		local owner = ns.db.baseOwner[base.key]
		local pending = ns.db.basePending[base.key]
		local row = rowsByKey[base.key]
		local statusColor
		if pending == myFaction then
			statusColor = ns.STATUS_COLORS.ownPending
			table.insert(mineKeys, base.key)
		elseif pending then
			statusColor = ns.STATUS_COLORS.enemyPending
			table.insert(otherKeys, base.key)
		elseif owner == myFaction then
			statusColor = ns.STATUS_COLORS.own
			table.insert(mineKeys, base.key)
		elseif owner then
			statusColor = ns.STATUS_COLORS.enemy
			table.insert(otherKeys, base.key)
		else
			statusColor = ns.STATUS_COLORS.neutral
			table.insert(otherKeys, base.key)
		end
		row.label:SetTextColor(statusColor[1], statusColor[2], statusColor[3], 1)
	end

	local slot = 1
	for _, key in ipairs(mineKeys) do
		local row = rowsByKey[key]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PADDING, RowY(slot))
		slot = slot + 1
	end

	local divider = ns.groupDivider
	if divider then
		if #mineKeys > 0 and #otherKeys > 0 then
			local dividerY = RowY(#mineKeys) - ROW_HEIGHT - 1
			divider:ClearAllPoints()
			divider:SetPoint("TOPLEFT", PADDING, dividerY)
			divider:SetPoint("TOPRIGHT", -PADDING, dividerY)
			divider:Show()
		else
			divider:Hide()
		end
	end

	for _, key in ipairs(otherKeys) do
		local row = rowsByKey[key]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PADDING, RowY(slot))
		slot = slot + 1
	end
end

local function ApplyPanelSkin(frame, theme)
	frame:SetBackdrop(theme.backdrop)
	frame:SetBackdropColor(unpack(theme.backdropColor))
	frame:SetBackdropBorderColor(unpack(theme.backdropBorderColor))
end

-- A small flat (no bevel) button: colored fill + 1px border, with hover/press
-- feedback done purely via alpha changes on flat textures. Used by the
-- "modern" theme.
local function CreateFlatButton(parent, width, height, color)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width, height)

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(ns.FLAT)
	Tint(bg, color, 0.28)
	btn.bg = bg

	local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
	border:SetAllPoints()
	border:SetBackdrop({ edgeFile = ns.FLAT, edgeSize = 1 })
	border:SetBackdropBorderColor(color[1], color[2], color[3], 0.65)

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("CENTER")
	label:SetTextColor(1, 1, 1, 1)
	btn.label = label

	btn:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			Tint(self.bg, color, 0.5)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		Tint(self.bg, color, 0.28)
	end)
	btn:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then
			Tint(self.bg, color, 0.75)
		end
	end)
	btn:SetScript("OnMouseUp", function(self)
		if self:IsEnabled() then
			Tint(self.bg, color, 0.5)
		end
	end)

	return btn
end

-- A real classic-era beveled button (native Blizzard template). Used by the
-- "classic" theme so it looks/feels like an authentic classic UI control.
local function CreateClassicButton(parent, width, height, text)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width, height)
	btn:SetText(text)
	local fs = btn:GetFontString()
	if fs then
		fs:SetFontObject("GameFontHighlightSmall")
	end
	return btn
end

local function SetRowEnabled(row, enabled)
	for _, btn in ipairs(row.buttons) do
		if enabled then
			btn:Enable()
		else
			btn:Disable()
		end
		if btn.bg then
			if enabled then
				Tint(btn.bg, row.color, 0.28)
				btn.label:SetAlpha(1)
			else
				Tint(btn.bg, row.color, 0.10)
				btn.label:SetAlpha(0.45)
			end
		end
	end
end

local function CreateRow(parent, base, theme, rowsByKey)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(PANEL_WIDTH - 2 * PADDING, ROW_HEIGHT)
	row.color = ns.COLORS[base.key]
	row.buttons = {}

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", 2, 0)
	label:SetWidth(90)
	label:SetJustifyH("LEFT")
	label:SetText(base.name)
	row.label = label

	local cooldownText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cooldownText:SetPoint("LEFT", 2, 0)
	cooldownText:SetWidth(90)
	cooldownText:SetJustifyH("LEFT")
	cooldownText:Hide()
	row.cooldownText = cooldownText

	local labels = { "1", "2", "3", "4+" }
	local btnWidth, spacing = 26, 4
	local anchor = label
	local anchorPoint, relPoint, xOff = "LEFT", "RIGHT", 8
	for i, text in ipairs(labels) do
		local btn
		if theme.buttonStyle == "classic" then
			btn = CreateClassicButton(row, btnWidth, ROW_HEIGHT - 4, text)
		else
			btn = CreateFlatButton(row, btnWidth, ROW_HEIGHT - 4, row.color)
			btn.label:SetText(text)
		end
		btn:SetPoint(anchorPoint, anchor, relPoint, xOff, 0)
		local count = i < 4 and i or 4
		btn:SetScript("OnClick", function()
			local ok = ns.SendAlert(base.key, base.name, count)
			if ok then
				ns.RefreshRowCooldown(row)
			end
		end)
		row.buttons[i] = btn
		anchor, anchorPoint, relPoint, xOff = btn, "LEFT", "RIGHT", spacing
	end

	-- Right-click reports "safe" for this base; Shift+left-click manually
	-- cycles its tracked ownership (fallback for after a long disconnect,
	-- where capture messages could've been missed); plain left-click on
	-- empty row space (rows are auto-sorted by ownership now, no manual
	-- reordering) falls back to moving the whole panel, same as clicking
	-- anywhere else on it.
	row:EnableMouse(true)
	row:SetScript("OnMouseDown", function(self, button)
		if button == "RightButton" then
			ns.SendAlert(base.key, base.name, nil, "safe")
		elseif button == "LeftButton" then
			if IsShiftKeyDown() then
				ns.CycleBaseOwnership(base.key, base.name)
			else
				parent.StartPanelMove()
			end
		end
	end)
	row:SetScript("OnMouseUp", function()
		parent.StopPanelMove()
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(base.name, 1, 1, 1)
		GameTooltip:AddLine("Right-click: report this base safe/clear", 0.6, 1, 0.6)
		GameTooltip:AddLine("Shift+Left-click: manually correct ownership", 0.8, 0.8, 1)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return row
end

function ns.RefreshRowCooldown(row)
	local remaining = ns.GetCooldownRemaining(row.base.key)
	if remaining > 0 then
		SetRowEnabled(row, false)
		row.cooldownText:SetText(string.format("%.0fs...", remaining))
		row.cooldownText:Show()
	else
		SetRowEnabled(row, true)
		row.cooldownText:Hide()
	end
end

local function CreateSettingsFrame(parent, theme)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(PANEL_WIDTH, 268)
	f:SetPoint("TOP", parent, "BOTTOM", 0, -6)
	ApplyPanelSkin(f, theme)
	f:Hide()

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", 0, -8)
	title:SetText("Settings")

	local templateLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	templateLabel:SetPoint("TOPLEFT", 10, -26)
	templateLabel:SetText("Message template ({base}, {count})")

	local templateBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	templateBox:SetSize(PANEL_WIDTH - 30, 16)
	templateBox:SetPoint("TOPLEFT", 14, -40)
	templateBox:SetAutoFocus(false)
	templateBox:SetText(ns.db.template)
	templateBox:SetScript("OnEnterPressed", function(self)
		ns.db.template = self:GetText()
		self:ClearFocus()
	end)
	templateBox:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.db.template)
		self:ClearFocus()
	end)

	local cooldownLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cooldownLabel:SetPoint("TOPLEFT", 10, -62)
	cooldownLabel:SetText("Cooldown (seconds)")

	local cooldownBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	cooldownBox:SetSize(40, 16)
	cooldownBox:SetPoint("TOPLEFT", 14, -76)
	cooldownBox:SetAutoFocus(false)
	cooldownBox:SetNumeric(true)
	cooldownBox:SetText(tostring(ns.db.cooldown))
	cooldownBox:SetScript("OnEnterPressed", function(self)
		local n = tonumber(self:GetText())
		ns.db.cooldown = n and n > 0 and n or ns.db.cooldown
		self:SetText(tostring(ns.db.cooldown))
		self:ClearFocus()
	end)
	cooldownBox:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(ns.db.cooldown))
		self:ClearFocus()
	end)

	local echoCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	echoCheck:SetPoint("TOPLEFT", 8, -98)
	echoCheck:SetSize(20, 20)
	echoCheck:SetChecked(ns.db.echoLocal)
	echoCheck:SetScript("OnClick", function(self)
		ns.db.echoLocal = self:GetChecked() and true or false
	end)

	local echoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	echoLabel:SetPoint("LEFT", echoCheck, "RIGHT", 2, 0)
	echoLabel:SetText("Echo alerts to local chat")

	local autoSapCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	autoSapCheck:SetPoint("TOPLEFT", 8, -122)
	autoSapCheck:SetSize(20, 20)
	autoSapCheck:SetChecked(ns.db.autoSapAlert)
	autoSapCheck:SetScript("OnClick", function(self)
		ns.db.autoSapAlert = self:GetChecked() and true or false
	end)

	local autoSapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	autoSapLabel:SetPoint("LEFT", autoSapCheck, "RIGHT", 2, 0)
	autoSapLabel:SetText("Auto-alert when Sapped near a base")

	local undefendedCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	undefendedCheck:SetPoint("TOPLEFT", 8, -146)
	undefendedCheck:SetSize(20, 20)
	undefendedCheck:SetChecked(ns.db.undefendedAlert)
	undefendedCheck:SetScript("OnClick", function(self)
		ns.db.undefendedAlert = self:GetChecked() and true or false
	end)

	local undefendedLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	undefendedLabel:SetPoint("LEFT", undefendedCheck, "RIGHT", 2, 0)
	undefendedLabel:SetText("Warn if my base is undefended")

	local undefendedNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	undefendedNote:SetPoint("TOPLEFT", 30, -164)
	undefendedNote:SetText("(adds a small periodic performance cost)")

	local themeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	themeLabel:SetPoint("TOPLEFT", 10, -184)
	themeLabel:SetText("Theme")

	local themeBtnWidth = 96
	local prevBtn
	for i, key in ipairs(ns.THEME_ORDER) do
		local def = ns.THEMES[key]
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(themeBtnWidth, 18)
		btn:SetText(def.label)
		if prevBtn then
			btn:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
		else
			btn:SetPoint("TOPLEFT", 18, -202)
		end
		if key == ns.db.theme then
			btn:Disable()
		end
		btn:SetScript("OnClick", function()
			ns.SetTheme(key)
		end)
		prevBtn = btn
	end

	local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	resetBtn:SetSize(96, 18)
	resetBtn:SetPoint("TOP", 0, -238)
	resetBtn:SetText("Reset position")
	resetBtn:SetScript("OnClick", function()
		ns.ResetPosition()
	end)

	return f
end

local function TeardownMainFrame()
	if ns.cooldownTicker then
		ns.cooldownTicker:Cancel()
		ns.cooldownTicker = nil
	end
	if ns.mainFrame then
		ns.mainFrame:Hide()
		ns.mainFrame:SetParent(nil)
		ns.mainFrame = nil
	end
	ns.settingsFrame = nil
	ns.rowsByKey = nil
	ns.groupDivider = nil
end

function ns.CreateMainFrame()
	local wasShown = ns.mainFrame and ns.mainFrame:IsShown()
	local settingsWasShown = ns.settingsFrame and ns.settingsFrame:IsShown()
	TeardownMainFrame()

	local theme = ns.THEMES[ns.db.theme] or ns.THEMES.classic

	local numRows = #ns.BASES
	local height = TITLE_HEIGHT + PADDING + numRows * (ROW_HEIGHT + 2) + PADDING

	local main = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	main:SetSize(PANEL_WIDTH, height)
	main:SetClampedToScreen(true)
	ApplyPanelSkin(main, theme)
	main:SetMovable(true)
	main:EnableMouse(true)
	main:SetToplevel(true)

	local point = ns.db.point
	main:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	main:SetScale(ns.db.scale)

	-- Plain anchor frame for the title row. Only the "modern" theme paints a
	-- solid color strip on it; "classic" leaves it transparent so the tooltip
	-- style border texture wraps the panel uninterrupted, including the top.
	local titleBg = CreateFrame("Frame", nil, main)
	titleBg:SetPoint("TOPLEFT")
	titleBg:SetPoint("TOPRIGHT")
	titleBg:SetHeight(TITLE_HEIGHT)

	if theme.buttonStyle ~= "classic" then
		local titleTex = titleBg:CreateTexture(nil, "ARTWORK")
		titleTex:SetAllPoints()
		titleTex:SetTexture(ns.FLAT)
		titleTex:SetVertexColor(unpack(theme.titleBarColor))
	end

	-- Thin divider under the title row so the header reads as visually
	-- separated from the row content below it, in both themes.
	local divider = titleBg:CreateTexture(nil, "OVERLAY")
	divider:SetPoint("BOTTOMLEFT", titleBg, "BOTTOMLEFT", 6, 0)
	divider:SetPoint("BOTTOMRIGHT", titleBg, "BOTTOMRIGHT", -6, 0)
	divider:SetHeight(1)
	divider:SetTexture(ns.FLAT)
	divider:SetVertexColor(unpack(theme.dividerColor))

	local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("LEFT", titleBg, "LEFT", 8, 0)
	title:SetText("AB CALL")
	title:SetTextColor(unpack(theme.titleColor))

	local closeBtn
	if theme.buttonStyle == "classic" then
		closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
		closeBtn:SetSize(20, 20)
		closeBtn:SetPoint("RIGHT", titleBg, "RIGHT", -8, 0)
	else
		closeBtn = CreateFlatButton(main, 16, 16, { 0.8, 0.25, 0.25 })
		closeBtn:SetPoint("RIGHT", titleBg, "RIGHT", -4, 0)
		closeBtn.label:SetText("\195\151") -- ×
	end
	closeBtn:SetScript("OnClick", function()
		main:Hide()
	end)

	local gear = CreateFrame("Button", nil, main)
	gear:SetSize(16, 16)
	gear:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	-- Shared by main's own drag handling and each row's left-click fallback
	-- (rows have mouse enabled for the right-click "safe" report, so a
	-- left-click drag started on a row needs to explicitly move the whole
	-- panel too, same as clicking anywhere else on it).
	function main.StartPanelMove()
		if not ns.db.locked then
			main:StartMoving()
			main.isMoving = true
		end
	end
	function main.StopPanelMove()
		if main.isMoving then
			main:StopMovingOrSizing()
			main.isMoving = false
			local p, _, rp, x, y = main:GetPoint()
			ns.db.point = { p, nil, rp, x, y }
		end
	end

	main:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then
			main.StartPanelMove()
		end
	end)
	main:SetScript("OnMouseUp", function()
		main.StopPanelMove()
	end)

	local rowsByKey = {}
	for _, base in ipairs(ns.BASES) do
		local row = CreateRow(main, base, theme, rowsByKey)
		row.base = base
		rowsByKey[base.key] = row
	end

	-- Divider shown between the "mine" and "other" ownership groups by
	-- ns.RefreshOwnership(); hidden whenever every base is in the same group.
	local groupDivider = main:CreateTexture(nil, "OVERLAY")
	groupDivider:SetTexture(ns.FLAT)
	groupDivider:SetHeight(1)
	groupDivider:SetVertexColor(unpack(theme.dividerColor))
	groupDivider:Hide()

	ns.rowsByKey = rowsByKey
	ns.groupDivider = groupDivider
	ns.RefreshOwnership()

	local settings = CreateSettingsFrame(main, theme)
	gear:SetScript("OnClick", function()
		settings:SetShown(not settings:IsShown())
	end)

	local resizeGrip = CreateFrame("Button", nil, main)
	resizeGrip:SetSize(16, 16)
	resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
	resizeGrip:SetFrameLevel(main:GetFrameLevel() + 10)
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

	local resizing = false
	local startCursorX, startCursorY, startScale

	resizeGrip:SetScript("OnMouseDown", function()
		resizing = true
		startScale = main:GetScale()
		startCursorX, startCursorY = GetCursorPosition()
	end)

	local function StopResizing()
		if resizing then
			resizing = false
			ns.db.scale = main:GetScale()
		end
	end
	resizeGrip:SetScript("OnMouseUp", StopResizing)
	resizeGrip:SetScript("OnHide", StopResizing)

	resizeGrip:SetScript("OnUpdate", function()
		if not resizing then
			return
		end
		local x, y = GetCursorPosition()
		local uiScale = UIParent:GetEffectiveScale()
		local dx = (x - startCursorX) / uiScale
		local dy = (startCursorY - y) / uiScale
		local newScale = startScale + ((dx + dy) / 2) / PANEL_WIDTH
		if newScale < MIN_SCALE then
			newScale = MIN_SCALE
		elseif newScale > MAX_SCALE then
			newScale = MAX_SCALE
		end
		main:SetScale(newScale)
	end)

	ns.mainFrame = main
	ns.settingsFrame = settings

	if wasShown then
		main:Show()
	else
		main:Hide()
	end
	if settingsWasShown then
		settings:Show()
	end

	ns.cooldownTicker = C_Timer.NewTicker(0.25, function()
		for _, row in pairs(rowsByKey) do
			ns.RefreshRowCooldown(row)
		end
	end)
end

function ns.SetTheme(key)
	if ns.THEMES[key] and ns.db.theme ~= key then
		ns.db.theme = key
		ns.CreateMainFrame()
	end
end

function ns.ResetPosition()
	ns.db.point = { "CENTER", nil, "CENTER", 0, 150 }
	if ns.mainFrame then
		ns.mainFrame:ClearAllPoints()
		local p = ns.db.point
		ns.mainFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	end
end
