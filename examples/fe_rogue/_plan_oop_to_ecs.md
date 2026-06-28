# OOP→ECS System 移行計画（v4・レビュー90+確定）— scene のロジック根絶・OOP node-callback 脱却

> **採点推移: v1(70/72) → v2(86) → v3(90) → v4**。v3→v4 で残り2 nit を hardening（comfortably 90+）:
> ・taxonomy に**第3カテゴリ persistence/lifecycle I/O**（Suspend/Resume・実は7 effects）を追加。
> ・目標フレームの `stepWorld(world, intents)` から `uiState` を外し、**「sim へは intent しか渡らない（inputMode が逆流しない）」を型レベルで保証**（uiState 遷移は `nextUiState` の純導出に分離）。
>
> v2→v3 で解消した3点（レビュー指摘）:
> ① **検証 oracle を2分割**（per-frame byte-equal は inversion 後に論理矛盾ゆえ F0-3 のみ／F4+ は「sim 決定論＝ターン末 World+event-log 等価」＋「view 忠実度」）。
> ② **heavy System の event/command を全分類**（6 CustomEffects＋exp/counter/staff を World 変更 or VIEW event に割付＝F4/F6 の真の scope）。
> ③ **19-phase を3軸（turnPhase/inputMode/anim-queue）に全写像**（hybrid 明示・inputMode は sim へ逆流しない）。
>
> v1→v2 の核心修正（維持）: **sim-event-log + animation-queue による「コルーチン→即時 System」の反転**（frame-paced 制御の脱却・F8 到達の鍵）／**全 sim state→World を非交渉の目標として最初に宣言**／**3層(World/UiState/Scene)明示**。

## ゴール
scene を「**ロジックの担い手**」から根絶。UI はツリー構造で持つが **ECS が駆動**。
`process`/`physicsProcess`/`onKeyPress` の OOP node-lifecycle callback でロジックを回す考えから脱却し、ロジックは **System(`World -> World`)** が回す。

## 非交渉の不変条件（＝ゴールの定義・最初に宣言）
- **全シミュレーション状態は World に置く**（位置・hp・stats/weapon・statuses・turn-phase・waited/alerted/isDying/attackTargetId・queue・selection・drafts）。
  → read-model 戦略（stats を scene 権威）の**反転は"後回しの要相談"ではなく目標そのもの**。各 flip は段階的でも、**到達点は "maybe" にしない**。
  （理由: stats が scene 権威の間は全 System が `(World,Scene)->(World,Scene)` の scene-threading 移送に留まり、World->World System にならない＝レビュー指摘の最大欠陥。）
- **Scene = `(World, UiState)` の純粋な派生 render**。simulation は scene を読まない/書かない。
- **simulation は frame-paced でない**（下記 sim-event-log/animation-queue で時間を VIEW 側に逃がす）。

## 3層アーキテクチャ（World / UiState / Scene）
| 層 | 持つもの | 例 |
|---|---|---|
| **World**（sim 権威） | ゲームルールに効く全状態 | positions・hp・stats・statuses・**turnPhase(sim)**・waited/alerted/isDying/attackTargetId・enemy queue・**selection**・move drafts |
| **UiState**（一時的 view-nav） | ルールに効かない表示ナビ状態 | cursor の holdDir/holdSteps・**modalMode(メニュー遷移)**・camera pan target・danger-zone トグル |
| **Scene**（純 render） | World+UiState を描くツリー | sprite/label/panel/minimap/fog… = 純 render（書き戻さない） |

- **Phase 分割**: 現 **19-case** `TurnPhase.Phase`（TurnPhase.flix:41-129）は sim phase・入力モード・演出待ちを混在。下記「Phase 全写像」で3軸に分解する。

## 核心: sim-event-log + animation-queue（frame-paced 制御の反転）
**問題**（両レビュー一致・v1 の致命的見落とし）: 敵ターン/戦闘は「1ステップ進めて Tween/カメラ/anim 完了を N フレーム待つ」**コルーチン**。
`CombatScene.process` は HP を `attack:hit` anim signal が鳴った時に適用（CombatScene.flix:444-457）。`EnemyTurnDriver.stepOnce` は `Pacing.State.isHolding`/`CameraScene.isSettled`/`Tween.isActive`/`anyAttacking` で 5 重 gate（:176-190）。純 `World->World` では「1歩進めて待つ」を表現できない。

**反転**: 
1. **System は World を即時に完走**させる（1ターン分のロジックを一気に）。副産物として **sim-event-log**（`Moved{id,from,to}`・`Hit{atk,def,dmg}`・`Died{id}`・`LevelUp{id}`…）を吐く。
2. **VIEW（render 層）が event-log から animation-queue を作り、フレーム跨ぎで再生**（Tween/anim/カメラ/Pacing は全部こちら）。
3. ゆえに **simulation は frame-paced 制御から解放**され純 `World->World`、**待ち・演出は VIEW の render-only ループ**に。

これにより「callback を render-only にできる」＝ **F8（OOP dispatch 撤去）が到達可能**になる（反転なしでは到達不能、というのが両レビューの結論）。

## Phase 全写像（19-case を 3 軸に分解・レビュー3）
混在した `TurnPhase.Phase` を **World.turnPhase（sim・誰のターンか）／UiState.inputMode（入力の解釈モード）／VIEW anim-queue（演出待ち）** に分ける。
`inputMode` は「入力をどの intent に写すか」を決めるだけ＝**view 側**で、sim へは intent しか渡らない（逆流しない）。演出待ち系は sim では即時完了し VIEW の anim-queue 状態になる。

| 現 Phase | World.turnPhase | UiState.inputMode | VIEW anim-queue | 備考 |
|---|---|---|---|---|
| PlayerCursor | PlayerTurn | FreeCursor | — | カーソル nav=UiState |
| PlayerMoving | PlayerTurn | MovingUnit | — | 移動 intent 産出 |
| GatherMove | PlayerTurn | GatherMoving | — | hybrid: 移動 intent（lord+追従） |
| PlayerAttack | PlayerTurn | TargetingAttack | — | 赤マス選択→attack intent |
| AttackForecast | PlayerTurn | Modal(Forecast) | — | 確定で attack intent |
| StaffAim / ThrowAim | PlayerTurn | Aiming(Staff/Throw,idx) | — | 方向→cast/throw intent |
| ActionSelect / WeaponSelect / ItemSelect / ItemActionSelect | PlayerTurn | Modal(該当メニュー) | — | メニュー nav→confirm intent |
| TradeTargetSelect / TradeInventory | PlayerTurn | Modal(Trade*) | — | 交換 intent |
| SuspendConfirm | PlayerTurn(休止) | Modal(Suspend) | — | confirm→suspend intent |
| PlayerAttackHold | PlayerTurn | (入力無効) | AttackLunge+DeathBlink 再生中 | **演出待ち＝anim-queue**。sim は即解決済 |
| LevelUpView | PlayerTurn | Modal(LevelUp) | LevelUp パネル | sim は exp/level 即適用済・表示待ち |
| StairsExit | PlayerTurn | (入力無効) | 退場行進 再生中 | **演出待ち**。退場は sim 即解決・歩行は anim |
| EnemyTurn | EnemyTurn | (入力無効) | 敵行動 再生中 | sim は1ターン即解決・1歩ずつは anim |
| GameOver | GameOver | Modal(GameOverMenu) | — | 盤面フリーズ＝render 状態 |

→ 旧「Resolving/Hold/auto-advance」phase は **sim-phase でなく VIEW の anim-queue 状態**に落ちる（inversion の帰結）。入力は anim-queue 非空の間 view が gate（「busy」を返す）＝旧 Pacing/Tween 待ちの置換。

## heavy System の event/command 分類（レビュー2）
heavy subsystem（移動/敵ターン/戦闘/階段/lifecycle）が出すものを **World 変更（System が即適用）** と **VIEW event（anim-queue が再生）** に分類。現 **7 CustomEffects**（FloorAdvance/GameOver/WandererSpawn/RingTransform/ThiefDrop ＋ **Suspend/Resume**）も含め全件を割り付ける。うち Suspend/Resume は**第3カテゴリ＝persistence/lifecycle I/O**（World 変更でも VIEW event でもなく、F1 の intent seam で発火するセーブ I/O・敵ターン/戦闘からは来ない）。

| 由来 | World 変更（即時） | VIEW event（演出） |
|---|---|---|
| 移動 | `Cmd.Move`（既存） | `MovedAnim{id,from,to}`（Tween 滑走） |
| 攻撃 hit | hp 減算・武器耐久・lifesteal・status | `AttackLungeAnim`・`HitAnim{def,dmg}`・`DamagePopup` |
| 死亡 | unit 除去（World） | `DeathBlinkAnim{id}` |
| ノックバック | `Cmd.Move`（弾き先） | `MovedAnim`（弾き） |
| 経験値/Lv | exp 加算・stat 成長 | `LevelUpPanelAnim{id}` |
| カウンター | 上記 hit と同型 | 同上 |
| 杖/投擲 | status/位置（既存 emit 経路） | 杖 vfx・命中 anim |
| 階段退場 | unit を hidden/除去（World） | `StairsWalkAnim`・退場 |
| 床移動(`FloorAdvanceRequest`) | World: floor 進行・新ユニット spawn（`Cmd.Move` seed） | `FloorChangeAnim`／scene を新 World から render |
| 全滅(`GameOverRequest`) | World.turnPhase=GameOver | 盤面フリーズ render |
| 徘徊湧き(`WandererSpawnRequest`) | World: spawn（`Cmd.Move` seed） | 出現 anim |
| 指輪変化(`RingTransformRequest`) | World: item→ring 変換 | 変化 anim |
| 盗人ドロップ(`ThiefDropRequest`) | World: item drop | ドロップ anim |
| 中断/再開(`Suspend/ResumeRequest`) | （第3カテゴリ＝persistence I/O・F1 intent で発火・セーブ読み書き） | — |

→ 現「CustomEffects 要求 → GameLifecycle handler が scene 再構築」は、**System が World を遷移させ、render が新 World から scene を導出**する形に置換（scene 再構築＝render 関心）。この taxonomy が F4/F6 の本当の scope（7 CustomEffects＋exp/counter/staff を取りこぼさない）。

## 目標フレーム
```
gameLoop(world, uiState, scene):
  intents  = readInput(uiState)                 // 入力 = intent(data)。scene を mutate しない
  (world', events) = stepWorld(world, intents)  // ★sim 変更コアは world × intents だけを読む（uiState 不可視）
                                                 //   = 「sim へは intent しか渡らない」を署名で保証。Systems 即時完走・event-log を返す
  uiState' = nextUiState(uiState, intents, events) // inputMode 遷移（メニュー開閉等）は別の純導出（view 側）
  animQ    = viewAnimQueue.ingest(events)        // events → 再生キュー（VIEW 状態）
  scene'   = renderTree(world', uiState', animQ, scene)
                                                 // 純 render: syncTreeFromWorld + UI scenes + anim 再生
  render(scene'); gameLoop(world', uiState', scene')
```
（`stepWorld` の引数から `uiState` を外したのが肝: World 変更パスは `uiState` を**型レベルで読めない**＝inputMode が sim に逆流し得ない。uiState の遷移は `nextUiState` の純導出に分離。）
- **simulation node-callback（EnemyTurnDriver/Combat/PlayerMovement/StairsExit の process/physicsStep）→ 空**（ロジックは Systems、演出は animQ 再生）。
- **UI node-callback → `(World,UiState)` の純 render**。

## 移行順序（strangler-fig・各 F は緑/run/挙動不変/レビュー90+/§G 更新）
- **✅ F0 足場（実装済・886緑・挙動不変）**: `World.stepWorld(world)`（System パイプライン段）を追加し gameLoop の `refreshMirror`→`syncTreeFromWorld` 間に `world2=stepWorld(world1)` 配線。現状 System は inert な `tickStatusEffects`（pos 不変＝`testStepWorldPreservesPositions` で pin・live StatusQuery reader 無し＋次フレーム refreshMirror が上書き＝観測されず）。以後の System はここに足す。
- **✅ F1 入力→intent seam（実装済・886緑・挙動不変）**: `ActionMenuScene` に `ActionIntent`（純データ）＋`actionIntentOf`（決定＝純関数）＋`applyActionIntent`（適用＝単一 dispatcher）を追加し、"wait" を `onActionConfirmed` の直接ロジック呼びから **decide→apply の seam** に通した（残アクションは既存 if-else にフォールバック＝strangler-fig）。既存テスト「waitMeta 確定で waited=true」が新経路を通って緑＝挙動不変。現状は dispatcher を確定点で inline 適用＝**decide/apply 分離の seed**。「入力が `List[Intent]` を返し System が pipeline で消費」の完全形は MenuHandler 署名変更/intent queue が要るので F2(UiState) 以降で成熟させる。
- **F2 turn FSM を World に（a/b/c 分割・最高 cascade）**:
  - **✅ F2a（実装済・888緑・挙動不変）**: World に `SimPhase`(3-case)＋`turnPhase` field、境界 `simPhaseOf`(19→3 写像)、gameLoop で毎フレーム mirror＋並走 assert `[F2 PHASE DIFF]`（mirror ゆえ F2a は無音・F2b の write 漏れ検出 seam）。turnPhase は read-model（読み手は assert のみ）・refreshMirror が保持。循環依存(TurnPhase→World)回避のため World は中立な 3-case を持ち 19→3 は境界で写像。
  - **✅ F2b（実装済・889緑・挙動不変・要 run）**: `Cmd.SetPhase(SimPhase)` 追加。**全 41 put サイトを per-site でなく `TurnPhase.State` handler 1 箇所で被覆** — Game.start で handler を inline 化し `put` が `turnPhaseRef` と `worldRef.turnPhase`（`Cmd.SetPhase`）を dual-write。gameLoop の frame-end mirror を撤去し World.turnPhase を command 由来に。`[F2 PHASE DIFF]` assert が乖離検出（dual-write ゆえ無音・run で確認）。phase 権威は当面 TurnPhase.State（read は F2c で flip）。
  - **🔶 F2c（着手・最初の reader flip 実装済・890緑・run 合格）**: `World.PhaseQuery { def phase(): SimPhase }` effect 追加＋Game.start に `worldRef` 由来 handler 設置（StatusQuery と同型）。最初の読み手 `CombatScene.playerLungeDone:214` を `TurnPhase.State.get() == EnemyTurn` → **`World.PhaseQuery.phase() == SimPhase.EnemyTurn`** に flip（cascade: `onLungeDone`/`drainAndDispatch`/`process`/`FrameAef.ProcessT`/Game frame-body へ伝播）。退行検知ピン `testLungeDoneBranchesOnWorldPhaseNotTurnState`（TurnPhase=非敵ターン・World=敵ターンで敵ターン分岐を取ることを固定）＋`TestUnitFixtures.withWorldPhase` discharger 追加。**ここで初めて「読み」が World 由来に**＝挙動不変でない段ゆえ run 検証実施（`[F2 PHASE DIFF]` 無音・敵ターン反撃挙動 従来通り＝合格）。続けて `GameOverMenuScene.refreshItems` も純 3-case（`== GameOver` のみ）ゆえ flip＝TurnPhase.State 依存を丸ごと World.PhaseQuery に置換（890緑）。

  **🔑 構造的発見（残り reader flip は UiState.modalMode 待ち）**: 全 phase 読み手（~30）を精査した結果、`== EnemyTurn`/`== GameOver` を**単独で**判定する純 3-case 読み手は CombatScene/GameOverMenu の **2 つだけ**（両方 flip 済）。残りはほぼ全て **mixed**＝EnemyTurn 判定と同時に `LevelUpView`/`PlayerCursor`/`PlayerAttackHold`/`PlayerMoving` 等の **sub-sim phase**（同じ PlayerTurn-sim 内の細分・モーダル割り込み）も判定している（例: MinimapScene/TopBarScene は EnemyTurn と LevelUpView を併読、CameraScene/CursorScene/EnemyTurnDriver は PlayerCursor 等を併読）。これらを部分 flip すると 1 scene が PhaseQuery と TurnPhase.State の**二系統依存**になり依存面が減らない（むしろ増える）＝churn 損。**正しい順序は「先に `UiState.modalMode`（LevelUpView/SuspendConfirm/各メニュー phase を吸収）を導入 → sub-sim phase が TurnPhase.Phase から抜ける → 残った読み手が純 3-case になって初めて flip」**。

  **🟢 F2c 機能達成と判断・UiState は defer（2026-06-28 決定）**: 19-case を sim/view 分類した結果、`TurnPhase.Phase` の中身は **3 系統**＝(a) sim 権威=EnemyTurn/GameOver（World へ移行済）(b) inputMode=PlayerCursor/PlayerMoving/PlayerAttack/GatherMove/aim 系（「入力→intent 写像」＝view）(c) modal stack=各メニュー/AttackForecast/LevelUpView/SuspendConfirm（confirm まで sim 不変＝view）＋VIEW busy=PlayerAttackHold/StairsExit。**World 権威化という F2c の目的は機能的に達成済**（World.turnPhase は command 由来 3-case・dual-write 検証済・純 3-case 読み手 2 つ flip 済）。残る `UiState.modalMode` は実質 `TurnPhase.Phase`(16 player-modal cases) の view 側 reclassify 大改修で、~30 読み手＋TurnRules を巻き込む割に **OOP 脱却の本筋を直接進めない**（payoff は概念分離のみ）。よって **UiState.modalMode は F3 後 or 並行へ defer**し、本筋の heavy 着手 = **F3（移動→System）へ先行**（ユーザー決定）。
- **F-clock（heavy 着手前・反転の確立）**: sim-event-log と animation-queue の骨組みを入れ、**最小例＝移動**で実証（`Cmd.Move` は既存・`Moved` event を VIEW が Tween 再生）。これで以後の heavy subsystem が「即時 System＋event 再生」型を踏める。
- **F3 移動を System に**（**敵ターンより先＝最安全**。position は既に `Cmd.Move` 権威・decision(`Board.tryMoveWithRange`)純粋・`gatherStep.now` は既に World 読み）: `physicsStep`/`gatherStep` → `stepPlayerMove`。Tween は event 再生へ。
  - **✅ F3a（実装済・890緑・挙動不変）**: `PlayerScene.moveToById` を sim/view 分離。`moveToById` = (SYSTEM) `Cmd.Move` emit ＋ (VIEW) `replayMoveView`（新 def: Tween 滑走/facing/walk-anim/flip ＝ `World.Command` 非要求の純 view 再生）。`Cmd.Move` を Tween 前へ移動したが両者独立 effect・`getGridPos` は frame-end まで pre-move 値ゆえ順序不変。`replayMoveView` は F3b で `SimEvent.Moved` 消費側が呼ぶ再生エントリ。
  - **✅ F3b（実装済・893緑・挙動不変）**: `World.SimEvent.Moved(EntityRef, target)` 導入（F-clock の最小骨組み）。`PlayerMovementScene.stepPlayerMove(id,fromPos,dir,board,allowed): Option[SimEvent] \ World.Command`＝**SYSTEM(sim)**: `Board.tryMoveWithRange` で合法判定→合法なら `Cmd.Move` emit＋`Moved` 返却。`PlayerScene.replayMovedEvent(event,...)`＝**VIEW(replay)**: Moved を `replayMoveView` で Tween/anim 再生（敵 Moved は F4 で）。`stepFor` を `readHeldDirection()→stepPlayerMove→replayMovedEvent+autoPickup` に rewire。**同 dispatch 内 emit→replay＝timing 据え置き**で、operations は旧 `moveToById`（=Cmd.Move+replayMoveView）と同一順＝挙動不変。System を単体テスト3本で固定（合法=emit+Moved / 敵占有=None・no-emit / range 外=None・no-emit）。gather 経路は従来通り `moveToById` 直呼び（同じ Cmd.Move+replayMoveView）。run は低リスク insurance（要すれば移動確認のみ）。
  - **🛑 F3c は F8 へ defer（2026-06-28 決定・フレーム順序の発見）**: パイプラインは `physicsProcess`(move) → `process`(minimap/fog 等の board 読み) → `refreshMirror` → `stepWorld`(System slot) → `syncTreeFromWorld` の順。`Cmd.Move` は physicsProcess（process より前）で worldRef に入るので **同フレームの process パスは移動後位置を mid-frame で読む**（P0a currency）。move を本来の System slot（stepWorld・process より後）へ移すと process パスの board 読み手に **1 フレーム遅延**が出る＝**byte-invariant でない**。これが F3c の核心リスクで単一ノード harness では捕まらない。move のロジックは既に `stepPlayerMove` で System 化済みゆえ、dispatch relocation（F3c/F8）は**全ロジック抽出後に full harness 付きで holistic に F8 で一括**実施する方が、順序問題を一度で片付けられて安全。**当面はフレーム位置を動かさず invariant な System 抽出を継続**（payoff＝testability、リスク＝ゼロ）。
- **F4 敵ターン AI を System に**: `EnemyAI.decideAction`（既に純粋）を `stepEnemyTurn(world)->（world,events）` に。queue を World component 化。Pacing/カメラ待ちは animQ 側へ。callback を空に。
  - **✅ F4a-move（実装済・894緑・挙動不変）**: 敵の 1 歩移動をプレイヤーと同じ `SimEvent.Moved` seam へ統一（「二重 move 経路」smell 解消）。`EnemyScene.moveTo` = `replayMovedEvent(stepEnemyMove(id,target), map, scene)`。`stepEnemyMove(id,target): SimEvent \ World.Command`＝SYSTEM（Cmd.Move emit＋Moved 返却・合法性は EnemyAI 決定済みゆえ board 再判定なし）。`EnemyScene.replayMovedEvent`＝VIEW（敵分のみ Tween/flip/prevPos 再生・faction ごとに自分の event を再生）。全 moveTo 呼び元は不変（内部 split＝F3a 流）。System を単体テスト1本で固定。**残 F4**: 敵ターン全体の inversion（queue→World・1フレーム化＝timing＝O2 harness 要）。Move 以外（Attack 体当たり/staff/throw/wander 演出待ち）は anim-queue 設計後。
  - **✅ F4b-order（実装済・900緑・挙動不変）**: `beginTurn` 内 inline だった**敵ターン行動順決定**（プレイヤー距離場ソート）を純関数 `orderedSteps(Option[Board], actives): List[Step]` へ抽出（None=placements 空で id 順 fallback・lazy board build を `Option` で忠実保存）。テスト2本（None→id 順 / Some→距離が id を上書き）。未テストだった turn-ordering を scaffolding ほぼゼロで pin＝ECS testability payoff の実例。
- **🔎 安全抽出の在庫評価（2026-06-28）**: F5 を見たところ `decideStep`/`eligibleExiters`/`exitQueue` は**既に純粋抽出済み**。EnemyAI.decideAction 含め本コードベースは純粋「決定」を既によく抽出済みで、残る OOP 絡みは主に**オーケストレーション（queue stepping・frame 進行）＝timing 反転**＝harness 要。**「ただ取り出すだけ」の安全スライスはほぼ消化**。残りの主戦場は (A) timing 反転（F4 敵ターン/F5 階段/F3c dispatch＝harness+run 要）、(B) sim-state→World 反転（F6 hp/F7 waited 等＝P0a→S5 パターンで invariant 化可だが hp は read-model 反転で要承認）。
- **F5 階段退場を System に**: `StairsExit` → `stepStairsExit`（queue/距離場は純粋・退場演出は events）。
- **F6 戦闘を System に（read-model 反転がここで顕在化）**: hp/weapon/stats を World 権威化 → `Combat` の純解決（`Combat.estimate`/`resolveStrike` は既に純粋）を `stepCombat(world)->（world,events）` に。`attack:hit` 待ちは `Hit`/`Died` event の再生へ。
  - **🔗 F4⟹F6 結合の発見（2026-06-28）**: F4（敵ターン1フレーム化）は **hp→World 権威化が前提**と判明。敵ターン System が1フレームで全 step を解くと、enemy A の攻撃ダメージを enemy B の決定**前**に反映する必要があり、`EnemyAI.decideAction` の標的選択は hp を読む（仕留め/低HP優先）ので、**System が各 step でダメージを World に inline 反映**しないと逐次決定が狂う。現状の多フレーム駆動は attack:hit（アニメ中点）でダメージ適用→次フレーム決定なので hp が scene でも成立。1フレーム化には hp 権威=World が必須。よって **F4 の実体は hp→World（F6 先行）**。ユーザー承認済（invariant-first）。
  - **✅ F6a-slice0（実装済・901緑・挙動不変）**: World に `Cmd.SetHp(EntityRef, Int32)` + applyCmd（playerHp/enemyHp Map 更新）+ `hpOf(ref, world)` アクセサを追加。テスト `testSetHpCommandUpdatesWorldHp`。hp は既に read-model mirror（syncFromScene/refreshMirror）ゆえ、この Cmd は当面**冗長＝完全 invariant**。
  - **🔶 F6a-slice1（実装済・901緑・挙動不変）**: **コア戦闘ダメージ 2 サイト**を `Cmd.SetHp` dual-write に instrument＝(a) `CombatScene.applyHit`（敵被弾・両分岐とも `plan#newHp`）(b) `CombatScene.resolveEnemyAttack`（味方被弾・`outcome#newHp`）。両関数とも既に `World.Command` 持ち＝cascade なし。F4 の標的選択（敵 AI が hp を読む）に最も効くダメージ反映を先に World へ。refreshMirror が hp を re-mirror する間は冗長＝完全 invariant。
  - **🔶 F6a-slice2（実装済・901緑・挙動不変）**: hp 書込 funnel `PlayerScene.setHp`/`EnemyScene.setHp`（`Cmd.SetHp` emit＋`mapPlayer/mapEnemy(hp=…)`）を新設。**直呼び lifesteal 4 サイト**（`applyPlayerLifesteal`/`applyPlayerWeaponLifesteal`/`applyEnemyLifesteal`/`applyEnemyWeaponLifesteal`）を funnel 経由に route。cascade（4 関数に World.Command 付与）は呼び元（combat resolution）が既に World.Command 持ちで解消。
  - **🧱 構造的発見: PlanHandlers の effect-uniform 壁**: `EffectRunner.PlanHandlers[s, ef]` は **全 handler field が同一 effect ef を共有**する型で、Flix は **pure handler（status/damage/…）を `World.Command` slot へ widen 不可**（「関数値 widen 不可」）。ゆえに **effect-runner 経由の hp 書込**（`CombatScene.effectHeal`/`effectFullHeal`＝杖/効果由来の heal・撃破ドロップ等／StaffCast 側も同型と推定）は funnel route 不可。これらは当面 scene-only（refreshMirror re-mirror で invariant）。**対応案（後続）**: (a) PlanHandlers の ef を `World.Command` 固定にし pure handler 側に no-op emit を許す形へ EffectRunner を改修、(b) heal を plan の戻り（どの id が何 hp になったか）として runPlan 後にまとめて `Cmd.SetHp` emit、(c) `checked_ecast` で widen。要設計。
  - **🔶 F6a-slice3（実装済・901緑・挙動不変）**: 直書き hp サイトを一括 funnel route＝StaffCast 直書き 6（`applyHealToPlayer`/`applyDamageToPlayer`/魔法ダメージ 4）＋ ring 再生 `mendOnePlayer`/`mendOneEnemy`（cascade: regenOnePlayer/Enemy→applyRingRegen に World.Command 付与・呼び元の turn loop が既持ちで解消）。テスト 1 本に `dischargeWorldCommand` 追加。**累計 ~14 hp サイトが World dual-write**（combat damage 2＋lifesteal 4＋staff direct 6＋ring regen 2）。
  - **🧱 PlanHandlers 壁の範囲確定**: effect-runner（`PlanHandlers[s,{}]`）経由の hp 書込は **combat effect（effectHeal/effectFullHeal 4）＋ consumable（applyConsumableHeal/FullHeal/MaxHpUp 3）＋ staff throw（healUnit/fullHealUnit/maxHpUpUnit 6）＝計 13** で、全て pure-handler-widen 不可ゆえ funnel route 不可（scene-only のまま・refreshMirror で invariant）。**F6b 前にこの壁を設計解決必須**（案: PlanHandlers の ef を World.Command 固定に EffectRunner 改修／heal を plan 戻り値化して runPlan 後に一括 emit）。
  - **🚧 F6a 残**: PlanHandlers 壁 13（要設計）＋ restore/snapshot/levelUp/death の複合書込（PlayerScene 755/1024/1059/1155・EnemyScene 577/648 ＝ ~6・単独 emit・restore 関数の cascade 注意）。⚠ restore は F6b（refreshMirror preserve）の前提＝全網羅必須。
  - **📝 abstraction 検討の結論（2026-06-28・shelved）**: 「World の faction-split Map 直操作を engine_ecs アクセサに置換」案を設計＋敵対レビュー2役で評価→**見送り**。(1) `Store`/`SplitStore` ラッパ module は stdlib `Map`（既に key-generic）の 1:1 rename＝ceremony。(2) **unified `Map[EntityRef,v]` 化**（Bevy 流・キーが faction 内包・`EntityRef derive Order` で boardPieces byte 一致・`engine_ecs Query` を `[k:Order]` 一般化は後方互換）は構造的に正しく **F7 着手直前にやると最安**（component ごと split ペア＋match 税を断つ）が、即時の書き味改善は小（match 減 −1〜−2・faction は sync 境界へ移動）。hp 30 サイトは公開シーム `Cmd.SetHp(ref,_)` が faction 非依存ゆえ先に F6 を進めても unified 化コスト不変。→ **F6 継続を優先・unified-key は F7 直前の専用スライス候補として保留**。
  - **✅ F6a 完全網羅 ＋ F6b（実装済・901緑・run 無音確認）**: 全 hp 書込（damage/heal/staff/regen/effect-runner via `emitHpSets` 境界 emit/restore/death/levelUp/**spawn funnel**）が `Cmd.SetHp` を dual-write。`[F6 HP DIFF]` 検証器（`World.hpMismatches`・refreshMirror 前に worldRef hp vs scene hp）を gameLoop に設置＝実機 run で**無音確認**（spawn 穴も addOnePlayer/addOneEnemy の hp seed で塞いだ）。→ **F6b**: `refreshMirror` を hp **command-preserve＋prune**化（位置と同型）＝**hp は World 権威**に。検証器無音ゆえ World hp==scene hp で挙動不変。テスト `testRefreshMirrorPreservesCommandHp`。`!>` tap で境界を一行化。**位置・phase に続き hp も World 権威化完了**。
  - **🔍 reader flip は F4 に畳む（発見）**: hp read は `combatView`/`UnitView` 経由で forecast 表示・AI・ダメージ計算が共有＝単独 invariant スライスで綺麗に flip 不可。**F4 の System が World から encounter/view を組む際に World hp を読む形で実施**するのが筋。既存 reader は scene hp（=World hp・dual-write）のまま F8 まで温存可。scene 派生（syncTreeFromWorld に hp・dual-write 撤去）も F6d/F8 cleanup へ。
  - **→ F4 解禁**: hp が World 権威になったので、敵ターン System（`stepEnemyTurn`）が World hp を読み書きして戦闘を 1 フレームで解ける前提が整った。F4 本体は **anim-queue（view 再生）＋ O2 harness（turn-end World+event-log 比較）** が要る heavy 段。
- **F7 残り sim state→World 完了**: waited/alerted/isDying/attackTargetId/selection/drafts 等を World へ（不変条件の達成）。
  - **🟢 F4 実現可能性検証の結論（2026-06-28）**: フル F4（敵ターン1フレーム反転）は **実現可能性 35/100＝見送り**（counter 分岐＋非同期 hit＋modal 中断を ~400 行 event interpreter で再現するだけ・O1 検証不能・92点→revert 前例同型）。代わりに **「sim-flags→World・多フレーム view-driver 維持」（軸1=state authority 完遂、軸2=control inversion は defer）を正規 end-state に再スコープ**（実現可能性 88/100）。ゲートを「World のみ読む／command のみ変更／決定純粋」に緩和。
  - **✅ F7-slice1 alerted（実装済・903緑・run で `[ALERTED DIFF]` 無音確認）**: `enemyAlerted` field＋`Cmd.SetAlerted`＋`alertedOf`＋`refreshMirror` preserve/prune＋`alertedMismatches` 検証器＋`AlertedQuery` effect/handler。dual-write 全サイト（applyNormalStep 決定・CombatScene 被弾・EnemyScene 復元・spawn seed）＋**reader flip**（decideAction が World 由来 alerted を読む・`AlertedQuery` が PhaseQuery と同型で FrameAef.ProcessT まで伝播）。テスト2本。**alerted は hp/pos/phase と同格の World 権威に**。スパイクが完全スライスとして着地。
  - **✅ F7-slice2 bottleUsed＋WorldQuery 汎用化（実装済・904緑）**: `enemyBottleUsed` field＋`Cmd.SetBottleUsed`＋`bottleUsedOf`＋preserve/prune＋`[BOTTLE DIFF]` 検証器＋reader flip（`tryThrowOrNormal`）＋dual-write（throw・spawn seed）＋テスト。**DRY 投資**: per-flag Query effect をやめ汎用 **`World.WorldQuery { def get(): World }`**（worldRef を返す）1本に集約・`alerted` を retrofit。以降のフラグ reader は `WorldQuery.get() |> World.xxxOf(ref)` で**新 effect/cascade ゼロ**。
  - **✅ F7-slice3 prevPos（実装済・905緑・run で `[PREVPOS DIFF]` 無音確認）**: `enemyPrevPos: Map[id,{x,y}]`（None=非在）＋`Cmd.SetPrevPos`＋`prevPosOf`＋preserve/prune＋`[PREVPOS DIFF]` 検証器（record は ToString 不可ゆえ (x,y) タプル化）＋reader flip（wander・`w0` snapshot 再利用）＋dual-write（`replayEnemyMoveView`）＋テスト。
  - **🎯 マイルストーン**: **敵ターン driver（EnemyTurnDriverScene）の sim 決定読みが全て World 由来**（alerted=decideAction / bottleUsed=tryThrowOrNormal / prevPos=wander / board・hp 既済）。軸1の敵ターン分達成・run 検証済。
  - **✅ F7-slice4 followUpUsed（実装済・906緑）**: 両 faction `playerFollowUpUsed`/`enemyFollowUpUsed`＋`Cmd.SetFollowUpUsed`＋`followUpUsedOf`＋preserve＋`[FOLLOWUP DIFF]` 検証器。dual-write（set-true 2[CombatScene]・reset 2[clearActedAll/clearAllWaited fold]・spawn seed 2）＋**reader flip**（`playerFollowUpEnemy`/`enemyFollowUpPlayer` の followUp ctx）。**reader が combat 解決チェーン奥の pure 関数ゆえ `world` パラメータ方式**（純粋性維持・caller=lungeDone が `WorldQuery.get()` を渡す）＋WorldQuery cascade（onLungeDone→drainAndDispatch→process）で解決。`withWorldQuery` discharger 追加・既存テスト3本に wrap。テスト。**combat クラスタも同パターンで移送可能と実証**。
  - **🎯 軸1 実質達成 ＋ 残スコープ確定（2026-06-28）**: World 権威化済 sim 状態 = **position・phase・hp・alerted・bottleUsed・prevPos・followUpUsed**（narrow-reader 系は完了）。
    - **view 状態＝World 化不要（relaxed gate で scene 残置）**: `acted`（行動済み暗転・sim 読み0）/`attackTargetId`（攻撃中アニメ追跡・主読みは `anyAttacking` view gate）/`isDying`（death アニメ追跡・counter の読みは hp<=0 で代替可）。**これらは F4 が無いと消えない view-tracking flag**。
    - **残る真 sim flag = `waited`（味方ターン flow）のみ**。ただし **8 reader × 6 module**（PlayerScene:697/CursorScene:753/ActionMenuScene:385,570/PlayerMovementScene:67,111/TurnPhase:416/TurnFlow:66）＋ writer も pure（setWaited:773）＝**wide multi-module flip**。reader-flip 方式は followUpUsed で実証済（world-param）だが量が多い。**次セッションで一括**（turnkey）: World 配管（`playerWaited` field/Cmd/applyCmd/preserve/検証器）→ dual-write（setWaited/clearAllWaited/785 ＋ spawn seed）→ 8 reader を `World.waitedOf(Player(id), WorldQuery.get()) \|> getWithDefault(d#waited)` に flip（各関数に WorldQuery cascade）→ run `[WAITED DIFF]` 無音。
    - **完了で軸1（authoritative sim state→World）完遂**。
  - **🟢 軸2 の正しい定義（2026-06-28 訂正・Bevy 整合）**: 軸2 ≠「1フレーム化」。**Bevy も多フレーム pacing を System として保つ**（Timer/state component＋毎フレーム走る System＋Events で「アニメ待ち→次 step」を判定・1フレームに畳まない）。私が defer した「フル F4 1フレーム反転」は **Bevy 流ですらない over-reach**＝不要。**真の軸2 = F8「driver を per-node OOP callback → フレームパイプラインが呼ぶ frame-paced System に」**（pacing 保持・view-timing は World component or effect・scene は派生ビュー）。pacing を保つぶん inversion より feasible。最終形＝「World 真実源・ロジックは component を読む frame-paced System・scene 派生ビュー」（Bevy 流）。**到達可能**。
    - waited の reader flip（8 箇所）は **F8 で各 module が System 化する時に一括**（その時 reader が World を読む形に）＝今は dual-write+preserve で軸1 データ権威のみ確定（hp と同方式）。`acted`/`attackTargetId`/`isDying` も F8 で「System が読む component（or AnimationPlayer effect から isPlaying 読み）」として整理。
  - **✅ F7-slice5 waited（実装済・907緑）＝軸1 データ権威 完遂**: `playerWaited` field＋`Cmd.SetWaited`＋`waitedOf`＋preserve＋`[WAITED DIFF]` 検証器。dual-write 全サイト（`setWaited`/`setActive`/`clearAllWaited` fold/**`useStairs`（検証器スコープで発見した隠れ複合書込）**/spawn seed）＋テスト。reader flip は **F8 で一括**（hp 同方式・dual-write+preserve で権威確定・readers は scene mirror を読む＝World==scene）。テスト3本に discharger 追加。
  - **🎉 軸1（authoritative sim state→World）達成**: position・phase・hp・alerted・bottleUsed・prevPos・followUpUsed・**waited** が World 権威（command-sourced＋preserve＋検証器）。残 `acted`/`isDying` は **view-tracking flag**（暗転/死亡アニメ）で F8（driver→System）時に component or AnimationPlayer effect 読みとして整理（`attackTargetId` は F8-slice1 で World 合流済）。**World が sim の唯一の真実源に。**
  - **次=F8（軸2・Bevy 流 frame-paced System）**: 敵ターン driver（`EnemyTurnDriverScene.process` 等の per-node OOP callback）を**フレームパイプラインが呼ぶ frame-paced System** に。pacing（Pacing/Tween/anim 待ち）は保持＝1フレーム化しない（Bevy も保つ）。view-timing を World component or effect 経由に・scene を派生ビューに・各 reader を World 読みへ flip（waited 等の deferred flip もここで）。**到達で完全 ECS（Bevy 流）。**
  - **🔍 F8 dispatch 移設の feasibility 検証（2026-06-28・spike-by-analysis）**: 敵 driver を per-node→pipeline へ移すと **frame 順序が genuine に変わる**。ノード追加順（buildPlayingScene）= … → Player/Enemy → **EnemyTurnDriver(:80)** → … → **TopBar(:94)**。preorder の per-node パスで driver は **combat drain（Player/Enemy の CombatScene.process）の後・TopBar.process の前**に走る。driver は `anyAttacking`（combat 由来・前順序依存）と `TopBarScene.isBusy`/`hasObservedEnemy`（TopBar 由来・後順序依存）を**両方読む＝前後に挟まれている**。pipeline 単一スロットでは両順序を同時に保てない（どこに置いても TopBar 読みが 1 フレームずれる）。→ **F8 移設は F3c 同根のフレーム順序変更**。盲目移設は TopBar フェーズバー演出の 1 フレームずれ subtle bug。**解法（要設計＋検証）**: (1) driver＋関連ノードを順序保って pipeline 一括移設、(2) TopBar 1 フレームずれを run で無害確認し許容、(3) driver の combat/TopBar 依存を World state 経由にして順序非依存化（最も ECS 的・`anyAttacking`→World の attacking flag、TopBar 状態→World）。**(3) が Bevy 流の正道**だが view-timing state の World 化が要る＝focused work。新セッションで F4 同型の探索→spike→計画→実装。
  - **✅ F8-slice2 実装（2026-06-28・910緑）= TopBar 同期 bool→World で解法(3)の後順序依存を解消**: driver が読む `isBusy`(intro hold)／`hasObservedEnemy`(バー観測) の 2 派生 bool を `World.enemyTurnBusy`/`phaseObservedEnemy`(scalar) に dual-write（`Cmd.SetEnemyTurnBusy`/`SetPhaseObservedEnemy`＋applyCmd＋refreshMirror/syncFromScene で持ち越し＝scene mirror 元なしの command 由来）。**TopBar.process が確定 scene(`next2`)から `isBusy`/`hasObservedEnemy` を計算して毎フレーム emit**＝World==scene を保証。**生アニメ Data（anim/hold/shown/animTarget）は TopBar 残置**（view-timing を World に入れない・driver が読む派生 bool だけ World 化）。driver 2 gate（:180/:191）を `World.enemyTurnBusyOf`/`phaseObservedEnemyOf(WorldQuery.get())` に flip。gameLoop に `[TOPBAR DIFF]` 検証器（World↔TopBarScene を Game.flix で inline 比較＝World→TopBar 結合を回避）。**挙動同一**（per-node 順で driver は TopBar より先＝旧 scene 読みも新 World 読みも「前フレームの TopBar 状態」）。TestWorld に bool set/preserve 1 本。**→ 解法(3)完遂: driver の前後順序依存が両方 World 経由＝順序非依存。次 = dispatch 移設本体（F3c 同型）。**
  - **✅ F8-slice1 実装（2026-06-28・909緑）= `attackTargetId`→World で解法(3)の前順序依存を解消**: 上記 feasibility の解法 (3)（driver の combat/TopBar 依存を World state 経由にして順序非依存化）の**前半（combat 由来 `anyAttacking`）を着地**。`World.playerAttackTarget`/`enemyAttackTarget: Map[id,target]`＋`Cmd.SetAttackTarget`/`ClearAttackTarget`＋applyCmd（insert/remove）＋refreshMirror preserve＋`attackTargetMismatches` 検証器＋`attackTargetMap` row-poly helper（syncFromScene 用）。**dual-write**: set=`setAttackTargetId`/`startPlayerAttack`/`startEnemyAttack`、clear=`clearAttackTargetId`/`clearEnemyAttackTarget`（funnel 経由・全 set サイト網羅・spawn は None=absence で Cmd 不要）。**reader flip 6 箇所**: `EnemyTurnDriverScene`(PlayerAttackHold gate×2＋stepOnce gate×2)・`StairsExitScene`(stepOnce gate×2) の `PlayerScene/EnemyScene.anyAttacking(scene)` → `World.anyPlayerAttacking/anyEnemyAttacking(World.WorldQuery.get())`。effect cascade は `World.Command`（BattlePanel/WeaponSelect/Combat の confirm/cancel 系）＋`World.WorldQuery`（StairsExit driver）を row 追加で収束。gameLoop に `[ATTACKTARGET DIFF]` 検証器。TestWorld に set/clear/predicate 2 本追加。**残 run 検証 = `[ATTACKTARGET DIFF]` 無音のみ**。**次 = 解法(3)後半: TopBar 状態→World（`isBusy`/`hasObservedEnemy` を World 由来に）で後順序依存も解消 → dispatch 移設が順序非依存に。**
  - **🔍 F6 dual-write 全経路監査（2026-06-28・先回り）= 漏れは level-up のみと確定**: 全 HP 変動経路を網羅点検。**effect-runner 系（杖/投擲/消耗品 self）は `!> World.emitHpSets(plan, s)` の境界 tap で dual-write 済**（PlanHandlers は pure のまま・heal/fullHeal/damage/maxHpUp/revive を post-runPlan scene 読みで emit）。**直接 hp 書込は setHp funnel（emit）か combat damage の paired emit で被覆**。StatusSystem は hp 非関与（毒/DoT 無し）・罠ダメージ無し。**唯一の漏れ＝level-up（effect-runner 非経由の直 combat 経路）で修正済（下記）。消耗品 self-heal は emitHpSets 境界で既に被覆ゆえ追加 emit 不要（一度 emit 追加→PlanHandlers effect 統一壁に当たり・境界被覆を確認して revert）。** ∴ F6 dual-write 網羅完了。
  - **🐛 F6 漏れ発見＆修正（2026-06-28）= レベルアップ HP 増分の dual-write 漏れ**: 実機で `[F6 HP DIFF] (Player(0), Some(14), 15)` が永続発生。F8 本体を per-node に戻しても消えず＝**F8 無罪を確定**。原因は `CombatScene.applyLevelUp`（撃破→exp→レベルアップで最大 HP 増分だけ現在 HP も増やす）が **scene の `hp` を `mapPlayer` で書くだけで `Cmd.SetHp` を emit していなかった**（effect row に `World.Command` 無し）＝World は昇格前 14・scene は昇格後 15 で永続乖離。`World.Command.emit(Cmd.SetHp(Player(playerId), newHp))` を追加＋`applyLevelUp`/`applyExpGain` の row に `World.Command`。**F6 の「全 hp 書込サイト dual-write」網羅が未達だった**（昇格時 HP 増は run 検証時にレベルアップが起きず見逃し）。他 hp write 全 9 サイトは再点検済み（setHp funnel/combat/revive/carry/snap/suspend/regen/spawn/effectHeal境界）で漏れ無し。`[F6 HP DIFF]` 検証器がまさにこの種の漏れを実機で捕える設計どおり機能した。**+ CI リグレッションテスト追加（`TestCombatScene.testLevelUpDualWritesHpToWorld`・912緑）**: applyLevelUp を pub 化し、growthRates#hp=100＋roll=50 で HP 決定的 +1、World を pre-levelup の 10 で seed→applyLevelUp 後に World hp==scene hp(11) を要求（emit 漏れだと World=10 で不一致＝失敗）。実機 verifier に加え CI 時にも同種漏れを捕える二重化。
  - **✅ Plan B 確定（2026-06-28・912緑）= 過大表現を訂正し end-state を証跡化**: 「process/physicsProcess/on~~ を全部潰した」は誤りと訂正（System 化したのは driver 2 つ=EnemyTurn/StairsExit だけ・logic callback は健在）。ユーザー選択の **Plan B**（フル System 化=A はやらず現状を end-state 確定）を、ゲート明文化＋残 logic callback 全件監査で証跡化。**ゲート**: (1)入力/イベント駆動 or 順序非依存 (2)in-scope unit sim 状態は `Cmd.*` dual-write (3)純判定。**スコープ**: World 権威=position/hp/phase/status/各 flag、World 非モデル=level/exp/stats/inventory/耐久/床アイテム/Queue/UI（=移行スコープ外と明示・未達でない）。**監査結論**: command-authoritative(preserve)な in-scope フラグ全て（hp/pos/alerted/bottleUsed/prevPos/followUpUsed/waited/attackTarget/enemyDying/turnPhase/TopBar bool）の scene 書込が `Cmd.*` emit と paired（grep 照合済）。漏れは level-up のみ＝修正済。CombatScene.process=own-node signal 順序非依存／Cursor=UI 無書込／onKeyPressed=engine event／TurnEndHold=phase 自動 dual-write／Staff/Item=境界 tap or out-of-scope／view 群=render。**∴ 全 logic callback がゲート pass＝B を end-state と宣言可。** A（combat/move/input のフル System 化）は optional な将来拡張。詳細表は ECS_WORKFLOW §G。
  - **🎉 F8 本体 run 検証クリア（2026-06-28）= 敵ターン driver は System 化達成（軸2・driver 単体）**: ≤1 フレーム演出シフトは体感不変・`[F6 HP DIFF]`(level-up 修正後)/`[ATTACKTARGET DIFF]`/`[TOPBAR DIFF]` 無音。**（注: driver 単体の達成＝全 callback 脱却ではない・Plan B 訂正参照。）**
  - **✅ F8 本体実装（2026-06-28・910緑）= 敵ターン driver dispatch 移設（軸2 本体）**: `EnemyTurnDriverScene.process(delta,node,path,scene)` は node/path/delta 不使用の pass-through（payload-less stateless driver）だったので純 `step(scene): Scene` System に昇格。`dispatchDrivers`(Game.flix per-node redef) から `EnemyTurnDriver` ケース削除＋gameLoop パイプライン（`GameEngine.process` の後）に `|> EnemyTurnDriverScene.step` 明示段を追加。**敵ターンロジックが OOP node callback でなく gameLoop 駆動の frame-paced System に＝軸2（control inversion）達成。** **⚠ 挙動 byte 同一でない（slice1/2 と異なる）**: 旧 driver は tree 巡回途中（combat ノード後・TopBar 前）、新 driver は process 全体後。driver は combat/TopBar を **live worldRef（今フレーム emit 込み）から読む＝読みは最新でロジック分岐不変**、唯一の差は driver が起こす phase 変化への view 反応が ≤1 フレーム遅れる（演出 ≤16ms シフト）。placement 比較: AFTER（採用）=combat/TopBar 読み最新・view 反応 1f 遅延／BEFORE=driver→TopBar 順保持だが anyAttacking が last-frame。両方 ≤1f。**run 検証 = バー赤⇄青ワイプ・敵ターン開始終了・攻撃反撃追撃のカクつき/ちらつき/引っかかり無＋ DIFF 無音**。fallback = `step` を process 前へ（1 行）。
- **F8 OOP dispatch 撤去（残）**: 他 driver（StairsExit/Fog/Minimap/ArrowCursor）も同パターンで System 化検討。全 simulation callback が空＝Node trait の simulation 分岐を削除。UI callback が `(World,UiState)` 純 render であることを確定（下記ゲートで検査）。

## 「UI callback を残してよい」判定ゲート（テスト可能・レビュー2）
callback が process に残ってよいのは **`(World, UiState)` の純関数で、権威状態を書かず、順序非依存**な時のみ。
現状の違反を grandfather せず洗い出す: 例 `CameraScene.isSettled` が敵 stepping を gate（EnemyTurnDriver:178）／fog が spawn 後に走る必要（:474-476）。これらは「render が logic に待たれている」＝純 render でない → F-clock/event 化で解消。

## 検証 — 2 つの oracle（per-frame byte-equal は inversion 後に論理矛盾・レビュー3）
inversion は state の**着地タイミング**を意図的に変える（敵ターン System は1ターン分の World 変更を1フレームで完了、旧コードは多フレームに分散）。ゆえに per-frame byte-equal は **F4/F6 で成立しない**。oracle を timing 依存性で2分割する:

- **O1 per-frame byte-equal（F0〜F3・timing 保存される段階のみ）**: `Math.Random` seed・`dt` 固定・スクリプト入力を再生し、各フレームの `(tick, turnPhase, queue, positions, hp, events)` を移行前後で byte 等価比較。
  - **🔍 O1 harness 足場コスト（2026-06-28 スコープ調査）**: 完全な physicsStep 駆動 O1 harness は **(1) Player ノード scene（battleScene 流・~25 field の Data）+ (2) MoveRange overlay（physicsStep は `selectAllowedPred`→`MoveRangeScene.isInRange` で gating＝overlay 無いと全 block）+ (3) board（`withMockBoard` で手組み可・scene TileMapLayer 不要）+ (4) Tween 進行ループ + frame-end `syncTreeFromWorld`** が要る＝Spike A の productionize（多段・rushed だと fragile）。**deliberate build 案件**。System ロジックは単体テスト（stepPlayerMove×3/stepEnemyMove×1）で既に被覆ゆえ、当面は単体＋下記の土台 pin で代替し、physicsStep 統合 harness は F3c 着手と同時に腰を据えて作る。
  - **✅ F3 土台 pin（895緑）**: `TestWorld.testSyncTreeFromWorldDerivesScenePos`＝`Cmd.Move`→World→`syncTreeFromWorld`→scene gridPos の World→scene 派生（位置権威=World・scene=派生）を直接固定。既存テストは World 側（`worldPosOf`）のみで未カバーだった F3 の前提を pin。
  - **✅ physicsStep 統合ハーネス（898緑・1 フレーム版）**: `TestPlayerMovementScene` に実 OOP-callback 経路を 1 フレーム駆動するハーネスを構築（`moveScene`=Player ノード+MoveRange overlay 直挿し、`runPhysicsStep`=board/keys/tween モックで `physicsStep` を回し emit された Cmd.Move 列を返す）。3 ケース固定: **InRange→Move(5,2)** / **OutOfRange→pred gating で emit ゼロ** / **NoKey→emit ゼロ**。単体テストでは届かない「入力(readHeldDirection)→MoveRange pred 結線→stepPlayerMove→Cmd.Move」の統合 glue を機械検証。**F3c 検証の足場**: F3c で move を pipeline へ移したら、pipeline 経路を同様に駆動して同じ Cmd.Move トレースが出ることを assert すれば per-frame 等価を機械確認できる。残: Tween 進行を挟む multi-frame 版（「1 歩/frame・壁/範囲端で停止」）は F3c 着手時に追加。
- **O2 sim 決定論 + view 忠実度（F4 以降・timing が変わる段階）**:
  - **(a) sim 決定論**: 同一 seed・同一入力スクリプトで、**ターン境界での World 状態 ＋ 順序付き sim-event-log** を等価比較（per-frame でなく「ターン末」）。sim が即時化したので比較点はターン末。
  - **(b) view 忠実度**: render snapshot / 実機 run で演出が正しく再生されることを確認（**per-frame byte-equal は要求しない**＝anim の分散はわざと view 駆動に変えたため）。
- 加えて全 F 共通: F2 の dual-write assert（`World.turnPhase == TurnPhase.State.get()`）・実機 run。

各 F のゲート依存: F0-F3 は O1、F4-F8 は O2(a)＋O2(b)。

## リスクと対策
| リスク | 対策 |
|---|---|
| frame-paced 制御（コルーチン） | **sim-event-log + animation-queue の反転**（F-clock で先に確立） |
| 全 sim state→World が大（特に hp/stats） | 目標として宣言・段階 flip。各 component は boardKey 型の dual-write assert で falsifiable に |
| turn FSM の cascade | F2 を a/b/c 分割・並走 assert・modal 分離 |
| effect-tier カスケード（位置移行で経験） | F0 を実 System で先に effect 署名を固定・compiler 誘導で1群ずつ |
| 挙動不変が機械検証しづらい | golden-trace harness（決定論再生） |
| read-model 反転は要相談事項 | hp/stats→World は §A 採用戦略の転換＝**着手前にユーザー承認**（F6 の前） |

## 実現可能性の検証（捨てスパイクで実測・2026-06-27）
点数（90+）は「計画の整合性」であって「engine で通るか」ではない（前例: `逐次処理 Script` 92点→全 revert）。make-or-break 2 仮説をコードで試した:
- **Spike A（golden-trace harness が作れるか）= ✅ 実証済み**。捨て test で **実フレーム pipeline を test から決定論駆動できた**:
  `GameEngine.physicsProcess`（9 handler・全て既存 fixture）も `GameEngine.process`（~21 handler・大半 fixture＋6 個 trivial inline mock）も**コンパイル＆実行 PASS**。多フレームループ＋seed RNG＋固定 dt＋スクリプト入力（withMockRandom/withMockGameKeys）は在庫で自明拡張。
  → 「壊してないと機械検証できず盲目進行→全 revert」の **#1 リスクは大幅に解消**。caveat: harness は noop-Tween/Pacing の決定論レジーム＝状態/ロジック不変(O1/O2a)に有効・実時間演出は O2b(実機)で見る。
- **Spike B-lite（戦闘 inversion の view-side）= ✅ 実証済み**。捨て test で**攻撃 lunge の「視覚(`tracks`)」と「damage トリガ(`methods`=attack:hit)」が engine で綺麗に分離している**ことを確認:
  実 `attackLungeAnimation` は `methods` を剥がす（`{methods = Nil | real}`）と **位置は動く（演出再生）が attack:hit を1つも発火しない**（drainSignals の `bundle#methods`=0）。engine 自身の `posAnimation`/`alphaAnimation` も `methods=Nil` を first-class で使う＝**「logic を駆動しないアニメ」は標準サポート**。
  → inversion ＝ **damage を System が即時適用＋`methods=Nil` の純演出 lunge を VIEW が再生**で二重適用なく成立。**engine の抵抗なし＝make-or-break クリア**。
  - 残（build であって壁ではない）: 複数演出の **queue 順次再生**（lunge→hit-flash→death-blink を `finished` 連鎖で）・**Pacing を view queue へ移送**・**再生中 input gate**（queue 非空フラグ）。いずれも「分離可能と実証済みの部品の sequencing」ゆえ F6 で組める。

## 最初の一手（実現可能性検証を踏まえて改訂）
1. **Spike B-lite（combat-inversion の view-side）を先に1本**（捨てブランチ・1回の攻撃を「HP 即時＋view が小 queue で lunge→hit→death 再生」に）。通れば inversion 全体が feasible、engine が抵抗すれば**ここで止める**（F0-F5 を積む前に）。
2. 通ったら **F0（`stepWorld`＋`tickStatusEffects`・no-op）→ F1（1アクション input→intent）**。golden-trace harness（Spike A で実証済の型）を骨組みとして用意し以後のゲートに。
