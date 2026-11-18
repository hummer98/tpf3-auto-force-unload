-- Force Unload by Default: turns on "Force Unload All Cargo On Arrival"
-- (stopConfig.forceUnload) at stops where the line loads nothing, and off
-- where it loads something, whenever the base line manager works out the
-- load config of a line (see fud_core.lua for the rules).
--
-- Hook: the base manager window (gui/line_vehicle_mgmt/manager_window.tl)
-- holds line_util as a module table and looks up line_util.autoLoadConfig /
-- line_util.makeNewStop on every call. ug_require caches modules by
-- resolved path, so the table returned here is that same table and
-- replacing its fields takes effect without overriding any base file (as
-- other mods do with getBestDepotForLine and makeLineActionDescriptor).
-- The fields are read when this script loads, so wrappers installed earlier
-- by other mods stay in the chain.
--
-- Second hook, the same way: line_react_util.LineCargoDisplay, which the
-- stop rows of the line manager call right after the stop name, gets a
-- small marker in front of it on stops whose forceUnload is on (all lines,
-- including hand-configured ones; it only reads).
--
-- When: data() installs both wraps (guarded, so once). It runs first for
-- replace.res.lua, a react-replacement-config with a low order, i.e. at GUI
-- bootstrap before most other mods' configs. Being early matters for
-- LineCargoDisplay: mods that wrap it later and look for its node among the
-- stop row's children (e.g. one that adds waiting passengers after the
-- cargo icons) then get our box as "the node" and still find it in the row;
-- wrapped after them, our box would hide their node. entry.res.lua (the mod
-- entry point plugin, which renders nothing) loads the script again in case
-- the config did not run; the guards make that a no-op.
-- Known limit: the field then holds a plain function. A mod handing that
-- field to ReplaceRecipe from a config with an order below -1000 (before
-- our shim), or to CallOriginalRecipe / GetRecipeId at any time, would get
-- our function instead of the recipe. No installed mod does (checked for
-- build 40444).
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local core = require "hummer_force_unload_default::/gui/hummer_force_unload_default/fud_core.lua"

local function log(msg)
	local text = "[FUD] " .. msg
	if debugPrint then debugPrint(text) else print(text) end
end

-- The params cannot change while a game runs, but they are read per call:
-- autoLoadConfig only runs on a stop edit, and a read that fails once (e.g.
-- before the game is fully up) is then retried instead of being stuck on
-- the default.
local paramsWarned = false
local function getMode()
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	if not ok or type(all) ~= "table" then
		if not paramsWarned then
			paramsWarned = true
			log("mod params unreadable (" .. tostring(all) .. "); using the default mode")
		end
		return core.DEFAULT_MODE
	end
	return core.modeFromParams(all)
end

-- The marker param is read once it can be read: it cannot change while a
-- game runs, and LineCargoDisplay renders often.
local iconEnabled = nil
local function isIconEnabled()
	if iconEnabled ~= nil then return iconEnabled end
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	if not ok or type(all) ~= "table" then return true end
	iconEnabled = core.iconFromParams(all)
	return iconEnabled
end

-- The base cargo filter window shows this icon for "Cargo can only be
-- unloaded at this stop." (cargofilter_window.tl), so it already means
-- unloading in this part of the UI.
local ICON_PATH = "::/gui/line_vehicle_mgmt/icons/symbol_cargo_arrow_up_send.tga"

local TOOLTIP_KEY = "hummer_force_unload_default_icon_tip"
local TOOLTIP_FALLBACK = "Force Unload All Cargo On Arrival: On\nUnload cargo even if stocks are full."
local function tooltipText()
	local ok, text = pcall(function() return _(TOOLTIP_KEY) end)
	if ok and type(text) == "string" and text ~= "" and text ~= TOOLTIP_KEY then return text end
	return TOOLTIP_FALLBACK
end

local function readStop(lineEntity, stopIndex)
	local ok, on = pcall(core.readForceUnload, function(entity)
		if not api.engine.entityExists(entity) then return nil end
		return api.engine.getComponent(entity, api.type.ComponentType.LINE)
	end, lineEntity, stopIndex)
	return ok and on == true
end

-- Recipes are registered once per GUI state and kept on the cached builtin
-- module table: this script is named by two resources (replace.res.lua and
-- entry.res.lua), and if the loader ran the chunk for each, a second
-- RegisterRecipe under the same name would leave the wrap (installed by the
-- first run) pointing at a recipe of the other run.
local SHARED_KEY = "__hummer_force_unload_default_recipes"
local shared = builtin[SHARED_KEY]
if type(shared) ~= "table" then
	shared = {}
	builtin[SHARED_KEY] = shared
end

-- Development switch for the stop marker (param dev_marker, default 1 =
-- the shipped variant). It exists to narrow down a GUI failure in game
-- (2026-11-18: "ReactFramework::Step() failed" as soon as a stop row was
-- decorated, with no Lua message); see core.MARKER_* for what each variant
-- leaves out. Read once, like the marker param.
local markerVariant = nil
local function getMarkerVariant()
	if markerVariant ~= nil then return markerVariant end
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	if not ok or type(all) ~= "table" then return core.MARKER_NORMAL end
	markerVariant = core.markerVariantFromParams(all)
	return markerVariant
end

-- Errors inside a recipe body are not reported by the engine (only
-- "Step() failed" and a GUI reload), so the marker's own code runs in
-- pcall, and after the first failure the stop rows are no longer decorated
-- at all: the base row is drawn as without this mod, and the half-built
-- marker is unmounted instead of being rendered again with a different
-- set of hooks.
local markerBroken = false
local function markBroken(where, err)
	if markerBroken then return end
	markerBroken = true
	log("stop marker disabled after a failure in " .. where .. ": " .. tostring(err))
end

local function placeholder()
	-- a Component with only a class is what the base uses as an empty
	-- cell next to cargo icons (line_react_util.tl "cargo-placeholder")
	return builtin.Component{ meta = { class = "fud-stop-icon" } }
end

local function iconView(class)
	return builtin.ImageView{
		meta = { class = class or "fud-stop-icon", tooltip = tooltipText() },
		path = ICON_PATH,
		scaling = builtin.type.ImageViewScaling.AutoFit,
	}
end

-- One per stop row: the icon when forceUnload is on, else an empty cell
-- of the same size, so the cargo icons of all rows stay in one column. A
-- leaf in both cases, shaped like the base's own cells: the first version
-- put a FloatingLayout here that had no child at all on stops without the
-- marker, a shape the base never builds, and that version failed in game
-- on such rows (the leading suspect; dev_marker 5 rebuilds it to confirm).
-- The value comes from the line in the game (where the cargo filter window
-- commits the checkbox), re-read on the step timer, so toggling the
-- checkbox shows up by itself.
if not shared.StopIcon then
	shared.StopIcon = react.RegisterRecipe("HummerForceUnloadStopIcon", function(params)
		local ok, node = pcall(function()
			local on
			if params.timer == false then
				on = readStop(params.lineEntity, params.stopIndex)
			else
				local onState = engine_react_util.useStepStateTimer(function()
					return readStop(params.lineEntity, params.stopIndex)
				end, 0.5)
				on = onState:old() == true
			end
			if params.legacy then
				-- MARKER_LEGACY: the first version's shape and CSS, kept only
				-- to confirm the cause in game (unlike then, inside this pcall)
				return builtin.Component{
					meta = { class = "fud-stop-icon-slot" },
					layout = builtin.FloatingLayout{
						children = {
							on and builtin.FloatingLayoutChild{ h = 0.5, v = 0.5, item = iconView("fud-stop-icon-legacy") } or nil,
						},
					},
				}
			end
			return on and iconView() or placeholder()
		end)
		if ok then return node end
		markBroken("the marker recipe", node)
		return placeholder()
	end)
end
local ForceUnloadStopIcon = shared.StopIcon

-- A classed Component around the box: a bare BoxLayout takes no style, and
-- the base stretches the cargo display to the row height
-- (R::LineCargoDisplay gravity), which this wrapper must pass on
-- (fud.css.lua).
local function decorate(node, params)
	local variant = getMarkerVariant()
	if variant == core.MARKER_PASSTHROUGH then return node end
	local marker
	if variant == core.MARKER_BARE_BOX then
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { placeholder(), node },
		}
	elseif variant == core.MARKER_BOX_ONLY then
		marker = placeholder()
	else
		marker = ForceUnloadStopIcon{
			lineEntity = params.lineEntity,
			stopIndex = params.stopIndex,
			timer = variant ~= core.MARKER_NO_TIMER,
			legacy = variant == core.MARKER_LEGACY,
		}
	end
	-- Once node is a child of the box it must not be handed back alone (it
	-- would get a second parent in the row), so a failure from here on
	-- returns the box, and only failures before this point fall back to the
	-- bare node (core.installIcon).
	local box = builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { marker, node },
	}
	local ok, wrapped = pcall(builtin.Component, {
		meta = { class = "fud-stop-cargo-box" },
		layout = box,
	})
	if ok then return wrapped end
	markBroken("the marker box", wrapped)
	return box
end

local function markerEnabled()
	return not markerBroken and isIconEnabled()
end

local function installIcon()
	local okReq, line_react_util = pcall(ug_require, "::/gui/line_vehicle_mgmt/line_react_util.tl")
	if not okReq then
		log("line_react_util could not be loaded: " .. tostring(line_react_util) .. "; no stop marker")
		return false
	end
	if type(line_react_util) == "table" and line_react_util[core.ICON_GUARD_KEY] then
		return true
	end
	local okInst, result = pcall(core.installIcon, line_react_util, { enabled = markerEnabled, decorate = decorate, log = log })
	if not okInst then
		log("wrapping LineCargoDisplay failed: " .. tostring(result))
		return false
	end
	return result and "new" or false
end

local function install()
	local okReq, line_util = pcall(ug_require, "::/gui/line_vehicle_mgmt/line_util.tl")
	if not okReq then
		log("line_util could not be loaded: " .. tostring(line_util) .. "; nothing wrapped")
		return false
	end
	if type(line_util) == "table" and line_util[core.GUARD_KEY] then
		return true -- a second load of this script: already wrapped
	end
	local okInst, result = pcall(core.install, line_util, { getMode = getMode, log = log })
	if not okInst then
		log("wrapping line_util failed: " .. tostring(result))
		return false
	end
	return result and "new" or false
end

if not shared.EntryPlugin then
	shared.EntryPlugin = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "HummerForceUnloadDefaultEntry", function()
		return builtin.BoxLayout{ children = {} }
	end)
end
local EntryPlugin = shared.EntryPlugin

-- doReplace of replace.res.lua: the wraps are already in (data() ran for
-- this resource); only the replacement api is adjusted, see
-- core.shimReplacementApi.
local function doReplace(replacementApi)
	local ok, line_react_util = pcall(ug_require, "::/gui/line_vehicle_mgmt/line_react_util.tl")
	if not ok then return end
	local okShim, err = pcall(core.shimReplacementApi, replacementApi, line_react_util)
	if not okShim then
		log("replacement api shim failed: " .. tostring(err))
	end
end

-- Entry point of a .script.lua resource: the engine calls the global data()
-- and ignores the chunk's return value (a trailing return {...} aborts the
-- GUI bootstrap with "function data() not defined").
-- One line per load that wraps something (the first of the two resources);
-- the second load finds both guards set and stays quiet.
function data()
	local auto = install()
	local icon = installIcon()
	if auto == "new" or icon == "new" then
		log("wrapped: line_util.autoLoadConfig " .. (auto and "yes" or "NO")
			.. ", line_react_util.LineCargoDisplay (stop marker) " .. (icon and "yes" or "NO"))
	end
	return {
		EntryPlugin = EntryPlugin,
		doReplace = doReplace,
	}
end
