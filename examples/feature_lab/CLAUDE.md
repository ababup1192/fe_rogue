# feature_lab

engine_world の新機能を雑多に試し、スナップショットで目視確認するための実験場。
本番ゲームではないので、実験が終わったモジュールは古い実験ごと入れ替えてよい。

`make bake`（実体は `bin/flix run --entrypoint Bake.all`）で `gallery/` に PNG・GIF・
コマ送りサイトを焼く。今の実験は Transition（フェード・ワイプ）: `make run` で 1/2/3/4 相当の
W/A/S/D キーで種類を切り替え、Space で再生し直せる。

実験中の機能一覧: withFixedStep（固定タイムステップ）— Main で有効化済み。絵は見た目上変えず、
Controls.countStep が回った回数を statusLine の `steps=` に出すだけ（HTTP の `/state` や
リモートデバッグの view=status で見える）。

AudioFade + マスター音量 — B キーで BGM（assets/sfx/bgm.wav・looping）のフェードの向きを反転、
M キーでマスター音量 1.0/0.3 を切り替え。値は statusLine の `bgm=` / `master=` に出る。
Controls.audioStep が「値の導出はエンジン（Transition.Progress + AudioFade.volumeOf）・
setVolume / setMasterVolume の適用はゲーム側 system」の分業の手本。gallery/ には音量カーブ
PNG 3 枚と、同じ volumeOf をサンプル毎に焼き込んだ試聴 WAV 3 本（audio.html から聴ける）。
