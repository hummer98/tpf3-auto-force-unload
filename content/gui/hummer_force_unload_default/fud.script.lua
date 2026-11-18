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

-- One per stop row. The slot always takes its width, so the cargo icons of
-- all rows stay in one column whether the marker shows or not. The value
-- comes from the line in the game (where the cargo filter window commits
-- the checkbox), re-read on the step timer like the base's own cargo
-- display of the same row, so toggling the checkbox shows up by itself.
local ForceUnloadStopIcon = react.RegisterRecipe("HummerForceUnloadStopIcon", function(params)
	local onState = engine_react_util.useStepStateTimer(function()
		return readStop(params.lineEntity, params.stopIndex)
	end, 0.5)
	local on = onState:old() == true
	return builtin.Component{
		meta = { class = "fud-stop-icon-slot" },
		layout = builtin.FloatingLayout{
			children = {
				on and builtin.FloatingLayoutChild{
					h = 0.5, v = 0.5,
					item = builtin.ImageView{
						meta = { class = "fud-stop-icon", tooltip = tooltipText() },
						path = ICON_PATH,
						scaling = builtin.type.ImageViewScaling.AutoFit,
					},
				} or nil,
			},
		},
	}
end)

-- A classed Component around the box: a bare BoxLayout takes no style, and
-- the base stretches the cargo display to the row height
-- (R::LineCargoDisplay gravity), which this wrapper must pass on
-- (fud.css.lua).
local function decorate(node, params)
	return builtin.Component{
		meta = { class = "fud-stop-cargo-box" },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				ForceUnloadStopIcon{ lineEntity = params.lineEntity, stopIndex = params.stopIndex },
				node,
			},
		},
	}
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
	local okInst, result = pcall(core.installIcon, line_react_util, { enabled = isIconEnabled, decorate = decorate, log = log })
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

local EntryPlugin = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "HummerForceUnloadDefaultEntry", function()
	return builtin.BoxLayout{ children = {} }
end)

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
