# Auto Force Unload at Drop-off Stops (Transport Fever 3)

[日本語は下にあります](#日本語)

**What this mod does:** it switches the base game's **Force Unload All
Cargo On Arrival** checkbox for you, stop by stop: on at stops where a cargo
line only unloads, off at stops that load cargo. A small icon in the Line
Manager's stop list shows where it is on. What the checkbox itself does is
the base game's behaviour, summarised [below](#what-the-checkbox-does-base-game).

## Features

- Whenever the Line Manager works out a line's load configuration by itself
  (the cargo each stop loads), this mod sets the checkbox stop by stop:
  - **on** at stops that load no cargo (passengers do not count: the base
    game switches them on at every stop that takes them, cargo truck stops
    included);
  - **off** at stops that load cargo.
- Lines that load no cargo anywhere (bus, tram and other passenger lines, a
  line with a single stop) keep it off at every stop.
- Lines you configured by hand are left alone: once you change a stop's
  cargo to load or one of its checkboxes, the base game marks the line as
  custom and stops configuring it automatically, and so does this mod.
- The setting is the base game's own checkbox (the cargo filter window of a
  stop), so you can still change it there; the line then counts as hand
  configured.

## When it acts, and when not

It acts when you edit a line in the Line Manager: create a line, add a stop
or a waypoint, remove a stop, or move one in the order. With the mod setting
**Stops to set**:

| Value | What is set |
|---|---|
| All stops of the line (default) | Every stop of the edited line, each time |
| New stops only | Only the stops added in that edit; the others keep their setting even if what they load changed (a line's very first stop is set again when the second one is added) |

It does not act:

- on lines that existed before the mod was added, until you edit them;
- on lines whose cargo settings or checkboxes you changed by hand;
- when a stop is only moved to another station;
- on lines made or changed without the Line Manager (by other mods' scripts,
  for example).

## What the checkbox does (base game)

This is the base game's behaviour, not something the mod adds. Measured in
build 40444 (2026-11-18, one cargo line into an industry):

- **On:** all cargo is unloaded on arrival. What fits into the receiving
  stock is accepted and paid for. When the stock is full, the rest is
  destroyed, and **no fare is paid** for the destroyed cargo.
- **Off:** cargo that is not accepted stays aboard and rides on to the next
  stop (on a two-stop line, back to where it was loaded).
- So at a stop along the way that loads no cargo, the mod's "on" also
  destroys cargo that could have gone on to a later stop of the same line.
  Turn the checkbox off there by hand (the line then counts as hand
  configured).

## The marker

In the Line Manager's stop list, a stop with Force Unload All Cargo On
Arrival switched on gets a small unload icon between its name and its cargo
icons (the base game's unload arrow from the cargo filter window). Stops
with it off get an empty cell of the same size, so the cargo icons stay in
one column. The marker is shown on every line, including the ones you
configured by hand, and only reads the line. The mod setting **Marker in
the stop list** switches it off.

## Compatibility

- Adding the mod to a running save and removing it again are both safe
  (`severityAdd: None`, `severityRemove: None`). The mod stores nothing of
  its own in the save: what it sets is the base game's `forceUnload` flag of
  each stop, which stays as it is after the mod is removed.
- `cosmetic`: what it changes in the game is only the base game's own
  per-stop checkbox, the one you can tick by hand in the Line Manager (plus
  a stop-list icon and its own settings); it adds no game rule.
- No base file is replaced. It wraps the base functions
  `line_util.autoLoadConfig`, `line_util.makeNewStop` and
  `line_react_util.LineCargoDisplay` at GUI start and calls the previous
  function first, so other mods that wrap the same functions stay in the
  chain.
- No dependencies.
- Similar mod: Line Toolkit (mod.io 6414310) switches force unload on per
  line after cargo has come back. This mod sets it while you build the line,
  per stop, from the cargo the stops load.

## Install

- mod.io: https://mod.io/g/transportfever3/m/auto-force-unload-at-drop-off-stops (or subscribe in the game's mod
  hub).
- Manually: the game loads a local mod only from a folder named exactly
  `hummer_force_unload_default_1` inside
  `<Steam>/userdata/<your id>/3493540/local/mods/`.
  - From the release zip: create that folder and extract the zip **into** it
    (the zip has no top folder of its own).
  - From GitHub: `git clone https://github.com/hummer98/tpf3-auto-force-unload
    hummer_force_unload_default_1` inside `local/mods/` (a different folder
    name will not load).
  - Then enable the mod in the game.

## Development

| File | Role |
|---|---|
| `content/gui/hummer_force_unload_default/fud_core.lua` | The rules (which stop gets force unload, the two modes) and the wraps of `autoLoadConfig` / `makeNewStop` and `LineCargoDisplay`, free of game globals so the tests run offline |
| `content/gui/hummer_force_unload_default/fud.script.lua` | GUI script: reads the mod settings and the line from the game, installs the wraps, builds the marker cell; logs only failures |
| `content/gui/hummer_force_unload_default/replace.res.lua` | Loads the script early at GUI start (a replacement config with a low order that replaces no recipe), so the marker wrap sits inside those of mods loaded later |
| `content/gui/hummer_force_unload_default/entry.res.lua` | Loads the script again through the mod entry point in case the config did not run (the second load does nothing) |
| `content/gui/hummer_force_unload_default/fud.css.lua` | Size and position of the marker cell in the stop rows |
| `mod.json` | modId, revision and the two mod settings |
| `VERSION` | The version (`MAJOR.MINOR.PATCH`); `mod.json`'s revision is MAJOR * 10000 + MINOR * 100 + PATCH |
| `CHANGELOG.md` | Changes per version ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)); new ones go under `## [Unreleased]` |
| `strings.json` | Texts in the game's 13 languages; the checkbox, Line Manager, stop and On/Off words are the base game's own |
| `_metadata/modinfo.json` | Name, summary and description for the game's mod list and the in-game mod.io upload (one text for all languages: the name in English only, at most 50 characters for mod.io; summary and description "English / 日本語") |
| `_metadata/0.png` | Cover image (required by the in-game uploader) |
| `docs/modio_description.md` | Description for the mod.io web page |
| `docs/release.md` | Versions and the release steps (Japanese) |

Tests run offline (no game needed; the checks against the installed game's
`base.mo` are skipped without it):

```sh
luajit tests/run.lua
TMPDIR=<scratch dir> python3 -m unittest discover -s tests
```

Set `TMPDIR` to a scratch directory for the Python tests and the tools
below (they create temporary folders), not `/tmp` or `local/mods`.

`python3 tools/package.py` runs both test suites and builds
`dist/hummer_force_unload_default_1.zip` with only `mod.json`,
`strings.json`, `content/` and `_metadata/`. LICENSE stays out: the game's
mod validation rejects files without an allowed extension. It refuses to
build without `_metadata/0.png`.

`python3 tools/stage.py` copies the mod into the game's staging area
(`local/staging_area/hummer_force_unload_default_1`) for the in-game upload.
Run it from the copy in `local/mods/` (it finds the staging area next to
that folder), while the game is stopped. It refuses uncommitted changes, a
missing cover and, after the first upload, an unraised `revision`, and
keeps the `_metadata/mod.io_fileid.txt` the game writes at the first upload,
which is what makes later uploads update the same mod.io page. Use
`--first-upload` for the first one.

Versions and releases ([docs/release.md](docs/release.md)): write each
change under `## [Unreleased]` in `CHANGELOG.md`. To release, in a
development clone (not the copy in `local/mods/`), run
`python3 tools/release.py patch|minor|major|X.Y.Z` (`--dry-run` first). It
writes `VERSION`, the revision and the changelog section, runs the tests,
commits `Release vX.Y.Z`, tags `vX.Y.Z`, builds
`dist/hummer_force_unload_default-vX.Y.Z.zip` and, with the `github`
remote, pushes the branch and that tag and creates the GitHub release with
the section as its notes. Then, with the game stopped, pull into the copy
in `local/mods/`, run `tools/stage.py` there and upload in game; the
raised revision is what lets `stage.py` accept the update. The tests fail
when `VERSION`, the revision and the changelog disagree.

## License

[MIT](LICENSE) © 2026 hummer

---

## 日本語

**降ろすだけの駅に積み下ろし強制を自動設定（Transport Fever 3）**

**この MOD がすること:** 本体のチェックボックス「**到着時にすべての貨物を強制的に積み下ろし**」を、停留所ごとに自動で切り替えます。貨物を降ろすだけの停留所ではオン、貨物を積む停留所ではオフです。オンの停留所は、路線マネージャーの停留所一覧に小さなアイコンで示します。チェックボックスそのものの働きは本体の仕様で、[下](#チェックボックスの働き本体の仕様)にまとめました。

### 機能

- 路線マネージャーが路線の積み込み設定（各停留所で積み込む貨物）を自動で決めるたびに、停留所ごとにこのチェックボックスを設定します。
  - 貨物を積まない停留所では**オン**（旅客は数えません。本体は、旅客を扱う停留所ではトラックの貨物停留所でも旅客をオンにするからです）。
  - 貨物を積む停留所では**オフ**。
- どの停留所でも貨物を積まない路線（バス・路面電車などの旅客の路線、停留所が 1 つの路線）は、全部オフのままです。
- 手で設定した路線には触りません。停留所の積み込む貨物やチェックボックスを一度変えると、本体はその路線を手動設定として扱い、自動で決めなくなります。この MOD も同じです。
- 設定するのは本体のチェックボックス（停留所の貨物フィルターの画面）なので、そこで手で変えることもできます。変えた路線は手で設定した路線になります。

### 動くとき・動かないとき

路線マネージャーで路線を編集したとき（路線を作る、停留所やウェイポイントを足す、停留所を消す、順番を入れ替える）に動きます。MOD の設定「**設定する停留所**」で、設定する範囲を選べます。

| 値 | 設定するもの |
|---|---|
| 路線の全停留所を合わせる（既定） | 編集した路線の全停留所を、毎回 |
| 新しく足した停留所だけ | その編集で足した停留所だけ。ほかの停留所は、積み込む貨物が変わっても設定をそのままにします（路線の最初の停留所だけは、2 つ目を足したときに設定し直します） |

次の場合は動きません。

- MOD を入れる前からある路線（次に編集するまで）。
- 積み込む貨物やチェックボックスを手で変えた路線。
- 停留所を別の駅へ動かしただけのとき。
- 路線マネージャーを通さずに作られた・変えられた路線（他の MOD のスクリプトなど）。

### チェックボックスの働き（本体の仕様）

ここに書くのは本体の動きで、この MOD が足したものではありません。build 40444 で測りました（2026-11-18、産業へ届ける貨物の路線 1 本）。

- **オン:** 到着した貨物を全部下ろします。届け先の在庫に入る分は受け取られ、運賃が入ります。在庫が満タンなら残りは破棄され、**破棄された分の運賃は入りません**。
- **オフ:** 受け取られない貨物は車両に載ったまま、次の停留所へ運ばれます（停留所が 2 つの路線なら、積んだ場所へ戻ります）。
- そのため、貨物を積まない途中の停留所でこの MOD がオンにすると、同じ路線の先の停留所へ運べたはずの貨物も破棄されます。そういう停留所では手でオフにしてください（その路線は手で設定した路線になります）。

### 目印

路線マネージャーの停留所一覧で、「到着時にすべての貨物を強制的に積み下ろし」がオンの停留所には、名前と貨物のアイコンの間に小さな積み下ろしのアイコン（貨物フィルターの画面にある本体の積み下ろしの矢印）を出します。オフの停留所には同じ大きさの空きを置くので、貨物のアイコンの列はそろったままです。目印は、手で設定した路線も含めすべての路線に出ます。路線の情報を読むだけで、何も変えません。MOD の設定「**停留所一覧の印**」で消せます。

### 互換性

- プレイ中のセーブに追加しても、外しても問題ありません（`severityAdd: None`、`severityRemove: None`）。この MOD は自分のデータをセーブに残しません。設定するのは本体の各停留所の `forceUnload` で、MOD を外してもそのまま残ります。
- `cosmetic` です。ゲームの中で変えるのは、路線マネージャーで手でも付けられる本体の停留所ごとのチェックボックスだけです（ほかは停留所一覧のアイコンとこの MOD の設定）。ゲームのルールは足しません。
- 本体のファイルは置き換えません。GUI の起動時に本体の `line_util.autoLoadConfig`・`line_util.makeNewStop`・`line_react_util.LineCargoDisplay` を包み、先に元の関数を呼びます。同じ関数を包む他の MOD もそのまま動きます。
- 依存する MOD はありません。
- 似た MOD: Line Toolkit（mod.io 6414310）は、貨物が戻ってきてから路線ごとに積み下ろし強制をオンにします。この MOD は、路線を作るときに、停留所が積む貨物から停留所ごとに決めます。

### 導入

- mod.io：https://mod.io/g/transportfever3/m/auto-force-unload-at-drop-off-stops（ゲーム内の MODハブからも購読できます）。
- 手動：ゲームは `<Steam>/userdata/<ID>/3493540/local/mods/` の中の、名前がちょうど `hummer_force_unload_default_1` のフォルダからだけ読み込みます。
  - リリースの zip から：そのフォルダを作り、その**中に** zip を展開します（zip には外側のフォルダがありません）。
  - GitHub から：`local/mods/` の中で `git clone https://github.com/hummer98/tpf3-auto-force-unload hummer_force_unload_default_1` とします（別のフォルダ名では読み込まれません）。
  - そのあとゲーム内で有効にします。

### 開発

ファイルの役割とテスト・パッケージの手順は、英語の「Development」の節を見てください。テストは `luajit tests/run.lua` と `TMPDIR=<スクラッチ> python3 -m unittest discover -s tests`、zip は `python3 tools/package.py`、ステージングは `local/mods/` のコピーで、ゲームを止めて `python3 tools/stage.py`（最初は `--first-upload`）です。版は `VERSION`、変更は `CHANGELOG.md` の `## [Unreleased]` に書き、release は開発用の clone で `python3 tools/release.py patch|minor|major|X.Y.Z` です（手順は [docs/release.md](docs/release.md)）。

### ライセンス

[MIT](LICENSE) © 2026 hummer
