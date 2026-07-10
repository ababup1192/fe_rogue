# platformer — ジャンプ手触りの検証台

値ベース第四作。背景なし・球体プレイヤー・崖 2 本で 3 分割の地面と浮き床 3 枚の最小構成で、
プラットフォーマーの手触り（可変ジャンプ高・コヨーテタイム・ジャンプバッファ・
非対称重力・慣性・空中制御・B ダッシュ・崖死亡）をエンジンが支えられるかを検証する。
物理は example 内の純粋関数（Physics2D の detect/separate を再利用・bounce は使わない）。
手触りが確定したら engine_world への昇格候補（Jump の数式・速度の法線成分ゼロ化政策）。

## モジュール地図（src — 生成系は src/bake/ に隔離）

| ファイル | 役割 |
|---|---|
| Main | App に部品を繋ぐ目次（宣言のみ） |
| Controls | キー割り当て（Frame → Field.Input）+ step / reloadParams |
| World | 全状態の型（mod Field）とレイアウト定数。Player/Platform/Event/statusLine |
| Step | 1フレームのルール（純粋）。タイマー → ジャンプ成立 → 走り・重力 → 物理 → 接地再計算 |
| Jump | ★手触りの式 = 本作の要。重力は「高さ h と頂点時間 t」で指定（-2h/t, 2h/t²） |
| GameParameters | F1 リロードの調整値 14 個（fail-open・既定値は Jump の定数が正） |
| View | World → 絵（Placed 列）。地形ボックス + 球体（着地スカッシュ）+ HUD 生値 |
| Palette | DB32 のロール名（描画コードは色リテラル禁止） |
| Sfx | 前後 World → 鳴らす音名（events を写すだけ） |
| Trace | テストとギャラリー共有のシナリオ（flatWorld/ledgeWorld/ceilingWorld/浮き床走破の台本） |
| Harness | 画面なしフォント焼き |
| debug/WorldDump | F8 注釈チケットと view=full の world.json（運動学・タイマー・params 全値・eventLog） |
| bake/Bake | make bake の入口（Gallery + SfxBake） |
| bake/Gallery | ギャラリー生成（満タン/タップ/浮き床走破の GIF → gallery/index.html） |
| bake/SfxBake | 効果音 3 種（jump/land/bump）を SfxSynth で合成して WAV へ |

test/ は検証のみ: TestPlatformer（ジャンプ曲線・タイマー・衝突・ダッシュ・崖死亡の pin 24 本）・
TestControls（キー割り当て 5 本）・TestWorldDump（world.json の中身 3 本）。

## 手触りの仕組み（要点）

- 重力は加速度でなく「頂点の高さ jumpHeight・頂点までの時間 timeToApex」で指定。
  初速 = -2h/t、上昇重力 = 2h/t²。既定 96px / 24フレーム。
- 非対称: 下降は fallGravityMult（1.8）倍、頂点帯（|vy| ≤ apexBand）は apexGravityMult（0.5）倍。
- 可変高: ボタンを離した瞬間、上昇速度を cutMult（0.4）倍に 1 回だけ削る。
- コヨーテ 6/64 秒・バッファ 8/64 秒（1/64 の倍数なのでテストの pin が厳密）。
- B ダッシュ（Z / 左 Shift）: 最高速の目標が dashMult（1.75）倍になるだけ。離しても
  即減速せず、加速と同じ速さで 160 へ戻る（勢いが残る）。
- 崖死亡: deathY（画面下端+40px）を割ったら death イベント + 出発点へ + deaths カウント。
  地形は A: 0..96 / 狭い穴 50px / B: 146..200 / 広い穴 80px / C: 280..320。
  広い穴はダッシュ低ホップ（6f・浮き床 B の下をくぐる）で渡れ、素の走りでは落ちる（ゲート）。
- ジャンプ判定は前フレームの接地を使う（1 フレームの遅れはコヨーテが吸収）。
  接地は separate 後の接触の法線（normal#y < -0.7）から毎フレーム再計算する。
- 重力は接地中も掛け続ける — separate が毎フレーム打ち消すので接触が切れず接地が安定。
- 衝突の速度解決は「面に食い込む法線成分をゼロ化」（跳ねない）。着地で vx が残る = 慣性。

## コマンド（このディレクトリで）

| コマンド | 用途 |
|---|---|
| `make run` | ゲームを起動する |
| `make debug` | F8 の時間停止・注釈・巻き戻し付きで起動する |
| `make bake` | ギャラリーと効果音 WAV を生成する |
| `make test` | テストを実行する（検証のみ・数秒） |
| `make check` | 型検査だけ走らせる |

## 操作

←→ = 走る / Z・左Shift = B ダッシュ / Space = ジャンプ（長押しで高く）/
F1 = parameters.json リロード / Escape = 終了 /
（make debug 時）F8 = 時間停止 + ←→スクラブ + ドラッグで注釈チケット

## 検証の流儀

- 挙動を変えないリファクタは `make bake` 後に `gallery/` と `assets/sfx/` の全ファイル shasum が
  **バイト一致**することで機械的に証明する（決定的に生成される）
- リモートデバッグ: `DEBUG=1 DEBUG_HTTP_PORT=7777 bin/flix run` で起動し
  `./debug/jump_probe.sh` がジャンプ曲線を lockstep で再現・観測する
  （view=status = 1 行サマリ / view=full = world.json 全文）
- Trace.runAcrossCues の浮き床走破台本は remote-debug の lockstep で振り付けた実測値
