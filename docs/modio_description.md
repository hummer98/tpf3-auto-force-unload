# mod.io page text

The in-game uploader has no description field: paste this into the mod.io web page.

**Summary:** Automatically turns on force unload at stops that only drop off cargo; stops that load cargo keep it off. / 貨物を降ろすだけの駅で積み下ろし強制を自動でオン、貨物を積む駅ではオフ。

## English: Auto Force Unload at Drop-off Stops

**What this mod does:** it switches the base game's "Force Unload All Cargo On Arrival" checkbox for you, stop by stop: on at stops where a cargo line only unloads, off at stops that load cargo.

**When:** whenever the Line Manager works out a line's load configuration by itself: when you create a line, add a stop or a waypoint, remove a stop or move one in the order. Passengers do not count as cargo. Lines that load no cargo anywhere (passenger lines, a line with a single stop) keep it off everywhere, and lines whose cargo settings or checkboxes you changed by hand are left alone. Lines that existed before the mod are adjusted the next time you edit them.

**What the mod adds:** a small unload icon next to the stop name in the Line Manager's stop list, where force unload is on (every line). Mod settings: Stops to set (All stops of the line, or New stops only) and Marker in the stop list (On / Off).

**What the checkbox does (base game, measured in build 40444 on one cargo line into an industry):** on: all cargo is unloaded; what fits into the receiving stock is accepted and paid for, the rest is destroyed when the stock is full, and no fare is paid for the destroyed cargo. Off: cargo that is not accepted stays aboard and rides on to the next stop. So at a stop along the way that loads no cargo, "on" also destroys cargo that could have gone on to a later stop; switch it off there by hand.

Adding and removing the mod is safe for saves: it only sets the base game's own checkbox, which stays as it is without the mod. Similar mod: Line Toolkit (mod.io 6414310) turns force unload on per line after cargo has come back; this one sets it per stop while you build the line.

Texts in all 13 game languages. License: MIT. Source code: https://github.com/hummer98/tpf3-auto-force-unload

## 日本語: 降ろすだけの駅に積み下ろし強制を自動設定

**この MOD がすること：** 本体のチェックボックス「到着時にすべての貨物を強制的に積み下ろし」を、停留所ごとに自動で切り替えます。貨物を降ろすだけの停留所ではオン、貨物を積む停留所ではオフです。

**動くとき：** 路線マネージャーが路線の積み込み設定を自動で決めるたびに動きます。路線を作る、停留所やウェイポイントを足す、停留所を消す、順番を入れ替える、のときです。旅客は貨物に数えません。どの停留所でも貨物を積まない路線（旅客の路線、停留所が 1 つの路線）は全部オフのままで、積み込む貨物やチェックボックスを手で変えた路線には触りません。MOD を入れる前からある路線は、次に編集したときに合わせます。

**MOD が足すもの：** 路線マネージャーの停留所一覧で、積み下ろし強制がオンの停留所の名前の横に小さな積み下ろしのアイコン（すべての路線）。MOD の設定：設定する停留所（路線の全停留所を合わせる／新しく足した停留所だけ）、停留所一覧の印（オン／オフ）。

**チェックボックスの働き（本体の仕様、build 40444、産業へ届ける路線 1 本で計測）：** オンでは到着した貨物を全部下ろします。届け先の在庫に入る分は受け取られて運賃が入り、在庫が満タンなら残りは破棄され、破棄された分の運賃は入りません。オフでは、受け取られない貨物は車両に載ったまま次の停留所へ運ばれます。そのため、貨物を積まない途中の停留所でオンにすると、先の停留所へ運べたはずの貨物も破棄されます。そういう停留所では手でオフにしてください。

セーブへの追加も、セーブからの削除も問題ありません。設定するのは本体のチェックボックスだけで、MOD を外してもそのまま残ります。似た MOD：Line Toolkit（mod.io 6414310）は、貨物が戻ってきてから路線ごとに積み下ろし強制をオンにします。この MOD は、路線を作るときに停留所ごとに決めます。

ゲームの13言語に対応。ライセンス：MIT。ソースコード：https://github.com/hummer98/tpf3-auto-force-unload
