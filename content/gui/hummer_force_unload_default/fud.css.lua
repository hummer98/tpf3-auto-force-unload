local ssu = require "::/gui/main/stylesheetutil.lua"

-- The stop list marker (fud.script.lua) sits between the stop name (232 px,
-- line_vehicle_mgmt.css.lua) and the cargo icons (18 px each). It is kept
-- smaller than a cargo icon so it reads as a note on the stop, not as one
-- more cargo type, and the slot is narrow because the base window is only
-- 500 px wide. Scoped to the stop rows (LineStopItem), the only place the
-- marker is added; the base styles that row the same way (!lmp-name-field).
function data()
	local result = {}
	local a = ssu.makeAdder(result)

	-- as the base's R::LineCargoDisplay: fill the row height, so the cargo
	-- card keeps its place inside our wrapper
	a("R::LineStopItem !fud-stop-cargo-box", {
		gravity = { 0, -1 },
	})
	-- the marker cell: an ImageView (on) or an empty Component (off), the
	-- same size either way so the cargo icons stay in one column
	a("R::LineStopItem !fud-stop-icon", {
		size = { 14, 14 },
		margin = { 0, 2, 0, 0 },
		gravity = { 0, 0.5 }, -- centred in the row height
	})
	-- only for the development variant MARKER_LEGACY: the first version's
	-- rules, unchanged, so that variant rebuilds it faithfully
	a("R::LineStopItem !fud-stop-icon-slot", {
		gravity = { 0, -1 },
		size = { 16, -1 },
		margin = { 0, 2, 0, 0 },
	})
	a("R::LineStopItem ImageView!fud-stop-icon-legacy", {
		size = { 14, 14 },
	})

	return result
end
