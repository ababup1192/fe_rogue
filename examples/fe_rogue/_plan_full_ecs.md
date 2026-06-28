# fe_rogue → Bevy 流 ECS 移行 計画（v3・レビュー2巡反映／v1 43→v2 52）

> v2 レビューの中核指摘を反映: **ユーザーの本当のゴール（faction 分岐除去・component 合成）は、危険な「戦闘エンジン並行再構築」なしに達成できる**。よって計画を **Track A（安全なコア・推奨）／Track B（任意の深掘り）** に分離。最大の決断は「unified id か」ではなく **「Track B をやるか」**。

## 0. ゴールの正確な再定義（Bevy 整合）
**ユーザー言明**: ECS 主軸・Scene(UI 以外)撤去・Player/Enemy の faction 分岐除去・Entity=Component 合成・UI はツリー維持で ECS 駆動。

**Bevy 整合の正確化**: Bevy でも **`Team`/`Faction` は component（DATA）として残る**（`Encounter.enemiesOf` が `u#faction != faction` で敵味方判定するのと同じ）。消すべきは **`match side {Player/Enemy}` の CONTROL FLOW**（ハードコード分岐）であって、team の概念ではない。
→ **コア成果物 = 「`match side` 制御分岐を消し、team を DATA(component) で表す」**。これは **EntityRef seam ＋ capability-query System** で達成でき、**stats 移送も battle 削除も save 変更も不要**。

**現状の faction 分岐は 12 箇所・全て `CombatScene.flix` に集中**（grep 実測）＝対象は bounded。cross-faction target は bare Int32（`EnemyAction.Attack(self#id, t#id)`・`attackTargetId: Option[Int32]`）。

## 1. 2トラック構成と「最大の決断」
| | Track A（推奨・コア） | Track B（任意・深掘り） |
|---|---|---|
| 何を達成 | **faction 分岐除去・component 合成（ユーザー言明ゴール）** | headless 決定論・World 単独 serialize（save/replay/netcode/balance-test） |
| 手法 | **additive strangler**（live CombatScene 維持・DIFF oracle 生存） | **並行再構築**（`fe_rogue_ecs` 別 entrypoint・golden-trace） |
| save 形式 | **不変** | 単一 id 化なら versioned 移行（first-class 段） |
| stats→World | **不要**（scene 読みのまま EntityRef dispatch） | **必要**（S-A0） |
| 戦闘 callback | **消さない** | 消す＝**second battle engine**（revert=branch-swap） |
| リスク | 低（既存 F-series と同型） | 高（F4 で combat フル反転=実現可能性35・隠れ big-bang） |
| 既存判定との整合 | Plan B(§G) の正統延長 | Plan B が valid end-state と宣言済の上での追加投資 |

**★ユーザーが決める唯一の点 = 「Track B をやるか」**（§6 で詳述）。やらなくてもゴール（分岐除去・合成）は Track A で達成。**Track B は「2 つ目の戦闘エンジンを建てる」覚悟が要る**（per-screen cutover 不能・golden-trace は timing/feel のズレを捕えない・revert は branch 一括差替）。

---

## 2. Track A（推奨）= faction-blind seam ＋ capability System
**性質**: 全段 additive・live scene 維持・`[DIFF]` oracle 生存・save 不変・stats 移送なし。

### A1. cross-faction 参照を Int32 → EntityRef（前提 additive slice）
split id-space では bare Int32 target は playerHp/enemyHp を**隠れ match side なしに解決できない**。→ `attackTargetId`・`EnemyAction.Attack` の target・counter target を **`EntityRef`(Player(id)/Enemy(id)) 化**。新 `Cmd`＋applyCmd＋`[DIFF]`（EntityRef-resolved defender == scene-resolved defender）。**これが faction-blind の前提**。

### A2. Team を component 化・`match side` 12 箇所を capability query へ
- **Team component**（`Map[EntityId, Faction]` or `players/enemies` tag を Team-as-data として読む）。敵味方は `team(a) != team(b)` で判定（分岐でなくデータ比較）。
- `CombatScene` の `match side` 12 箇所を、attacker/defender を **EntityRef accessor で取得**して faction を見ない関数へ。純モジュール（`Combat.estimate/damage`・`CounterAttackRules`）は無改造で中身に流用（builder が UnitView を**scene から**組んで渡す＝stats 移送不要）。
- exp 付与は **`progress` component を持つ entity への capability query**（Player marker テストでなく）。
- `CounterAttackRules.decide`/`decideForEnemy` の鏡像を **1 関数に collapse**（defender alive? in range? has weapon? の team 非依存 query）。
- **検証**: 各 `match side` 撤去ごとに parallel-run DIFF（撤去版 == 旧 match 版の出力）＋実機 OK。**live CombatScene を消さない**ので oracle 生存。

### A3. 2軸 phase（19-case を分解・load-bearing 表）
**SimPhase**(PlayerTurn/EnemyTurn/GameOver) が sim を gate・**UiMode resource** が UI/入力のみ gate。Game.flix の `simPhaseOf` が既に写像の半分。
| TurnPhase(~19) | SimPhase | UiMode |
|---|---|---|
| PlayerCursor | PlayerTurn | Cursor |
| ActionSelect/WeaponSelect/ItemSelect/StaffAim/ThrowAim/TradeTarget/TradeInventory/AttackForecast | PlayerTurn | （各 modal） |
| PlayerMoving/GatherMove | PlayerTurn | None(anim) |
| PlayerAttackHold | PlayerTurn | None(anim) |
| LevelUpView/SuspendConfirm | PlayerTurn | （modal・割込） |
| StairsExit | PlayerTurn | StairsExit |
| EnemyTurn | EnemyTurn | None |
| GameOver | GameOver | None |
**どの System も 19-case を直読みしない**（SimPhase か UiMode のみ）。

### A4. effect 分類表（「pure pipe」主張の load-bearing・~14 effect）
| effect | 移行先 |
|---|---|
| `World.Command` | scene/view bridge（core は applyCmd を pure fold で使い emit plumbing は使わない） |
| `TurnPhase.State` | SimPhase + UiMode resource |
| `SelectedPlayer.State` | UiMode/cursor resource |
| `EnemyTurn.Queue` | actionQueue resource（**Track B**） |
| `BoardQuery` | World-derive（`boardFromWorld`・**Track B 前提**） |
| `Pacing/Tween/AnimationPlayer.Scheduler` | view-local（gameLoop で純 step 後） |
| `Math.Random` | World RNG resource（**Track B**） |
| `GameLogger`/`Audio` | ambient・純 step 後に gameLoop で実行（dodge `playPhaseAudio`） |
| `GatherResume/PartySelection/FloorProgress/InitialSpawns/FloorSnapshot.State` | resource or ambient（flow-setup） |

### A5. スコープの正直な線引き（Track A は何を消さないか）
`EnemyTurnDriver`/`MapScene`/`Fog`/`Minimap`/`EncounterBuilder` は **placements/roomCount/move-drafts/lit-rooms/terrain** に依存し、これらは Track A では World に移さない＝**Scene 権威のまま・本計画で削除しない**。`BattlePanelScene.confirm` は TopBar 同様に分類: **「sim Action を enqueue し phase を直接変えない」**（binding 表で確定）。menu(Item/Trade/Action/cursor) も scene 権威維持（Plan B gate と同じ）。UI は §A6。

### A6. UI（ツリー維持・IDE 両立）
IDE-authored(scene.json: layout/style)は uiSyncSystem が**絶対上書きしない** vs World-bound dynamic props(text/visible/phase-color)のみ binding 表で sync。TopBar wipe timer は view-local・driver が要る派生 bool だけ World(F8-slice2 実証済)。S-F は読み取り HUD/banner sync に限定。

**→ Track A 完了で**: 戦闘ロジックが team-as-data の capability System・`match side` 全廃・2軸 phase・UI は World 駆動 retained tree。**ユーザーゴール達成・save 不変・低リスク。**

---

## 3. Track B（任意・深掘り）= sim/view 分離・headless・World serialize
**前提**: Track B は「2 つ目の戦闘エンジン」。着手は §6 の決断 YES のときのみ。以下を **hard 前提スライス**として並行再構築の前に緑化:

### B0. 前提スライス（各々 parallel-run DIFF 緑が gate）
- **S-A0 stats/maxHp/weapon(combat-read field=atk/hit/crit/type/effect のみ)/statuses を World read-model 化**（hp/level と同型 Cmd+applyCmd+preserve+`[DIFF]`）。durability/inventory は scene 権威のまま。**dual-write-site 監査**（level-up stat gain・equip/swap/trade/break/pickup ~9 files）を hard count。
- **S-A1 RNG を World resource 化**: PRNG(seed+counter)・System 内 pure next()/split()・FloorSnapshot/SuspendSave に永続。**draw 順は「frame-timing 非依存だが消費順は現状と IDENTICAL」**（canonical reorder しない）。**先に既存 scene path を seed して trace 記録→ECS path をそれに一致**。per-action draw 列を列挙(hit→crit→thief?→kill 時 growth×9→effectRule?→follow-up)。
- **`boardFromWorld(world)`**: Board.pieces は**生の駒位置**＝World playerPos/enemyPos から毎回再構成。DIFF= scene-built Board == World-built Board（pieces+occupancy byte 一致）。
- **emit-flip**: World.flix:264-271 に「emit は UNWIRED（emit した Cmd が次フレーム頭 syncFromScene で上書き）」と明記。despawn/thief-drop spawn が永続しない。→ **syncFromScene→refreshMirror cutover＋worldRef threading を sim 再構築の前に**、or headless path が threaded World のみで走り scene 上書きを bypass することを証明。

### B1. sim core の実行形（明示）
- **`applyCmd` を pure fold `List[Cmd] -> World -> World`** として `fe_rogue_ecs` 内で使う。`World.Command` effect(262 emit-site)は**view/scene bridge 限定**。core は Cmd/EntityRef の**データ型**を再利用し emit plumbing は使わない。
- **PlayerTurn/EnemyTurn の pipe を spike 成果物として明記**（engine_ecs に scheduler 無し＝hand-ordered pipe が load-bearing）。各 System に guard（simPhase/uiMode/no-active-tween/modalOpen）。
- **`resolveSystem` = 明示的再帰 drain**: 各 queued `Attack` に kind ∈ {Main,FollowUp,Counter} と `mayRetaliate`(Counter/FollowUp は false) を付与・Main→FollowUp→Counter 固定順 enqueue・**終了は既存 followUpUsed flag に紐付け**。受入テスト「attack→followup→counter, counter は再 counter しない」。

### B2. 反応・死亡・event（headless 決定論の defect 修正込み）
- **counter = 後続 Action を actionQueue に enqueue**し同 Resolving pass で解決。
- **死亡を 2 つの World 事実に分離**: **`alive=false` を resolveSystem が即時適用**（同フレームで occupancy/AI/targeting から除外）vs **`view.dying`** は ViewReplay が death_blink 完了で drain。**occupancy = alive && not hidden**（死体がマスを塞がない）。golden-trace 表明「just-killed-cell への follow-up/move が headless==live」。
- **enemy-turn lifecycle は sim 所有事実で gate**（`resolveSystem` が `enemyTurnIntroConsumed` を立てる）＝TopBar 書込の phaseObservedEnemy/enemyTurnBusy bool に**依存しない**。headless テスト「敵 0 体の敵ターンが終了する（deadlock しない）」。
- **死亡/exp/level-up = `events: List[SimEvent]`**（Died/Killed/LeveledUp/…）を despawnSystem/expSystem(progress 持ちのみ)/level-up UI が drain。**ViewReplay が log を pacing timer で再生・`LeveledUp` で停止(modal-gate)・入力で再開**。

### B3. view 層・write-side 副作用
`resolveAttack` の ~9 副作用を **World 変異**(hp・knockback pos・thief spawn・lifesteal hp) と **SimEvent for view**(SE 名・popup text/color・explosion・death_blink) に仕分け（system は `(World,[SimEvent])` を返す・view が log から発火）。**engine AnimationPlayer は VIEW 用に維持**（attack:hit/death_blink/camera settle/tween を engine_ecs は持たない）。**headless は sim System のみ**（view は非再現と明記）。

### B4. golden-trace oracle と並行再構築
固定 seed 入力列→**現 scene path の hp/pos/death/exp 列を凍結**→ECS pipeline が同列再現。削除前に凍結。並行ゆえ live scene を消さず DIFF/golden 両取り。cutover は **all-battle-at-once**（per-screen 不能）＝golden-trace 緑＋実機 feel 確認で一括差替・revert=branch。

---

## 4. Flix codegen 対策（両トラック共通）
World を nested サブレコード（components/markers/resources/view）に分割（1 リテラル<40 field）。`applyCmd` を per-domain applier 分割＋薄い外側 match。**各スライスに `flix build`(codegen) CI gate**（MethodTooLarge は codegen でしか出ない・既に Game.flix dispatch 4 分割実績）。

## 5. 検証
- **Track A**: `flix test`＋`flix build` 緑＋`match side` 撤去ごと parallel-run DIFF＋実機 OK＋既存 `[XXX DIFF]` 無音。
- **Track B**: 前提スライス各 `[DIFF]` 緑→headless 決定論（同 seed 二重 replay 一致＋legacy-vs-ECS 同 seed 等価）→golden-trace 一致→all-battle cutover 実機 feel。

## 6. ユーザーが今決める 1 点
**Track A（推奨）だけで、あなたのゴール「faction 分岐除去・Player/Enemy を component 合成」は達成され、save も挙動も不変、リスクは既存 F-series と同型。**

決めるのは **「Track B（headless 決定論・World 単独 serialize＝save/replay/netcode/balance-test）を*やるか*」**:
- **やらない（推奨・既定）**: Track A で完了。live CombatScene 維持。S-A0/RNG/golden-trace/並行再構築/§3 大半が不要。Plan B end-state の正統延長。
- **やる**: 「2 つ目の戦闘エンジン」を建てる覚悟。前提スライス(B0)＋golden-trace 必須・cutover は一括・revert=branch。能力(save/replay/headless balance)を解禁。F4 が combat フル反転を実現可能性35 と評価済＝最大の賭け。

→ **この 1 点（Track B yes/no）で全段が確定。** Track A は今すぐ着手可能。
