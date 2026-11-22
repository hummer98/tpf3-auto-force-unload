# Changelog

All notable changes to Auto Force Unload at Drop-off Stops are recorded
here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the mod uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The mod's
`revision` in `mod.json` is MAJOR * 10000 + MINOR * 100 + PATCH.

## [Unreleased]

### Changed
- The mod is now marked `cosmetic`: in the game it only switches the base
  game's own per-stop **Force Unload All Cargo On Arrival** checkbox, which
  players can also tick by hand, and adds no game rule. Metadata only; the
  behaviour is unchanged.

## [1.0.1] - 2026-11-22

### Fixed
- The mod's name in the game's mod list and on mod.io is now English only
  and within mod.io's 50-character limit, so the in-game uploader accepts it.

## [1.0.0] - 2026-11-22

### Added
- First public release. Whenever the Line Manager works out a line's load
  configuration by itself, the mod sets the base game's **Force Unload All
  Cargo On Arrival** checkbox stop by stop: on at stops that load no cargo
  (passengers do not count), off at stops that load cargo, so cargo is
  unloaded where it is delivered even when the stock is full instead of
  riding back.
- Lines that load no cargo anywhere (passenger lines, a line with a single
  stop) keep it off at every stop. Lines you configured by hand are left
  alone, as the base game stops configuring them automatically too.
- Mod setting **Stops to set**: all stops of the edited line (default) or
  only the stops added in that edit.
- A small unload icon in the Line Manager's stop list marks the stops with
  force unload on, on every line; the mod setting **Marker in the stop
  list** switches it off.
- Texts in the game's 13 languages.
- Safe to add to and remove from a running save; no base file is replaced
  and no dependencies.
