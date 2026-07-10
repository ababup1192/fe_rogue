# platformer — ジャンプ手触りの検証台

値ベース第四作。背景なし・球体プレイヤー。画面は 480×360 の引きの画角（窓 960×720・
windowScale 2）。classic のシナリオ地形だけは Field.classicW/H の 320×240 に固定
（design に連動させると壁位置ごと動いて pin が壊れる）。本番レベルはマリオ 1-1 規模の
208×30 テキストグリッド（3328×480px・FollowCam が横縦とも追従）で、プラットフォーマーの手触り
（可変ジャンプ高・コヨーテタイム・ジャンプバッファ・非対称重力・慣性・空中制御・
B ダッシュ・崖死亡・動く床・一方通行・坂・敵 3 種・中間地点・クリアと花火）を
エンジンが支えられるかを検証する。レベル設計は「疾走感」: 全体を止まらず 1 本の
ダッシュで走破でき、敵の踏みバウンドが小ジャンプを兼ねる（敵 = トランポリン・
Motion の phase で歩き/バタつき/フェリーの位相を台本に合わせてある）。
物理は example 内の純粋関数（Physics2D の detect/separate を再利用・bounce は使わない）。
手触りが確定したら engine_world への昇格候補（Jump の数式・速度の法線成分ゼロ化政策）。

## モジュール地図（src — 生成系は src/bake/ に隔離）

| ファイル | 役割 |
|---|---|
| Main | App に部品を繋ぐ目次（宣言のみ） |
| Controls | キー割り当て（Frame → Field.Input）+ step / reloadParams |
| World | 全状態の型（mod Field）とレイアウト定数。Player/Platform/Enemy/Event/statusLine |
| Level | 本番レベル。208×30 テキストグリッド（16px セル・3328×480px）を run 融合で Platform 化。敵グリフ（w/f/s・600 番台）・坂（500 番台）・フェリー（400）・中間地点/ゴールの旗も供給 |
| FollowCam | 横+縦スクロールカメラ（不感帯 → 追従 → レベル端クランプ）。状態は World の camX/camY・縦の不感帯は広め（60px） |
| Step | 1フレームのルール（純粋）。タイマー → ジャンプ成立 → 走り・重力 → 物理 → 接地再計算 |
| Jump | ★手触りの式 = 本作の要。重力は「高さ h と頂点時間 t」で指定（-2h/t, 2h/t²） |
| GameParameters | F1 リロードの調整値 16 個（fail-open・既定値は Jump の定数が正） |
| View | World → 絵（Placed 列）。地形ボックス（草は露出上面のみ・一方通行は薄板+影線）+ 球体（着地スカッシュ・速度で色分け・回転ドット・最高速の残像）+ 演出の粒 + HUD 生値 |
| Palette | DB32 のロール名（描画コードは色リテラル禁止） |
| GameFx | 閉形式パーティクル — bursts（種＋原点＋経過秒）の種から粒の位置・透明度を毎フレーム導出する |
| Sfx | 前後 World → 鳴らす音名（events を写すだけ） |
| Trace | テストとギャラリー共有のシナリオ（flatWorld/ledgeWorld/ceilingWorld/浮き床走破/レベル完全走破 levelRunCues の台本） |
| Harness | 画面なしフォント焼き |
| debug/WorldDump | F8 注釈チケットと view=full の world.json（運動学・タイマー・params 全値・eventLog） |
| bake/Bake | make bake の入口（Gallery + SfxBake） |
| bake/Gallery | ギャラリー生成（満タン/タップ/浮き床走破/完全走破 full_clear_run の GIF → gallery/index.html） |
| bake/SfxBake | 効果音 8 種（jump/land/bump/death/stomp/clear/checkpoint/firework）を SfxSynth で合成して WAV へ |

test/ は検証のみ（計 97 本）: TestPlatformer（ジャンプ曲線・タイマー・衝突・ダッシュ・空中 DI・崖死亡 27）・
TestControls（キー割り当て 6）・TestMoving（動く床・一方通行 10）・
TestLevel（グリッドパーサ・敵/坂/旗の抽出・寸法 8）・
TestCamera（追従・クランプ・camY・ワイドレベルのスモーク・完全走破の台本 13）・
TestClear（P スピードゲート・中間地点・クリア・花火 10）・TestWorldDump（world.json の中身 3）・
TestSlope（坂の登り下り・吸着・接地しきい値・静止摩擦・登りの逆滑り回帰 8）・
TestFx（演出の粒: ジャンプ噴射の発生・ダッシュ土埃の cadence・寿命切れ・alpha の範囲 4）・
TestEnemy（敵 3 種: 触れたら死・踏みバウンド・トゲ・骸すり抜け・物理不干渉・同フレーム安全側 9）。

## 手触りの仕組み（要点）

- 昇格済み（バッチ A）: pingPong 往復（Curve.pingPong + Motion.Oscillation）・速度の法線成分
  ゼロ化（Physics2D.slide / normalToward）・カメラ追従の数式（CameraRig.followDelta / clampAxis）は
  数式の本体が engine_world にあり、example 側（Field / Step / FollowCam）は委譲だけ。
- 重力は加速度でなく「頂点の高さ jumpHeight・頂点までの時間 timeToApex」で指定。
  初速 = -2h/t、上昇重力 = 2h/t²。既定 96px / 24フレーム。
- 非対称: 下降は fallGravityMult（1.8）倍、頂点帯（|vy| ≤ apexBand）は apexGravityMult（0.5）倍。
- 可変高: ボタンを離した瞬間、上昇速度を cutMult（0.4）倍に 1 回だけ削る。
- コヨーテ 6/64 秒・バッファ 8/64 秒（1/64 の倍数なのでテストの pin が厳密）。
- B ダッシュ（Z / 左 Shift）= マリオの P スピード: 最高速の目標が dashMult（1.75）倍。
  加速は二帯 — |vx| が 160 までは今までどおり（地上 900 / 空中 500）、160 超の帯は
  dashAccel（80px/s²）でじわじわ = 160→280 に 1.5 秒（約 330px の助走）。離しても
  目標が 160 に下がるだけで、帯の中の減衰も dashAccel — 勢いがなかなか死なない（仕様）。
  この帯は下り坂の滑りにも効く（45° 下りの overspeed がゆっくりしか戻らない）。
  空中だけ帯の適用が非対称（スマブラの DI 風のベクトル変更）: 切り返し（進行方向と逆への
  入力）は常に airAccel（500）で強く効き、進行方向への上積みだけが dashAccel の P 帯
  = ダッシュジャンプ中も舵は切れるが、空中で速度は盛れない。
- 崖死亡: 死亡線（levelH + 40px・Field.deathLineOf）を割ったら death イベント +
  リスポーン地点へ + deaths カウント。リスポーンは出発点、中間地点の旗（x=1688）を
  越えた後はそこ（World.respawnPos が権威・カメラも両軸スナップ）。
  本番レベルは Level.flix の 208×30 グリッド（3328×480px・カメラは FollowCam が横縦追従）。
  classic 地形（A: 0..96 / 狭い穴 50px / B: 146..200 / 広い穴 80px / C: 280..320）は
  Trace のシナリオ用（Trace.classicWorld）。広い穴は P スピード + 低ホップ（6f・浮き床 B の
  下をくぐる）で渡れ、素の走りでは落ちる（ゲート）。classic の助走路は 280 に届かないので
  崖越えシナリオ（Trace.dashGapWorld）は vx=280 preset で始める（助走は本番レベルが提供）。
- 敵 3 種（当たり判定は半径 10 の円のまま・600 番台 id・動きは base+pingPong の閉形式で状態は
  alive だけ）: 見た目は自機の球体と混線しないよう「まんじゅう型」（角丸ボックスの上半分 +
  平らな底 + 白目に黒い瞳の目玉）に統一している（View.enemyItems・当たり判定は不変）。
  歩く敵（横往復・踏める・足が歩きの揺れで動く）/ パタパタ（縦往復・踏める・羽ばたく羽つき・
  足なしで浮く）/ トゲ（固定・踏んでも死ぬ・ドーム上側だけに大きい上向きの棘が並ぶ）。
  触れたら崖死亡と同じ扱い（death + 出発点へ + deaths++）。踏み判定 =
  「前フレーム（carry 後）の足元が敵の頭（上端+2px）より上 ∧ 下向きに落ちている」で、
  成立すると敵が死に（alive=false・骸は当たらない・描かない）、vy が -320（半ジャンプの
  バウンド）になり stomp が鳴る。同フレームで踏みと致命の接触が同時なら死亡が勝つ（安全側）。
  敵は床の物理（Physics2D の positions/shapes）に一切入らない — enemies=Nil なら全挙動が
  従来とバイト一致。
- ジャンプ判定は前フレームの接地を使う（1 フレームの遅れはコヨーテが吸収）。
  接地は separate 後の接触の法線（normal#y < groundedNormalY = -0.6）から毎フレーム再計算する。
- 坂（SlopeShape2D・斜辺が上面の直角三角形）: 45° の法線は y=-0.707 なので接地しきい値は
  0.6。下り坂は 6px の吸着（snapProbe）が接地を繋ぐ — 坂の面と真上向きの面接触だけを
  支えと認め、矩形の角のかすめは拾わない（崖離れを遅らせない）。
- 坂の上は二本立て（Step.climbVelocity と静止摩擦）: 登り（入力が坂の高い側）は速度を
  斜面の接線に沿わせる（重力なし・小さな吸い付き速度で接触維持・45° の登りは走り 160 が
  水平 80 = 接線 x 成分の 2 乗倍に落ちる）。入力なしはその場に停める（静止摩擦・x 不変）。
  下り・P スピード帯の勢いの滑走・空中は従来の物理のまま（45° 下りの overspeed は仕様）。
- 重力は接地中も掛け続ける — separate が毎フレーム打ち消すので接触が切れず接地が安定。
- 衝突の速度解決は「面に食い込む法線成分をゼロ化」（跳ねない）。着地で vx が残る = 慣性。
- 段階演出はすべて |vx| から導く（新しい状態なし）: 球体の色 3 段階（≤160 黄 /
  >160 橙 / ≥279.5 白）・土埃の cadence と大きさ（band = clamp((|vx|-160)/120, 0, 1) で
  8〜24 回/秒・粒 4〜8 個・半径 1〜1.8 倍）・最高速の残像 2 枚（pos − vel×3dt / ×6dt・
  alpha 0.35/0.18）・転がりの点 2 個（θ = x/半径・潰れ中は省略）。着地の瞬間は左右へ
  土煙 2 発（power は落下速度から）。Burst は power（0..1・勢い）を持ち、GameFx が
  bursts の種から毎フレーム閉形式で粒を導く — 位置も保存せず、elapsed だけが状態。
- クリア: World.goalX（レベルは旗 x=3272・classic は届かない levelW+1000）を越えた 1 回だけ
  clear イベント + clearedAt=Some(時刻)。以後 HUD に CLEAR!・ゲームは止まらない。
  花火はクリアの 0.6 秒後から 0.2 秒間隔で 10 発（Step が clearedAt から決定的に発射・
  FxKind.FireworkKind = 24 粒の放射リング + 重力の垂れ 40t²・色は Palette.fireworkColor が
  発番号で 4 色巡回）。中間地点も同型: World.checkpointPos の x を越えた 1 回だけ
  checkpoint イベント + respawnPos がそこへ移る（旗の見た目は白 → 緑）。
- Motion に phase（0..1）が入った: pingPong(t/period + phase)。既存の動く床・敵は 0.0 で
  従来とバイト一致。レベルの歩く敵（列 155/163）・パタパタ（列 157）・フェリー（0.32）は
  走破の台本が待たずに通れる位相の実測値（Level の *PhaseAt 表と ferryPhase）。
- 地形の見た目: 一方通行は上端 6px の薄板 + 1px の影線（薄い = すり抜けの記号・当たり判定は
  従来のまま）。動く床は厚い一枚板（厚い = 硬い）。草キャップは真上に別の硬い床が無い
  露出上面だけに描く。レベル端はグリッドの柱でなく画面外の見えない壁（Level.boundaryWalls・
  id 198/199・[0,3328] の外）が受ける。

## コマンド（このディレクトリで）

| コマンド | 用途 |
|---|---|
| `make run` | ゲームを起動する |
| `make debug` | F8 の時間停止・注釈・巻き戻し付きで起動する |
| `make bake` | ギャラリーと効果音 WAV を生成する（看板 GIF = full_clear_run 1127f） |
| `make test` | テストを実行する（検証のみ・数秒） |
| `make check` | 型検査だけ走らせる |

## 操作

←→ = 走る / Z・左Shift = B ダッシュ / Space = ジャンプ（長押しで高く）/
↓+ジャンプ = すり抜け降下（一方通行の床から降りる）/
F1 = parameters.json リロード / Escape = 終了 /
（make debug 時）F8 = 時間停止 + ←→スクラブ + ドラッグで注釈チケット

## 検証の流儀

- 挙動を変えないリファクタは `make bake` 後に `gallery/` と `assets/sfx/` の全ファイル shasum が
  **バイト一致**することで機械的に証明する（決定的に生成される）
- リモートデバッグ: `DEBUG=1 DEBUG_HTTP_PORT=7777 bin/flix run` で起動し
  `./debug/jump_probe.sh` がジャンプ曲線を lockstep で再現・観測する
  （view=status = 1 行サマリ / view=full = world.json 全文）
- Trace.runAcrossCues の浮き床走破台本は remote-debug の lockstep で振り付けた実測値
