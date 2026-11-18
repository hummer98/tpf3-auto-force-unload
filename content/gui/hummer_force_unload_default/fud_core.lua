-- Force Unload by Default: logic, kept free of game globals so it runs in
-- the offline tests.
--
-- The base line manager decides every stop's load list in
-- line_util.autoLoadConfig (gui/line_vehicle_mgmt/line_util.tl), which
-- manager_window.tl calls after each stop edit (new line, add / remove /
-- reorder a stop, add a waypoint) and right before it commits the line.
-- forceUnload itself is only ever set by makeNewStop (always false) and by
-- the player in the cargo filter window. Running after autoLoadConfig, the
-- load lists are final, so "this stop loads nothing" can be read off them.
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

local function applyTo(via)
	local cfg = stopConfigOf(via)
	if cfg == nil then return end
	cfg.forceUnload = not M.hasLoad(cfg.load)
end

-- Sets forceUnload on the stops of line (a Line.ReactLine). isNew(via) tells
-- whether the stop was made in this edit; it is only asked in MODE_NEW.
function M.apply(line, mode, isNew)
	if type(line) ~= "table" or line.customFilters then return end
	local path = line.path
	if type(path) ~= "table" then return end

	if mode ~= M.MODE_NEW then
		for _, via in ipairs(path) do
			applyTo(via)
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
		applyTo(via)
	end
	-- A line is created as soon as its first stop is placed, and with one
	-- stop nothing can be loaded there yet (cargo is only loaded for another
	-- stop that takes it), so that first verdict is almost always "on". When
	-- the line grows from that single stop, it is decided again together
	-- with the new ones; otherwise every line's first stop would keep
	-- force-unloading even where it loads.
	if #oldVias == 1 then
		applyTo(oldVias[1])
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
			M.apply(line, deps.getMode and deps.getMode() or M.DEFAULT_MODE, isNew)
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

return M
