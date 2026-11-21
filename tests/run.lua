-- Offline tests for Force Unload by Default. Run from anywhere:
--   luajit tests/run.lua
-- No game needed: the globals the scripts expect (api, ug_require,
-- debugPrint) are stubbed below with just enough behaviour.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)/tests/[^/]*$") or "."

local loaders = package.loaders or package.searchers
table.insert(loaders, 2, function(name)
	local rel = name:match("^hummer_force_unload_default::/(.*)$")
	if rel then return assert(loadfile(root .. "/content/" .. rel)) end
end)

local failures, passes = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

local core = require "hummer_force_unload_default::/gui/hummer_force_unload_default/fud_core.lua"

------------------------------------------------------------------------
-- fixtures
------------------------------------------------------------------------
-- cargo type ids 0..3 -> load arrays indexed 1..4 (the base's IdVector);
-- index 1 stands for passengers here.
local function load(...)
	local t = { false, false, false, false }
	for _, i in ipairs({ ... }) do t[i] = true end
	return t
end

local function via(loadList, forceUnload)
	return { stop = { stationGroup = 1, passThroughStopData = {
		stopConfig = { load = loadList, maxLoad = {}, forceUnload = forceUnload },
		maxAdditionalWaitingTime = 30,
	} } }
end

local function fu(v) return v.stop.passThroughStopData.stopConfig.forceUnload end

-- A line_util stand-in: autoLoadConfig writes the load lists from
-- line.plan (stop index -> list), as the base decides them, and skips
-- customFilters lines like the base does.
local function fakeLineUtil()
	local lu = { calls = 0, newCalls = 0 }
	lu.autoLoadConfig = function(line)
		lu.calls = lu.calls + 1
		if line.customFilters then return end
		for i, v in ipairs(line.path) do
			if v.stop and line.plan and line.plan[i] then
				v.stop.passThroughStopData.stopConfig.load = line.plan[i]
			end
		end
		return "orig-result", 2
	end
	lu.makeNewStop = function(details)
		lu.newCalls = lu.newCalls + 1
		return via(load(), false)
	end
	return lu
end

local function installed(mode, logs)
	local lu = fakeLineUtil()
	local ok = core.install(lu, {
		getMode = function() return mode end,
		log = function(m) if logs then logs[#logs + 1] = m end end,
	})
	assert(ok, "install failed")
	return lu
end

------------------------------------------------------------------------
-- params
------------------------------------------------------------------------
test("modeFromParams: 1-based values, default when unknown or unreadable", function()
	eq(core.modeFromParams({ hummer_force_unload_default = { mode = 1 } }), core.MODE_ALL)
	eq(core.modeFromParams({ hummer_force_unload_default = { mode = 2 } }), core.MODE_NEW)
	eq(core.modeFromParams({ hummer_force_unload_default = { mode = 0 } }), core.MODE_ALL)
	eq(core.modeFromParams({ hummer_force_unload_default = { mode = 3 } }), core.MODE_ALL)
	eq(core.modeFromParams({ hummer_force_unload_default = {} }), core.MODE_ALL)
	eq(core.modeFromParams({ other_mod = { mode = 2 } }), core.MODE_ALL)
	eq(core.modeFromParams({}), core.MODE_ALL)
	eq(core.modeFromParams(nil), core.MODE_ALL)
	eq(core.modeFromParams("x"), core.MODE_ALL)
	eq(core.DEFAULT_MODE, core.MODE_ALL)
end)

test("mod.json: mode param default is the first value (\"all stops\")", function()
	local f = assert(io.open(root .. "/mod.json"))
	local s = f:read("*a"); f:close()
	assert(s:find('"key": "mode"', 1, true), "mode param missing")
	assert(s:find('"defaultIndex": 0', 1, true), "defaultIndex 0 expected")
	assert(s:find('"cosmetic": false', 1, true), "cosmetic false expected")
	local all = s:find("hummer_force_unload_default_mode_all", 1, true)
	local new = s:find("hummer_force_unload_default_mode_new", 1, true)
	assert(all and new and all < new, "values order: all, new")
end)

-- The game's 13 UI languages (base/strings/<lang>); a missing language
-- falls back to the raw key, so every key must be in every block.
local LANGS = { "en", "ja", "de", "es", "fr", "it", "ko", "nl", "pl", "pt_BR", "ru", "zh_CN", "zh_TW" }

test("strings.json: all 13 languages have every key mod.json uses", function()
	local f = assert(io.open(root .. "/strings.json"))
	local s = f:read("*a"); f:close()
	local blocks = 0
	for _ in s:gmatch('\n\t"[%w_]+": (%b{})') do blocks = blocks + 1 end
	eq(blocks, #LANGS, "language blocks in strings.json")
	for _, lang in ipairs(LANGS) do
		local block = s:match('"' .. lang .. '"%s*:%s*(%b{})')
		assert(block, lang .. " block missing")
		for _, key in ipairs({ "mod_name", "hummer_force_unload_default_mode_name", "hummer_force_unload_default_mode_tip",
			"hummer_force_unload_default_mode_all", "hummer_force_unload_default_mode_new" }) do
			assert(block:find('"' .. key .. '"', 1, true), lang .. ": " .. key .. " missing")
		end
	end
end)

------------------------------------------------------------------------
-- hasLoad
------------------------------------------------------------------------
test("hasLoad: nil / empty / all false -> false; any true -> true", function()
	eq(core.hasLoad(nil), false)
	eq(core.hasLoad({}), false)
	eq(core.hasLoad(load()), false)
	eq(core.hasLoad(load(3)), true)
	eq(core.hasLoad(load(1)), true) -- passengers count
end)

test("hasLoad: a sparse table is read completely (pairs, not ipairs)", function()
	eq(core.hasLoad({ [1] = false, [5] = true }), true)
end)

test("hasLoad: a non-table load goes the ipairs way; a broken one throws for the wrapper's pcall", function()
	-- An engine vector (userdata) cannot be built under LuaJIT, whose ipairs
	-- also rejects userdata; this only checks that such a value is not
	-- silently read as "loads nothing".
	local ok = pcall(core.hasLoad, 42)
	eq(ok, false)
end)

------------------------------------------------------------------------
-- apply: MODE_ALL
------------------------------------------------------------------------
test("all: load all false on a line that carries cargo -> forceUnload true", function()
	local line = { path = { via(load(2), false), via(load(), false) } }
	core.apply(line, core.MODE_ALL, nil, 1)
	eq(fu(line.path[1]), false)
	eq(fu(line.path[2]), true)
end)

test("all: passengers-only stop with the passenger slot unknown counts as loading -> off", function()
	-- on a cargo line, so only the passenger counting keeps it off
	local line = { path = { via(load(2), true), via(load(1), true) } }
	core.apply(line, core.MODE_ALL, nil, nil)
	eq(fu(line.path[2]), false)
end)

test("all: mixed line -> loading stop off, unload-only stop on", function()
	local line = { path = { via(load(2, 3), true), via(load(), false), via(load(4), nil) } }
	core.apply(line, core.MODE_ALL)
	eq(fu(line.path[1]), false)
	eq(fu(line.path[2]), true)
	eq(fu(line.path[3]), false)
end)

test("all: customFilters = true -> nothing changes", function()
	local line = { customFilters = true, path = { via(load(), false), via(load(2), true) } }
	core.apply(line, core.MODE_ALL)
	eq(fu(line.path[1]), false)
	eq(fu(line.path[2]), true)
end)

test("all: customFilters nil (a brand-new line) counts as false", function()
	local line = { path = { via(load(3), true), via(load(), false) } }
	core.apply(line, core.MODE_ALL, nil, 1)
	eq(fu(line.path[2]), true)
end)

test("all: waypoints (no stop) and stops without stopConfig are skipped", function()
	local wp = { waypoint = { tag = 3 } }
	local bare = { stop = { stationGroup = 1 } }
	local line = { path = { via(load(), false), wp, bare, via(load(2), true) } }
	core.apply(line, core.MODE_ALL)
	eq(fu(line.path[1]), true)
	eq(wp.stop, nil)
	eq(bare.stop.passThroughStopData, nil)
	eq(fu(line.path[4]), false)
end)

test("apply: empty path, missing path, nil and non-table lines do nothing", function()
	core.apply({ path = {} }, core.MODE_ALL)
	core.apply({}, core.MODE_ALL)
	core.apply(nil, core.MODE_ALL)
	core.apply("line", core.MODE_ALL)
	core.apply({ path = {} }, core.MODE_NEW, function() return true end)
end)

------------------------------------------------------------------------
-- apply: MODE_NEW
------------------------------------------------------------------------
test("new: existing stops keep their value, only new ones are set", function()
	local a, b, n = via(load(), false), via(load(2), true), via(load(), false)
	local line = { path = { a, b, n } }
	core.apply(line, core.MODE_NEW, function(v) return v == n end)
	eq(fu(a), false)
	eq(fu(b), true)
	eq(fu(n), true)
end)

test("new: no stop marked -> nothing changes", function()
	local a, b = via(load(), false), via(load(2), true)
	core.apply({ path = { a, b } }, core.MODE_NEW, function() return false end)
	eq(fu(a), false)
	eq(fu(b), true)
	core.apply({ path = { a, b } }, core.MODE_NEW, nil)
	eq(fu(a), false)
	eq(fu(b), true)
end)

test("new: a line growing from its single first stop sets that stop again", function()
	-- the first stop was on (e.g. set before); it loads once the second
	-- stop is added, so it must turn off
	local first, n = via(load(3), true), via(load(), false)
	core.apply({ path = { first, n } }, core.MODE_NEW, function(v) return v == n end)
	eq(fu(first), false)
	eq(fu(n), true)
end)

test("new: waypoints do not count as existing stops", function()
	local first, n = via(load(3), true), via(load(), false)
	local line = { path = { first, { waypoint = {} }, n } }
	core.apply(line, core.MODE_NEW, function(v) return v == n end)
	eq(fu(first), false, "the single existing stop is set again")
end)

test("new: customFilters = true -> nothing changes, even for new stops", function()
	local n = via(load(), false)
	core.apply({ customFilters = true, path = { n } }, core.MODE_NEW, function() return true end)
	eq(fu(n), false)
end)

------------------------------------------------------------------------
-- install / wrappers
------------------------------------------------------------------------
test("install: autoLoadConfig runs the original first, keeps its results", function()
	local lu = installed(core.MODE_ALL)
	local line = { path = { via(load(), false), via(load(), true) }, plan = { load(2), load() } }
	local r1, r2 = lu.autoLoadConfig(line)
	eq(lu.calls, 1)
	eq(r1, "orig-result"); eq(r2, 2)
	eq(fu(line.path[1]), false, "decided on the load the original wrote")
	eq(fu(line.path[2]), true)
end)

test("install: customFilters line -> original runs, nothing changes", function()
	local lu = installed(core.MODE_ALL)
	local line = { customFilters = true, path = { via(load(), false) } }
	lu.autoLoadConfig(line)
	eq(lu.calls, 1)
	eq(fu(line.path[1]), false)
end)

test("install: nil line -> the original decides (no extra error)", function()
	local lu = fakeLineUtil()
	local seen = "unset"
	lu.autoLoadConfig = function(line) seen = line end
	local logs = {}
	core.install(lu, { getMode = function() return core.MODE_ALL end, log = function(m) logs[#logs + 1] = m end })
	lu.autoLoadConfig(nil)
	eq(seen, nil)
	eq(#logs, 0)
end)

test("install: an error in the original propagates unchanged, nothing applied", function()
	local lu = fakeLineUtil()
	lu.autoLoadConfig = function() error("base failure", 0) end
	core.install(lu, { getMode = function() return core.MODE_ALL end })
	local line = { path = { via(load(), false) } }
	local ok, err = pcall(lu.autoLoadConfig, line)
	eq(ok, false)
	eq(err, "base failure")
	eq(fu(line.path[1]), false)
end)

test("install: a failing post-step is logged once and does not break the edit", function()
	local logs = {}
	local lu = fakeLineUtil()
	core.install(lu, { getMode = function() error("boom") end, log = function(m) logs[#logs + 1] = m end })
	local r = lu.autoLoadConfig({ path = {} })
	eq(r, "orig-result")
	lu.autoLoadConfig({ path = {} })
	eq(#logs, 1)
	assert(logs[1]:find("post%-processing failed"), logs[1])
end)

test("install: getMode is asked per call (mode switches take effect)", function()
	local mode = core.MODE_NEW
	local lu = fakeLineUtil()
	core.install(lu, { getMode = function() return mode end })
	local a, b = via(load(), false), via(load(2), false)
	lu.autoLoadConfig({ path = { a, b } })
	eq(fu(a), false, "MODE_NEW, nothing marked")
	mode = core.MODE_ALL
	lu.autoLoadConfig({ path = { a, b } })
	eq(fu(a), true)
end)

test("install twice: wrapped once (guard on the line_util table)", function()
	local lu = installed(core.MODE_ALL)
	local wrapped = lu.autoLoadConfig
	local wrappedNew = lu.makeNewStop
	eq(core.install(lu, { getMode = function() return core.MODE_ALL end }), true)
	eq(lu.autoLoadConfig, wrapped)
	eq(lu.makeNewStop, wrappedNew)
	lu.autoLoadConfig({ path = {} })
	eq(lu.calls, 1, "original ran once per call")
end)

test("install: non-table line_util / missing autoLoadConfig -> false + log", function()
	local logs = {}
	local log = function(m) logs[#logs + 1] = m end
	eq(core.install(nil, { log = log }), false)
	eq(core.install({}, { log = log }), false)
	eq(#logs, 2)
	assert(logs[1]:find("unavailable"), logs[1])
end)

test("install: missing makeNewStop -> autoLoadConfig still wrapped, logged", function()
	local logs = {}
	local lu = fakeLineUtil()
	lu.makeNewStop = nil
	eq(core.install(lu, { getMode = function() return core.MODE_ALL end, log = function(m) logs[#logs + 1] = m end }), true)
	eq(#logs, 1)
	local line = { path = { via(load(2), false), via(load(), false) } }
	lu.autoLoadConfig(line)
	eq(fu(line.path[2]), true)
end)

test("mode new, end to end: add a stop to an existing line", function()
	local lu = installed(core.MODE_NEW)
	local a, b = via(load(2), false), via(load(), false) -- existing, both off
	local n = lu.makeNewStop({ stationGroup = 7 })
	eq(lu.newCalls, 1)
	local line = { path = { a, b, n }, plan = { load(2), load(), load() } }
	lu.autoLoadConfig(line)
	eq(fu(a), false)
	eq(fu(b), false, "existing unload-only stop not changed")
	eq(fu(n), true, "new unload-only stop on")
end)

test("mode new: the mark is not written into the stop sent to the game", function()
	local lu = installed(core.MODE_NEW)
	local n = lu.makeNewStop({})
	local keys = {}
	for k in pairs(n) do keys[#keys + 1] = k end
	eq(#keys, 1); eq(keys[1], "stop")
	for k in pairs(n.stop.passThroughStopData.stopConfig) do
		assert(k == "load" or k == "maxLoad" or k == "forceUnload", "unexpected field " .. tostring(k))
	end
end)

test("mode new: marks are dropped after the edit (a later edit sees an existing stop)", function()
	local lu = installed(core.MODE_NEW)
	local a, b = via(load(2), false), via(load(), false)
	local n = lu.makeNewStop({})
	local line = { path = { a, b, n } }
	lu.autoLoadConfig(line)
	eq(fu(n), true)
	n.stop.passThroughStopData.stopConfig.forceUnload = false
	lu.autoLoadConfig(line) -- e.g. a reorder of the same tables
	eq(fu(n), false, "no longer new")
end)

test("mode new: a stop rebuilt around the same .stop is still new", function()
	local lu = installed(core.MODE_NEW)
	local a, b = via(load(2), false), via(load(), false)
	local n = lu.makeNewStop({})
	local rebuilt = { stop = n.stop }
	lu.autoLoadConfig({ path = { a, b, rebuilt } })
	eq(fu(rebuilt), true)
end)

test("mode new: an unmarked stop that is not makeNewStop's is unchanged", function()
	local lu = installed(core.MODE_NEW)
	local a, b, stranger = via(load(2), false), via(load(), false), via(load(), false)
	lu.autoLoadConfig({ path = { a, b, stranger } })
	eq(fu(stranger), false)
end)

test("mode new: a new line's first stop (one stop, nothing to carry yet) -> off", function()
	local lu = installed(core.MODE_NEW)
	local first = lu.makeNewStop({})
	lu.autoLoadConfig({ path = { first } })
	eq(fu(first), false)
end)

test("mode new: the first stop is decided again when the second is added (unload end first)", function()
	-- the player starts the line at the receiving industry: alone it was
	-- off; once the loading stop is added it must turn on
	local lu = installed(core.MODE_NEW)
	local first = lu.makeNewStop({})
	lu.autoLoadConfig({ path = { first } })
	eq(fu(first), false)
	local second = lu.makeNewStop({})
	lu.autoLoadConfig({ path = { first, second }, plan = { load(), load(2) } })
	eq(fu(first), true)
	eq(fu(second), false)
end)

test("makeNewStop wrapper passes arguments and results through", function()
	local lu = fakeLineUtil()
	local got
	lu.makeNewStop = function(d, extra) got = { d, extra }; return "via", "second" end
	core.install(lu, { getMode = function() return core.MODE_NEW end })
	local r1, r2 = lu.makeNewStop("details", 5)
	eq(got[1], "details"); eq(got[2], 5)
	eq(r1, "via"); eq(r2, "second")
end)

test("install keeps an earlier wrapper of another mod in the chain", function()
	local lu = fakeLineUtil()
	local base = lu.makeNewStop
	local otherCalled = 0
	lu.makeNewStop = function(...) otherCalled = otherCalled + 1; return base(...) end
	core.install(lu, { getMode = function() return core.MODE_NEW end })
	local n = lu.makeNewStop({})
	eq(otherCalled, 1)
	lu.autoLoadConfig({ path = { via(load(2), false), via(load(), false), n } })
	eq(fu(n), true)
end)

------------------------------------------------------------------------
-- fud.script.lua under stubs
------------------------------------------------------------------------
-- A line_react_util stand-in: LineCargoDisplay returns a recognisable node
-- and counts its calls.
local function fakeLineReactUtil()
	local lru = { cargoCalls = 0 }
	lru.LineCargoDisplay = function(...)
		lru.cargoCalls = lru.cargoCalls + 1
		local n = select("#", ...)
		return { base = true, params = (select(n, ...)), argc = n }
	end
	return lru
end

local function loadScript(env)
	local logs = {}
	local lineUtil = env.lineUtil
	local lineReactUtil = env.lineReactUtil or fakeLineReactUtil()
	local recipes = env.recipes or {}
	local registered = env.registered or { n = 0 }
	local timers = {}
	local currentRecipe = nil
	local function widget(kind) return function(p) p = p or {}; p.kind = kind; return p end end
	-- one table per module, as ug_require caches them, so a test can wrap
	-- a field the script also uses
	local modules = env.modules or {
		["::/gui/main/react.lua"] = {
			RegisterPluginRecipe = function(ep, name, fn)
				assert(ep == "EP", "extension point from mod_entry_point")
				return { name = name, fn = fn }
			end,
			-- a recipe call returns a node that remembers its params;
			-- render(node) runs the recipe function on them
			RegisterRecipe = function(name, fn)
				registered.n = registered.n + 1
				recipes[name] = fn
				return function(p) return { recipe = name, params = p } end
			end,
			getCurrentRecipeName = function() return currentRecipe end,
		},
		["::/gui/main/builtin.lua"] = {
			BoxLayout = widget("BoxLayout"), Component = widget("Component"),
			FloatingLayout = widget("FloatingLayout"), FloatingLayoutChild = widget("FloatingLayoutChild"),
			ImageView = widget("ImageView"),
			type = { Orientation = { Horizontal = "H" }, ImageViewScaling = { AutoFit = "fit" } },
		},
		["::/gui/main/mod_entry_point.tl"] = { ModEntryPointExtension = "EP" },
		["::/gui/main/engine_react_util.tl"] = { useStepStateTimer = function(fn, interval)
			local st = { v = fn(), interval = interval }
			st.old = function() return st.v end
			timers[#timers + 1] = { state = st, tick = function() st.v = fn() end }
			return st
		end },
	}
	local G = setmetatable({
		debugPrint = function(m) logs[#logs + 1] = m end,
		_ = env.translate,
		ug_require = function(path)
			if path == "::/gui/line_vehicle_mgmt/line_util.tl" then
				if env.requireError then error(env.requireError) end
				return lineUtil
			elseif path == "::/gui/line_vehicle_mgmt/line_react_util.tl" then
				if env.reactRequireError then error(env.reactRequireError) end
				return lineReactUtil
			end
			local m = modules[path]
			if m == nil then error("unexpected ug_require " .. tostring(path)) end
			return m
		end,
		api = {
			engine = {
				config = { getModParams = env.getModParams },
				entityExists = function(e) return env.lines ~= nil and env.lines[e] ~= nil end,
				getComponent = function(e, t)
					assert(t == "LINE", "reads the LINE component")
					return env.lines[e]
				end,
			},
			type = { ComponentType = { LINE = "LINE" } },
		},
	}, { __index = _G })
	local chunk = assert(loadfile(root .. "/content/gui/hummer_force_unload_default/fud.script.lua"))
	setfenv(chunk, G)
	chunk()
	local exports = G.data()
	-- runs a recipe node; a plain builtin node is returned as is
	local function render(node)
		if not node.recipe then return node end
		return recipes[node.recipe](node.params)
	end
	G.__timers = timers
	G.__modules, G.__recipes, G.__registered = modules, recipes, registered
	G.__logs = logs
	G.__setRecipe = function(name) currentRecipe = name end
	return exports, logs, G, render, lineReactUtil
end

test("script: data() wraps line_util once, logs nothing when all is well", function()
	local lu = fakeLineUtil()
	local lru = fakeLineReactUtil()
	local exports, logs = loadScript({ lineUtil = lu, lineReactUtil = lru, getModParams = function() return {} end })
	assert(exports.EntryPlugin and exports.EntryPlugin.name == "HummerForceUnloadDefaultEntry")
	-- the game log only gets our lines on failures
	eq(#logs, 0, "no success line")
	eq(lu[core.GUARD_KEY] ~= nil, true, "autoLoadConfig wrapped")
	eq(lru[core.ICON_GUARD_KEY] ~= nil, true, "LineCargoDisplay wrapped")
	local wrapped = lu.autoLoadConfig
	local wrappedCargo = lru.LineCargoDisplay
	-- the script loaded a second time (another chunk, same cached tables)
	local _, logs2 = loadScript({ lineUtil = lu, lineReactUtil = lru, getModParams = function() return {} end })
	eq(lu.autoLoadConfig, wrapped, "not wrapped again")
	eq(lru.LineCargoDisplay, wrappedCargo, "marker not wrapped again")
	eq(#logs2, 0)
	lu.autoLoadConfig({ path = {} })
	eq(lu.calls, 1)
end)

test("script: data() called twice in one load wraps once", function()
	local lu = fakeLineUtil()
	local _, _, G = loadScript({ lineUtil = lu, getModParams = function() return {} end })
	local wrapped = lu.autoLoadConfig
	G.data()
	eq(lu.autoLoadConfig, wrapped)
end)

test("script: params mode 2 reach the wrapper", function()
	local lu = fakeLineUtil()
	loadScript({ lineUtil = lu, getModParams = function() return { hummer_force_unload_default = { mode = 2 } } end })
	local a, b = via(load(2), false), via(load(), false)
	lu.autoLoadConfig({ path = { a, b } })
	eq(fu(b), false, "MODE_NEW: existing stop untouched")
end)

test("script: unreadable params -> default mode, logged once", function()
	local lu = fakeLineUtil()
	local _, logs = loadScript({ lineUtil = lu, getModParams = function() error("restricted") end })
	local a = via(load(), false)
	lu.autoLoadConfig({ path = { via(load(2), false), a } })
	lu.autoLoadConfig({ path = { via(load(2), false), a } })
	eq(fu(a), true, "MODE_ALL")
	local n = 0
	for _, m in ipairs(logs) do if m:find("mod params unreadable", 1, true) then n = n + 1 end end
	eq(n, 1)
end)

test("script: line_util cannot be loaded -> failure logged, nothing thrown", function()
	local exports, logs = loadScript({ requireError = "no such file", getModParams = function() return {} end })
	assert(exports.EntryPlugin)
	eq(#logs, 2)
	assert(logs[1]:find("^%[FUD%] line_util could not be loaded"), logs[1])
	assert(logs[2]:find("autoLoadConfig NO, line_react_util.LineCargoDisplay (stop marker) yes", 1, true), "the marker is independent of the line_util wrap: " .. logs[2])
end)

test("script: the plugin renders an empty layout", function()
	local lu = fakeLineUtil()
	local exports = loadScript({ lineUtil = lu, getModParams = function() return {} end })
	local node = exports.EntryPlugin.fn()
	eq(#node.children, 0)
end)

------------------------------------------------------------------------
-- stop list marker: core
------------------------------------------------------------------------
test("iconFromParams: off only for value 1; default and unknown -> on", function()
	eq(core.iconFromParams({ hummer_force_unload_default = { stop_icon = 1 } }), false)
	eq(core.iconFromParams({ hummer_force_unload_default = { stop_icon = 2 } }), true)
	eq(core.iconFromParams({ hummer_force_unload_default = {} }), true)
	eq(core.iconFromParams({}), true)
	eq(core.iconFromParams(nil), true)
end)

test("mod.json: stop_icon param defaults to its second value (On)", function()
	local f = assert(io.open(root .. "/mod.json"))
	local s = f:read("*a"); f:close()
	local block = s:match('"key": "stop_icon".-}')
	assert(block, "stop_icon param missing")
	assert(block:find('"defaultIndex": 1', 1, true), "defaultIndex 1 expected")
	local off = block:find("hummer_force_unload_default_off", 1, true)
	local on = block:find("hummer_force_unload_default_on", 1, true)
	assert(off and on and off < on, "values order: off, on")
end)

test("strings.json: marker keys in all 13 languages", function()
	local f = assert(io.open(root .. "/strings.json"))
	local s = f:read("*a"); f:close()
	for _, lang in ipairs(LANGS) do
		local block = s:match('"' .. lang .. '"%s*:%s*(%b{})')
		for _, key in ipairs({ "hummer_force_unload_default_icon_name", "hummer_force_unload_default_icon_param_tip",
			"hummer_force_unload_default_off", "hummer_force_unload_default_on", "hummer_force_unload_default_icon_tip" }) do
			assert(block:find('"' .. key .. '"', 1, true), lang .. ": " .. key .. " missing")
		end
	end
end)

test("stopRowParams: only stop rows (stopCargoDisplay + line + index)", function()
	local p = { stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 }
	eq(core.stopRowParams(p), p)
	eq(core.stopRowParams("ref", p), p, "X(ref, params) form")
	eq(core.stopRowParams({ lineEntity = 5 }), nil, "line row (whole line)")
	eq(core.stopRowParams({ stopCargoDisplay = false, lineEntity = 5, stopIndex = 0 }), nil)
	eq(core.stopRowParams({ stopCargoDisplay = true, stopIndex = 0 }), nil, "no line")
	eq(core.stopRowParams({ stopCargoDisplay = true, lineEntity = 5 }), nil, "no stop index")
	eq(core.stopRowParams(), nil)
	eq(core.stopRowParams(nil), nil)
end)

local function lineWith(...)
	local stops = {}
	for i, v in ipairs({ ... }) do stops[i] = { stopConfig = { forceUnload = v } } end
	return { stops = stops }
end

test("readForceUnload: 0-based stop index into the line's stops", function()
	local lines = { [7] = lineWith(false, true) }
	local get = function(e) return lines[e] end
	eq(core.readForceUnload(get, 7, 0), false)
	eq(core.readForceUnload(get, 7, 1), true)
	eq(core.readForceUnload(get, 7, 2), false, "past the end")
	eq(core.readForceUnload(get, 8, 0), false, "no such line")
	eq(core.readForceUnload(get, nil, 0), false)
	eq(core.readForceUnload(get, 7, nil), false)
	eq(core.readForceUnload(function() return {} end, 7, 0), false, "no stops")
	eq(core.readForceUnload(function() return { stops = { {} } } end, 7, 0), false, "no stopConfig")
end)

local function iconDeps(over)
	local d = { decorated = 0, logs = {} }
	d.enabled = function() return over.enabled ~= false end
	d.decorate = over.decorate or function(node, params)
		d.decorated = d.decorated + 1
		return { wrapped = node, params = params }
	end
	d.log = function(m) d.logs[#d.logs + 1] = m end
	return d
end

test("installIcon: stop rows get decorated, the base is called once with the same args", function()
	local lru = fakeLineReactUtil()
	local d = iconDeps({})
	eq(core.installIcon(lru, d), true)
	local p = { stopCargoDisplay = true, lineEntity = 5, stopIndex = 2, configureStopButton = true }
	local r = lru.LineCargoDisplay(p)
	eq(lru.cargoCalls, 1)
	eq(r.wrapped.base, true)
	eq(r.wrapped.params, p, "base got the params table untouched")
	eq(r.params, p)
	eq(d.decorated, 1)
end)

test("installIcon: line rows and other calls pass through unchanged", function()
	local lru = fakeLineReactUtil()
	local d = iconDeps({})
	core.installIcon(lru, d)
	local r = lru.LineCargoDisplay({ lineEntity = 5, neutralBackground = false })
	eq(r.base, true)
	r = lru.LineCargoDisplay("ref", { lineEntity = 5 })
	eq(r.base, true); eq(r.argc, 2, "all arguments passed on")
	eq(d.decorated, 0)
end)

test("installIcon: marker switched off -> base node only", function()
	local lru = fakeLineReactUtil()
	local d = iconDeps({ enabled = false })
	core.installIcon(lru, d)
	local r = lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 })
	eq(r.base, true)
	eq(d.decorated, 0)
	eq(lru.cargoCalls, 1)
end)

test("installIcon: a failing decorate shows the base node, logged once", function()
	local lru = fakeLineReactUtil()
	local d = iconDeps({ decorate = function() error("boom") end })
	core.installIcon(lru, d)
	local p = { stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 }
	eq(lru.LineCargoDisplay(p).base, true)
	eq(lru.LineCargoDisplay(p).base, true)
	eq(#d.logs, 1)
	assert(d.logs[1]:find("stop marker failed"), d.logs[1])
end)

test("installIcon: an error in the base propagates, nothing decorated", function()
	local lru = fakeLineReactUtil()
	lru.LineCargoDisplay = function() error("base failure", 0) end
	local d = iconDeps({})
	core.installIcon(lru, d)
	local ok, err = pcall(lru.LineCargoDisplay, { stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 })
	eq(ok, false); eq(err, "base failure")
	eq(d.decorated, 0)
end)

test("installIcon twice: wrapped once; missing field / table -> false + log", function()
	local lru = fakeLineReactUtil()
	core.installIcon(lru, iconDeps({}))
	local w = lru.LineCargoDisplay
	eq(core.installIcon(lru, iconDeps({})), true)
	eq(lru.LineCargoDisplay, w)
	lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 })
	eq(lru.cargoCalls, 1)
	local d = iconDeps({})
	eq(core.installIcon({}, d), false)
	eq(core.installIcon(nil, d), false)
	eq(#d.logs, 2)
end)

test("installIcon keeps another mod's earlier wrapper in the chain", function()
	local lru = fakeLineReactUtil()
	local base = lru.LineCargoDisplay
	local other = 0
	lru.LineCargoDisplay = function(...) other = other + 1; return base(...) end
	core.installIcon(lru, iconDeps({}))
	local r = lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 })
	eq(other, 1)
	eq(r.wrapped.base, true)
end)

------------------------------------------------------------------------
-- stop list marker: script under stubs
------------------------------------------------------------------------
local STOP = { stopCargoDisplay = true, lineEntity = 7, stopIndex = 1, configureStopButton = true }

local function rowEnv(over)
	local env = { lineUtil = fakeLineUtil(), lines = { [7] = lineWith(false, true) },
		getModParams = function() return {} end }
	for k, v in pairs(over or {}) do env[k] = v end
	return env
end

test("script marker: stop row -> classed Component around a horizontal box {marker, base node}", function()
	local _, _, _, render, lru = loadScript(rowEnv())
	local wrapper = lru.LineCargoDisplay(STOP)
	eq(wrapper.kind, "Component")
	eq(wrapper.meta.class, "fud-stop-cargo-box", "classed, so the CSS can pass on the row height")
	local row = wrapper.layout
	eq(row.kind, "BoxLayout")
	eq(row.orientation, "H")
	eq(#row.children, 2)
	eq(row.children[1].recipe, nil, "no recipe of ours: a plain builtin cell")
	eq(row.children[1].kind, "ImageView", "stop 1 has forceUnload on")
	eq(row.children[2].base, true, "base node second, i.e. the marker is right after the name")
	eq(row.children[2].params, STOP)
end)

test("script marker: forceUnload on -> icon with path and tooltip", function()
	local translate = function(k) if k == "hummer_force_unload_default_icon_tip" then return "TIP" end return k end
	local _, _, _, render, lru = loadScript(rowEnv({ translate = translate }))
	local icon = render(lru.LineCargoDisplay(STOP).layout.children[1])
	eq(icon.kind, "ImageView", "a leaf, no layout of ours around it")
	eq(icon.meta.class, "fud-stop-icon")
	eq(icon.path, "::/gui/line_vehicle_mgmt/icons/symbol_cargo_arrow_up_send.tga")
	eq(icon.meta.tooltip, "TIP")
end)

test("script marker: forceUnload off -> empty slot (keeps the column)", function()
	local _, _, _, render, lru = loadScript(rowEnv())
	local p = { stopCargoDisplay = true, lineEntity = 7, stopIndex = 0 }
	local icon = render(lru.LineCargoDisplay(p).layout.children[1])
	eq(icon.kind, "Component")
	eq(icon.meta.class, "fud-stop-icon", "same class (size) as the icon")
	eq(icon.layout, nil, "an empty cell: no layout, in particular no childless FloatingLayout")
end)

test("script marker: missing line / stop -> empty slot, no error", function()
	local _, logs, _, render, lru = loadScript(rowEnv())
	local icon = render(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 99, stopIndex = 0 }).layout.children[1])
	eq(icon.kind, "Component")
	icon = render(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = 9 }).layout.children[1])
	eq(icon.kind, "Component")
	eq(#logs, 0, "a missing line or stop is not logged")
end)

test("script marker: a waypoint row (no LineCargoDisplay with a stop index) gets nothing", function()
	local _, _, _, _, lru = loadScript(rowEnv())
	-- LineStopItem does not call LineCargoDisplay for waypoints; a call
	-- without stopIndex must not be decorated either
	local r = lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7 })
	eq(r.base, true)
end)

test("script marker: shown on customFilters lines too (display only reads)", function()
	local lines = { [7] = lineWith(true) }
	lines[7].customFilters = true
	local _, _, _, render, lru = loadScript(rowEnv({ lines = lines }))
	local icon = render(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = 0 }).layout.children[1])
	eq(icon.kind, "ImageView", "icon expected")
end)

test("script marker: switched off in the mod settings -> base node only", function()
	local _, _, _, _, lru = loadScript(rowEnv({ getModParams = function()
		return { hummer_force_unload_default = { stop_icon = 1 } } end }))
	local r = lru.LineCargoDisplay(STOP)
	eq(r.base, true)
end)

test("script marker: params unreadable -> shown (default), read again later", function()
	local readable = false
	local _, _, _, _, lru = loadScript(rowEnv({ getModParams = function()
		if not readable then error("restricted") end
		return { hummer_force_unload_default = { stop_icon = 1 } } end }))
	eq(lru.LineCargoDisplay(STOP).kind, "Component")
	readable = true
	eq(lru.LineCargoDisplay(STOP).base, true, "the real value once readable")
end)

test("script marker: tooltip falls back to English when _ is missing or returns the key", function()
	for _, tr in ipairs({ false, function(k) return k end }) do
		local _, _, _, render, lru = loadScript(rowEnv({ translate = tr or nil }))
		local icon = render(lru.LineCargoDisplay(STOP).layout.children[1])
		assert(icon.meta.tooltip:find("^Force Unload All Cargo On Arrival: On"))
	end
end)

test("script marker: line_react_util cannot be loaded -> logged, autoLoadConfig still wrapped", function()
	local env = rowEnv({ reactRequireError = "missing" })
	local _, logs = loadScript(env)
	local found = false
	for _, m in ipairs(logs) do if m:find("line_react_util could not be loaded", 1, true) then found = true end end
	assert(found, "failure logged")
	assert(env.lineUtil[core.GUARD_KEY], "line_util wrapped anyway")
end)

test("script marker: line_react_util cannot be loaded -> one summary line names the working half", function()
	local _, logs = loadScript(rowEnv({ reactRequireError = "missing" }))
	local n = 0
	for _, m in ipairs(logs) do
		if m:find("autoLoadConfig yes, line_react_util.LineCargoDisplay (stop marker) NO", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)

test("script: a normal session (load twice, edits in both modes, stop rows on and off) logs nothing", function()
	for _, mode in ipairs({ 1, 2 }) do
		local env = rowEnv({ lineReactUtil = fakeLineReactUtil(),
			getModParams = function() return { hummer_force_unload_default = { mode = mode } } end })
		local _, logs, G, render, lru = loadScript(env)
		G.__modules["::/gui/main/cargo_util.tl"] = { getPassengerCargoTypeId = function() return 0 end }
		-- the second resource loads the script again
		local _, logs2 = loadScript(env)
		eq(#logs2, 0, "second load")
		local a, b = via(load(2), false), via(load(), false)
		env.lineUtil.autoLoadConfig({ path = { a, b } })
		env.lineUtil.autoLoadConfig({ path = { a, b, via(load(1), false) } })
		for i = 0, 2 do render(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = i }).layout.children[1]) end
		eq(#logs, 0, "mode " .. mode .. ": " .. tostring(logs[1]))
	end
end)

------------------------------------------------------------------------
-- replacement config, ReplaceRecipe shim, other mods in the chain
------------------------------------------------------------------------
test("shimReplacementApi: ReplaceRecipe(our wrapper) reaches the wrapped recipe", function()
	local lru = fakeLineReactUtil()
	local recipe = lru.LineCargoDisplay
	core.installIcon(lru, iconDeps({}))
	local got = {}
	local api = { ReplaceRecipe = function(original, repl) got[#got + 1] = { original, repl } end }
	eq(core.shimReplacementApi(api, lru), true)
	api.ReplaceRecipe(lru.LineCargoDisplay, "X")
	eq(got[1][1], recipe, "mapped to the recipe")
	eq(got[1][2], "X")
	api.ReplaceRecipe("other", "Y")
	eq(got[2][1], "other", "other recipes untouched")
	-- shimming twice wraps once
	local shimmed = api.ReplaceRecipe
	eq(core.shimReplacementApi(api, lru), true)
	eq(api.ReplaceRecipe, shimmed)
end)

test("shimReplacementApi: no-op without our wrap or without ReplaceRecipe", function()
	eq(core.shimReplacementApi({ ReplaceRecipe = function() end }, fakeLineReactUtil()), false)
	local lru = fakeLineReactUtil()
	core.installIcon(lru, iconDeps({}))
	eq(core.shimReplacementApi({}, lru), false)
	eq(core.shimReplacementApi(nil, lru), false)
end)

test("script: doReplace exported and shims the api the game hands it", function()
	local exports, _, _, _, lru = loadScript(rowEnv())
	local seen
	local api = { ReplaceRecipe = function(original) seen = original end }
	exports.doReplace(api)
	api.ReplaceRecipe(lru.LineCargoDisplay, "X")
	assert(seen ~= lru.LineCargoDisplay, "our wrapper is not handed to the engine")
	exports.doReplace(nil) -- tolerated
end)

test("replace.res.lua: an early react-replacement-config pointing at doReplace", function()
	local chunk = assert(loadfile(root .. "/content/gui/hummer_force_unload_default/replace.res.lua"))
	local env = {}
	setfenv(chunk, env); chunk()
	local r = env.data()
	eq(r.type, "react-replacement-config")
	eq(r.data.filePath, "hummer_force_unload_default::/gui/hummer_force_unload_default/fud.script")
	eq(r.data.doReplaceFn, "doReplace")
	assert(r.data.order < 0, "runs before configs with the default order")
end)

test("entry.res.lua: mod entry point plugin pointing at EntryPlugin", function()
	local chunk = assert(loadfile(root .. "/content/gui/hummer_force_unload_default/entry.res.lua"))
	local env = {}
	setfenv(chunk, env); chunk()
	local r = env.data()
	eq(r.type, "react-plugin ::ModEntryPointExtension")
	eq(r.data.filePath, "hummer_force_unload_default::/gui/hummer_force_unload_default/fud.script@EntryPlugin")
end)

-- A mod that wraps LineCargoDisplay later and then, in its own wrap of
-- builtin.BoxLayout, looks for the node it got among the stop row's
-- children to put something right after it (the pattern of a waiting
-- passengers mod). Installed after ours (its config order is higher), it
-- must still find its node in the row, and our marker must stay.
test("chain: a later wrapper that looks up its node in the row still finds it", function()
	local _, _, G, _, lru = loadScript(rowEnv())
	local builtin = G.ug_require("::/gui/main/builtin.lua")
	local prevCargo, pending, inserted = lru.LineCargoDisplay, nil, false
	lru.LineCargoDisplay = function(...)
		local node = prevCargo(...)
		pending = node
		return node
	end
	local function row(cargoNode)
		-- what LineStopItem builds: name, cargo display, spacer
		local children = { "name", cargoNode, "spacer" }
		for i, c in ipairs(children) do
			if pending and c == pending then
				table.insert(children, i + 1, "waiting")
				inserted = true
				break
			end
		end
		return builtin.BoxLayout{ children = children }
	end
	local r = row(lru.LineCargoDisplay(STOP))
	assert(inserted, "the other mod found its node in the row")
	eq(r.children[2].layout.children[1].kind, "ImageView", "our marker kept")
	eq(r.children[3], "waiting")
end)

test("chain: Reverse-Lines-style observer outside ours sees the args unchanged", function()
	local _, _, _, _, lru = loadScript(rowEnv())
	local prev, seenParams = lru.LineCargoDisplay, nil
	lru.LineCargoDisplay = function(...)
		local n = select("#", ...)
		seenParams = select(n, ...)
		return prev(...)
	end
	local lineRow = { lineEntity = 7 }
	eq(lru.LineCargoDisplay(lineRow).base, true)
	eq(seenParams, lineRow)
	eq(lru.LineCargoDisplay(STOP).kind, "Component")
end)

------------------------------------------------------------------------
-- review follow-ups
------------------------------------------------------------------------
-- The waiting passengers mod as it is written: it wraps LineCargoDisplay
-- (remembering the node its inner function returned) and builtin.BoxLayout
-- (while LineStopItem renders, the layout whose children hold that node is
-- the row; it puts its widget after the node). Its config (order 960) runs
-- after our data(), so it wraps outside ours.
local function installWaitingMod(builtin, lru, react)
	local prevCargo, prevBox, pending = lru.LineCargoDisplay, builtin.BoxLayout, nil
	lru.LineCargoDisplay = function(...)
		local node = prevCargo(...)
		if react.getCurrentRecipeName() == "LineStopItem" then pending = node end
		return node
	end
	builtin.BoxLayout = function(p)
		if pending and react.getCurrentRecipeName() == "LineStopItem" and type(p.children) == "table" then
			for i, c in ipairs(p.children) do
				if c == pending then
					pending = nil
					local children = {}
					for k, v in ipairs(p.children) do children[k] = v end
					table.insert(children, i + 1, "waiting")
					p.children = children
					break
				end
			end
		end
		return prevBox(p)
	end
end

test("chain (real pattern): waiting-passengers mod outside ours finds the row, not our box", function()
	local _, _, G, _, lru = loadScript(rowEnv())
	local builtin = G.ug_require("::/gui/main/builtin.lua")
	local react = G.ug_require("::/gui/main/react.lua")
	installWaitingMod(builtin, lru, react)
	G.__setRecipe("LineStopItem")
	local cargo = lru.LineCargoDisplay(STOP)
	-- our inner box must not have been taken for the row
	eq(#cargo.layout.children, 2)
	eq(cargo.layout.children[2].base, true)
	local row = builtin.BoxLayout{ children = { "name", cargo, "spacer" } }
	eq(row.children[2], cargo)
	eq(row.children[3], "waiting", "its widget right after the cargo display")
	eq(row.children[4], "spacer")
end)

test("chain (real pattern, reversed order): documents what happens if ours were outside", function()
	-- Not the order the game produces (data() runs before every doReplace),
	-- kept so a change of that order is noticed: the other mod's node ends
	-- up inside our box and its widget there instead of in the row.
	local lu, lru = fakeLineUtil(), fakeLineReactUtil()
	local react = { getCurrentRecipeName = function() return "LineStopItem" end }
	local builtin = { BoxLayout = function(p) p.kind = "BoxLayout"; return p end }
	installWaitingMod(builtin, lru, react)
	core.installIcon(lru, { decorate = function(node) return builtin.BoxLayout{ children = { "icon", node } } end })
	local cargo = lru.LineCargoDisplay(STOP)
	eq(cargo.children[3], "waiting", "inside our box")
end)

test("stopConfig as an engine object (proxy with __index/__newindex) is read and written", function()
	local store = { load = load(), forceUnload = false }
	local writes = 0
	local cfg = setmetatable({}, {
		__index = function(_, k) return store[k] end,
		__newindex = function(_, k, v) writes = writes + 1; store[k] = v end,
	})
	local v = { stop = { passThroughStopData = { stopConfig = cfg } } }
	core.apply({ path = { via(load(2), false), v } }, core.MODE_ALL, nil, 1)
	eq(store.forceUnload, true)
	eq(writes, 1)
	-- passengers only on the proxy: still counts as "no cargo loaded"
	store.load = load(1)
	core.apply({ path = { via(load(2), false), v } }, core.MODE_ALL, nil, 1)
	eq(store.forceUnload, true)
	eq(rawget(cfg, "forceUnload"), nil, "written through the object, not beside it")
end)

------------------------------------------------------------------------
-- GUI failure in game (2026-11-18): marker shape and guards
------------------------------------------------------------------------
-- every node of a tree, recipes rendered
local function walk(node, render, visit)
	if type(node) ~= "table" then return end
	visit(node)
	if node.recipe then walk(render(node), render, visit) end
	if node.layout then walk(node.layout, render, visit) end
	if node.item then walk(node.item, render, visit) end
	for _, c in pairs(node.children or {}) do walk(c, render, visit) end
end

test("default marker never builds a FloatingLayout (the shape that failed in game)", function()
	for _, fu in ipairs({ false, true }) do
		local _, _, _, render, lru = loadScript(rowEnv({ lines = { [7] = lineWith(fu) } }))
		walk(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = 0 }), render, function(n)
			assert(n.kind ~= "FloatingLayout" and n.kind ~= "FloatingLayoutChild", "floating layout built")
		end)
	end
end)

test("entry plugin registered once when the chunk runs twice in one GUI state", function()
	-- the stub returns a new table per RegisterPluginRecipe call, so the
	-- same export from both runs means the second run did not register
	local lu, lru = fakeLineUtil(), fakeLineReactUtil()
	local e1, _, G = loadScript({ lineUtil = lu, lineReactUtil = lru, getModParams = function() return {} end })
	local e2 = loadScript({ lineUtil = lu, lineReactUtil = lru, getModParams = function() return {} end,
		modules = G.__modules, recipes = G.__recipes, registered = G.__registered })
	eq(e2.EntryPlugin, e1.EntryPlugin, "same plugin recipe exported")
end)

test("decorate: a failure after the box holds the base node returns the box, not the node", function()
	local env = rowEnv()
	local _, logs, G, _, lru = loadScript(env)
	local builtin = G.__modules["::/gui/main/builtin.lua"]
	local realComponent = builtin.Component
	builtin.Component = function(p)
		if p.meta and p.meta.class == "fud-stop-cargo-box" then error("component failed") end
		return realComponent(p)
	end
	local r = lru.LineCargoDisplay(STOP)
	eq(r.kind, "BoxLayout", "the box that already holds the node")
	eq(r.children[2].base, true)
	local n = 0
	for _, m in ipairs(logs) do if m:find("stop marker disabled after a failure in the marker box", 1, true) then n = n + 1 end end
	eq(n, 1)
	eq(lru.LineCargoDisplay(STOP).base, true, "later rows undecorated")
end)

test("a line with marker on and off rows: icon and empty cell side by side", function()
	local _, _, _, render, lru = loadScript(rowEnv({ lines = { [7] = lineWith(false, true, false) } }))
	local kinds = {}
	for i = 0, 2 do
		local cell = render(lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = i }).layout.children[1])
		kinds[#kinds + 1] = cell.kind
		eq(cell.meta.class, "fud-stop-icon")
	end
	eq(table.concat(kinds, ","), "Component,ImageView,Component")
end)

test("normal: no recipe of ours anywhere in the decorated row, no hooks", function()
	for _, fu in ipairs({ false, true }) do
		local _, _, G, _, lru = loadScript(rowEnv({ lines = { [7] = lineWith(fu) } }))
		local box = lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = 0 })
		walk(box, function(n) return n end, function(n)
			assert(n.recipe == nil, "recipe node " .. tostring(n.recipe))
			assert(n.kind ~= "FloatingLayout", "floating layout built")
		end)
		eq(#G.__timers, 0, "no step timer (no hooks inside the base row)")
	end
end)

test("normal: each row render reads the game value again (checkbox toggled)", function()
	local lines = { [7] = lineWith(false) }
	local _, _, _, _, lru = loadScript(rowEnv({ lines = lines }))
	local p = { stopCargoDisplay = true, lineEntity = 7, stopIndex = 0 }
	eq(lru.LineCargoDisplay(p).layout.children[1].kind, "Component")
	lines[7].stops[1].stopConfig.forceUnload = true
	eq(lru.LineCargoDisplay(p).layout.children[1].kind, "ImageView", "next render shows it")
end)

test("normal: a failure building the cell falls back to the bare base node", function()
	local _, logs, G, _, lru = loadScript(rowEnv())
	local builtin = G.__modules["::/gui/main/builtin.lua"]
	builtin.ImageView = function() error("image failed") end
	local r = lru.LineCargoDisplay(STOP)
	eq(r.base, true, "base node, not boxed: nothing holds it yet")
	local n = 0
	for _, m in ipairs(logs) do if m:find("stop marker failed", 1, true) then n = n + 1 end end
	eq(n, 1)
end)

test("fud.css.lua: cell rule has size and gravity; no leftover probe rules", function()
	local f = assert(io.open(root .. "/content/gui/hummer_force_unload_default/fud.css.lua")); local s = f:read("*a"); f:close()
	local cell = s:match('"R::LineStopItem !fud%-stop%-icon", (%b{})')
	assert(cell and cell:find("size") and cell:find("gravity"), "cell rule")
	assert(not s:find("probe", 1, true), "probe rules removed")
end)

test("a failing icon stops all decoration (no mix of boxed and bare rows)", function()
	local _, logs, G, _, lru = loadScript(rowEnv({ lines = { [7] = lineWith(false, true, false) } }))
	local builtin = G.__modules["::/gui/main/builtin.lua"]
	builtin.ImageView = function() error("image failed") end
	local row = function(i) return lru.LineCargoDisplay({ stopCargoDisplay = true, lineEntity = 7, stopIndex = i }) end
	eq(row(0).kind, "Component", "off row boxed before the failure")
	eq(row(1).base, true, "the failing (on) row: bare base node")
	eq(row(0).base, true, "off rows bare from now on too")
	eq(row(2).base, true)
	local n = 0
	for _, m in ipairs(logs) do if m:find("stop marker failed", 1, true) then n = n + 1 end end
	eq(n, 1)
	eq(lru.cargoCalls, 4, "base drawn every time")
end)

test("installIcon: onFailure called once with the error; later calls skip decorate", function()
	local lru = fakeLineReactUtil()
	local calls, seen = 0, {}
	local d = iconDeps({ decorate = function() calls = calls + 1; error("boom", 0) end })
	d.onFailure = function(err) seen[#seen + 1] = err end
	core.installIcon(lru, d)
	local p = { stopCargoDisplay = true, lineEntity = 5, stopIndex = 0 }
	lru.LineCargoDisplay(p); lru.LineCargoDisplay(p)
	eq(calls, 1, "decorate not tried again")
	eq(#seen, 1); eq(seen[1], "boom")
end)

------------------------------------------------------------------------
-- judgement: cargo other than passengers (in-game finding 2026-11-18)
------------------------------------------------------------------------
test("hasCargoLoad: passengers ignored when their slot is known; nil index counts them", function()
	eq(core.hasCargoLoad(load(1), 1), false)
	eq(core.hasCargoLoad(load(1, 3), 1), true)
	eq(core.hasCargoLoad(load(), 1), false)
	eq(core.hasCargoLoad(nil, 1), false)
	eq(core.hasCargoLoad(load(1), nil), true, "unknown slot: passengers count (safe side)")
	eq(core.hasCargoLoad({ [1] = true, [9] = true }, 1), true, "sparse table read completely")
end)

test("cargo truck line: the unload stop with passengers on (as the game sets it) -> on", function()
	-- clay pit loads clay (3) + passengers; brick works only passengers
	local pit, works = via(load(1, 3), false), via(load(1), false)
	core.apply({ path = { pit, works } }, core.MODE_ALL, nil, 1)
	eq(fu(pit), false)
	eq(fu(works), true)
end)

test("passenger-only line: every stop off (no marker on bus stops)", function()
	local a, b = via(load(1), true), via(load(1), true)
	core.apply({ path = { a, b } }, core.MODE_ALL, nil, 1)
	eq(fu(a), false); eq(fu(b), false)
end)

test("a line where no stop loads anything: every stop off", function()
	local a, b = via(load(), true), via(load(), true)
	core.apply({ path = { a, b } }, core.MODE_ALL, nil, 1)
	eq(fu(a), false); eq(fu(b), false)
end)

test("one-stop line (being built): off", function()
	local a = via(load(1), true)
	core.apply({ path = { a } }, core.MODE_ALL, nil, 1)
	eq(fu(a), false)
	local b = via(load(), true)
	core.apply({ path = { b } }, core.MODE_ALL, nil, 1)
	eq(fu(b), false)
end)

test("passenger slot unknown (nil): passengers count, the brick works stays off", function()
	local pit, works = via(load(1, 3), true), via(load(1), true)
	core.apply({ path = { pit, works } }, core.MODE_ALL, nil, nil)
	eq(fu(pit), false)
	eq(fu(works), false, "safe side: never on by mistake")
end)

test("mode new on a passenger-only line: the new stop stays off", function()
	local a, b, n = via(load(1), false), via(load(1), false), via(load(1), true)
	core.apply({ path = { a, b, n } }, core.MODE_NEW, function(v) return v == n end, 1)
	eq(fu(n), false)
end)

test("install passes the passenger slot from deps.passengerIndex", function()
	local lu = fakeLineUtil()
	core.install(lu, { getMode = function() return core.MODE_ALL end, passengerIndex = function() return 1 end })
	local pit, works = via(load(1, 3), false), via(load(1), false)
	lu.autoLoadConfig({ path = { pit, works } })
	eq(fu(works), true)
end)

test("script: passenger slot from cargo_util (id + 1); unreadable -> passengers count", function()
	local lu = fakeLineUtil()
	local env = { lineUtil = lu, getModParams = function() return {} end }
	local _, _, G = loadScript(env)
	-- the stub has no cargo_util: unreadable -> nil -> passengers count
	local pit, works = via(load(1, 3), false), via(load(1), false)
	lu.autoLoadConfig({ path = { pit, works } })
	lu.autoLoadConfig({ path = { pit, works } })
	eq(fu(works), false)
	local n = 0
	for _, m in ipairs(G.__logs or {}) do if m:find("passenger cargo type unreadable", 1, true) then n = n + 1 end end
	eq(n, 1, "logged once")
	-- with cargo_util (passengers = id 0 -> slot 1)
	G.__modules["::/gui/main/cargo_util.tl"] = { getPassengerCargoTypeId = function() return 0 end }
	lu.autoLoadConfig({ path = { pit, works } })
	eq(fu(works), true)
end)

test("dev_marker is gone: no param, no strings, no recipe registered by the script", function()
	local f = assert(io.open(root .. "/mod.json")); local m = f:read("*a"); f:close()
	assert(not m:find("dev_marker", 1, true), "param removed")
	f = assert(io.open(root .. "/strings.json")); local st = f:read("*a"); f:close()
	assert(not st:find("_dev_", 1, true), "strings removed")
	local _, _, G = loadScript(rowEnv())
	eq(G.__registered.n, 0, "no RegisterRecipe (only the entry plugin, via RegisterPluginRecipe)")
end)

print(string.format("\n%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
