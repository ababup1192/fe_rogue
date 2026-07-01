# fe_rogue B（render-from-World）ワークフロー（道標・living）

> **A（World=sim 状態の唯一の真実源 / scene-tree=render 層）は完成済み**（達成記録は git history / コミット参照）。
> 本 doc は **B＝scene-tree 撤廃・World component を render System が直接 `Drawable` 化**（重複②＝entity↔NodePath ＋ syncTree 同期層 の撲滅）の道標。
> 新セッションは「現状・次の一手」→「B ワークフロー」で現在地を確認してから着手する。

---

## 現状・次の一手（2026-07-01）

- **環境**: worktree `~/Desktop/fe_rogue-b-gate`（branch `b-gate-spike`）。`bin` を main から symlink・`make sync` で engine 改修込みパッケージを注入済 → fe_rogue build green。**B 作業はここで**（main の A は不変・安全）。
- **直近の到達点**: ユニット sprite を World render System へ移行（m1）＋ tween/描画位置を World で回す（m2 両 faction）。さらに **動きの統一抽象 `EcsTween`（汎用 ECS tween）を導入し、味方/敵の移動を単一 `World.moveUnit` に統一**（個別実装を撤廃・純粋層テスト 8 本 green・全 1072 green・92点リファクタ済）。設計道標は `~/.claude/plans/ecs-workflow-md-stateful-stroustrup.md`。
- **次の一手**: 動き統一スパイクは **Phase 4 lib 昇華まで完成**（`EcsTween` を `engine_ecs` lib へ移設・fe_rogue は use のみ・dodge 等も利用可）。残る前進路は延期（engine tween 退役＝scene-tree 撤去と同時）ゆえ、**B 主レーンの次項目**（HUD→World / 背景 map・fog・minimap→World / メニュー…）へ。着手時は各々 explore→plan から。
  - **延期**: engine tween 退役＋marker 単一権威（条件付き syncMarkers・unitDraw marker 単一読み・isMoving→isAnimating）は `Tween.Scheduler` cascade＋cancel 経路 World 化を伴うため **scene-tree 撤去と同時**（敵武器/HP の 1 フレームラグ根治もここで・ユーザー判断 2026-07-01）。
- **参考資料**: `~/.claude/plans/phase-b-eval-node-tree-removal.md`（B 評価リサーチ・engine gap・工数内訳 ≈ 9〜13週）。

---

## ✅ 完了（B）

- [x] **B 評価ゲート**（feasible 判定 → ユーザー GO）
- [x] **engine: `GameEngine.renderArgs(scene)`** — render() の drawable 抽出を返す版（scene + World 由来 drawable を 1 回の renderCommands で合成可能に）
- [x] **engine: `Render.textTinted`** — text 着色（menu の disabled/cursor/header 色用）
- [x] **engine: `Render.drawAtlas`**（effectful `\ GameEngine.Game`）— region atlas 描画（`getTextureInfo` で UV 計算・`Sprite2D.computeUv` 相当）。既存 pure `draw` 不変＝dodge 非破壊
- [x] **m1: ユニット sprite を World render System へ**
  - [x] `RenderWorld.renderUnits`（World→Drawable）＋ Game.flix で `renderArgs` に合成 overlay
  - [x] `hideUnitSprites` で scene 側 unit sprite を render から除外＝ユニットは World 描画のみ（重複②の一角を剥離）
  - [x] fog/hidden/待機暗転を `effectiveVisibleAt`/`effectiveModulateAt`/`effectiveZIndexAt` で faithful 再現
- [x] **m2-step1: World に tween System の基盤**（`renderPos`/`moveAnim` store・`Cmd.SetRenderPos`/`StartMove`・`stepWorld(world, dt)` が **実時間 dt（秒）で `Vec2.lerp`**＝engine tween と lockstep 同期〔fps 非依存〕・`renderPosOf`/`isAnimating`）。※ tick ベースだと fps≠60 で engine tween と desync（武器/HP 遅延・逆ジャンプ）→ 実時間化で解消。
- [x] **m2-step2a: 味方移動を World tween 駆動**（`moveTo` が `StartMove` emit・`renderUnits` が `renderPosOf` 読み・engine tween と共存同期・実機確認済）
- [x] **m2-motion: 動きの統一抽象 `EcsTween`**（汎用 ECS tween・設計レビュー 91/100→実装 92/100）
  - [x] 新規 `ecs/EcsTween.flix`: 複合キー `Tweens[k,c]`＝`Map[(entity,channel), Entry]`・`Track`(Vec/Scalar)/`Out`/`Easing`/yoyo・純粋・実時間 dt・`step` は `(tweens', outs, done)`（完了は t=1.0 clamp の exact スナップ）。lib は「値の補間」だけ知り意味（Position/Alpha）はゲームの `Channel` が持つ（Bevy Lens の no-reflection 版）
  - [x] World: `Channel` enum・`moveAnim`→`tweens` store・`Cmd.StartTween`・`applyTweenOut`（不能組 `bug!`）・refreshMirror 剪定・**`moveUnit`（faction-blind smart constructor）**
  - [x] **味方 `moveTo` と敵 `replayEnemyMoveView` が同一 `World.moveUnit(ref, span, sec)` 1本に統一**（個別実装撤廃）
  - [x] 純粋層テスト `TestEcsTween` 8 本 green（補間/easing/完了スナップ/active gate/多チャンネル実証/yoyo 往復）＝Phase 3「多チャンネル実証」を投機 production コードなしで達成
  - [x] **Phase 4 lib 昇華**（ユーザー承認 2026-07-01）: `EcsTween.flix`＋`TestEcsTween.flix` を `engine_ecs`（lib）へ移設。`make sync-engine-ecs` で fpkg 配布。fe_rogue は World.flix 無改修で lib 経由解決（check green・1064 tests green）。engine_ecs 23 tests green・dodge も非破壊 green。**当初ゴール「汎用機構をエンジン側で提供し各ゲームが使う」を達成**（scene `Tween` と衝突回避で名前は `EcsTween` 維持）

---

## 🔲 B ワークフロー（残り・チェックボックス）

### 主レーン（依存順・最後が B 完成宣言）

- [x] **m2 機能完了（ユニット sprite が World tween 駆動・両 faction・実機 OK）**
  - [x] 味方/敵移動の `StartMove` emit（World が tween を回す＝本筋の核心）
  - [x] `renderUnits` が `renderPosOf` で位置を読む（fallback=scene marker）
  - [x] **renderUnits は「移動アニメ中だけ renderPos、それ以外は marker」**（`isAnimating` gate）＝攻撃 lunge/knockback 等の marker アニメを正しく捕捉。
  - **★重要発見（2026-06-30）**: `renderPos` は **移動しか持たない**。攻撃 lunge は別アニメ（AnimationPlayer が marker を動かす）。→ marker を renderPos で全上書きする `syncMarkersToRenderPos` は **lunge を消す**ので撤回（enemy も renderPos 速度に固定され遅く見えた）。**真の単一源化＝全アニメ（move/lunge/knockback）を World 化**してからでないと「全部 renderPos」にできない。当面は move=renderPos / 他=marker のハイブリッド。
  - 〜以下は scene-tree 撤去フェーズで（engine tween は isMoving timer として存続）〜
  - [ ] lunge/knockback 等を World アニメ化（→ renderPos が全位置を持つ）
  - [ ] `isMoving` → `World.isAnimating`・engine tween 撤去＝完全単一源（⚠ Tween.Scheduler effect cascade・scene-tree 撤去と同時が自然）
- [ ] **HUD を World 描画**（TopBar・ユニット情報パネル等・text 主体＝`textTinted` 活用）
- [ ] **メニュー全面移植** ★最大の山（4〜6週相当）
  - [ ] 共通ウィジェットを手書き（ItemList の cursor/focus/disabled/auto-size、input bubbling）
  - [ ] 各 menu を World 描画へ（ActionMenu / WeaponSelect / ItemMenu / TradeMenu / GameOver / LevelUp / 他）
- [ ] **camera を World 化** ★要相談（engine camera System 新規・追従/smoothing/limit）
- [ ] **scene-tree 完全撤去**＝**B 完成宣言**（EntityScene / `syncTreeFromWorld` / render-from-scene 経路 / 重複② の物理撤去）
- [ ] **統合・全体 run 検証**

### ∥ 並列レーン（主レーンと同時進行できる＝本物の並列益）

- [ ] **∥ engine Systems**（★要相談・多くの移植の前提ゆえ早めに着手すると後続が楽）
  - [ ] parent-child 変換合成（`globalPositionAt` 相当を World component で）← HUD/menu 階層描画の前提
  - [ ] y-sort（renderOrder）
  - [ ] modulate 色継承（祖先乗算）
  - [ ] CanvasLayer（カメラ非適用 UI レイヤ）
- [ ] **∥ 背景描画・オーバーレイ**（互いに独立・ユニット移植と独立）
  - [x] **fog を World**（`RenderWorld.renderFog`＝FogScene 純粋関数を再利用し暗幕を solidBox Drawable 化・`hideHaze` で scene プール隠し・Map ノード存在ガード。実機 OK）
  - [x] **MoveAttackRange（脅威範囲）を World**（`RenderWorld.renderMoveAttackRange`＝表示専用ゆえ格納セルを `RangeOverlay.tileDrawables` で hatch Panel の Drawable 化・`hideTiles`。実機 OK）
  - [x] **汎用化＋lib 昇華: `Render.applyCameraScale`**（units/fog/range の camera 適用〔applyToWorldPos＋scale×zoom〕の重複 spine を `engine_ecs/Render` へ昇華。dodge 等も再利用可）＝flow「実装×2→法則→汎用→lib」の 1 サイクル完了
  - [ ] map タイルを World 描画（tilemap from `Board`/World。★per-cell atlas データが World 未保持＝engine 相談要）
  - [ ] minimap を World（★accumulated 状態移送＋CanvasLayer 要）
  - [x] **MoveRange（移動範囲・青）を World**（`renderMoveRange`＝renderMoveAttackRange と同型 3 行。描画セル stoppable を `Data#drawCells` に格納して再計算回避。**helper 投資の回収実証**＝新規ロジックなし）
  - [ ] 残 range overlays（DangerZone/TradeRange/EnemyRange）を同様に（各 ~数行・`tileDrawables` 再利用）

### 依存関係メモ
- **engine Systems（parent-child）→ HUD/メニュー**（階層描画の前提）。並列レーンだが、UI 移植より**先行**させると楽。
- **camera World 化**は描画位置に効くが、現状 `renderUnits` は `findActiveCamera` で camera transform を読めている → camera 撤去は **scene-tree 撤去の直前**でよい（後ろ倒し可）。
- **scene-tree 撤去**は全要素（ユニット/HUD/menu/背景/camera）が World 描画になってから（最後）。
- **メニュー**は共通ウィジェット 1 本を作ってから各 menu に並列展開（早すぎる個別実装を避ける）。

---

## B 固有の重要知見（ハマりどころ）

- **tween/描画位置は scene 側にある**（離散 grid + engine Tween）→ render-from-World には **render-position component（`moveAnim`/`renderPos`）を World に持ち、`stepWorld` で補間**する必要がある。dodge は連続 physics 位置を World に持つので不要だった。fe_rogue 固有の山。
- **engine 描画基盤の再利用**: `engine_ecs/Render`（`RenderItem`→`Drawable`・Bevy bevy_sprite 相当）＋ dodge `examples/dodge_the_creeps_ecs/src/render/RenderWorld.flix`（動く World→Drawable 参考実装）＋ `pathToDrawables`（camera 適用手順）。**ノードの drawable は `GameEngine.Renderable.toDrawables(node, screenPos)` で再利用できる**（texture/region/offset/flip が正しく出る）。
- **region atlas の UV** は `getTextureInfo` で texSize を引いて計算（render extract が `\ GameEngine.Game` 化する）。
- **engine 改修は事前相談**（「Godot 準拠のみ」「engine 拡張は必ず事前相談」）。region/camera/parent-child は Godot 標準対応物ゆえ追加の正当性あり。
- **scene.json の GUI 編集は B で失われる**（メニューを Flix code で組む＝オーサリング速度↓・IDE プロジェクトと競合）。go/no-go の判断材料として記録済（ユーザーは GO 済）。

---

## §B0. 最重要原則：既存ロジックは再実装せず「昇華」して再利用する

**過去の資産を必ず生かす。一から書き直さない。** 機能が必要になったら、まず既存実装を探し、見つかったら**再利用または昇華**する。新規実装は「既存に無い」と確認できた時だけ。

**探す順**: (1) `examples/fe_rogue` の純粋層 → (2) engine の純粋関数（ノードに埋まっていても可）→ (3) lib `flix_engine_ecs` → 無ければ新規。

**昇華（elevate）の型**:
- engine の **ノード由来ロジック** → ノードから切り離して再利用。障壁2種:
  - **(a) 既に pub＋純粋** ＝ 呼ぶだけ（engine 改修ゼロ）。実例: `Render` ← `Label2D.toDrawables`、`Renderable.toDrawables`。
  - **(b) pub だが effect 依存** ＝ **effect を引数注入で外す純粋化 refactor（engine 改修＝要相談）**。実例: region 描画は `texSize(\Game)` を引数注入すれば pure 化できる（B0b で `drawAtlas` として吸収済）。
- 汎用なら **lib に昇華**（実証後）、ゲーム固有なら **System／ゲーム内**へ。

**再利用ノート**（各ステップ必須）: 「どこを探したか／ヒット・不発／再利用・昇華・新規のどれをなぜ選んだか」を 1 段落で記録。

---

## §C. 再利用ツールキット（lib `flix_engine_ecs`）と sync 層

- **engine 描画**: `engine_ecs/Render`（RenderItem→Drawable）。dodge `RenderWorld` が参考実装。`render_core/Frame`（安定ソート混合描画）。
- **グリッド座標は新規不要**: `engine_core.Vec2i`（add/sub/eq/zero/方向）＋ `Vec2`（lerp/round）を再利用。
- **sync 層の現形**: `syncTreeFromWorld(world, scene)`（World→node 派生）＋ `PartyQuery`/`RosterQuery`/`BoardQuery`（effect facade・handler が scene 実体に委譲）。B では handler/描画を World 由来へ差し替えていく。
- **engine 編集後は `make sync`**（fpkg 再ビルド＋symlink・examples は fpkg 経由）。worktree は `bin` symlink ＋ `make sync` 必須。

---

## §F. 既知の落とし穴（Flix / engine 固有）

- **予約語をフィールド/変数名に使わない**: `from` / `to`(疑わしい) / `region` / `spawn` / `select` / `eff` / `project`（パースエラー）。位置記録は `srcPos`/`dstPos` 等に。
- **型位置の record** は `=`（値と同じ）だが **2 段ネスト・複数行は parse 不可** → `Vec2.Vec2` 等の型エイリアスで 1 段・1 行化。
- レコード丸ごとの `assertEq` は ToString 不在で不可 → スカラフィールドで assert。
- `Float64 → Int32` は `Float64.tryToInt32(Float64.floor(x)) |> Option.getWithDefault(d)`。
- 未使用 def/import は **Redundancy Error**（E7956）でビルド不可 → 使わなくなったら消す。
- `if (...) {block} else ...` の後に文が続くなら **`;` が要る**。`forM (...) yield {...} |> f` は **forM 全体を括弧で囲む**（pipe precedence）。
- fe_rogue の full build は肥大テストで `MethodTooLargeException` になりうる → 型/effect 検証は `./bin/flix check`。
- engine 改修の検証は worktree が dep 解決不可なので **main repo に copy→check→restore**、または `make sync` 後に worktree build。

---

## 決定ログ（B）
- 2026-06-30 **B GO**（A で本質目標達成・重複②撲滅のため full B 着手・2〜3ヶ月マイルストーン駆動・ユーザー判断）。
- 2026-06-30 **m2 路線=tween を World component 化**（mirror や他要素移植でなく本筋・ユーザー選択）。
