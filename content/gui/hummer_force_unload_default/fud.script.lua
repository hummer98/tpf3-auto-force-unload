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
-- The wrap is installed from data(), i.e. when the GUI loads this mod's
-- entry-point plugin (entry.res.lua), before any line can be edited. The
-- plugin itself renders nothing.
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"
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
	if result then
		log("line_util.autoLoadConfig wrapped")
	end
	return result
end

local EntryPlugin = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "HummerForceUnloadDefaultEntry", function()
	return builtin.BoxLayout{ children = {} }
end)

-- Entry point of a .script.lua resource: the engine calls the global data()
-- and ignores the chunk's return value (a trailing return {...} aborts the
-- GUI bootstrap with "function data() not defined").
function data()
	install()
	return {
		EntryPlugin = EntryPlugin,
	}
end
