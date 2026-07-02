# 混在 sim-Scene の split 計画 — 「view ＝ Scene / 中核 ＝ System」

対象: `CombatScene` `PlayerScene` `EnemyScene` `MapScene` `StaffCastScene` `ItemScene`（混在）。
原則: **sim 状態の変更・判定 = System（純ロジック）／ノード生成・アニメ・SE・popup = View(Scene)。**

## 難度の見取り図（軽い → 重い）

| 部分 | 難度 | 理由 |
|---|---|---|
| 純関数の抽出（戦闘 rules 等） | **軽** | 既に effect なし・型参照だけ |
| spawn funnel の分離（Entity） | 軽〜中 | view ノード生成 と World seed が同居・分けやすい |
| view ops の分離（sprite/anim/HPBar） | 中 | 純 view・抽出は機械的だが量が多い |
| MapScene 構造 vs 描画 | 中 | board model は既に sim・残りは tile 描画(view) |
| Item/Staff の pickup/effect 適用 | 中 | effect-runner は sim 済・orchestration が view と交錯 |
| **scene-authority → World-authority（mirror 撤去）** | **重** | hp/status reader を World へ flip・pure builder の wiring（既知の churn） |
| **CombatScene の戦闘 orchestration** | **最重** | sim 書込と view 発火が同一関数内・counter 分岐・async death・level-up modal ＝ **SimEvent モデル必須** |

---

## Phase A — 軽い split（SimEvent モデル不要・additive・低リスク・即着手可）

各々 `flix test`＋実機で挙動不変を確認しながら。

**A1. CombatScene の純 rules を `sim/` へ抽出**
`resolveStrike`・`attackForecast`・`shouldFollowUp`・`braveFollowUp`・`hitSoundName`・`replaceOrDropHead` は effect なしの純関数。`sim/CombatRules.flix`（or `Combat.flix` に合流）へ。CombatScene は呼ぶだけ。
*注: `attackForecast(player: PlayerScene.Data,…)` は `PlayerData.Data` 受けに変えると sim→scenes 依存が切れる（callers 軽微修正）。*

**A2. spawn funnel を Entity として分離**
`addOnePlayer`/`addOneEnemy` を `ecs/spawn/`（or `systems/spawn`）へ。中で「**World seed（Cmd emit）= sim**」と「**view ノード生成 = Scene 呼び出し**」を 2 関数に割る（`spawnEntity`＝component bundle、`buildUnitNode`＝view）。

**A3. PlayerScene/EnemyScene の純 view ops を `PlayerView`/`EnemyView`(Scene) へ**
`setSpriteModulate`・`playAnim`・`showAllActive`・HPBar 連携・`death_blink` アニメ等は純 view。View モジュールへ移し、PlayerScene/EnemyScene は sim ops＋accessor に痩せさせる。

**A4. MapScene を 構造(sim/resource) と 描画(view) に**
board/terrain は既に `sim`(Board/MapSnapshot)。MapScene に残るのは tile ノード描画＝view。構造読み出しを sim 由来にし、MapScene を render 専任化。

**A5. ItemScene の pickup ロジック分離**
床アイテム取得（inventory 変更＝out-of-scope の scene 権威）と item ノード/popup(view) を分離。pickup 判定を純関数化。

→ **Phase A 完了で**: CombatScene/Player/Enemy/Map から純ロジック・spawn・view が剥がれ、**残るのは「sim orchestration」だけ**になる。これが Phase C の対象を最小化する。

---

## Phase B — 中：scene-authority → World-authority（mirror 撤去）

Phase A 後、PlayerScene/EnemyScene の sim ops（setHp/move/status/waited…）はまだ scene＋World に dual-write。**reader を World へ flip し scene 書込を撤去**して scene を**純粋な派生 view**にする（位置は `syncTreeFromWorld` で実証済の §A payoff を hp/status/flag へ拡張）。

- **既知の壁**: combat の pure builder（`unitView`/`Encounter`）が `#hp/#stats` を読む → World 渡しの builder で wiring（call-site churn）。**component 単位・1 call-point ずつ・parallel-run DIFF**。
- **前提**: stats/maxHp/weapon を World read-model 化（S-A0）。`progress`/`team` は済。
- ここまでで PlayerData/EnemyData の **scene 権威が消え**、Data record は World component の派生になる（並行型 PlayerData/EnemyData の統合へ道が開く）。

---

## Phase C — 最重：CombatScene 戦闘 orchestration の SimEvent 化（＝中核 System の分離本体）

ここが「見た目と中核の分離」の核心かつ最大リスク。**sim を即解決して event log を出す System ＋ event を replay する View** に割る。

**C1. SimEvent モデル設計（spike）**
`resolveAttack`/`applyHit`/`onLungeDone` を `resolveCombat(world): (World, List[SimEvent])` に。
- counter = `actionQueue` に follow-up `Attack` を enqueue（同 pass 解決・再 counter 不可）。
- 死亡/exp/level-up = `SimEvent`（Died/Killed/LeveledUp…）。死亡は **alive=false 即時(sim)** と **view.dying(replay)** に 2 分。
- 副作用（popup/SE/explosion/knockback/thief/lifesteal）は SimEvent に載せ、**view 層が log から発火**。

**C2. ViewReplay System**
event log を pacing timer で再生（lunge→hit→death_blink）。`LeveledUp` で停止＝modal-gate。engine AnimationPlayer は view timeline として維持。

**C3. cutover（all-battle・revert=branch）**
golden-trace oracle（固定 seed の hp/pos/death/exp 列）を凍結→ECS resolver が同列再現を確認→**実機 feel A/B**→一括差替。**signal 駆動 CombatScene は branch 温存**（消さない）。

**C の前提スライス**（B0・各 DIFF 緑が gate）: RNG を World resource 化（消費順 IDENTICAL）・`boardFromWorld`・emit-flip（syncFromScene 上書き解消）。← 過去レビューで blocker 指摘済。

---

## リスク緩和（C は revert-hell 帯）
- **golden-trace**（削除前に凍結・削除後の oracle）＋ **headless 決定論**（同 seed 二重 replay 一致）＋ **legacy-vs-ECS 等価**。
- **spike-first**: 「味方攻撃→反撃→撃破→level-up modal」1 本を C 着手前に試作。
- **branch 温存**: working CombatScene を消さずに並行構築・cutover 時のみ差替。

## 推奨順序と即着手点
1. **Phase A（軽・即）** ← 今ここから。低リスクで「orchestration 以外」を全部剥がす。Phase C の対象を最小化。
2. **Phase B（中）** ← scene を派生 view に。
3. **Phase C（最重・spike gate）** ← SimEvent モデル。ここで初めて「2つ目の戦闘エンジン」を建てる。

**最初の一手 = A1（CombatScene 純 rules → sim/）**。最も軽く・効果（CombatScene の純ロジックが sim に集約）が見える。
