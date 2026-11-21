# mod.io page text

The in-game uploader has no description field: paste this into the mod.io web page.

**Summary:** Automatically turns on force unload at stops that only drop off cargo; stops that load cargo keep it off. / 貨物を降ろすだけの駅で積み下ろし強制を自動でオン、貨物を積む駅ではオフ。

## English: Auto Force Unload at Drop-off Stops

Turns on "Force Unload All Cargo On Arrival" at the stops where a cargo line only unloads, so the cargo is unloaded there even when the stock is full instead of riding back to where it was loaded. Stops that load cargo keep it off.

It acts whenever the Line Manager works out a line's load configuration by itself: when you create a line, add a stop or a waypoint, remove a stop or move one in the order. Passengers do not count as cargo. Lines that load no cargo anywhere (passenger lines, a line with a single stop) keep it off everywhere, and lines whose cargo settings or checkboxes you changed by hand are left alone. Lines that existed before the mod are adjusted the next time you edit them.

In the Line Manager's stop list, a small unload icon next to the stop name shows where force unload is on, on every line.

Mod settings: Stops to set (All stops of the line, or New stops only) and Marker in the stop list (On / Off).

Note: with force unload on, cargo is unloaded into a full stock and destroyed, also at a stop along the way where it could have gone on to a later stop. Switch the checkbox off there by hand.

Adding and removing the mod is safe for saves: it only sets the base game's own checkbox, which stays as it is without the mod. Similar mod: Line Toolkit (mod.io 6414310) turns force unload on per line after cargo has come back; this one sets it per stop while you build the line.

Texts in all 13 game languages. License: MIT. Source code: https://github.com/hummer98/tpf3-auto-force-unload

## 日本語: 降ろすだけの駅に積み下ろし強制を自動設定

貨物の路線で、積み下ろすだけの停留所の「到着時にすべての貨物を強制的に積み下ろし」をオンにします。在庫が満タンでも貨物をそこで下ろすので、積んだ場所まで貨物が戻ってこなくなります。貨物を積む停留所ではオフのままです。

路線マネージャーが路線の積み込み設定を自動で決めるたびに動きます。路線を作る、停留所やウェイポイントを足す、停留所を消す、順番を入れ替える、のときです。旅客は貨物に数えません。どの停留所でも貨物を積まない路線（旅客の路線、停留所が 1 つの路線）は全部オフのままで、積み込む貨物やチェックボックスを手で変えた路線には触りません。MOD を入れる前からある路線は、次に編集したときに合わせます。

路線マネージャーの停留所一覧では、積み下ろし強制がオンの停留所の名前の横に、小さな積み下ろしのアイコンを出します（すべての路線）。

MOD の設定：設定する停留所（路線の全停留所を合わせる／新しく足した停留所だけ）、停留所一覧の印（オン／オフ）。

注意：オンの停留所では、在庫が満タンでも貨物を下ろして破棄します。途中の停留所で、先の停留所へ運べたはずの貨物も消えます。そういう停留所では手でオフにしてください。

セーブへの追加も、セーブからの削除も問題ありません。設定するのは本体のチェックボックスだけで、MOD を外してもそのまま残ります。似た MOD：Line Toolkit（mod.io 6414310）は、貨物が戻ってきてから路線ごとに積み下ろし強制をオンにします。この MOD は、路線を作るときに停留所ごとに決めます。

ゲームの13言語に対応。ライセンス：MIT。ソースコード：https://github.com/hummer98/tpf3-auto-force-unload
