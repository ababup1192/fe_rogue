# Phase C 事前準備プラン（壁打ちスコア 76・承認済み）

Phase C（`resolveCombat → (World, [SimEvent]) + ViewReplay`）に着手する前に必要な 4 スライスの基盤を整える計画。各スライスは単独で `flix test` green / `flix check` clean を維持し、スライス境界がコミット境界になる。

---

## ビルド順序（Sequencing）

1. **`rng-world` を最初に** — ゲーティング前提条件。再現可能な PRNG を worldRef 上に持たない限り golden-trace を決定論的にできない。このスライスは単独で green に着地しなければならない。
   - 拡張した `withMockRandom`（`World.RngDraw = k(50)` を discharge）が、effect カスケードが既存 8 箇所の TestCombatScene サイトを RED にしないためのゲート。
   - `FrameAef.ProcessT` の編集を必ず含める（含めないと `Game.flix:177/179` の `checked_ecast` widening がコンパイルに失敗する）。
   - `withNoopThiefDrop` の移設と、2 つの呼び出しサイト更新（93/364）も同スライスで行う。

2. **`board-lock` と `simevent-algebra` を次に並行** — どちらも additive/pure で、`rng-world` とも互いとも独立。
   - `board-lock` は既出荷の `World.toBoard` と visible-entity prune guard を pin する。
   - `simevent-algebra` は自己完結の design spike で、TOTAL な `cmdKey`（`Cmd` に Eq がなく自身のテストが必要とするため golden-trace から移動）を所有し、既存の `stepEnemyMove`/`replayMovedEvent` seam 上で emit→replay timing を証明する。

3. **`golden-trace` を最後に** — `rng-world`（再現性）+ `board-lock`（最終ボード parity）+ `simevent-algebra`（cmdKey）に依存。
   - レガシーの Cmd を emit する combat を PUBLIC seam（`applyAttackHit`/`applyEnemyAttackHit`/`onLungeDone`、scene-seeded attackTargetId）経由で駆動。private な `resolveAttack`/`resolveEnemyAttack` ではない。SimEvent でもない。よって cmdKey を消費するが `applyEventToWorld` は呼ばない。

各スライスで `flix test` green / `flix check` clean を維持。Live combat は終始 bit-identical を保つ（delegating な `World.RngDraw` ハンドラの BODY-IDENTITY による。ハンドラ本体は今日の rollPercent 本体と verbatim 同一、`Math.Random` は `start():~736` でスコープ内）。seeded PRNG はテスト/トレースハーネスのみが行使する。

---

## スライス 1: `rng-world`

**タイトル**: RNG chokepoint → 単一の `World.RngDraw` effect（ゲーティング前提条件。dormant な `World.rng` フィールド。live な数値は BODY-IDENTITY により bit-identical）

### Approach

**GOAL**: あらゆる combat roll を、決定論的かつ再現可能な PRNG に backed された 1 つの World 媒介 effect 経由にルーティングする。live outcome を変えず、かつ脆弱な draw order を乱さない。

**SCOPE-HONEST**: effect の CHOKEPOINT + DORMANT な `World.rng` フィールドを着地させる。production RNG はまだ World に移動しない（live ハンドラは `Math.Random` に delegate し、`w#rng` を決して進めない）。Seeded PRNG はテスト/トレースハーネスのみが行使する。

**EQUIVALENCE GUARANTEE（修正版フレーミング）**: live な数値が bit-identical なのは、弱い 1:1-source-position の主張によるのではなく、**BODY-IDENTITY** による。live な `World.RngDraw` ハンドラ本体は文字どおり `Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64()*100.0))` で、今日の rollPercent 本体と character-for-character 同一の式。同じ RNG ソース・同じ reduction → code-identity の事実として同一バイト。

**NAMING（衝突なし）**: PRNG は `mod Prng`、型 `Prng.State`。World effect は `pub eff World.RngDraw { def nextPercent(): Int32 }`。World フィールドは `rng = Prng.State`。Qualified `Prng.*` + op `World.RngDraw.nextPercent` により、`mod World` 内で bare な `Rng` prefix を経由して解決されるものは何もない。

#### (1) NEW `src/ecs/Prng.flix` — pure splitmix64、zero effects

- `pub enum State`（Int64 をラップ）、`pub def seed(s)`、`pub def nextPercent(st): (Int32, State)`。
- REDUCTION は rollPercent のドメイン `Float64.truncateToInt32(Float64.floor(unit*100.0))` と等しくする。`unit = top53 / 2^53`。
- **SHIFT-SEMANTICS サブタスク**: splitmix64 は UNSIGNED 右シフト（`>>>30/27/31`）を必要とする。Flix Int64 の `>>>` セマンティクスを freeze 前に必ず probe する。3 行の probe で `(-1i64) >>> 60` を計算し `flix check` + evaluate を実行。sign-fill する場合は mask で logical shift を実装: `(x >>> n) &&& ((1i64 <<< (64-n)) - 1i64)`。経験的に DECIDE し、仮定しない。

#### (2) `src/ecs/World.flix`

- record に `rng = Prng.State` を追加（`phaseObservedEnemy` の後 ~78 行目）。
- `World.empty()` は `Prng.seed(0i64)` で seed する。
- syncFromScene（~155）と refreshMirror（~210）の **両方** で VERBATIM に carry: `rng = w#rng`（`enemyTurnBusy` と同じ）。さもないと毎フレーム seed が silently reset される。
- 追加: `pub def drawPercent(world): (Int32, World)`、`pub def seedRng(s, world): World`、`pub def rngOf(world): Prng.State`、そして他の World effect の隣に `pub eff RngDraw { def nextPercent(): Int32 }`。

#### (3) `src/scenes/CombatScene.flix`

- `rollPercent()`（行 449/450）の effect row を `\ Math.Random` → `\ World.RngDraw` に変更、本体を `World.RngDraw.nextPercent()` に。これが CombatScene で唯一の Math.Random USE。
- その後 `flix check` に cascade を駆動させる。全 transitive caller の effect row で機械的に Math.Random → World.RngDraw に swap: process/drainAndDispatch、applyAttackHit:143、applyEnemyAttackHit:157、onLungeDone:170（follow-up @203/322 含む）、resolveAttack:498、applyDamageToEnemy:484、resolveEnemyAttack:706、applyEnemyEffectRule、applyExpGain:966、applyLevelUp:986、rollGrowth、startEnemyCounter:287。**`flix check` が authoritative であり、このリストではない。**

#### (4) `src/game/FrameAef.flix` — BLOCKER-FIX（以前は省略されていた）

- `ProcessT`（:27-39 のエイリアス。すでに Math.Random@~38 を carry）に `World.RngDraw` を追加。
- `Game.flix:177/179` は `checked_ecast` で CombatScene.process を ProcessT へ widen する。process が World.RngDraw を得ると、ProcessT がそれを含まない限り cast が失敗する。
- `T`（:15-19）は UNTOUCHED のまま — Math.Random を持たず、physics/movement パスは roll を draw しない（`flix check` が確認）。TurnPhase.flix/GatherResume.flix は ProcessT をエイリアスし、この追加を harmlessly に継承する。

#### (5) `src/game/Game.flix`

- `flix check` がフラグした effect row（gameLoop + EnemyTurnDriverScene.step + physicsProcess 内の CombatScene.process dispatch + 任意の pipeline wrapper）に World.RngDraw を追加。
- `start()` ハンドラスタック（World.Command @881 / World.WorldQuery @893 と並べて）に追加:
  ```
  with handler World.RngDraw { def nextPercent(k) = k(Float64.truncateToInt32(Float64.floor(Math.Random.randomFloat64()*100.0))) }
  ```
  Math.Random はスコープ内（start が @~736 で carry）。
- 9 つの非 combat Math.Random サイト（item-throw 279/301/318、gameover 502/645、dungeon-gen/save 737/940/1000）は EXPLICITLY に Math.Random のまま keep する。

#### (6) `test/scenes/TestUnitFixtures.flix`

- `withMockRandom`（行 416）を EXTEND し、`with handler World.RngDraw { def nextPercent(k) = k(50) }` も install する（50 = floor(0.5*100)、Math.Random=0.5 スタブと byte-identical）。
- シグネチャ `a \ (ef - Math.Random)` → `a \ ((ef - Math.Random) - World.RngDraw)`。これで既存 8 箇所の TestCombatScene サイトが per-call 編集なしで green を保つ。
- ADD: `withSeededRng(seed, thunk)`（region-Ref[World] seeded ハンドラ、World.drawPercent 経由、withWorldCommand を模倣）と `withRecordedRolls`（ordered List[Int32] を返す）。
- MOVE: `withNoopThiefDrop` を TestCombatScene:332 から TestUnitFixtures へ移し、既存 2 呼び出しサイト TestCombatScene:93 と :364 を同スライスで `TestUnitFixtures.withNoopThiefDrop` に更新する（`flix check` が漏れをフラグ）。

**INTRA-EXPRESSION EVAL-ORDER NOTE（明示化）**: 正しさは Flix が record フィールド（rollGrowth が構築する `{hp=rollPercent(), attack=rollPercent(),...}`@951-959）と call ARGUMENTS（thief roll@548 は arg）を left-to-right で決定論的に評価することに rest する。これは成立し、かつ call-path-shared なので、リテラルな順序に関わらず seeded == live。growth assertion は 12 の ORDERED draw を、stat↔position マッピングを仮定せず COUNT する。

### Files

- `src/ecs/Prng.flix`
- `src/ecs/World.flix`
- `src/scenes/CombatScene.flix`
- `src/game/FrameAef.flix`
- `src/game/Game.flix`
- `test/ecs/TestPrng.flix`
- `test/scenes/TestUnitFixtures.flix`
- `test/scenes/TestCombatScene.flix`
- `test/scenes/TestCombatRolls.flix`

### Tests

**NEW `test/ecs/TestPrng.flix`**:
- (a) determinism（same seed → same sequence）
- (b) range invariant（every draw 0..99）
- (c) frozen first-N sequence、COMPILED IMPL から GENERATED
- (d) drawPercent が state を advance
- (e) SHIFT-SEMANTICS + Int64-wrap テスト、Int64.maxValue 近傍で seed。**CRITICAL**: ここでの expected percents は INDEPENDENTLY に導出する（1 つの seed の hand-computed splitmix64 reference、または second oracle）。同じ impl から再生成しない。よってこのテストは shift/reduction の正しさについて self-confirming ではない。

**NEW seeded multi-frame CARRY テスト**: seed → draw k1 → syncFromScene THEN refreshMirror を run → draw k2 → k2 が SAME sequence を継続すると assert（rng が両 sync パスを生き延びた）。

**NEW `test/scenes/TestCombatRolls.flix`**（roll-sequence equivalence）: withSeededRng + withRecordedRolls + mocked Tween/Anim/Audio/Logger/Board/WorldQuery + scene-seeded attackTargetId のもとで:
- (1) PUBLIC applyAttackHit on hit→crit→thief→kill→level-up fixture。12 の ORDERED draw `[hit, crit, thief, then 9 growth]` を COUNT+order で assert（stat-position ではない）。
- (2) applyEnemyAttackHit（effectRule + guaranteed-hit）。`[hit, crit, effect]` を assert。
- (3) PUBLIC onLungeDone。follow-up roll @203 が IN POSITION で draw されると assert（speed を pin してブランチが fire しないが roll は消費される）。

`flix check` clean = transitive cascade 全体（FrameAef.ProcessT、Game、driver 含む）がコンパイル。Full suite を run: 新 effect/field からの unused-case/zero-warning regression が NO であることを confirm。

### Risks

- (a) Effect-cascade churn — mechanical。`flix check` が completeness を pin（FrameAef.ProcessT checked_ecast widening 含む）。
- (b) `rng=w#rng` を両 sync パスに必ず追加。
- (c) withMockRandom シグネチャ変更は additive（effect subtraction）。8 TestCombatScene サイトは編集不要。
- (d) 9 つの非 combat Math.Random サイトを sweep してはならない。
- (e) Flix Int64 `>>>` sign-fill は probe するまで未検証 — 必要なら mask logical shift。Int64-wrap テスト expectation は self-confirmation を避けるため independently 導出。
- (f) world.rng は live パス上 DORMANT。frame-carry は seeded multi-frame テストのみが行使（将来の live flip まで test-only、DoD に記載）。
- (g) withNoopThiefDrop の移設はサイト 93+364 を同スライスで更新する必要。

### DependsOn

なし

---

## スライス 2: `board-lock`

**タイトル**: boardFromWorld verify-and-lock（BoardQuery で既出荷 — parity を pin、prune asymmetry を VISIBLE entity でガード）

### Approach

**FINDING**: `World.toBoard(world, scene) = {map=BoardSnapshot.mapSnapshotOf(scene), pieces=boardPieces(world)}` はすでに存在し（World.flix:729）、production board source（BoardQuery ハンドラ、Game.flix:879）。boardPieces、boardKey（order-independent な (faction,id,x,y) normal form、hidden-filtered @~760）、hidden-filter テストも存在する。このスライスは新規ビルドではなく reconciliation/LOCK。Phase C に「World-derived board == scene-derived board」の明示的な frozen guarantee と、prune-timing asymmetry のガードを与える。

#### (1) `src/ecs/World.flix`

- 追加: `pub def boardMatchesScene(world, scene): Bool` = `boardKey(toBoard(world, scene)) == boardKey(BoardSnapshot.fromScene(scene))`
- 追加: `pub def boardKeyMismatch(world, scene): Option[(List, List)]`（diff 時に 2 つの normalized key を返す）
- 既存 boardKey を reuse。新 traversal なし。

#### (2) toBoard の doc-comment を reconcile

pieces は World pos-store（Cmd.Move-authoritative、hidden-filtered）、map は static-from-scene。boardMatchesScene は将来の resolveCombat board input が満たすべき contract。

### Files

- `src/ecs/World.flix`
- `test/ecs/TestWorld.flix`

### Tests

`test/ecs/TestWorld.flix` を拡張:
- (1) testToBoardEqualsFromScene — players（hidden 含む）+ enemies の scene、world=syncFromScene(scene, empty)。boardMatchesScene true AND `boardKey(toBoard)==boardKey(fromScene)` を assert（明示的な order-independent List 等価）。
- (2) Negative（World-as-authority）: world のみに Cmd.Move を apply（scene stale）→ その mid-frame 点で boardMatchesScene false。
- (3) ONE-SIDED GUARD（non-vacuous）: scene に VISIBLE entity（hidden ではない — hidden は boardPieces@760 と BoardSnapshot.fromScene@32 の両方からフィルタされ、ガードを誤って pass させる）を含め、World pos entry を持たせない（prune/pre-sync をシミュレート）→ boardMatchesScene false を confirm。すなわちヘルパーは id の union 上で symmetric。

### Risks

Very low — 既証明関数上の additive pure ヘルパー。Board は Eq のない type alias → Eq を持つ `boardKey List[(Int,Int,Int,Int)]` を比較。Production behavior 変更なし。prune-asymmetry ガードは non-vacuous であるため VISIBLE entity を使う必要（hidden は両側で除外）。boardKey は各 source を independently に walk するので symmetric-difference カバレッジが成立。

### DependsOn

なし

---

## スライス 3: `simevent-algebra`

**タイトル**: SimEvent algebra + cmdKey（DESIGN SPIKE）: partitioned closed event set、pure reducer、CORRECTED order の SimEvent→Cmd adapter、TOTAL cmdKey、既存 move seam 上での cmd-equal AND emit→replay-timing-equal の証明

### Approach

**REFRAMED DESIGN SPIKE**（settled equivalence contract ではない）。成果物:
- (a) closed で EXPLICITLY-PARTITIONED な event set
- (b) pure reducer + VERIFIED emit order を持つ SimEvent→Cmd ADAPTER
- (c) TOTAL な `cmdKey` projection（golden-trace からここへ MOVED — blocker fix 参照）
- (d) 既出荷の Moved パス上での、cmd-key レベル AND emit→replay timing レベルの両方での証明

このフェーズで production emitter はなし。CombatScene から新 event を emit しない。

**BLOCKER FIX — cmdKey はここに lives**: simevent-algebra のテストは `eventToCmds(...).map(cmdKey)` を assert する。Cmd に Eq がないので cmdKey が唯一の比較通貨。後続の golden-trace スライスでは定義できない。`pub def cmdKey(c: Cmd): (String, Int32, Int32, Int32)` を World.flix にこのスライスの一部として定義する。golden-trace はそれを得るために simevent-algebra に dependsOn する。

**BLOCKER FIX — cmdKey は全 19 Cmd variant 上で TOTAL**（verified enum、World.flix）: `pub def` の total match、variant ごとに 1 arm、(tag, uid, a, b) へ projection:

| Variant | Projection |
|---------|-----------|
| SetHp | ("SetHp", uid, hp, 0) |
| Move | ("Move", uid, x, y) |
| SetProgress | ("Progress", uid, lv, xp) |
| SetAttackTarget | ("AtkTgt", uid, tgt, 0) |
| ClearAttackTarget | ("ClrTgt", uid, 0, 0) |
| SetFollowUpUsed | ("FollowUp", uid, bool01, 0) |
| SetAlerted | ("Alerted", uid, bool01, 0) |
| SetDying | ("Dying", uid, 0, 0) |
| SetBottleUsed | ("Bottle", uid, bool01, 0) |
| SetWaited | ("Waited", uid, bool01, 0) |
| SetPrevPos | ("PrevPos", uid, x, y) |
| ClearImmobilized | ("ClrImmob", uid, 0, 0) |
| Add | ("Add", uid, StatusSystem statusOrdinal(status), 0) — status IDENTITY ordinal で key（小さな statusKindToInt ヘルパーを定義） |
| Seed | ("Seed", uid, 0, 0) — payload は StatusEffects 全体。tag+uid が discriminating key、fixtures が Seed を replay しないので十分 |
| SetPhase | ("Phase", phaseOrdinal(p), 0, 0) |
| TickPlayers | ("TickP", 0, 0, 0) |
| TickEnemies | ("TickE", 0, 0, 0) |
| SetEnemyTurnBusy | ("ETBusy", bool01, 0, 0) |
| SetPhaseObservedEnemy | ("PhObs", bool01, 0, 0) |

uid は EntityRef→uid 経由。Exhaustiveness は `flix check` が強制。

**CRITICAL PARTITION**: legacy Cmd-stream には 2 クラスがある:
- **SIM-AFFECTING**: SetHp, SetProgress, Move
- **CONTROL/LIFECYCLE**: SetAttackTarget@42/117, ClearAttackTarget@48/54, SetFollowUpUsed@205/324, SetAlerted, SetDying...

Phase C で resolveCombat は CONTROL Cmd を `[SimEvent]` と並べて DIRECTLY emit する。これらは event fold の OUT。reducer は SIM-AFFECTING SUBSET にスコープされる。

**VERIFIED PER-CMD COVERAGE**:
- SetHp は attack ごとに multi-emit（Damaged enemy@applyDamageToEnemy → [if killed] Lifesteal player@567 → WeaponLifesteal player@582; enemy Lifesteal@902）。emit order は Damaged→Lifesteal→WeaponLifesteal。
- SetProgress: applyLevelUp は SetHp@997 THEN SetProgress@999 を emit。applyExpGain@975 は kill-WITHOUT-levelup で BARE な SetProgress(level, exp) を emit → 自身の event。
- Move→Moved。
- SetDying は combat から emit されない → Died は VIEW-ONLY。

#### (1) `src/ecs/World.flix` — enum SimEvent を拡張（現在 Moved ~326 のみ）

- **SIM-AFFECTING**:
  - `Damaged(EntityRef, {newHp, dmg})`
  - `Healed(EntityRef, {newHp, amt})`
  - `Lifesteal(EntityRef, {newHp, amt})`
  - `ExpGained({entity, newLevel, newExp})` — bare-:975 用に SetProgress-ONLY へマップ
  - `LeveledUp({entity, newLevel, newExp, newHp, result=LevelSystem.Result})` — Result は view panel 専用
  - Moved を keep
- **VIEW-ONLY umbrella**: `ViewFx(ViewFxKind)` where `pub enum ViewFxKind { case Popup({x,y,text}), Sound(String), Explosion({x,y}), Knockback(EntityRef,{x,y}), Thief({x,y}), Died(EntityRef) }`。Killed は ViewFx として fold（exp はすでに ExpGained/LeveledUp absolutes にあり double-count なし）。

#### (2) `src/ecs/World.flix` — PURE reducer

- `pub def applyEventToWorld(ev, world): World`（applyCmd 経由）:
  - Moved→Cmd.Move
  - Damaged/Healed/Lifesteal→Cmd.SetHp(newHp)
  - ExpGained→Cmd.SetProgress(newLevel, newExp)
  - LeveledUp→Cmd.SetHp(newHp) THEN Cmd.SetProgress(newLevel, newExp)（SetHp FIRST、:997 then :999 にマッチ）
  - ViewFx→identity
- `pub def eventToCmds(ev): List[Cmd]` ADAPTER:
  - LeveledUp=[SetHp(newHp), SetProgress(newLevel, newExp)]
  - ExpGained=[SetProgress(newLevel, newExp)]
  - ViewFx=[]
- `pub def eventEntity(ev): Option[EntityRef]` TOTAL match（SYNTACTIC closure、semantic な Phase-C completeness ではない）。

#### (3) emitter 変更なし

C5 を Document: ViewFx + sim event は既存の finished-signal seam 経由で replay（actionQueue なし）。HONEST SCOPE: これらの foundation は resolveCombat が frozen な INTERLEAVED control+sim ordering を RECONSTRUCT できることを証明しない — それは Phase-C work、golden trace に対して validate される。

#### (4) EMIT→REPLAY TIMING PROOF（move パス上、design-note 要件を closes）

production move seam `EnemyScene.stepEnemyMove(id, target):514` は Cmd.Move を emit し SimEvent.Moved を RETURN する。次に `replayMovedEvent:522` がそれを consume する（`PlayerScene.replayMovedEvent:424` も symmetric）。algebra がその seam であることを証明する: withWorldCommand-recorded ハンドラのもとで、`cmdKey(stepEnemyMove が emit する Cmd) == cmdKey(stepEnemyMove が返す Moved の eventToCmds の単一要素)` を assert、AND `applyEventToWorld(thatMoved, world)` が stepEnemyMove run 後の worldRef と SAME boardKey を yield。これで新 algebra を、C5 を抽象的に assert するのではなく EXISTING emit→replay seam に tie する。

### Files

- `src/ecs/World.flix`
- `test/ecs/TestSimEvent.flix`

### Tests

**NEW `test/ecs/TestSimEvent.flix`**:
- (1) per-variant reducer — Damaged は hpOf==newHp。LeveledUp は progressOf==(newLevel,newExp) AND hpOf==newHp の BOTH。ExpGained は progressOf==(level,newExp) で hp UNCHANGED。Healed/Lifesteal は hp を set。
- (2) ADAPTER ORDER + cmd-equivalence: Moved `eventToCmds(Moved).map(cmdKey)==[cmdKey(Cmd.Move)]` AND `applyEventToWorld(Moved)==applyCmd(Cmd.Move)`（boardKey で）。LeveledUp `eventToCmds(LeveledUp).map(cmdKey)==[cmdKey(SetHp),cmdKey(SetProgress)]` その順序で。
- (3) MOVE-SEAM TIMING（new）: PUBLIC EnemyScene.stepEnemyMove を recording World.Command ハンドラのもとで駆動。recorded Cmd の cmdKey == eventToCmds(returned Moved).map(cmdKey) 単一要素 AND boardKey(applyEventToWorld(Moved, pre)) == boardKey(post-step worldRef) を assert。emit(Cmd) と returned-event adapter が real seam で agree することを証明。
- (4) cmdKey TOTALITY: 19 タグごとに少なくとも 1 つの Cmd を pattern-construct し distinct/expected タグ文字列を assert → flix check が totality を confirm。unused-case 警告なし。
- (5) Exhaustiveness: eventEntity total match がコンパイル。
- (6) ViewFx World-identity（boardKey/hp 不変）を全 ViewFxKind（Died 含む）について。
- Header NOTE: combat sim-subset は golden-trace で LEGACY Cmd-stream に対して cross-check される、ここではない。

### Risks

emitter のない variant は dead code に見える — mitigated: reducer+adapter を fully tested、move-seam timing proof + cmdKey LeveledUp/Moved proof が bridge を real にする。Flix が zero-warning bar を trip する unused-case 警告を emit しないことを verify（Cmd/SimEvent 先例では出ない。full suite run で confirm）。LevelSystem.Result に Eq なし → progress+hp absolutes でテスト。cmdKey は全 19 variant 上で TOTAL（Add は status ordinal で key、Seed/Tick/control は tag-only）— flix check が enforce。主張は「sim-affecting subset にスコープされた design spike」であり「the contract」ではない。legacy cross-check は golden-trace に lives。

### DependsOn

なし

---

## スライス 4: `golden-trace`

**タイトル**: Golden-trace oracle（CORE/PARTIAL）: PUBLIC seam 経由の frozen FULL Cmd-stream + final-World literals、scene-seeded attackTarget、ref-backed harness、level-up AND no-level-up サブ fixture、counter-attack chain

### Approach

resolveCombat が再現すべき決定論的 legacy oracle を build。rng-world（再現性）、board-lock（board parity）、simevent-algebra（cmdKey lives there）を reuse。ハーネスは legacy combat を駆動し、それは Cmd を emit する（SimEvent ではない）→ applyEventToWorld を invoke しない。SimEvent↔Cmd bridge は simevent-algebra で証明済み。

**LABELING**: CORE/PARTIAL oracle — freeze するもの:
- (a) 単一の applyAttackHit/applyEnemyAttackHit の synchronous Cmd-stream
- (b) ORCHESTRATED な onLungeDone→follow-up chain
- (c) COUNTER-attack chain（味方攻撃→反撃→撃破）

Regression lock + legacy-emission freeze であり、全 Phase-C ブランチの full coverage ではない。

**PUBLIC-SEAM DRIVING**: resolveAttack:498/resolveEnemyAttack:706 は pub ではない。TestCombatScene と同様に PUBLIC seam 経由で駆動: applyAttackHit(pub:143)、applyEnemyAttackHit(pub:157)、onLungeDone(pub:170)。

**BLOCKER FIX — attackTarget seeding は SCENE 経由、World ではない**: VERIFIED — applyAttackHit は `d#attackTargetId` を SCENE から読む（CombatScene.flix:150 `enemyId <- d#attackTargetId`、PlayerScene.get 経由）、World ではない。元の「pre-apply Cmd.SetAttackTarget to the world ref」レバーは scene 側 attackTargetId を set しない → applyAttackHit が silently no-op → empty trace。FIX: fixture player SCENE Data を `attackTargetId = Some(enemyId)` で構築（TestCombatScene.flix:31 と完全に同様）、OR CombatScene.setAttackTargetId(:40-43) を call（scene Data を書く）。Symmetric: enemy fixture は applyEnemyAttackHit 用に attackTargetId を得る。non-empty-stream GUARD assertion（recordedCmdKeys が非 []）を ADD し、将来の no-op パスへの regression が vacuously pass せず red になるように。NOTE: applyAttackHit 自体は SetAttackTarget/ClearAttackTarget を emit しない → stream contents を predict しない。GENERATE-THEN-FREEZE。

**BLOCKER FIX — Add 用の two-enemy fixture**: status サブトレースは effectRule enemy（Cmd.Add を emit）を必要とし、一方で level-up player パスは status-free のままでなければならない。TWO enemy を使う: enemyA（effectRule なし、player level-up attack の target）と enemyB（effectRule あり、applyEnemyAttackHit サブトレースの attacker）。cmdKey はすでに Add を status ordinal で key する（simevent-algebra で定義）ので、サブトレース (B) の Add Cmd は cleanly に project される。

#### (1) `test/scenes/TestUnitFixtures.flix` — `withTracedWorld(seed, thunk)` を追加

`seed` で seed された SINGLE region Ref[World]、THREE の協調ハンドラで wire（NEW code、withWorldQuery の reuse ではない。withWorldQuery は STATIC snapshot @531 を取る）:
- World.Command（apply AND cmdKey を recorded list に append）
- NEW ref-backed World.WorldQuery（get が SAME Ref を返すので combatViewOf が this-frame writes を見る）
- World.RngDraw（SAME Ref 上で World.drawPercent 経由 draw）

syncFromScene 経由で seed THROUGH（rng-world の rng=w#rng carry が seed を keep）。withNoopThiefDrop を reuse（rng-world で fixtures に移動済み）。`(result, recordedCmdKeys, finalWorld)` を返す。

#### (2) NEW `test/ecs/TestGoldenTrace.flix` — documented INVARIANTS を持つ fixture

withTracedWorld(SEED) + mocked Tween(noop)/Anim(noop)/Audio/GameLogger/Board/ThiefDropRequest(noop)/Pacing/PhaseQuery のもとで:

**PRE-GUARD（vacuity gap を closes）**: `World.combatViewOf(ref, seedWorld)` が attacker と defender の BOTH で Some であると assert — syncFromScene mirror（baseStats/weaponView/ringBonus）が incomplete だと resolveAttack が scene combatView に fall back し、World-driven trace が vacuously 'equal' になる。これが [COMBATVIEW DIFF] invariant をガード。

- **(A) LEVEL-UP path**: 1 rogue + thief-capable weapon vs adjacent enemyA、exp を pre-set し kill が level threshold を cross（9 growth roll）→ isolated applyAttackHit = 12 draw `[hit, crit, thief, growth×9]`。Scene-seeded attackTargetId=Some(enemyA)。ordered cmdKey list + final-World projection を capture。SetHp@997-then-SetProgress@999 order を assert。
- **(A2) NO-LEVEL-UP path（ExpGained cross-check gap を closes）**: identical fixture だが exp を pre-set し kill が threshold を cross しない → legacy が BARE SetProgress@975 を emit（SetHp なし、growth roll なし）。この stream を freeze。これは ExpGained がマップする REAL legacy emission で、simevent-algebra の ExpGained を live behavior に対して cross-check。
- **(B) ENEMY effectRule サブトレース**: enemyB（effectRule + guaranteed hit）が applyEnemyAttackHit を駆動 → `[hit, crit, effect]` roll stream + Cmd.Add(status); freeze。
- **(C) ORCHESTRATED onLungeDone**: follow-up ブランチを SPEED で pinned OFF（player/enemy speed を set し corrected-speed-diff+3 が fail → follow-up は never fire、roll @203 は依然 in position で消費）。follow-up-roll-in-position + resolvePlayerMainAttack continuation Cmd ordering を capture — Phase C が rewrite する signal-seam boundary。
- **(D) COUNTER-attack chain（motivating-scenario gap を closes）**: sequence onLungeDone → (Outcome.Counter → startEnemyCounter:287) → enemy reattack → applyEnemyAttackHit → enemyLungeDone を public seam 経由で順に駆動、FULL multi-callback Cmd-stream + final World を capture。これは resolveCombat の hardest async path; 'PARTIAL' のもとで unscoped に放置せず explicitly に freeze。counter が DOES fire し決定論的に resolve するよう stats を pin。

Freeze: (a) ordered List[cmdKey]、(b) final-World tuples（hpOf/posOf/progressOf）を golden literals として（initial run で GENERATED し paste、human-verified freeze）。

#### (3) Oracle assertions

- (a) EQUIVALENCE LOCK — full cmdKey stream（control+sim）+ final-World tuples == frozen golden（A/A2/B/C/D）。
- (b) REPRODUCIBILITY — twice run → identical。
- (c) NON-EMPTY guard（fixture ごと、silent no-op なし）。
- (d) FINAL-BOARD（board-lock を使用）: final piece-list literal を freeze AND `boardKey(toBoard(finalWorld, ORIGINAL scene))` == その literal AND `boardMatchesScene(finalWorld, originalScene)`（adjacent attack は piece を動かさない → positions stable; finalWorld から synthesize した scene ではなく INDEPENDENTLY frozen expectation に対して）。
- (e) combatViewOf-Some pre-guard。
- NOTE: Moved↔combat equivalence は simevent-algebra の move-seam timing テストで validate される; この combat fixture は piece を動かさない。

### Files

- `src/ecs/World.flix`
- `test/scenes/TestUnitFixtures.flix`
- `test/ecs/TestGoldenTrace.flix`

### Tests

TestGoldenTrace.flix が verifier:
- (1) frozen full cmdKey-stream equality（control+sim）A/A2/B/C/D。
- (2) frozen final-World tuple equality（independently frozen literals、syncTreeFromWorld-derived ではない → non-vacuous）。
- (3) double-run determinism。
- (4) final-board parity（frozen piece-list literal vs boardKey(toBoard(finalWorld, original scene)) AND boardMatchesScene）。
- (5) orchestrated onLungeDone follow-up-roll-in-position + continuation Cmd-ordering（ブランチ speed で OFF）。
- (6) COUNTER-chain (D) multi-callback Cmd-stream + final World frozen。
- (7) NO-LEVEL-UP (A2) bare-SetProgress stream（ExpGained cross-check）。
- (8) combatViewOf-Some pre-guard + non-empty-stream guard（fixture ごと）。

Green = CORE oracle established + stable。Fixed SEED + seeded PRNG + documented invariants + scene-seeded attackTargetId が literals を legitimate にする。flix check が 3-handler ref-backed harness の type-check を confirm。

### Risks

Highest-surface スライス: applyAttackHit は ~10 effect を pull — 全 mockable だが、ハーネスは ONE worldRef を Command/WorldQuery/RngDraw で share する必要（NEW ref-backed WorldQuery、static withWorldQuery snapshot ではない）、さもないと combatViewOf read-after-write が壊れる。attackTargetId を SCENE で seed する必要（World ではない）、さもないと applyAttackHit no-op → empty trace（non-empty guard が catch）。Golden literals は run-derived: generate then paste。Two-enemy fixture が Add をサブトレース (B) に isolate; cmdKey は Add を status ordinal で key。combatViewOf-Some pre-guard が vacuous scene-fallback equality を防ぐ。Counter-chain (D) は multi-callback — fire するよう stats を pin して決定論的に。重すぎる場合は A/A2/B/C を先に land し D を後で追加、スライスを incrementally に green に保つ。PARTIAL oracle — 全 Phase-C ブランチをカバーしない; DoD に記載。emit-flip（syncFromScene の per-frame hp/status overwrite 除去）はここで delivered されない — DoD に remaining Phase-C prereq として記載。

### DependsOn

- `rng-world`
- `board-lock`
- `simevent-algebra`

---

## Definition of Done（DoD）

全 4 スライスが、`export GITHUB_TOKEN="$(gh auth token)" && ../../bin/flix test` green（>=918 baseline + new tests、0 fail）かつ `../../bin/flix check` clean、NO new warnings でマージされる。

**(1) RNG** は単一の `World.RngDraw` effect を通る（PRNG `mod Prng`/`Prng.State`、`Rng`-prefix 衝突なし; splitmix64 は経験的 `>>>` probe が sign-fill を示す場合に限り MASKED logical right shift を使う; golden literals は compiled impl から regenerate、ただし Int64-wrap/shift expectation のみは INDEPENDENTLY 導出され shift-correctness テストが self-confirming でない）。Live combat は BODY-IDENTITY により numerically UNCHANGED — live ハンドラ本体は今日の rollPercent 本体と character-identical（Math.Random は start():~736 でスコープ内）; world.rng は live パス上 DORMANT/test-only。FrameAef.ProcessT が World.RngDraw を得て Game.flix:177/179 checked_ecast widening が依然コンパイル（FrameAef.T は untouched）。withMockRandom を EXTEND し World.RngDraw=k(50) を discharge、既存 8 TestCombatScene サイトを green に keep; withNoopThiefDrop を TestUnitFixtures に移し両呼び出しサイト（TestCombatScene:93,364）を更新。seeded PRNG は World に lives、両 sync パスで VERBATIM carry（multi-frame carry テスト）。Roll-sequence equivalence は COUNT+ORDER で証明（12 draw hit→crit→thief→growth×9、stat-position 仮定なし; rollGrowth records/thief-arg の intra-expression left-to-right eval-order 依存は明示され call-path-shared なので seeded==live）、plus hit→crit→effect と orchestrated follow-up draw-in-position。9 つの非 combat Math.Random サイトは Math.Random のまま。

**(2)** World.toBoard が boardMatchesScene で pin される（positive + World-authority negative + VISIBLE-entity prune-asymmetry guard）、Phase C board contract として documented。

**(3)** SimEvent は closed で EXPLICITLY-PARTITIONED set: sim-affecting subset（Moved/Damaged/Healed/Lifesteal/ExpGained-SetProgress-only/LeveledUp-with-absolute-newLevel/newExp/newHp）が pure applyEventToWorld reducer + eventToCmds adapter を持ち、その LeveledUp order は CORRECTED な [SetHp, SetProgress]（legacy :997 then :999 にマッチ）、ExpGained は bare-:975 no-levelup SetProgress をカバー; level-up seam 上で cmd-equal AND EXISTING stepEnemyMove/replayMovedEvent move seam 上で emit→replay-TIMING-equal を証明（C5 move-path 要件を closes）; multiple-SetHp-per-attack order（Damaged→Lifesteal→WeaponLifesteal）を documented; 単一の ViewFx umbrella（Died 含む）が view-only effect をカバー; control Cmd（SetAttackTarget/ClearAttackTarget/SetFollowUpUsed/SetAlerted）と SetDying は fold の OUT として documented; Killed は exp delta を carry しない。全 19 Cmd variant 上の TOTAL `cmdKey`（Add は status ordinal で key、Seed/Tick/control は tag-only）がここ（golden-trace ではない）で定義され Cmd-no-Eq 比較がコンパイルする。production emitter のない DESIGN SPIKE として label; interleaving reconstruction は Phase-C work で golden trace に対して validate される、ここで証明されない。

**(4)** fixed-seed golden-trace CORE oracle が、PUBLIC seam 経由（attackTargetId を SCENE で seed して applyAttackHit が no-op しない; non-empty-stream guard + combatViewOf-Some pre-guard が vacuous pass を防ぐ）で駆動され、FULL legacy Cmd-stream（control+sim、cmdKey 経由）+ final-World literals（independently frozen、syncTreeFromWorld-derived ではない）を FIVE の documented fixture 上で freeze: (A) level-up 12-draw path、(A2) no-level-up bare-SetProgress path（ExpGained を live emission に対して cross-check）、(B) two-enemy effectRule サブトレース（Cmd.Add は status ordinal で key）、(C) orchestrated onLungeDone follow-up-roll-in-position（ブランチ speed で OFF）、(D) COUNTER-attack chain（味方攻撃→反撃→撃破、motivating Phase-C scenario）。NEW ref-backed 3-handler harness（Command + ref-backed WorldQuery + RngDraw、ONE worldRef 上）を使い、double-run deterministic、frozen-board parity を boardKey(toBoard(finalWorld, original scene)) AND boardMatchesScene で assert。explicitly に PARTIAL oracle（synchronous seam + follow-up + counter chain）、full Phase-C coverage ではない。

**REMAINING Phase-C prereq（ここで delivered されない、honesty のため記載）**: emit-flip — syncFromScene の per-frame statuses/hp overwrite 除去 — は resolveCombat の返す (World, [SimEvent]) が次フレームを生き延びる前に land する必要がある; rng-world は rng=w#rng 経由で rng のみ persist する。Phase C（resolveCombat → (World, [SimEvent]) + ViewReplay）はこれら 4 つの foundation に対して開始でき、その [SimEvent] output を eventToCmds（corrected LeveledUp order + ExpGained）経由で frozen legacy Cmd-stream と比較する。
