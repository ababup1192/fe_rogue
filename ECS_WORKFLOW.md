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
| 2 | 在庫・装備・耐久（weapons/staves/consumables/rings） | scene `Data#weapons` 等（World は mirror） | **P2** |
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

依存関係: **P1 → (P2 ∥ P3) → (P4 ∥ P5) → P6**。P2/P3 は完全独立、P4/P5 もほぼ独立（TurnEndHold だけ P4 の入力状態に触る）。

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

### P2 — 在庫・装備・耐久の World 権威化

**目的**: weapons/staves/consumables/rings の権威を scene `Data#...` から World store へ flip。`Weapon.consumeEquippedWeapon` 等の scene 副作用を Cmd 化。

**達成条件**:
- [ ] 在庫の read/write が全て World 経由（メニューの読みも含む）
- [ ] 耐久消費・アイテム増減が `World.applyCmd` 経由の Cmd になっている
- [ ] `[PLAYERDATA DIFF]` / `[ENEMYDATA DIFF]` assert が沈黙 → 撤去
- [ ] scene `Data` から在庫 field を削除（NodeTag.Player(Data) のダイエット第一弾）

**対象**: `ecs/World.flix`, `scenes/PlayerScene.flix`(W=119 の主因), `ItemMenuScene.flix`, `TradeMenuScene.flix`, `WeaponSelectScene.flix`, `StaffCastScene.flix`, `game/` の Weapon 系 rules

**並列**: store 単位（weapons / staves / consumables / rings）で 4 レーン。World field 追加は冒頭 1 コミット集約（§C）。

**注意**: セーブ互換を壊さない — save は scene 由来のまま（P6 まで）、World は runtime 権威。トレード（TradeMenu）は 2 エンティティ同時更新なので Cmd を 1 つの atomic variant にする（2 Cmd に割ると DIFF assert が transient を誤検知）。

---

### P3 — 配置物の Entity 化（P2 と並列可）

**目的**: Chest / Stairs / GroundItem をツリーノードから World entity（pos + kind component）にする。

**達成条件**:
- [ ] `chests/stairs/groundItems` store が World にあり、spawn/開封/取得が Cmd
- [ ] 描画が RenderWorld 経由（ChestScene 等の addChild 撤去）
- [ ] 開封済み・取得済み状態がツリーの有無でなく component で表現される

**対象**: `scenes/ChestScene.flix`(251), `StairsScene.flix`(119), `ItemScene.flix`(474), `ecs/World.flix`, `scenes/RenderWorld.flix`, spawn 経路（`GameLifecycle.flix` / `DungeonComposer` 出口）

**並列**: 3 種で 3 レーン完全独立。

**注意**: GroundItem は P2 の在庫 store と受け渡し（拾う=ground から消して inventory へ）があるので、P2/P3 並走時は **Cmd の境界を先に合意**してから分担。unified-id 規約（enemy=+1,000,000）に倣い、配置物にも id 帯域を割る（例: +2,000,000〜）。

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

**注意**: 非 driver Scene の読みは effect 経由の慣習を維持（PartyQuery/RosterQuery パターン、モジュール名直タイプ禁止）。`[xxx]` 表示は BBCode 扱いされる罠 — メニュー描画を組み替えるとき Label2D/別表現を維持。CursorScene は入力ロジック濃度が高いので「状態移送」と「入力→intent 整理」を別スライスに割る。

---

### P5 — 演出・残 driver の System 化（P4 と並列可）

**目的**: 演出ノード（DamagePopup/Explosion/ItemPickupPopup/HoldGauge/lunge marker）を EcsTween + RenderItem に置換し、per-node `process` dispatch と engine `Tween.tickAll` 依存を空にする。

**達成条件**:
- [ ] 演出の寿命・位置が `World.tweens`（EcsTween）または専用 store で駆動される
- [ ] `dispatchTickables` / `dispatchDrivers` の対象が 0 になり、gameLoop の明示 step 呼びに一本化
- [ ] Fog / Minimap / ArrowCursor が F8 パターン（frame-paced step）に移行
- [ ] MoveDraft の scene 副作用が Cmd/System 経由になる
- [ ] 武器/HP バー marker が RenderWorld 直描き（`Game.flix:1147` の「marker は engine 駆動のまま」解消）

**対象**: `scenes/DamagePopupScene.flix`(145), `ExplosionScene.flix`(115), `ItemPickupPopupScene.flix`(312), `TurnEndHoldScene.flix`(246), `UnitHPBarScene.flix`(208), `FogScene`, `MinimapScene`, `ArrowCursorScene`, `systems/PlayerMovementScene.flix`, `game/Game.flix`(dispatch 表), `engine_ecs/src/EcsTween.flix`

**並列**: 演出 4 種 + driver 3 種で独立レーン。EnemyTurnDriverScene/StairsExitScene の step が参照実装。

**注意**: engine_ecs へ機能追加したくなったら **Godot 対応物があるものだけ・事前相談**（feedback 済み制約）。ゲーム固有便利関数は fe_rogue 側に置く。render-from-World の O(root×N) 罠 — 描画対象 root を増やすときは `subtreeDrawablesForRoots`（paths 1 回共有）に載せる。

---

### P6 — Scene ツリー撤去 & 大掃除（最終・直列）

**目的**: 「ノードを積んで隠して World から描き直す」二重構造を解消し、legacy 資産を撤去する。

**達成条件（順番厳守）**:
- [ ] 1. hide-then-render 廃止: そもそもノードを積まない（P3-P5 完了で積む理由が残っていないことを grep で確認: `addChild` 使用が Game/GameLifecycle 以外ゼロ）
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

**現在フェーズ: P1（Cutover 完遂）— 未着手**

- テスト baseline: 970+ green（着手前に実測して数字をここに記録すること）
- 完了済み前史: Track A/A'（faction 統合・unified-id）、F0-F8（sim state 権威化・driver step 化）、pos 統合、Phase C 前提 4 スライス、combat/staff cutover（トグル 3 つ true）、render-from-World 常時化
- **次の一手**: P1 の 6 TODO のうち「ViewReplay level-up モーダル発火」から。golden-trace の雛形は `test/ecs/TestGoldenTrace.flix`
- 履歴:
  - 2026-07-02: 本 doc 作成（Scene vs ECS 全棚卸し → P1-P6 ワークフロー策定）
