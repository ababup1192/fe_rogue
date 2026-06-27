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
  - **F3b（次・要設計/run）**: `SimEvent.Moved{entity,target}` 導入＋move を intent→System→event→`replayMoveView` 形に。gating が混在（isMoving=Tween 待ち＝view / immobilized=status＝world / walkable・range・enemy＝board）ゆえ「view が attempt 可否を gate → System が legal 判定」に層分け要。timing 不変なら同 dispatch 内 emit→replay で済むが、pipeline 段移設（F3c）は要 run。
- **F4 敵ターン AI を System に**: `EnemyAI.decideAction`（既に純粋）を `stepEnemyTurn(world)->（world,events）` に。queue を World component 化。Pacing/カメラ待ちは animQ 側へ。callback を空に。
- **F5 階段退場を System に**: `StairsExit` → `stepStairsExit`（queue/距離場は純粋・退場演出は events）。
- **F6 戦闘を System に（read-model 反転がここで顕在化）**: hp/weapon/stats を World 権威化 → `Combat` の純解決（`Combat.estimate`/`resolveStrike` は既に純粋）を `stepCombat(world)->（world,events）` に。`attack:hit` 待ちは `Hit`/`Died` event の再生へ。
- **F7 残り sim state→World 完了**: waited/alerted/isDying/attackTargetId/selection/drafts 等を World へ（不変条件の達成）。
- **F8 OOP dispatch 撤去**: 全 simulation callback が空＝Node trait の simulation 分岐を削除。UI callback が `(World,UiState)` 純 render であることを確定（下記ゲートで検査）。

## 「UI callback を残してよい」判定ゲート（テスト可能・レビュー2）
callback が process に残ってよいのは **`(World, UiState)` の純関数で、権威状態を書かず、順序非依存**な時のみ。
現状の違反を grandfather せず洗い出す: 例 `CameraScene.isSettled` が敵 stepping を gate（EnemyTurnDriver:178）／fog が spawn 後に走る必要（:474-476）。これらは「render が logic に待たれている」＝純 render でない → F-clock/event 化で解消。

## 検証 — 2 つの oracle（per-frame byte-equal は inversion 後に論理矛盾・レビュー3）
inversion は state の**着地タイミング**を意図的に変える（敵ターン System は1ターン分の World 変更を1フレームで完了、旧コードは多フレームに分散）。ゆえに per-frame byte-equal は **F4/F6 で成立しない**。oracle を timing 依存性で2分割する:

- **O1 per-frame byte-equal（F0〜F3・timing 保存される段階のみ）**: `Math.Random` seed・`dt` 固定・スクリプト入力を再生し、各フレームの `(tick, turnPhase, queue, positions, hp, events)` を移行前後で byte 等価比較。
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
