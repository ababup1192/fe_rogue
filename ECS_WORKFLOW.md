# ECS_WORKFLOW.md — fe_rogue Scene 撲滅ワークフロー（道標・living document）

新セッションはまず **§G 進捗** で現在フェーズと次の一手を確認してから着手する。
対象: `examples/fe_rogue/`（106 ファイル / 約 32,000 行）。検証: `cd examples/fe_rogue && java -XstartOnFirstThread -jar ../../bin/flix.jar test`（baseline は §G に記録）。engine_ecs を触ったら `make sync-engine-ecs` 必須。

---

## §A ゴール定義

「Scene 撲滅」= Scene ツリーから **①状態の権威 → ②ロジック → ③ノードそのもの** の順に責務を抜き、最終的に

- 状態は **World（component store）** と **resources/（*.State effect handler）** のみが持つ
- ロジックは **ecs/rules/（純関数）+ ecs/systems/（World→World）+ frame-paced step** のみが担う
- 描画は **render-from-World**（RenderItem/Drawable 直合成）のみ。hide-then-render の二重化を廃止
- legacy 経路・トグル・golden oracle・`syncTreeFromScene/FromWorld` を撤去

旧 doc の「Plan B end-state 確定（フル System 化見送り）」は本 doc が**上書き**する。ただし段階戦略（strangler-fig / dual-write → reader flip → writer flip → mirror 撤去）は全面継承する。

---

## §B 現在地マップ（2026-07 実測）

### ECS 化済み（権威が World / systems 側）

| 機能 | 場所 | 状態 |
|---|---|---|
| 戦闘解決（味方/敵、damage/crit/exp/knockback） | `ecs/systems/CombatSystem.flix` | `useEcsCombat=true`（ギャップ残: §D-P1） |
| 杖発動（味方 4-enum / 敵 Bind） | `ecs/systems/StaffSystem.flix` | `useEcsStaff/useEcsEnemyStaff=true`（Stopgap は legacy） |
| 戦闘演出 replay | `scenes/ViewReplay.flix` | level-up モーダル・thief/status view 未配線 |
| 位置 / HP / status / 各種 flag / level / exp / 装備 view | `ecs/World.flix` store 群 | 権威化・reader flip 済み |
| Board（盤面） | `World.toBoard` / `sim/BoardSnapshot` | 常時 World 由来 |
| render-from-World（ユニット/fog/range/tile/HUD） | `scenes/RenderWorld.flix` + `Game.flix:1140-1160` | トグル無し常時（ただし hide-then-render） |
| 敵ターン / 階段退場 driver | `systems/EnemyTurnDriverScene, StairsExitScene` | frame-paced step 化済み（F8） |
| PRNG（splitmix64） | `ecs/Prng.flix` / `World.rng` | dormant（live 値は未経由） |
| 純粋ルール群 | `ecs/rules/*`（Combat/EnemyAI/LevelSystem 等） | scene 非依存化済み |

### Scene に残っているもの（撲滅対象）

| # | 残存機能 | 権威の場所 | 対応フェーズ |
|---|---|---|---|
| 1 | ECS combat/staff の cutover ギャップ（level-up モーダル・thief/status view・Stopgap 杖・敵 knockback・武器耐久・lifesteal+heal stacking） | legacy 経路 | **P1** |
| 2 | 在庫・装備・耐久（weapons/staves/consumables/rings） | scene `Data#weapons` 等（World は mirror） | **P2（最後・P6 直前）** |
| 3 | 配置物（Chest/Stairs/GroundItem）の実体 | ツリーノード | **P3** |
| 4 | メニュー/HUD/カーソルの UI 状態 | NodeTag ペイロード（`ItemMenu(Int32,Set)` 等） | **P4** |
| 5 | TurnPhase 19-case FSM | `resources/TurnPhase.State`（resource なので存続。scene 側 mirror だけ整理） | **P4** |
| 6 | 演出（DamagePopup/Explosion/Pickup/HoldGauge/lunge marker） | ツリーノード + engine Tween | **P5** |
| 7 | 残 driver（Fog/Minimap/ArrowCursor）の per-node dispatch | `process` callback | **P5** |
| 8 | 移動トランザクションの scene 副作用（MoveDraft） | `PlayerMovementScene` 等 | **P5** |
| 9 | Scene ツリー構築・`applyPhaseChange` の `Scene.empty()` 再構築・`syncTreeFromWorld`・hide-then-render | `Game.flix` / `GameLifecycle.flix` | **P6** |
| 10 | セーブ/ロード（FloorSnapshot/SuspendSave が scene 直列化） | `resources/FloorSnapshot.flix` | **P6** |
| 11 | `*Legacy` 4 関数・トグル 3 個・golden oracle・並走 DIFF assert | `CombatScene` / `StaffCastScene` / `Game.flix` | **P6**（最後まで消すな） |

---

## §C 共通レシピ（各フェーズを速くする型）

**1 store 移送の定型 5 手**（過去 A'/F 系列で実証済み。1 スライス = 1 store = 1 コミット）:
1. World に store 追加（`empty/syncFromScene/refreshMirror` の 3 builder 全てに配線 — 1 つでも漏れると mirror が腐る）
2. dual-write（scene 書き込み点から `World.applyCmd` を併発）
3. 並走 assert（`[XXX DIFF]` println。乖離は「次フレーム頭までに解消」で判定、hidden/spawn フレームは transient carve-out）
4. reader flip（読みを World 由来に。呼び出し箇所単位で分割可）
5. writer flip → scene 側 store 撤去 → assert 撤去

**検証の 2 段構え**: ① `flix test` green 維持（コミット毎）② `run` での実機確認はフェーズ末尾に 1 回で良い（スライス毎は不要、DIFF println が代替）。

**golden-trace パターン再利用**: 新 resolve* を書くときは legacy をバイト無改変のまま oracle にして final-World 等価を pin（`test/ecs/TestGoldenTrace.flix` が雛形）。

**並列作業の原則**: store/メニュー/演出は互いに独立 → ファイル単位で衝突しなければ複数エージェント同時投入可。World.flix の record field 追加だけは衝突源なので、**フェーズ冒頭に field をまとめて 1 コミットで追加**してから分担する。

---

## §D フェーズ別ワークフロー

実施順: **P1 → P3 → (P4 ∥ P5) → P2 → P6**。P4/P5 はほぼ独立（TurnEndHold だけ P4 の入力状態に触る）。
**P2（在庫の World 権威化）は最後に回す**（ユーザー判断・2026-07-02）: writer flip がセーブ capture の付け替えと不可分ゆえ、セーブ移行を行う P6 の直前でまとめて実施する方が手戻りが少ない。dual-write は既に稼働・`[PLAYERDATA DIFF]` 検証済みで機能上は困らないため、それまで温存。番号 P2 は据え置き（順序だけ末尾へ）。

---

### P1 — Cutover 完遂（legacy 経路を不要にする）

**目的**: `useEcsCombat/useEcsStaff/useEcsEnemyStaff=true` の既知ギャップをゼロにし、legacy に fallback する理由を消す。

**達成条件**:
- [ ] ViewReplay で level-up モーダルが発火する
- [ ] thief drop / status 付与の view 配線完了
- [ ] Stopgap 杖（warp）が ECS 経路で動く（World read-model に階段位置を追加）
- [ ] 敵ノックバック・武器耐久・lifesteal+heal stacking の 3 除外項目を resolve* へ移送
- [ ] `useEcsCombat` の doc コメント（`CombatScene.flix:510-513`、実値と逆の記述）を実態に修正
- [ ] 各スライスで golden-trace green + 実機 run 1 回

**対象**: `ecs/systems/CombatSystem.flix`, `StaffSystem.flix`, `scenes/ViewReplay.flix`, `ecs/World.flix`(read-model 追加), `scenes/CombatScene.flix`, `StaffCastScene.flix`, `test/ecs/TestGoldenTrace.flix` ほか golden 3 本

**並列**: 6 項目は独立スライス。ViewReplay 系 3 つ / resolve* 系 3 つで 2 レーン推奨。

**注意**: 新 SimEvent variant は増やさない方針（CLOSED 集合、`World.flix:383-409`）を原則維持。どうしても必要なら追加前にユーザー相談。`_resolvecombat_sim_plan.md` の「二相 fold」（level-up hp base は post-lifesteal）を崩さない。

---

### P2 — 在庫・装備・耐久の World 権威化 （**実施は最後・P6 直前**）

> **順序メモ**: セクション番号は P2 のままだが、実施は P3→P4/P5 の後・P6 直前に回す（上記「実施順」参照）。writer flip がセーブ capture 付け替えと不可分＝P6 のセーブ移行とまとめると手戻りが少ない。再開時は rings/ringEquipped（player-only 最小）から read→writer→save→render→field削除 の縦スライスで。

**目的**: weapons/staves/consumables/rings の権威を scene `Data#...` から World store へ flip。`Weapon.consumeEquippedWeapon` 等の scene 副作用を Cmd 化。**インフラ（7 Cmd・emit funnel・accessor・refreshMirror preserve+prune）は全て既存**＝新規実装でなく「scene 直書きの撤去＋読み/描画/セーブの World 付け替え」が実務。

**達成条件**:
- [~] 在庫の read/write が全て World 経由（メニューの読みも含む）— P2-r1 で read 側をほぼ完了: ItemMenu の全在庫読み（weapons/staves/consumables/rings・カテゴリ/行/サブメニュー/なげる/すてる）・UnitCard・mend・transformable を PartyQuery（dataFromWorld オーバーレイ）へ flip。**意図的例外 2 種**: ①位置/カーソル距離計算（ItemMenu cursorTargetDistance）②**read-during-mutation**（TradeMenu receiverCanAccept＝まとめ渡し fold 内の逐次重量ゲート。threaded scene が正・snapshot 供給に寄せると 2 個目以降が陳腐化＝test で顕在化し revert 済み）。write は Cmd dual-write 済（撤去は field 削除と同時）
- [x] 耐久消費・アイテム増減が `World.applyCmd` 経由の Cmd になっている（D3/D4 で既達・emit funnel 完備）
- [ ] `[PLAYERDATA DIFF]` / `[ENEMYDATA DIFF]` assert が沈黙 → 撤去（P6 の field 削除と同時）
- [ ] scene `Data` から在庫 field を削除（**P6 送り**: CombatScene legacy 戦闘 twin が scene Data の rings/weapons を読む＝golden oracle 無改変の制約で legacy 撤去〔P6 手順5〕より先に消せない）

**対象**: `ecs/World.flix`, `scenes/PlayerScene.flix`(W=119 の主因), `ItemMenuScene.flix`, `TradeMenuScene.flix`, `WeaponSelectScene.flix`, `StaffCastScene.flix`, `game/` の Weapon 系 rules

**並列**: store 単位（weapons / staves / consumables / rings）で 4 レーン。World field 追加は冒頭 1 コミット集約（§C）。

**注意**: セーブ互換を壊さない — save は scene 由来のまま（P6 まで）、World は runtime 権威。トレード（TradeMenu）は 2 エンティティ同時更新なので Cmd を 1 つの atomic variant にする（2 Cmd に割ると DIFF assert が transient を誤検知）。

---

### P3 — 配置物の Entity 化（P1 の次に実施）

**目的**: Chest / Stairs / GroundItem をツリーノードから World entity（pos + kind component）にする。

**達成条件**:
- [ ] `chests/stairs/groundItems` store が World にあり、spawn/開封/取得が Cmd
- [ ] 描画が RenderWorld 経由（ChestScene 等の addChild 撤去）
- [ ] 開封済み・取得済み状態がツリーの有無でなく component で表現される

**対象**: `scenes/ChestScene.flix`(251), `StairsScene.flix`(119), `ItemScene.flix`(474), `ecs/World.flix`, `scenes/RenderWorld.flix`, spawn 経路（`GameLifecycle.flix` / `DungeonComposer` 出口）

**並列**: 3 種で 3 レーン完全独立。

**進捗**: ✅ 全完了（Level 1）。P3-a Stairs（stairsPos scalar）／P3-b Chest（chests store・cell key→Data）／P3-c GroundItem（groundItems store・elapsed は view 専用で store 対象外）。存在=World store の在/不在、spawn/開封/取得=Cmd、gameplay reader は World へ flip。scene ノード（＋item の 4 outline/点滅）は描画 view 残置。**セーブ capture の World 化は P2-r2 で完了**（Item/Chest=store 直読み・stairs=stairsPosOf）。**未達（意図的に P6 へ委譲）**: addChild 撤去・catalog 直描画・minimap/occupancy の World 化（World 等価の scene view 読みで代替中）。パターンは §G「次の一手」参照。

**注意**: GroundItem は在庫（拾う=ground から消して inventory へ）と受け渡すが、P2 は保留中で在庫は今も scene 直書き+dual-write のまま。P3 は GroundItem の**存在・位置**の Entity 化に限り、拾得先の inventory 書込は既存経路（scene+Cmd）をそのまま呼ぶ（在庫権威の flip は P2 の担当）。unified-id 規約（enemy=+1,000,000）に倣い、配置物にも id 帯域を割る（例: +2,000,000〜）。

---

### P4 — UI 状態の Resource/Component 化（NodeTag ペイロード撲滅）

**目的**: メニュー・カーソル等の UI 状態を NodeTag ペイロード（ツリー埋め込み）から `resources/` の *.State effect handler（または World の ui store）へ移す。NodeTag を「識別のみの純タグ」にする。

**達成条件**:
- [ ] 各メニューの開閉・カーソル位置・選択状態が resource で読める
- [ ] `NodeTag` の全 variant がペイロードレス（`Player(Data)` は P2/P5 で縮小済み前提）
- [ ] TurnPhase.State はそのまま存続（resource は ECS の一級市民）。World の 3-case mirror との dual-write 関係を doc 化のみ
- [ ] メニュー描画が「resource → RenderItem」の純関数になっている

**対象（軽い順に並列 8+ レーン可、1 メニュー = 1 スライス）**:
`LogScene`(140), `ArrowCursorScene`(127), `GameOverMenuScene`(117), `SuspendConfirmScene`(122), `TopBarScene`(289), `WeaponSelectScene`(373), `LevelUpPanelScene`(372), `ActionMenuScene`(733), `ItemMenuScene`(931), `TradeMenuScene`(811), `CursorScene`(787・最重、scene-tree primitive 51), `MinimapScene`(661), `CharacterSelectScene`(656), `BattlePanelScene`(641), `UnitCardScene`/`EnemyCardScene`, `FogScene`(318)

**並列/高速化**: 完全にファイル独立なので最も fan-out が効くフェーズ。先に 1 本（LogScene 推奨・最軽量）を通して**変換パターンをコミットで確立**し、それを他レーンの参照実装にする。

**進捗**: ✅ (a) 全消化 — P4-a Log・P4-b BattlePanel・P4-c TurnEndHold・P4-d LevelUpPanel（入力連鎖）・P4-e ItemPickupPopup（3 経路連鎖）・P4-f TopBar（World 2 bool の dual-write は最終 Data から emit・isBusy/hasObservedEnemy は Data 純関数化・add が State.put でフロア毎リセット）・P4-g Title（入力駆動・add が State.put で再突入リセット＝resumable 再判定込み）。DamagePopup/Explosion/HPBar は P5-b/c で World store 化・payload 撤去済み。**残る NodeTag payload** は entity（Player/Enemy=P6）・配置物 view（Stairs/Chest/GroundItem=P6）・メニュー構造データ（ItemMenu の cat/marks・TradePanel・CharacterSelect・MinimapDriver・ArrowCursor 等＝(b) または P6 と束ね）。

**P4 の 2 種の作業（調査で判明）**:
- **(a) NodeTag payload → resource**（易・LogScene/BattlePanel で確立済）: `NodeTag.Xxx(Data)` に埋めた HUD/演出の状態を effect resource へ。対象は payload を持つ variant のみ。**注意**: `Stairs`/`Chest`/`GroundItem` の payload は P3 で描画 view として意図的に残置＝**P6 で撤去**（P4 対象外）。残る (a) 候補: `TopBar`/`LevelUpPanel`/`Title`/`ItemPickupPopup`/`HoldGauge`/`DamagePopup`/`Explosion`/`HPBar` 等（演出系は P5 と重なる）。
- **(b) engine プリミティブ（ItemList/Cursor）→ resource**（難・未着手）: メニューの**カーソル位置/選択/項目**は NodeTag でなく engine の `ItemList`/`Cursor` ノードが持つ（例: `GameOverMenu` は既にペイロードレスで状態は ItemList）。「メニュー描画が resource→RenderItem の純関数」達成条件はここ。CursorScene（最重）が代表。ActionMenu/ItemMenu/Trade 等はこの (b) が本体。

**P4-a で確立したパターン（NodeTag ペイロード → resource effect）**: ① 対象 Scene mod 内に `pub eff State { def get(): Data; def put(d: Data): Unit }` ＋ `pub def withState(rc)`（Ref-backed・Pacing.State と同型）を定義（状態が Scene 固有なら co-locate、汎用なら `resources/` へ）。② `NodeTag.Xxx(Data)` → `NodeTag.Xxx`（ペイオードレス）。enum 定義（Game.flix）＋構築/ match 全サイトを修正。③ `process`（or reader）が `Scene.getState` でなく `State.get()/put()` を使う。scene ノードは Label/CanvasLayer 等の**描画 view** として残す。④ `process` に新 effect を足したら **FrameAef.ProcessT** ＋ **gameLoop の効果行**（Game.flix）に `Xxx.State` を追記し、**Game.start に `with Xxx.withState(rc)` を 1 行注入**（既存 Pacing/GatherResume の並びに追加）。⑤ dispatch の `case NodeTag.Xxx(_) =>` を `case NodeTag.Xxx =>` に。純粋ロジック（enqueue/tick 等）は不変ゆえ既存テストがそのまま通る（挙動不変リファクタ）。

**注意**: 非 driver Scene の読みは effect 経由の慣習を維持（PartyQuery/RosterQuery パターン、モジュール名直タイプ禁止）。`[xxx]` 表示は BBCode 扱いされる罠 — メニュー描画を組み替えるとき Label2D/別表現を維持。CursorScene は入力ロジック濃度が高いので「状態移送」と「入力→intent 整理」を別スライスに割る。

**P4-d/e で判明した連鎖コスト（見積もりの参考）**: 状態を書く関数が「入力確定」経路にあると、`confirm`→`dispatchMenuKey`→`onPlayingKeyPressed`→`onKeyPressed`→**InputHandler の `type Aef`** まで効果行の追記が伝播する（P4-d）。さらに physicsProcess 経路（着地自動取得等）にもあると **FrameAef.T** と `physicsStep`/`gatherStep`/`stepFor`、MenuHandler の `type Aef` にも波及し、直呼びテストには `withNoopPickupPopup` 型の no-op discharge fixture（TestUnitFixtures）を足す（P4-e）。process 経路だけで閉じる Scene（Log/BattlePanel/TurnEndHold）はこの伝播が無く最安。

---

### P5 — 演出・残 driver の System 化（P4 と並列可）

**目的**: 演出ノード（DamagePopup/Explosion/ItemPickupPopup/HoldGauge/lunge marker）を EcsTween + RenderItem に置換し、per-node `process` dispatch と engine `Tween.tickAll` 依存を空にする。

**達成条件**:
- [x] 演出の寿命・位置が `World.tweens`（EcsTween）または専用 store で駆動される（P5-b: popupFx/explosionFx store・tick=stepWorld・view 派生=syncView。DamagePopup/Explosion 対象）
- [x] `dispatchTickables` / `dispatchDrivers` の対象が 0 になり、gameLoop の明示 step 呼びに一本化（P5-a/c）
- [x] Fog / Minimap / ArrowCursor が F8 パターン（frame-paced step）に移行（P5-a）
- [x] MoveDraft の scene 副作用が Cmd/System 経由になる（P5-d: 精査の結果 D3/D4/S5b/S6/P3-c で既達。revertDraftAction 全 6 case の sim 変更は Cmd 経由〔snapTo=SetRenderPos+Move・setActive=SetWaited・respawn=SpawnItem・在庫= emit*FromScene〕。残る scene 書きは anim/modulate の純 view と P2 スコープの dual-write twin のみ）
- [x] 武器/HP バー marker が RenderWorld 直描き（P5-e: per-unit の WeaponIcon/HPBar subtree root を renderSubtrees〔drawables〕・renderSubtreePolygons〔グリフ〕へ合流し hideSubtrees で renderArgs から除外。位置駆動は従来どおり marker=移動 tween+lunge が単一権威＝描画側のみ World 経路化）

**対象**: `scenes/DamagePopupScene.flix`(145), `ExplosionScene.flix`(115), `ItemPickupPopupScene.flix`(312), `TurnEndHoldScene.flix`(246), `UnitHPBarScene.flix`(208), `FogScene`, `MinimapScene`, `ArrowCursorScene`, `systems/PlayerMovementScene.flix`, `game/Game.flix`(dispatch 表), `engine_ecs/src/EcsTween.flix`

**並列**: 演出 4 種 + driver 3 種で独立レーン。EnemyTurnDriverScene/StairsExitScene の step が参照実装。

**注意**: engine_ecs へ機能追加したくなったら **Godot 対応物があるものだけ・事前相談**（feedback 済み制約）。ゲーム固有便利関数は fe_rogue 側に置く。render-from-World の O(root×N) 罠 — 描画対象 root を増やすときは `subtreeDrawablesForRoots`（paths 1 回共有）に載せる。

---

### P6 — Scene ツリー撤去 & 大掃除（最終・直列）

**目的**: 「ノードを積んで隠して World から描き直す」二重構造を解消し、legacy 資産を撤去する。

**達成条件（順番厳守）**:
- [~] 1. hide-then-render 廃止: そもそもノードを積まない（判定: `addChild` 使用が Game/GameLifecycle 以外ゼロ）
  - 調査済み（2 agent 棚卸し）: **engine 追加は不要**（テキスト=Label2D.make+toDrawables は pure／sprite=SpriteResource→Sprite2D 値→Renderable.toDrawables／矩形=solidBox／ポリゴン=toRenderCmd(s) が全て tree 非依存）。残置必須ノード= Camera2D（viewTransform 源）・AudioStreamPlayer（BGM）・ユニット Marker2D（lunge target/位置権威/Data store）・敵 Sprite（deathBlink alpha target）・Cursor（snag isPlaying 入力ゲート）・ItemList（選択状態=P4(b)）・driver タグ 3 種。Title/CharacterSelect はダンジョン外＝スコープ外。
  - ✅ P6-1a Range タイル Panel 撤去（renderRangeOverlays が唯一経路・hideRangeTiles 撤去）
  - ✅ P6-1b Fog 暗幕 ColorRect プール撤去（renderFog が唯一経路・hideHaze 撤去。applyFogWith は点灯 visibility 制御のみ残る）
  - ✅ P6-1c Stairs 脱ノード（**ノードを一切積まない第一号**。見た目= scene.json→定数化〔texture/spriteScale/spriteZIndex〕、renderStairs が World.stairsPos+fog lit ゲートで直描き。Minimap/Chest 占有の階段読みを World へ flip。NodeTag.Stairs/isAt/getPos は legacy 杖 twin+golden fixture の手組みノード用 seam として残置）
  - ✅ P6-1d Chest 脱ノード（renderChests=chestKey→ChestCatalog sprite 直描き・`Cmd.ClearChests` を build choke 2 経路の**頭**で emit〔addFromSnaps より前が必須〕・refreshMirror/syncFromScene は preserve 化・takeAt は store 存在ゲート＋Cmd のみ）
  - ✅ P6-1e GroundItem 脱ノード（renderItems=spriteOf 直描き・本体 z5＋縁取り 4 枚 z4・**点滅位相は Data#elapsed を stepWorld が tick**〔per-item stagger 維持・fx と同じ lane〕・`Cmd.ClearItems`・pickup/auto-pickup/階段占有/minimap の読みを World へ flip。**GroundItem の手組みノード→syncFromScene seed はテスト seam として残置**〔stairs と同型〕・fixture/assert は withTracedWorld（ONE Ref の Command+Query）へ移行）
  - ✅ P6-1f fx（ダメージ数字/爆発）ノード全廃。PopupFx/ExplosionFx store に pos/text/color/scale を拡張し、emit は `Cmd.SpawnPopupFx/SpawnExplosionFx` **単独**（WorldQuery/Game 依存が消え効果行が大幅縮小＝呼び出し連鎖の**逆向き**cleanup を CombatScene/StaffCast/ViewReplay/Game で 6 波）。描画は renderPopups（Label2D 値の直描き・上方向 float は比率導出）/renderExplosions（コマ番号を比率導出）。**golden trace は view の Spawn*Fx Cmd を記録から除外**（apply はする＝sim Cmd 列の比較通貨を維持）。in-world subtree root は Cursor/ArrowCursor のみに。
  - ✅ P6-1g WeaponIcon/HPBar ノード全廃。HP/最大 HP/装備系統/暗転はすべて World store（hp/baseStats/weaponView/waited/enemyActed）から導出し `UnitHPBarScene.renderBars`（ColorRect 値直描き）と `WeaponIconScene.renderPlates/renderGlyphs`（囲い=drawables・グリフ=Polygon2D/Arc2D 値→toRenderCmd(s)）が毎フレーム描画。**push API（update/updateMaxHp/setModulate/attach/refresh）と呼び出し 55 箇所を全撤去**（SetHp 等の Cmd が唯一の書込に）。攻撃予報の「減る分」点滅だけは BattlePanel が毎フレーム計算する view 状態＝新設 `UnitHPBarScene.ForecastState` resource 経由（put(None)=全消し）。祖先 modulate 伝播は mulColor 乗算で代替。**gameLoop が JVM 64KB メソッド上限を超過→描画セクションを `renderFrame` に分離**。
  - ☐ P6-1h ユニット sprite（アニメ frame の World component 化＋advanceFrame System＋deathBlink 再レーン）
- [ ] 2. `syncTreeFromWorld` / `refreshMirror` / `syncFromScene` 撤去（World が唯一の真実源になる）
- [ ] 3. `applyPhaseChange` の `Scene.empty()` 再構築を「GamePhase 別の World/resource 初期化」に置換
- [ ] 4. セーブを EcsCodec 経由の World serialize に置換（`FloorSnapshot`/`SuspendSave` 改修。旧セーブの読み込み互換 or 明示的破棄をユーザーに確認）
- [ ] 5. **最後に** `*Legacy` 4 関数・トグル 3 個・golden oracle・DIFF assert を撤去（oracle の代替として headless 決定論テストが十分あることを確認してから）
- [ ] 6. `_plan_*.md` 群を「完了アーカイブ」節に整理、本 doc §G を final 化

**対象**: `game/Game.flix`, `game/GameLifecycle.flix`, `resources/FloorSnapshot.flix`, `scenes/CombatScene.flix`, `StaffCastScene.flix`, `engine_ecs/src/EcsCodec.flix`(未結線 → wire)

**並列**: 不可。ここは 1 レーン直列（gameLoop の中核を触るため）。

**注意**:
- **`*Legacy` と test-only seam は最後まで消さない**（golden oracle。dead 判定は定義コメントとトグル生死を確認してから）
- `Scene.empty()` 再構築を触ると **prevKeyState 引き継ぎ**が壊れる既知バグ帯 — gameLoop の setPrevKeyState 維持を必ず確認
- セーブ形式変更は**破壊的**なのでユーザー承認必須
- 撤去はスライスごとに `flix test` + 実機 run。ここだけはスライス毎の run を省略しない

---

## §E 設計で気を付けるポイント（横断）

1. **strangler-fig を崩さない**: 一気の書き換え禁止。dual-write → assert → reader flip → writer flip の順（§C）。過去にフル書き換え路線（Track B / フル F4）は実現可能性 35 で却下済み。
2. **World の 3 builder 配線**: store 追加時は `empty/syncFromScene/refreshMirror` 全部（P6 の 2 で syncFromScene/refreshMirror は消えるが、それまでは 3 点セット）。
3. **RNG**: live 値は BODY-IDENTITY（`Float64.truncateToInt32(Float64.floor(...*100.0))`）を崩さない。消費順が変わる変更は golden を壊す。
4. **Flix 固有**: `match` は単一 match に束ねて E6217/checked_ecast を回避。`from` 予約語・record 内 `///` 禁止・注釈なし def は純粋扱い。コンパイルエラーは `/compile-fix`。
5. **テスト**: パターンマッチでなく Option コンビネータ + assertEq、期待値は具体値 pin。新 System には golden 等価テストを先に書く。`/quality-assurance` 参照。
6. **engine / engine_ecs 拡張**: Godot 対応物のみ・事前相談・scene.json 宣言可能に。編集後 `make sync-engine`(-ecs)。
7. **パフォーマンス**: render-from-World は O(root×N) に注意（`subtreeDrawablesForRoots` 共有）。フレーム毎の Map 再構築を増やさない（mirror は差分 or フレーム末 1 回）。
8. **gameLoop にロジックを書かない**: 追加するのは step 呼びと handler 結線だけ。ロジックは systems/ へ。

---

## §F 関連 doc の位置づけ

| doc | 状態 |
|---|---|
| `examples/fe_rogue/_split_plan.md` | Phase A/B/C ラベルの発生源。A/B は概ね消化、C は本 doc P1 が引き継ぐ |
| `examples/fe_rogue/_resolvecombat_sim_plan.md` | P1a〜P3 実行済み（cutover 済み）。除外項目が本 doc P1 の TODO |
| `examples/fe_rogue/_phase_c_prereq_plan.md` | 4 スライス（rng/board-lock/simevent/golden）完了済み |
| `examples/fe_rogue/_plan_full_ecs.md` / `_plan_oop_to_ecs.md` | Track A/A'・F0-F8 完了。歴史資料 |
| `examples/fe_rogue/_ecs_taxonomy.md` | 役割分類（rules/systems/View 等）。新規ファイルの置き場判断に現役 |
| `examples/fe_rogue/_plan_position_ecs.md` | pos 統合として完了済み。歴史資料 |

---

## §G 進捗（living — 更新はここだけで良い）

**現在フェーズ: P5 完了（run 確認待ち: P5-d/e 分）— 達成条件 5/5。a=view driver step 化・b=fx store・c=tickable step 化（dispatch 対象 0）・d=MoveDraft revert は既達と検証・e=marker 装飾の RenderWorld 直描き。次は P2（在庫の World 単独化・セーブ改修と不可分）→ P6（Scene ツリー撤去・直列）。P4 残（TopBar/Title の△・(b) engine ItemList/Cursor〔要事前相談〕）は P6 前の任意タイミングで**

> **P3 完了メモ（2026-07-02・全 Level 1）**: 配置物 3 種の存在/位置/中身を World store に権威化し、gameplay reader（メニュー gate・階段 driver 等）を World へ flip。scene ノードは描画/フォグ/点滅アニメ view として残置（renderSubtrees 経路不変・dual-write で despawn 時にノードも消える）。RenderWorld 調査で「ユニットも scene sprite ノードを保持＝World は存在 gate のみ」「node-less 描画（Render.drawAtlas+regionRect）は Stairs が catalog 非対応で詰む」と判明したため、addChild 撤去＋catalog 直描画は P6（ユニットの脱ノードと同時）へ委譲するのが妥当。

> **P2 保留メモ（2026-07-02）**: 在庫の Cmd/emit/accessor/dual-write は全て既存で稼働・`[PLAYERDATA DIFF]` で World==scene 検証済み。残りの「scene 権威を落として World 単独化」は read-before-mutate＋描画（UnitCard 等）＋**セーブ capture（`captureSnaps` が scene Data 直読み）**の付け替えを伴う重い縦スライスで、セーブ移行が不可分。機能上は今困っていない（P6 撤去まで dual-write 温存で動く）ため、独立でクリーンな P3 を先行。P2 再開時は rings/ringEquipped（player-only 最小）から縦スライスで。

- テスト baseline: 1063（P1 着手前）→ 1070（P1）→ 1071（P3-a）→ 1072（P3-b）→ 1073（P3-c＝P3 完了）→ 1073（P4-a〜e・挙動不変）→ 1076（P5-b fx store +3）→ **1077 green**（P2-r1 equippedRing 導出 pin +1）
- 完了済み前史: Track A/A'（faction 統合・unified-id）、F0-F8（sim state 権威化・driver step 化）、pos 統合、Phase C 前提 4 スライス、combat/staff cutover（トグル 3 つ true）、render-from-World 常時化
- **P1 実像の訂正**: 当初 6 TODO のうち level-up モーダルと武器耐久は既に配線済み（doc 陳腐化のみ）だった。実装が要ったのは Stopgap 杖・thief drop・敵ノックバックの 3 点。
- **次の一手**: P2 read 側（P2-r1/r2）・P4 (a) 全消化・P5 完了。残る大物は 2 つ: ①**P4 (b) engine ItemList/Cursor の resource 化**（メニュー選択状態を engine プリミティブから引き剥がす。**engine 変更を伴うため事前相談必須**）②**P6（Scene ツリー撤去・直列）** — 手順 1 の hide-then-render 廃止から。手順 4 のセーブ形式変更（EcsCodec 直列化）は**破壊的＝ユーザー承認必須**だが、capture は P2-r2 で全面 World 読みになっており射影先の差し替えだけで済む。P2 の残（write 撤去・field 削除・DIFF 撤去）は P6 手順 5（legacy 撤去）と同時に。どちらへ進むかはユーザーと相談。
  - **P3 で確立したパターン（配置物 = World 権威・scene ノードは view）※P6 の脱ノードや他 store 化で再利用**: ① World に store field ＋ `Cmd.SpawnXxx/RemoveXxx`（scalar なら `SetXxx`）＋ applyCmd ＋ cmdKey を足す。② 配置/除去関数が `Cmd` を emit（scene ノードも従来通り set/remove＝描画/フォグ/frame-1 seed の view として残す＝dual-write）。③ refreshMirror は **command 由来を preserve**（変数個は scene 在キーで prune＝unit の validUids 相当）／syncFromScene は frame-1 seed として scene を読む＝hp/pos と同型。emit が Playing 突入・floor 遷移とも `World.Command` 文脈で refreshMirror より先に走るので seed は正しい。④ gameplay reader（driver/メニュー gate/overload 判定）を `World.xxxOf` へ flip。⑤ 描画/フォグ/セーブ capture/build-time 占有判定・deep な execution 経路は scene 読みのまま可（dual-write で World と等価。真の脱ノードは P6）。⑥ record は Eq/Order 未定義＝比較は `Option.exists(c -> c#x==.. and c#y==..)`、Map key は cell を `cellKey=x*1000+y` で Int32 符号化。⑦ reader へ WorldQuery を足すと呼び出し連鎖に伝播（ActionMenu では buildItems/refreshItems/onActionConfirmed と MenuHandler の `type Aef`・Game.flix dispatch まで）。全 reader flip で menu 関数の `scene` 引数が未使用化することがある＝`_scene`。テストは `withMenuReadMocks*` に `withWorldQuery(syncFromScene(scene,empty()))` を仕込み済みで一括で通る。scene ノードを直接組む純粋テストで emit 関数を呼ぶ場合は `run { … } with handler World.Command { def emit(_,k)=k() }` で捨てるか、Ref[World] 版で applyCmd して store 権威を pin。
- 履歴:
  - 2026-07-02: 本 doc 作成（Scene vs ECS 全棚卸し → P1-P6 ワークフロー策定）
  - 2026-07-02: P6-1g 実機バグ修正（fog 中の敵の HP バー/武器アイコンが見える）＋監査。原因 2 つ: ①**fog ゲート欠落** — 旧実装は bar/icon が敵 marker の子で、applyFog の marker 不可視に連動して消えていた。直描きは可視合成を持たない＝`EnemyScene.isVisible`（applyFog の真実源）で filter。②**暗転ソースの選択ミス** — waited/acted store 導出だと敵ターン中の `showAllActive`（待機者も通常色に戻す view 演出）を再現できない。**本体 sprite ノードの modulate を読んで流用**（`spriteModulate`）が完全パリティ。**教訓: 脱ノード時は「祖先合成で暗黙に得ていた性質（可視/modulate）」を明示的に再現する必要がある。可視 = そのドメインの真実源 API（isVisible 等）、modulate = 本体ノード流用（P6-1h でユニット sprite が消えたら World 導出へ置換）**。他 lane（stairs/chest/item/fx）は fog ゲート・非ゲートとも旧挙動と一致を確認。全 1077 green。
  - 2026-07-02: P6-1f fx ノード全廃。学び 2 点: ①emit の効果 slim 化（Game/WorldQuery 除去）は呼び出し連鎖の**未使用効果エラー（E6217）を逆向きに 6 波**引き起こす＝effect 追加より撤去のほうが cascade が読みにくい（unused は「宣言したが使わない」で発火点が呼び出し元）。②fx の Spawn は sim を動かさない view Cmd ＝ golden trace の記録から除外して比較通貨を守る（withTracedWorld/withConstTracedWorld の record 段で名前フィルタ・apply は継続）。全 1077 green。
  - 2026-07-02: P6-1d/e Chest・GroundItem 脱ノード＝**配置物 3 種が完全ノードレス**。設計の要: ①scene 再構築による store の自動 prune が消えるため、**フロア再構築の掃除は build choke 頭の明示 `Cmd.ClearChests/ClearItems`** が担う（rebuildFloorFromSnapshot では addFromSnaps より前が必須＝後置すると spawn を消す事故。1 回踏んで前置に修正）。②refreshMirror/syncFromScene の該当 store は preserve 化（GroundItem のみ手組みノード seed seam を残置）。③点滅（縁取り pulse）は Data#elapsed を stepWorld が tick（per-item stagger 維持）し renderItems が alpha 化＝view state の World 移送例。④takeAt/pickup 系は「store 存在ゲート＋Cmd emit」に単純化（scene ノード削除が消えた）。⑤直描き共有ヘルパー `standaloneSprite`（tree に積まない Sprite2D 値→Drawable）と `fogHolesOpt`（fog 穴の frame 1 回計算・全配置物 lit ゲート共有）を新設。テストは withTracedWorld（ONE Ref[World] で Command+Query+Rng を wire）へ移行し、runOnActionConfirm は最終 World も返す 3 要素タプルに。全 1077 green。
  - 2026-07-02: **P6 手順 1 着手**（調査 2 本＋a/b/c の 3 スライス）。1a: Range の Tile_<idx> Panel を生成ごと撤去（RangeOverlay.renderTiles/hideTiles・各 submod hideTiles・RenderWorld.hideRangeTiles 削除。cells は NodeTag 保持のまま＝tileDrawables が唯一の描画）。1b: Fog の ColorRect×24 プールを生成ごと撤去（applyHazePool/setPoolRect/hidePoolRect/hideHaze 削除。applyFogWith は敵/アイテム/宝箱の点灯 visibility 制御のみに）。1c: **Stairs 脱ノード第一号** — add（scene.json ロード）/placeAt の node 書き/applyFog/mapStairs を撤去し、見た目を定数化（texture "stairs"/scale{0.65,0.52}/z1）、`RenderWorld.renderStairs` が World.stairsPos＋fog lit ゲート（holesForDraft）で直描き。読み flip: Minimap stairsDiscovered/collectMarkers・ChestScene occupiedCells → `World.stairsPosOf`（WorldQuery）。**syncFromScene の stairs seed は残置**（golden/menu テストが手組みノード→syncFromScene で World を seed する seam。production は node 不在で None→Cmd 由来を preserve）。テストは placeAt の node 検証を「手組み placed ノードの isAt/getPos seam pin」に書換。全 1077 green。
  - 2026-07-02: P4-f TopBar・P4-g Title を resource 化＝**P4 (a) レーン全消化**。TopBar: `State`（get/put Data）＋add が `resetState`（State.put）でフロア毎に初期化、step は presence gate（getState gate の代替）、EnemyTurnDriver 向け World 2 bool は**最終 Data（State.get read-after-write）から emit**（旧: scene 再読み）、isBusy/hasObservedEnemy → isBusyOf/hasObservedEnemyOf（Data 純関数・テストも Data 直で観測）。Title: add が State.put で再突入時リセット（resumable の SaveManager 再判定込み）＝「withState の seed は 1 回きり」問題への解。効果配線: gameLoop 行＋applyPhaseChange＋InputHandler Aef/onKeyPressed（Title）＋GameLifecycle build チェーン 8 行（TopBar）。全 1077 green。
  - 2026-07-02: P2-r2 セーブ capture の World 化（enemy＋配置物）＝**capture 全面 World 由来が完成**。EnemyScene.captureSnaps/snapshotSpawns を `dataFromWorldEnemy` オーバーレイに（player 側 P2-r1 と同型）、ItemScene/ChestScene.captureSnaps を **store 直読み**（groundItemsOf/chestsOf の Map.valuesOf・scene ノード列挙を撤去＝並びは cellKey 昇順に変わるが決定論・形式・意味論不変）、captureFloorSnapshot の stairs を `stairsPosOf` に。呼び出し元は P2-r1 の WorldQuery 配線で被覆済み＝cascade ゼロ。全 1077 green。P6 のセーブ改修（EcsCodec 直列化）は capture がすでに World 読みなので「射影先の差し替え」だけになる。
  - 2026-07-02: P2-r1 在庫 read の World 単独化（rings 起点で全在庫に波及）。①**セーブ capture の World 化（player 側）**: captureSnaps/snapshotCarry/snapshotSpawns の射影元を `World.dataFromWorld` オーバーレイ（scene fallback）に＝W-store 全 field（hp/在庫/level/exp/pos/statuses）が World 読みへ。セーブ形式不変。②メニュー/HUD の在庫読み flip: ItemMenu（カテゴリ数/行/passive判定/装備バッジ/なげる/すてる/使う）・UnitCard・applyRingRegen（mend）・transformableItems を PartyQuery 経由へ（stavesOf/consumablesOf/ringsOf 薄ラッパ追加）。③World 内部: refreshMirror の equippedRing（player 側）を scene Data 読みから **w#rings/w#ringEquipped 導出**へ（P6 の field 削除前提を先取り・pin テスト追加）。**学び（重要）**: TradeMenu の receiverCanAccept（まとめ渡し fold 内の逐次重量ゲート）は read-during-mutation ゆえ flip 不可＝threaded scene が正（snapshot/overlay に寄せると 2 個目以降が陳腐化。testBulkTransferStopsWhenReceiverFull が検出→revert）。読み flip の判定基準は「単発読み=flip 可／変異 fold 内の逐次読み=scene 残置（write 撤去と同時に World 化）」。全 1077 green（+1=equippedRing 導出 pin）。
  - 2026-07-02: P5-e marker 装飾（武器アイコン/HP バー）を RenderWorld 直描き化＝**P5 完了（5/5）**。`unitMarkerRoots(scene)`（per-unit の WeaponIcon/HPBar root・動的）を renderSubtrees の drawables batch へ、`unitGlyphRoots` を renderSubtreePolygons へ合流し、hideSubtrees で renderArgs から除外。marker の**子**を root にするので移動 tween/lunge/待機暗転（親 marker の位置・modulate）は drawContext の祖先合成でそのまま乗る＝挙動等価は batch API の構成的 parity（subtreeDrawablesForRoots=renderArgs と同一合成）で保証。素手ユニットの WeaponIcon 不在は全 API no-op で安全。全 1076 green。
  - 2026-07-02: P5-d は**精査の結果すでに達成済み**と確認（コード変更なし）。revertDraftAction 全 6 case の sim 状態変更は D3/D4/S5b/S6/P3-c で Cmd 経由化済み: MovedFrom=snapTo（SetRenderPos+Move）/PickedUp=respawn（SpawnItem）+removeLastInventoryItem（drop*→emit*FromScene）/Equipped=emitWeaponsFromScene/Dropped・Traded=insert/removeLastInventoryItem（emit*FromScene 完備・Ring 含む）/GatherWaited=setActive（SetWaited）。残る scene 書きは anim/modulate の純 view と P2 スコープの dual-write twin のみ。
  - 2026-07-02: P5-c 表示系 tickable 8 種を明示 step 化＝**dispatchTickables 対象 0**。GroundItem（全 item fold）/TopBar/ItemPickupPopup（frameStep）/CharacterSelect/Log/TurnEndHold（frameStep）/Camera を step 化、HPBar は no-op process ごと削除。**順序制約を pipeline で再現**: TopBar は EnemyTurnDriver.step より前（World 2 bool の dual-write 元）、TurnEndHold は LogScene.step より後（ログ帯上書き・旧 root 追加順の再現）。**明示 step は毎フレーム走る**ため「ノードが居るときだけ」を gate で再現（TurnEndHold/Camera=getEngineNode gate、TopBar/CharacterSelect=getState gate、Log/ItemPickupPopup/GroundItem=mapAt no-op で自然安全）。Camera は「返り node を engine が書き戻す」旧契約が消えるので mapEngineNode(cameraPath) で自書き。全 1076 green。
  - 2026-07-02: P5-b DamagePopup/Explosion の寿命を World fx store 化＝演出の World 権威第一号。`popupFx/explosionFx = Map[seq, {remaining,total(,startY)}]`＋`popupFxNextSeq/explosionFxNextSeq`、spawn=`Cmd.SpawnPopupFx/SpawnExplosionFx`（applyCmd が採番+1・emit は WorldQuery で次 seq 先読み=read-after-write 一致）、**寿命 tick と期限切れ drop は stepWorld**（EcsTween と同じ「stepWorld が World を直接進める」lane・per-frame Cmd なし）、view 派生は gameLoop（syncMarkers 後）の `syncView(world2)`（Y 補間/コマ送り＋store 不在子の removeAt）。NodeTag 4 variant（DamagePopupsRoot/DamagePopup/ExplosionsRoot/Explosion）ペイロードレス化。3-builder は preserve（transient ゆえ prune 不要・floor 遷移残骸は自然 expire）。emit 効果伝播は CombatScene applyMiss/applyHit・StaffCastScene throw 系のみ。test +3（採番/tick&drop/preserve）＝全 1076 green。
  - 2026-07-02: P5-a Fog/Minimap/ArrowCursor を F8 明示 step 化＝**dispatchDrivers 対象 0**。3 Scene の process(node,path,delta) → `step(scene)`（Minimap は StairsExit 同型に getState/writeData で payload 維持）。gameLoop は EnemyTurnDriver/StairsExit の後に 3 step を追加。**罠と対処**: 明示 step はタイトル/選択画面でも走るため、Fog は Map 不在で `getPlacements` が bug! する＝FogDriver ノード presence gate（stepPlaying 分離）を追加。全 1073 green。
  - 2026-07-02: P4-e ItemPickupPopupScene の PopupData を resource 化（(a) レーン一旦完了）。`State`（get/put PopupData）＋`withState`、`NodeTag.ItemPickupPopup(PopupData)`→ペイロードレス、show/showMessage/showFull/reserveGetItemSound/setState/process を State 経由に（scene はパイプ素通し）。**3 経路に伝播**: ①process（ProcessT）②メニュー確定（applyPickup/applyOpenChest→onActionConfirmed→MenuHandler `type Aef`＋InputHandler 連鎖）③physicsProcess（autoPickupOrLog→stepFor→physicsStep/gatherStep→**FrameAef.T**）。テストは `withNoopPickupPopup` fixture（TestUnitFixtures）を新設し 5 箇所に discharge、reserveGetItemSound テストは withState+State.get 観測へ書換。全 1073 green（挙動不変）。実機 run（拾う→中央ポップ＋取得音／自動取得→音のみ／満杯→「持ち物がいっぱいです」）はユーザー確認へ。
  - 2026-07-02: P4-d LevelUpPanelScene の PanelState を resource 化。`State`（get/put PanelState）＋`withState`、`NodeTag.LevelUpPanel(PanelState)`→ペイロードレス、currentState/writeState を State.get/put に。confirm が入力確定経路のため `dispatchMenuKey`→`onPlayingKeyPressed`→`onKeyPressed`→InputHandler `type Aef` まで効果行追記（**入力連鎖の初例**）。ProcessT/gameLoop 行/Game.start 配線。全 1073 green（挙動不変）。
  - 2026-07-02: P4-c TurnEndHoldScene の GaugeData を resource 化。`State`（get/put GaugeData）＋`withState`、`NodeTag.HoldGauge(GaugeData)`→ペイロードレス、process は `State.get/put`（setState ヘルパー撤去）。ProcessT/gameLoop 行/Game.start 配線。純粋ロジック（step/initialData）不変で全 1073 green（挙動不変）。
  - 2026-07-02: P1 完了。P1-a Stopgap ECS化（World.stairsPos read-model + StaffSystem.stopgapEvents + 敵詠唱 log parity）、P1-b thief drop ECS化（World.isRogueOf〔growth#name 由来〕+ ViewFx(Thief) emit + wrapper applyThiefDrop）、P1-c 敵ノックバック（resolveEnemyAttack で faction-blind knockbackEvents 再利用）、P1-d 陳腐化コメント修正。golden +7（Stopgap 味方/敵・thief emit/非ローグ/seam・敵 knockback）。実機 run はユーザー確認へ defer。
  - 2026-07-02: P4-b BattlePanelScene の点滅タイマーを resource 化。`BattlePanelScene.State`（eff get/put Duration）＋`withState`、`NodeTag.BattlePanel(Duration)`→`BattlePanel`（ペイオードレス）、process は node payload 操作を撤去し `State.get/put`。ProcessT/gameLoop 行/Game.start 配線。全 1073 green（挙動不変）。P4 で判明: NodeTag payload を持つ variant は (a) の対象だが Stairs/Chest/GroundItem は P6 送り、メニュー選択状態は engine ItemList プリミティブ＝(b) 未着手（本体は Cursor/ActionMenu/ItemMenu/Trade）。
  - 2026-07-02: P4-a LogScene の状態を resource 化（**P4 パターン確立**）。`LogScene.State`（eff get/put Data）＋`withState(rc)` を co-locate、`NodeTag.Log(Data)`→`Log`（ペイオードレス・enum/dispatch/構築 全 5 サイト修正）、process は `Scene.getState` でなく `State.get()/put()`。FrameAef.ProcessT＋gameLoop 効果行に `LogScene.State` 追記、Game.start に `with LogScene.withState(rc)` 注入。純粋ロジック（enqueue/tickIdle）不変ゆえ既存 TestLogScene がそのまま green＝挙動不変。全 1073 green。
  - 2026-07-02: P3-c GroundItem を World 権威化（Level 1）＝**P3 完了**。World store `groundItems = Map[cellKey, ItemScene.Data]`（`cellKey` を chests と共有）、3-builder（seed=itemsFromScene／preserve＋prune・chests 同型）、`Cmd.SpawnItem/RemoveItem`（applyCmd/cmdKey）を addOneItem/takeAt が emit（add/respawn/addFromSnaps/dropFloorItem に World.Command 伝播）、accessor groundItemsOf/groundItemAtOf。gameplay reader flip: 「拾う」gate（selectedPlayerMenuItems＋gatherAdjacentMenuItems）＋ wouldPickupOverload → `World.groundItemAtOf`（reader 全 flip で 2 menu 関数の `scene` 引数が未使用化＝`_scene`）。`elapsed`（点滅位相）は view 専用ゆえ store は spawn 値スナップショット。pickupFloorItem 内部の dataAt/takeAt・auto-pickup・minimap・セーブは scene view（World 等価）のまま P6 へ。RenderWorld 調査完了（Level 2 は Stairs が catalog 非対応で詰む＝P6 委譲が妥当と確認）。test +1（`testTakeAtDrivesWorldItemStore`）・全 1073 green。実機 run はユーザー確認へ defer。
  - 2026-07-02: P3-b Chest を World 権威化（Level 1・ユーザー選択）。World store `chests = Map[cellKey, Data]`（`chestCellKey=x*1000+y`）、3-builder（syncFromScene seed=chestsFromScene／refreshMirror preserve＋scene 在セルで prune＝unit pos 同型）、`Cmd.SpawnChest/RemoveChest`（applyCmd/cmdKey）を addOneChest/takeAt が emit（dual-write）、accessor chestsOf/chestAtOf。gameplay reader flip: ActionMenu の「あける」gate（selectedPlayerMenuItems）＋ openTarget → `World.chestAtOf`。占有回避/minimap/セーブ capture は scene view のまま（World 等価・P6 で撤去）。test +1（`testTakeAtDrivesWorldChestStore`）・全 1072 green。実機 run はユーザー確認へ defer。
  - 2026-07-02: P3-a Stairs を World 権威化（完全縦スライス）。`Cmd.SetStairs(Option[cell])` 追加（applyCmd/cmdKey）、`StairsScene.placeAt` が emit、`refreshMirror` を stairsPos preserve へ（syncFromScene は frame-1 seed 維持＝hp 同型）。gameplay reader を flip: `StairsExitScene.begin`/`stepOnce`（退場 driver）と `ActionMenuScene` の「階段」gate ×2。WorldQuery 伝播で buildItems/refreshItems/onActionConfirmed/MenuHandler.Aef と Game.flix dispatch を更新。描画/フォグ/セーブ capture/宝箱占有判定・legacy 杖 warp は scene ノード読みのまま（World と等価・真のノード撤去は P6）。`StairsScene.isAt` は test-only seam 化（残置）。test +1（`testPlaceAtDrivesWorldStairsPos`）・全 1071 green。実機 run はユーザー確認へ defer。
