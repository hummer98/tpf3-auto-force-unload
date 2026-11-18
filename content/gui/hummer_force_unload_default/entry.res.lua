-- Loads fud.script.lua at GUI start through the base mod entry point (the
-- extension point every mod can plug into, rendered by gui/main/game.tl).
-- The script's job is the line_util wrap done while it loads; the plugin
-- draws nothing, so its order is irrelevant.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "hummer_force_unload_default::/gui/hummer_force_unload_default/fud.script@EntryPlugin",
			order = 0,
		},
	}
end
