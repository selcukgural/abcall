local _, ns = ...

-- The 5 Arathi Basin bases. Names/order are hardcoded because Classic Era's
-- API does not expose AB node names anywhere.
ns.BASES = {
	{ key = "stables",    name = "Stables" },
	{ key = "farm",       name = "Farm" },
	{ key = "lumbermill", name = "Lumber Mill" },
	{ key = "blacksmith", name = "Blacksmith" },
	{ key = "goldmine",   name = "Gold Mine" },
}

-- Per-base accent colors used to tint the count buttons.
ns.COLORS = {
	stables    = { 0.30, 0.69, 0.90 },
	farm       = { 0.55, 0.80, 0.35 },
	lumbermill = { 0.80, 0.55, 0.25 },
	blacksmith = { 0.80, 0.35, 0.35 },
	goldmine   = { 0.90, 0.75, 0.20 },
}

-- Short, mutually-exclusive, case-insensitive keywords used to match a base
-- against real BG system chat text (e.g. "The Alliance has taken the
-- blacksmith!", "...has assaulted the mine!"). These are NOT the display
-- names - Gold Mine shows up as just "mine" in chat, "Farm" sometimes shows
-- as "the southern farm", etc., confirmed from actual in-game screenshots.
ns.BASE_KEYWORDS = {
	stables    = "stables",
	farm       = "farm",
	lumbermill = "lumber mill",
	blacksmith = "blacksmith",
	goldmine   = "mine",
}

-- Base-name label colors reflecting live ownership status. The "Pending"
-- variants are a muted shade shown while a capture is in progress but not
-- yet confirmed (the real ~1 minute uncontested window AB uses before a
-- capture actually finalizes) - full color only once "has taken" confirms it.
ns.STATUS_COLORS = {
	neutral      = { 0.6, 0.6, 0.6 },
	own          = { 0.2, 0.85, 0.3 },
	ownPending   = { 0.6, 0.8, 0.35 },
	enemy        = { 0.9, 0.25, 0.25 },
	enemyPending = { 0.85, 0.5, 0.3 },
}

-- Arathi Basin's uiMapID, confirmed via Questie's own zone database
-- (areaID 3358 -> uiMapID 1461 in Questie/Database/Zones/data/areaIdToUiMapId.lua).
ns.AB_MAP_ID = 1461

-- Best-effort published flag coordinates (normalized 0-1, matching
-- C_Map.GetPlayerMapPosition's return shape), based on AB's well-known
-- pentagon layout (Stables north, Blacksmith center, Farm SW, Lumber Mill SE,
-- Gold Mine south). Not measured in-client yet - see the plan's verification
-- step to sanity-check/tune these against a live GetPlayerMapPosition reading.
ns.BASE_COORDS = {
	stables    = { x = 0.51, y = 0.21 },
	blacksmith = { x = 0.51, y = 0.50 },
	farm       = { x = 0.28, y = 0.65 },
	lumbermill = { x = 0.75, y = 0.63 },
	goldmine   = { x = 0.51, y = 0.84 },
}

-- Flat white texture used everywhere for backdrops/borders/buttons, present
-- since Vanilla and safe on Classic Era.
ns.FLAT = "Interface\\Buttons\\WHITE8x8"

ns.FONT = "Fonts\\FRIZQT__.TTF"

-- Two selectable visual skins. "classic" leans on the real classic-era beveled
-- button template + a warm gold/parchment palette; "modern" is the flat
-- minimalist skin (the addon's original look), closer to current retail UI.
ns.THEMES = {
	classic = {
		label = "Classic",
		buttonStyle = "classic",
		-- The genuine classic-era gold/black tooltip border (same family of
		-- texture used throughout the stock Vanilla/Classic UI), so the panel's
		-- outer frame reads as authentically "classic" as the buttons do.
		backdrop = {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		},
		backdropColor = { 0.08, 0.06, 0.03, 0.95 },
		backdropBorderColor = { 1, 1, 1, 1 },
		titleBarColor = { 0.30, 0.16, 0.05, 0.75 },
		titleColor = { 1, 0.82, 0.0, 1 },
		dividerColor = { 0.55, 0.45, 0.18, 0.8 },
	},
	modern = {
		label = "Modern",
		buttonStyle = "flat",
		backdrop = { bgFile = ns.FLAT, edgeFile = ns.FLAT, edgeSize = 1 },
		backdropColor = { 0.06, 0.06, 0.06, 0.85 },
		backdropBorderColor = { 1, 1, 1, 0.2 },
		titleBarColor = { 0.16, 0.6, 0.35, 0.55 },
		titleColor = { 1, 1, 1, 1 },
		dividerColor = { 1, 1, 1, 0.15 },
	},
}

ns.THEME_ORDER = { "classic", "modern" }
