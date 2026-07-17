# feature_lab

engine_world の新機能を雑多に試し、スナップショットで目視確認するための実験場。
本番ゲームではないので、実験が終わったモジュールは古い実験ごと入れ替えてよい。

`make bake`（実体は `bin/flix run --entrypoint Bake.all`）で `gallery/` に PNG・GIF・
コマ送りサイトを焼く。今の実験は Transition（フェード・ワイプ）: `make run` で起動すると
覆いなしの Idle（HUD は `idle (W/A/S/D)`）で立ち上がり、W/A/S/D キーで該当の遷移を最初から
再生する。再生し終えると自動で Idle に戻る（FadeOut の黒も残らない）。Space は今の種類を
再生し直す（Idle 中は直前に選んだ種類・起動直後は FadeOut）。

実験中の機能一覧: withFixedStep（固定タイムステップ）— Main で有効化済み。絵は見た目上変えず、
Controls.countStep が回った回数を statusLine の `steps=` に出すだけ（HTTP の `/state` や
リモートデバッグの view=status で見える）。

AudioFade + マスター音量 — B キーで BGM（assets/sfx/bgm.wav・looping）のフェードの向きを反転、
M キーでマスター音量 1.0/0.3 を切り替え。値は statusLine の `bgm=` / `master=` に出る。
Controls.audioStep が「値の導出はエンジン（Transition.Progress + AudioFade.volumeOf）・
setVolume / setMasterVolume の適用はゲーム側 system」の分業の手本。gallery/ には音量カーブ
PNG 3 枚と、同じ volumeOf をサンプル毎に焼き込んだ試聴 WAV 3 本（audio.html から聴ける）。

フルスクリーン切替 + カーソル非表示 — Enter キーでウィンドウ⇄ボーダーレスフルスクリーンを
切り替え、H キーでマウスカーソルの表示/非表示を切り替える。値は statusLine の `fullscreen=` /
`cursor=` に加え、HUD（画面内左上のテキスト）にも `fullscreen=on/off` / `cursor=on/off` を
出す（フルスクリーン時はタイトルバーごと statusLine が見えなくなるため）。
実窓の切替そのもの（黒帯の出方・カーソルの消え方）は gallery には出せず起動確認のみ
（`make run` で手元のウィンドウを見て確かめる）。判定方法: 画面には design 領域の四辺に
シアンの縁取り・四隅に黄色い L 字マーカー・中央に十字を焼き込んである。フルスクリーンに
した時、**縁取りの外側が黒帯（レターボックス）として見えれば viewport が design 通りに
収まっている証拠**。四隅マーカーが直角のまま欠けずに見えていればスケーリングも歪んでいない。
ポーズ中（F8）は system が回らないため Enter/H が効かない。F8 解除で復帰する。

light.json 駆動のカンテラ探索 — カンテラの光の質感（暗さ・照り返しフチの太さ/強さ・
ハロの大きさ倍率・光の半径/色/強さ）は `assets/Lantern.light.json` が持つ（位置だけは
矢印キーで動く World の値が正）。`make debug` で起動中は、json を保存するたびに
`App.watchFile` が検知して即座に絵へ反映される（F1 の ui.json 再読込と同じ枠組み）。
