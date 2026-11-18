-- Loads fud.script.lua early at GUI bootstrap (configs run sorted by
-- order, lowest first) so that its wrap of line_react_util.LineCargoDisplay
-- sits inside the wraps of mods whose configs come later; see the header of
-- fud.script.lua. It replaces no recipe.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "hummer_force_unload_default::/gui/hummer_force_unload_default/fud.script",
			doReplaceFn = "doReplace",
			order = -1000,
		},
	}
end
