-- Force Unload by Default: logic, kept free of game globals so it runs in
-- the offline tests.
--
-- The base line manager decides every stop's load list in
-- line_util.autoLoadConfig (gui/line_vehicle_mgmt/line_util.tl), which
-- manager_window.tl calls after each stop edit (new line, add / remove /
-- reorder a stop, add a waypoint) and right before it commits the line.
-- forceUnload itself is only ever set by makeNewStop (always false) and by
-- the player in the cargo filter window. Running after autoLoadConfig, the
-- load lists are final, so "this stop loads no cargo" can be read off them.
--
-- Lines with customFilters = true are left alone: the base sets it when the
-- player edits a stop's load config or one of its checkboxes, and its own
-- autoLoadConfig returns early for them too.
local M = {}

M.MOD_ID = "hummer_force_unload_default"

-- Values of the "mode" param, as the game hands them (1-based index into
-- the mod.json values list).
M.MODE_ALL = 1 -- every stop of the edited line
M.MODE_NEW = 2 -- only stops made by makeNewStop in this edit
M.DEFAULT_MODE = M.MODE_ALL

-- Values of the "stop_icon" param (same indexing): the marker in the line
-- manager's stop list. On unless the player switched it off.
M.ICON_OFF = 1
M.ICON_ON = 2

-- Values of the development param "dev_marker" (same indexing). Default
-- and anything unknown: MARKER_NORMAL. The probes put the marker in a
-- recipe of its own (the form that failed in game) and differ in one thing
-- each, to tell the cause apart.
M.MARKER_NORMAL = 1         -- box { icon or empty cell, built in the row's render, base node }
M.MARKER_BOX_ONLY = 2       -- box { empty cell, base node }: the form that worked in game
M.MARKER_PROBE_GRAVITY = 3  -- recipe root: empty Component, class with gravity + margin
M.MARKER_PROBE_TOOLTIP = 4  -- recipe root: ImageView with tooltip, class with size only
M.MARKER_PROBE_PLAIN = 5    -- recipe root: empty Component, class with size only

-- Marker field on the line_util table: the GUI may load the entry script
-- more than once, and a second wrap would run the post-processing twice and
-- keep a stale closure in the chain.
M.GUARD_KEY = "__hummer_force_unload_default"

-- The mode from api.engine.config.getModParams()'s result. Anything that is
-- not a known value (params unreadable, mod missing from the table, a value
-- from a future mod.json) falls back to the default.
function M.modeFromParams(all)
	local mine = type(all) == "table" and all[M.MOD_ID] or nil
	local v = type(mine) == "table" and mine.mode or nil
	if v == M.MODE_NEW then return M.MODE_NEW end
	return M.DEFAULT_MODE
end

-- Whether the stop list marker is shown. Unreadable or unknown -> shown
-- (the default in mod.json).
function M.iconFromParams(all)
	local mine = type(all) == "table" and all[M.MOD_ID] or nil
	local v = type(mine) == "table" and mine.stop_icon or nil
	return v ~= M.ICON_OFF
end

function M.markerVariantFromParams(all)
	local mine = type(all) == "table" and all[M.MOD_ID] or nil
	local v = type(mine) == "table" and mine.dev_marker or nil
	if type(v) == "number" and v >= M.MARKER_BOX_ONLY and v <= M.MARKER_PROBE_PLAIN and v % 1 == 0 then
		return v
	end
	return M.MARKER_NORMAL
end

-- true when the load list has at least one cargo type (passengers count)
-- switched on. The base fills it as a Lua array (makeIdvector); one read back
-- from a StopConfig may be an engine vector, which the base itself walks
-- with ipairs (cargofilter_window.tl), so that is the fallback.
function M.hasLoad(load)
	if load == nil then return false end
	if type(load) == "table" then
		for _, v in pairs(load) do
			if v == true then return true end
		end
		return false
	end
	for _, v in ipairs(load) do
		if v == true then return true end
	end
	return false
end

local function stopConfigOf(via)
	local stop = type(via) == "table" and via.stop or nil
	local data = type(stop) == "table" and stop.passThroughStopData or nil
	return type(data) == "table" and data.stopConfig or nil
end

-- true when the load list has a cargo other than passengers switched on.
-- The base switches passengers on at every stop whose station takes them,
-- cargo truck stops included (seen in game), so counting them would leave
-- no stop "loading nothing". passengerIndex is the 1-based slot of the
-- passenger cargo type (cargo id + 1); nil counts every slot.
function M.hasCargoLoad(load, passengerIndex)
	if passengerIndex == nil then return M.hasLoad(load) end
	if load == nil then return false end
	if type(load) == "table" then
		for k, v in pairs(load) do
			if v == true and k ~= passengerIndex then return true end
		end
		return false
	end
	for k, v in ipairs(load) do
		if v == true and k ~= passengerIndex then return true end
	end
	return false
end

-- A passenger-only line has no cargo to force-unload; leaving it alone also
-- keeps the stop-list marker off every bus stop.
local function lineLoadsCargo(path, passengerIndex)
	for _, via in ipairs(path) do
		local cfg = stopConfigOf(via)
		if cfg ~= nil and M.hasCargoLoad(cfg.load, passengerIndex) then return true end
	end
	return false
end

local function applyTo(via, cargoLine, passengerIndex)
	local cfg = stopConfigOf(via)
	if cfg == nil then return end
	cfg.forceUnload = cargoLine and not M.hasCargoLoad(cfg.load, passengerIndex)
end

-- Sets forceUnload on the stops of line (a Line.ReactLine). isNew(via) tells
-- whether the stop was made in this edit; it is only asked in MODE_NEW.
-- passengerIndex: see hasCargoLoad.
function M.apply(line, mode, isNew, passengerIndex)
	if type(line) ~= "table" or line.customFilters then return end
	local path = line.path
	if type(path) ~= "table" then return end
	local cargoLine = lineLoadsCargo(path, passengerIndex)

	if mode ~= M.MODE_NEW then
		for _, via in ipairs(path) do
			applyTo(via, cargoLine, passengerIndex)
		end
		return
	end

	local newVias, oldVias = {}, {}
	for _, via in ipairs(path) do
		if stopConfigOf(via) ~= nil then
			if isNew and isNew(via) then
				newVias[#newVias + 1] = via
			else
				oldVias[#oldVias + 1] = via
			end
		end
	end
	if #newVias == 0 then return end
	for _, via in ipairs(newVias) do
		applyTo(via, cargoLine, passengerIndex)
	end
	-- A line is created as soon as its first stop is placed, and with one
	-- stop no cargo can be loaded yet (cargo is only loaded for another stop
	-- that takes it), so that first stop is always decided "off" (no cargo
	-- line). When the line grows from that single stop, it is decided again
	-- together with the new ones; otherwise a line started at its unload
	-- end would never get force unload there.
	if #oldVias == 1 then
		applyTo(oldVias[1], cargoLine, passengerIndex)
	end
end

-- The game runs Lua 5.x with table.unpack (the base uses it); the offline
-- tests run on LuaJIT, which only has the global.
local unpack = table.unpack or unpack

local function pack(...)
	return { n = select("#", ...), ... }
end

-- Wraps line_util.autoLoadConfig (and makeNewStop, for MODE_NEW) once.
-- deps: getMode() -> mode, log(msg) for failures, marks (optional weak
-- table; a fresh one by default). Returns true when autoLoadConfig is
-- wrapped (now or by an earlier load).
function M.install(line_util, deps)
	deps = deps or {}
	local log = deps.log or function() end
	if type(line_util) ~= "table" then
		log("line_util unavailable (" .. type(line_util) .. "); nothing wrapped")
		return false
	end
	if line_util[M.GUARD_KEY] then return true end

	local origAuto = line_util.autoLoadConfig
	if type(origAuto) ~= "function" then
		log("line_util.autoLoadConfig is " .. type(origAuto) .. "; nothing wrapped")
		return false
	end

	-- Stops made by makeNewStop, keyed by the via table it returns (which the
	-- manager window puts into the path as is) and by its .stop, in case a
	-- wrapper in between rebuilds the via around the same stop. Weak keys: a
	-- stop of an edit that never reaches autoLoadConfig must not be kept.
	-- Nothing is written into the stop itself, since it is sent to the game.
	local marks = deps.marks or setmetatable({}, { __mode = "k" })
	local function isNew(via)
		return marks[via] == true or (type(via) == "table" and via.stop ~= nil and marks[via.stop] == true)
	end
	local function clearMarks(line)
		local path = type(line) == "table" and line.path or nil
		if type(path) ~= "table" then return end
		for _, via in ipairs(path) do
			if type(via) == "table" then
				marks[via] = nil
				if via.stop ~= nil then marks[via.stop] = nil end
			end
		end
	end

	local failed = false
	line_util.autoLoadConfig = function(line, ...)
		-- The base call runs unprotected: if it throws, the edit fails exactly
		-- as it would without this mod, and nothing below runs.
		local results = pack(origAuto(line, ...))
		local ok, err = pcall(function()
			M.apply(line, deps.getMode and deps.getMode() or M.DEFAULT_MODE, isNew, deps.passengerIndex and deps.passengerIndex() or nil)
		end)
		pcall(clearMarks, line)
		if not ok and not failed then
			-- once: a broken step would otherwise log on every stop edit
			failed = true
			log("autoLoadConfig post-processing failed: " .. tostring(err) .. " (further failures not logged)")
		end
		return unpack(results, 1, results.n)
	end

	local origNew = line_util.makeNewStop
	if type(origNew) == "function" then
		line_util.makeNewStop = function(...)
			local results = pack(origNew(...))
			local via = results[1]
			if type(via) == "table" then
				marks[via] = true
				if type(via.stop) == "table" then marks[via.stop] = true end
			end
			return unpack(results, 1, results.n)
		end
	else
		log("line_util.makeNewStop is " .. type(origNew) .. "; \"new stops only\" changes nothing")
	end

	line_util[M.GUARD_KEY] = true
	return true
end

------------------------------------------------------------------------
-- Stop list marker
------------------------------------------------------------------------
-- The stop rows of the line manager (LineStopItem, a file-local recipe of
-- gui/line_vehicle_mgmt/line_manager_panel.tl, so it cannot be replaced from
-- outside) render the stop name and right after it
-- line_react_util.LineCargoDisplay{ lineEntity, stopIndex,
-- stopCargoDisplay = true, ... }. That is the only caller passing
-- stopCargoDisplay (the line rows and the vehicle rows show the whole
-- line's cargo). The module field is looked up per call, so wrapping it
-- puts the marker between the name and the cargo icons without replacing
-- any recipe: the base node is built by the previous function with its own
-- params, untouched, and other wrappers of the field stay in the chain.

M.ICON_GUARD_KEY = "__hummer_force_unload_default_icon"

-- Recipes and builtins can be called as X{params} or X(ref, {params}); the
-- params table is the last argument.
local function lastArg(...)
	local n = select("#", ...)
	if n == 0 then return nil end
	return (select(n, ...))
end
M.lastArg = lastArg

-- The params of a stop row's cargo display, or nil for any other call.
function M.stopRowParams(...)
	local p = lastArg(...)
	if type(p) ~= "table" or p.stopCargoDisplay ~= true then return nil end
	if p.lineEntity == nil or type(p.stopIndex) ~= "number" then return nil end
	return p
end

-- Reads stopConfig.forceUnload of the stop at the 0-based API index of a
-- line (engine.d.tl Line.stops; the stop row passes params.stopIndex, which
-- the base also hands to the cargo filter window as apiStopIndex0).
-- getComponent(entity, type) -> component or nil. false when anything is
-- missing.
function M.readForceUnload(getComponent, lineEntity, stopIndex)
	if lineEntity == nil or type(stopIndex) ~= "number" then return false end
	local line = getComponent(lineEntity)
	if line == nil then return false end
	local stops = line.stops
	if stops == nil then return false end
	local stop = stops[stopIndex + 1]
	local cfg = stop and stop.stopConfig
	return cfg ~= nil and cfg.forceUnload == true
end

-- Wraps line_react_util.LineCargoDisplay once. deps: enabled() -> boolean
-- (the param), decorate(node, params) -> node with the marker, log(msg),
-- onFailure(err) (optional). A failing decorate returns the base node,
-- logged once, and switches the marker off for the session.
function M.installIcon(line_react_util, deps)
	deps = deps or {}
	local log = deps.log or function() end
	if type(line_react_util) ~= "table" then
		log("line_react_util unavailable (" .. type(line_react_util) .. "); no stop marker")
		return false
	end
	if line_react_util[M.ICON_GUARD_KEY] then return true end
	local prev = line_react_util.LineCargoDisplay
	if prev == nil then
		log("line_react_util.LineCargoDisplay missing; no stop marker")
		return false
	end
	-- After the first failure no stop row is decorated any more: a part that
	-- keeps failing (e.g. only the icon) would otherwise leave some rows
	-- boxed and others bare, and the cargo column would zigzag.
	local failed = false
	line_react_util.LineCargoDisplay = function(...)
		local node = prev(...)
		if failed then return node end
		local params = M.stopRowParams(...)
		if params == nil then return node end
		local ok, result = pcall(function()
			if deps.enabled and not deps.enabled() then return node end
			return deps.decorate(node, params)
		end)
		if ok and result ~= nil then return result end
		if not ok then
			failed = true
			log("stop marker failed, stop rows are no longer decorated: " .. tostring(result))
			if deps.onFailure then pcall(deps.onFailure, result) end
		end
		return node
	end
	-- prev / wrapper are kept for shimReplacementApi
	line_react_util[M.ICON_GUARD_KEY] = { prev = prev, wrapper = line_react_util.LineCargoDisplay }
	return true
end

-- The field now holds a plain function, not the registered recipe. A mod
-- whose replacement config runs later and calls
-- ReplaceRecipe(line_react_util.LineCargoDisplay, x) would hand the engine
-- that function; map it back to the recipe it wraps (as other mods that
-- wrap recipe fields do). No-op when the api has no ReplaceRecipe.
function M.shimReplacementApi(replacementApi, line_react_util)
	if type(replacementApi) ~= "table" or type(line_react_util) ~= "table" then return false end
	local state = line_react_util[M.ICON_GUARD_KEY]
	local replace = replacementApi.ReplaceRecipe
	if type(state) ~= "table" or type(replace) ~= "function" then return false end
	if replacementApi[M.ICON_GUARD_KEY] then return true end
	replacementApi.ReplaceRecipe = function(original, ...)
		if original == state.wrapper then original = state.prev end
		return replace(original, ...)
	end
	replacementApi[M.ICON_GUARD_KEY] = true
	return true
end

return M
