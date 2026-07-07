/// ゲーム全体の進行状態。ノード単位の状態（NodeTag）や戦闘ターンのサブフェーズ（TurnPhase）
/// とは別レイヤーで、「今どの画面か」を表す。
///   CharacterSelect — 起動直後の出撃メンバー / リーダー選択画面。
///   Playing         — ダンジョン本編。
pub enum GamePhase with Eq {
    /// 起動時のタイトル画面（はじめから / 中断から再開）。
    case Title
    case CharacterSelect
    case Playing
}

/// GamePhase の読み書き effect。どの handler からでも `put` で遷移を要求でき、
/// 実体（region の Ref）は `Game.start` で注入する。gameLoop が前フレームとの差分を見て
/// `applyPhaseChange` で画面を組み替える。
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    /// 選択カーソルの識別用純タグ（論理状態は `CursorState.State` resource へ移設・ペイロードレス）。
    case Cursor
    /// ArrowCursorScene の Marker2D（杖発射方向を視覚化する矢印カーソル）。
    /// 論理状態は ArrowCursorState.State resource が権威で、タグはペイロードレス。
    case ArrowCursor
    /// Stairs の Marker2D（フロアの階段。床のランダムセルに 1 つ配置される）
    case Stairs(Stairs.Data)
    /// GroundItems の床アイテム識別タグ。production ではノードを積まない（描画は renderItems
    /// 直描き）。手組みノードで World を seed するテスト seam（syncFromScene の itemsFromScene
    /// が読む）として残置。
    case GroundItem(GroundItems.Data)
    /// GroundItems の床に落ちている武器（拾える）
    /// Chests の床に置かれた宝箱（ローグだけが開けられる。中身は配置時に確定済み）
    case Chest(Chests.Data)
    /// `EnemyTurnDriver` の常駐タグ専用ノード (Marker2D)。process redef で phase を
    /// 見て EnemyTurn 中なら stepOnce、PlayerAttackHold 中なら hold 終了判定を行う。
    case EnemyTurnDriver
    /// `StairsExitDriver` の常駐タグノード (Marker2D)。phase==StairsExit のとき
    /// 退場 id 列(queue)を 1 体ずつ階段へ歩かせて退場させる。
    case StairsExitDriver(StairsExitDriver.Data)
    /// `FogScene` の常駐タグ専用ノード (Marker2D)。process redef で毎フレーム、現在パーティの
    /// いる部屋/通路だけ明るくし、それ以外は薄暗いモヤ＋敵/アイテム/階段を非表示にする。
    case FogDriver
    case NoTag
}

// physicsProcess の engine 巡回で動くのは Player ノードだけ。`PlayerMoving` 中は
// **選択中の味方 1 体だけ** が方向キーを polling し、`GatherMove` 中は主人公(id 0)が動く。
// カーソルの入力ポーリングは scene ノードを持たないため engine 巡回では回らず、gameLoop が
// `CursorScene.physicsProcess` を明示 System として 1 回呼ぶ（phase 判定は CursorScene 内部）。
// それ以外のフェーズ（`EnemyTurn` 等）では `(node, scene)` を返して no-op になる。
instance Node[NodeTag] {
    type Aef = FrameAef.T
    type ProcessAef = FrameAef.ProcessT
    redef physicsProcess(delta: Duration.Duration,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.T =
        match EngineNode.getState(node) {
            case NodeTag.Player(data) =>
                // 選択中プレイヤー & PlayerMoving フェーズだけが移動を受け付ける。
                // 集合(GatherMove)では主人公(id 0)が移動範囲内で動き、味方が追従する。
                let phase = TurnPhase.State.get();
                if (phase == TurnPhase.Phase.PlayerMoving
                    and SelectedPlayer.State.get()#id == Some(data#id))
                    PlayerMovementDriver.physicsStep(delta, node, path, scene)
                // 集合(行軍)中は主人公(id 0)を移動範囲内で動かし、味方が 1 歩ずつ追従する。
                else if (phase == TurnPhase.Phase.GatherMove and data#id == 0)
                    PlayerMovementDriver.gatherStep(delta, node, path, scene)
                else (node, scene)
            case _ => (node, scene)
        }
    // process redef は持たない（engine の process 巡回は gameLoop から外し、Player / Enemy の
    // 戦闘シグナル解決は `CombatDriver.stepEntities` を明示 System としてパイプライン段で回す）。
    // `type ProcessAef` は trait Node が要求するため宣言だけ残す（既定の no-op process が使われる）。
}

// 決定キー（Z / Space / Enter）/ キャンセルキー（X）の意味はフェーズで変わる。
// 判断ロジックは `TurnRules.decide` に集約してあり、ここでは
// 「キー → Input → 判断 → apply」という配線だけを行う（実体は `GameManager`）。
//
//   PlayerCursor + Z   : 味方マス → 選択 / それ以外 → 集合メニュー
//   PlayerMoving + Z/X : Tween 中はガード。Z で攻撃フェーズ、X で origin へ戻して PlayerCursor
//   PlayerAttack + Z/X : 敵マスで Z → 攻撃モーション開始、X / 空マスで Z → 行動終了
//   GatherMove + Z/X   : Z で隣接メニュー（交換/全員待機/キャンセル）、X で開始位置へ巻き戻し
//   EnemyTurn          : 入力無視（自動進行）
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {GameEngine.Game, GameEngine.Audio, BoardQuery, 
                 AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                 PlayerData.PartyQuery, EnemyData.RosterQuery,
                 CustomEffects.FloorAdvanceRequest, CustomEffects.ResumeRequest,
                 CustomEffects.SuspendRequest,
                 GamePhaseState, PartySelection.State, CharacterSelectState.State,
                 // アイテム投擲の命中ロール（Math.Random）と誤射による味方脱落のゲームオーバー判定。
                 Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery,
                 // 全滅モーダルの選択・確定・F1 ホットリロードが UI 状態とファイルを触る。
                 Fs.FileRead, UiWorldState.State,
                 // レベルアップ演出パネルの確定（LevelUpPanelUi.confirm）が State resource を触る。
                 LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State}
    // ActionMenu / ItemMenu / ItemActionMenu / AttackForecast フェーズでは
    // FERogue のキー慣習として Z（決定）/ X（ウィンドウを閉じる）でメニュー操作する。
    // ItemMenu と ItemActionMenu は同じ ItemMenuUi が扱い、`confirmCurrentSelection`
    // 内部で現在のフェーズに応じて分岐する。
    // それ以外のフェーズはこれまで通り TurnRules 経由で振る舞いを決める。
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                                          
                                          AnimationPlayer.Scheduler,
                                          GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State,
                                          SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                                          PlayerData.PartyQuery,
                                          EnemyData.RosterQuery,
                                          CustomEffects.FloorAdvanceRequest,
                                          CustomEffects.ResumeRequest,
                                          CustomEffects.SuspendRequest,
                                          GamePhaseState, PartySelection.State, CharacterSelectState.State,
                                          Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery,
                                          Fs.FileRead, UiWorldState.State,
                                          LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State} =
        // F1: World-entity UI の ui.json を sources 台帳ごとホットリロードする（デバッグ用・画面問わず）。
        if (key == GameEngine.Key.F1) { UiWorldState.State.put(UiSpec.reloadAll(UiWorldState.State.get())); scene }
        // 画面がタイトル / 選択中なら各画面へ委譲。本編（Playing）のときだけ戦闘用ルーティングを走らせる。
        else match GamePhaseState.get() {
            case GamePhase.Title           => TitleMenuUi.onKeyPressed(key, scene)
            case GamePhase.CharacterSelect => CharacterSelectUi.onKeyPressed(key, scene)
            case GamePhase.Playing         => onPlayingKeyPressed(key, scene)
        }
}

/// Playing フェーズのキー処理。GamePhase 分岐を onKeyPressed から分離し推論複雑度を下げる。
def onPlayingKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                           AnimationPlayer.Scheduler,
                           GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                           SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State, PlayerData.PartyQuery,
                           EnemyData.RosterQuery, CustomEffects.FloorAdvanceRequest,
                           CustomEffects.SuspendRequest,
                           Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery,
                           UiWorldState.State,
                           LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State} =
        // 物理キーを「決定 / キャンセル / それ以外 (None)」の意味論的入力に正規化する。
        // phase と独立した直交概念として扱いたいので、bool 2 個ではなく Option[Input] に畳む。
        let input: Option[TurnRules.Input] =
            if (key == GameEngine.Key.Z or key == GameEngine.Key.Space
                                        or key == GameEngine.Key.Enter)
                Some(TurnRules.Input.Confirm)
            else if (key == GameEngine.Key.X or key == GameEngine.Key.Escape)
                Some(TurnRules.Input.Cancel)
            else None;
        let phase = TurnPhase.State.get();
        // Shift トグル（いずれもメニュー効果音を鳴らす。対象外フェーズは無反応）:
        //   PlayerCursor / PlayerMoving … 危険範囲(紫 = 全敵に攻撃されうるマス)の表示/非表示
        //   ItemSelect … カーソル位置のアイテムの複数選択（まとめて捨てる用の印）
        //   TradeInventory … カーソル位置の自分のアイテムの複数選択（まとめ渡し用の印）
        if (key == GameEngine.Key.LeftShift)
            match phase {
                case TurnPhase.Phase.PlayerCursor =>
                    AudioStreamPlayer.play("confirm");
                    DangerZoneScene.toggle(scene)
                case TurnPhase.Phase.PlayerMoving =>
                    AudioStreamPlayer.play("confirm");
                    DangerZoneScene.toggle(scene)
                case TurnPhase.Phase.ItemSelect =>
                    AudioStreamPlayer.play("confirm");
                    ItemMenuUi.toggleMarkAtCursor(scene)
                case TurnPhase.Phase.TradeInventory =>
                    AudioStreamPlayer.play("confirm");
                    TradeMenuUi.toggleTradeMarkAtCursor(scene)
                case _ => scene
            }
        // C キー / ゲームパッド Y: 集合モードのトグル。
        //   PlayerCursor … 集合可能(他に生存味方が居て主人公が未行動、かつ敵が見えていない)なら
        //                  「集合」を直接確定。
        //   GatherMove   … 一歩も動いていない（手動確定直後 / 継続でターン開始した状態）なら
        //                  集合を解いて個別行動モード(PlayerCursor)へ戻す。移動を始めたら不可。
        else if (key == GameEngine.Key.C)
            if (phase == TurnPhase.Phase.PlayerCursor and ActionMenuUi.gatherEnabled(scene)) {
                AudioStreamPlayer.play("confirm");
                ActionMenuUi.gatherShortcut(scene)
            } else if (phase == TurnPhase.Phase.GatherMove and PlayerScene.gatherNotMovedYet(scene)) {
                // 何も動いていないので cancelSelection の巻き戻しは実質 no-op。gatherActive を
                // 解いてカーソル選択（個別行動）へ復帰する。
                AudioStreamPlayer.play("cancel");
                PlayerScene.cancelSelection(scene)
            } else scene
        else {
            // プレイヤー操作のフィードバック効果音（決定 / キャンセル / メニューカーソル移動）。
            // onKeyPressed は物理キー押下ごとに 1 度だけ発火するので、ここで鳴らせば 1 押下 = 1 音。
            // 実際の処理分岐 (dispatchMenuKey 等) は別途行うが、音はこの単一地点に集約する。
            playInputSfx(phase, input, key);
            // メニュー系フェーズ (ActionMenu / ItemMenu / TradeMenu) の Z/X は別関数で処理。
            // Some が返ってくれば dispatcher が処理済みなのでその scene をそのまま返す。
            // 入力があればメニュー dispatcher に渡す。処理済み(Some)ならその scene、
            // 未処理(None)・入力なしは非メニュー処理へ。2 段の match を flatMap + 1 match に畳む。
            match input |> Option.flatMap(inp -> checked_ecast(dispatchMenuKey(phase, inp, scene))) {
                case Some(after) => after
                case None        => dispatchNonMenuKey(phase, input, key, scene)
            }
        }

// ────────────────────────────────────────────────────────
// StaffAim フェーズ用ヘルパー（方向キー → applyStaffCast、X/Esc → メニューに戻る）
// ────────────────────────────────────────────────────────

/// 方向キーを `Dir4.Dir4` に変換する。方向以外のキーは None。
def keyToStaffDirection(key: GameEngine.Key): Option[Dir4.Dir4] = match key {
    case GameEngine.Key.W     => Some(Dir4.Up)
    case GameEngine.Key.Up    => Some(Dir4.Up)
    case GameEngine.Key.S     => Some(Dir4.Down)
    case GameEngine.Key.Down  => Some(Dir4.Down)
    case GameEngine.Key.A     => Some(Dir4.Left)
    case GameEngine.Key.Left  => Some(Dir4.Left)
    case GameEngine.Key.D     => Some(Dir4.Right)
    case GameEngine.Key.Right => Some(Dir4.Right)
    case _                     => None
}

/// StaffAim フェーズで方向キーが押されたら `ArrowCursorScene.aim` で矢印の向きだけ更新する。
/// 発射は別キー (Z) で確定する。方向以外のキーは無視。
def staffAimDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ ArrowCursorState.State =
    match keyToStaffDirection(key) {
        case None      => scene
        case Some(dir) => ArrowCursorScene.aim(dir, scene)
    }

/// StaffAim フェーズで Z が押されたら、矢印が指している方向で applyStaffCast を呼ぶ。
def staffAimConfirm(scene: Scene[NodeTag]):
        Scene[NodeTag] \ {RangeOverlayState.State, AnimationPlayer.Scheduler,
                           BoardQuery, GameLogger.GameLogger,
                           EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                           ArrowCursorState.State,
                           GameEngine.Audio, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection();
    // 選択中プレイヤー → その Data → selectedItem を forM で 1 本に畳み、
    // 杖(Staff)を選んでいるときだけ発射する（3 段の match ネストを解消）。
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        player   <- PlayerScene.get(playerId, scene);
        item     <- player#selectedItem
    ) yield (playerId, item);
    match selected {
        case Some((playerId, PlayerData.ItemKind.Staff(idx))) =>
            StaffCast.applyStaffCast(playerId, idx, dir, scene)
        // 投擲系の消費アイテム（目潰し薬 / 鈍足薬）も同じ StaffAim 経路で方向投擲する。
        case Some((playerId, PlayerData.ItemKind.Consumable(idx))) =>
            StaffCast.applyConsumableDirectional(playerId, idx, dir, scene)
        case _ => scene
    }

/// ThrowAim フェーズで Z が押されたら、矢印が指している方向で選択中アイテムを投げる。
/// 種別（武器/杖/薬/指輪）に依らず `applyThrow` が振り分ける。
def throwAimConfirm(scene: Scene[NodeTag]):
        Scene[NodeTag] \ {RangeOverlayState.State, AnimationPlayer.Scheduler,
                           BoardQuery, GameLogger.GameLogger,
                           EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                           ArrowCursorState.State,
                           GameEngine.Audio, Math.Random,
                           CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection();
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        player   <- PlayerScene.get(playerId, scene);
        item     <- player#selectedItem
    ) yield (playerId, item);
    match selected {
        case Some((playerId, kind)) =>
            StaffCast.applyThrow(playerId, kind, dir, scene)
        case None => scene
    }

/// プレイヤー操作のフィードバック効果音を鳴らす。
///   - 決定 (Z / Space / Enter)        → "confirm"（メニューを開く / 項目を確定する操作も含む）
///   - キャンセル (X / Escape)         → "cancel"
///   - メニュー中の方向キー            → "cursor"（リストのカーソル移動 / 交換のペイン切替）
/// onKeyPressed から 1 押下につき 1 回だけ呼ばれる。確定/取消・カーソル音いずれも
/// 「その入力が実際に何かする」フェーズでだけ鳴らす（演出中・自動進行中など、ボタンを
/// 押しても無反応なフェーズで音だけ鳴るのを防ぐ）。
def playInputSfx(phase: TurnPhase.Phase, input: Option[TurnRules.Input],
                  key: GameEngine.Key): Unit \ GameEngine.Audio =
    match input {
        case Some(TurnRules.Input.Confirm) =>
            if (confirmCancelMakesSound(phase, TurnRules.Input.Confirm))
                AudioStreamPlayer.play("confirm") else ()
        case Some(TurnRules.Input.Cancel)  =>
            if (confirmCancelMakesSound(phase, TurnRules.Input.Cancel))
                AudioStreamPlayer.play("cancel") else ()
        case None                          =>
            if (isMenuCursorMove(phase, key)) AudioStreamPlayer.play("cursor")
            else ()
    }

/// 決定 / キャンセル音を鳴らすべきフェーズ×入力か。
/// 演出・自動進行など「その入力が何もしない（メニューも開けない）」フェーズでは false にして、
/// ボタンを押しても無反応なのに音だけ鳴るのを防ぐ。
/// 何かしらの操作が成立する通常フェーズ（カーソル選択・各メニュー・攻撃・レベルアップ確認など）
/// では true。`dispatchMenuKey` / `dispatchNonMenuKey` / `TurnRules.decide` の「無反応(Stay)」
/// 分岐と対応させてある。
def confirmCancelMakesSound(phase: TurnPhase.Phase, input: TurnRules.Input): Bool =
    match (phase, input) {
        // 全入力を無視する演出フェーズ（攻撃モーション中 / 敵ターン / 戦闘予報）
        case (TurnPhase.Phase.PlayerAttackHold, _) => false
        case (TurnPhase.Phase.EnemyTurn,        _) => false
        case (TurnPhase.Phase.AttackForecast,   _) => false
        // 集合(行軍): Z=確定して隣接メニュー / X=巻き戻し。どちらも操作が成立するので音を鳴らす(case _ => true)。
        case _                                                          => true
    }

/// メニュー系フェーズで「カーソル移動とみなす方向キー」か判定する。
/// リスト選択 (ActionSelect / ItemSelect / ItemActionSelect) は ↑↓ (W/S) のみ、
/// 交換 (TradeInventory) は ↑↓ のカーソル移動と ←→ のペイン切替の両方を移動音の対象にする。
def isMenuCursorMove(phase: TurnPhase.Phase, key: GameEngine.Key): Bool =
    let vertical = match key {
        case GameEngine.Key.Up   => true
        case GameEngine.Key.Down => true
        case GameEngine.Key.W    => true
        case GameEngine.Key.S    => true
        case _                   => false
    };
    let horizontal = match key {
        case GameEngine.Key.Left  => true
        case GameEngine.Key.Right => true
        case GameEngine.Key.A     => true
        case GameEngine.Key.D     => true
        case _                    => false
    };
    match phase {
        case TurnPhase.Phase.ActionSelect     => vertical
        case TurnPhase.Phase.SuspendConfirm   => vertical
        // ItemSelect は ↑↓ がアイテム選択、←→ がページ切替（ロード職の 2 ページ）。
        case TurnPhase.Phase.ItemSelect       => vertical or horizontal
        case TurnPhase.Phase.ItemActionSelect => vertical
        case TurnPhase.Phase.TradeInventory   => vertical or horizontal
        // 武器選択中: 上下=武器切り替え / 左右=ターゲットの敵選択。どちらもカーソル移動音を鳴らす。
        case TurnPhase.Phase.WeaponSelect     => vertical or horizontal
        // 攻撃中: 上下=武器切り替え / 左右=ターゲット選択。どちらもカーソル移動音を鳴らす。
        case TurnPhase.Phase.PlayerAttack     => vertical or horizontal
        case _                                => false
    }

/// メニュー系フェーズ (ActionSelect / ItemSelect / ItemActionSelect / TradeInventory)
/// の Z/X dispatch をまとめる。`onKeyPressed` の match は phase 数 × bool パターンで
/// 型推論の複雑度が膨らみがちなので、メニュー dispatch を関数に切り出して肩代わりする。
/// 戻り値は「dispatcher が処理したら Some、対象外なら None」。
def dispatchMenuKey(phase: TurnPhase.Phase, input: TurnRules.Input, scene: Scene[NodeTag]):
        Option[Scene[NodeTag]] \ {AnimationPlayer.Scheduler,
                                    GameLogger.GameLogger, EnemyTurn.Queue,
                                    TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                                    PlayerData.PartyQuery, EnemyData.RosterQuery,
                                    CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                                    CustomEffects.GameOverRequest, CustomEffects.SuspendRequest, World.Command, World.WorldQuery, BoardQuery,
                                    UiWorldState.State,
                                    LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State} =
        match (phase, input) {
        // 全滅メニュー: Z/Enter で選択確定（restart を emit）、X は無反応（必ず選ばせる）。
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Confirm)
                                              => Some(GameOverMenuUi.confirmSelection(scene))
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Cancel)
                                              => Some(scene)
        // 中断確認: Z/Enter で「はい/いいえ」確定、X で中断をやめて PlayerCursor へ。
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Confirm)
                                              => Some(SuspendConfirmUi.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Cancel)
                                              => Some(SuspendConfirmUi.cancel(scene))
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Confirm)
                                              => Some(ActionMenuUi.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ActionMenuUi.onActionCancelled(scene)))
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Confirm)
                                              => Some(checked_ecast(WeaponSelectUi.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Cancel)
                                              => Some(checked_ecast(WeaponSelectUi.onCancelled(scene)))
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Confirm)
                                              => Some(checked_ecast(ItemMenuUi.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ItemMenuUi.onItemCancelled(scene)))
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Confirm)
                                              => Some(checked_ecast(ItemMenuUi.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ItemMenuUi.onActionCancelled(scene)))
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Confirm)
                                              => Some(checked_ecast(TradeMenuUi.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Cancel)
                                              => Some(checked_ecast(TradeMenuUi.cancelCurrent(scene)))
        // レベルアップのステータス変化パネルは Z / Enter / X いずれでも閉じる（確認するだけ）。
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Confirm)
                                              => Some(checked_ecast(LevelUpPanelUi.confirm(scene)))
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Cancel)
                                              => Some(checked_ecast(LevelUpPanelUi.confirm(scene)))
        case _                                => None
    }

/// メニュー以外のフェーズ (GatherMove / StaffAim / AttackForecast 等) の Z/X dispatch。
/// `onKeyPressed` から `dispatchMenuKey` で処理されなかったときに呼ばれる。
/// 方向キーなど input = None もここに来る (StaffAim 中の direction、ほかは no-op)。
def dispatchNonMenuKey(phase: TurnPhase.Phase, input: Option[TurnRules.Input],
                        key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {RangeOverlayState.State, GameEngine.Audio, BoardQuery, 
                            AnimationPlayer.Scheduler,
                            GameLogger.GameLogger,
                            EnemyTurn.Queue, TurnPhase.State,
                            SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
                            ItemMenuState.State, TradeMenuState.State,
                            PlayerData.PartyQuery,
                            EnemyData.RosterQuery,
                            Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery,
                            UiWorldState.State} =
        match (phase, input) {
        case (TurnPhase.Phase.StaffAim,       Some(TurnRules.Input.Cancel))
                                              => checked_ecast(staffAimCancel(scene))
        case (TurnPhase.Phase.StaffAim,       Some(TurnRules.Input.Confirm))
                                              => checked_ecast(staffAimConfirm(scene))
        // StaffAim 中の方向キーは applyStaffCast へ
        case (TurnPhase.Phase.StaffAim,       None)
                                              => checked_ecast(staffAimDirection(key, scene))
        // ThrowAim（アイテム投擲）。StaffAim と同じ矢印 UI を共用し、Z で投げ確定。
        case (TurnPhase.Phase.ThrowAim,       Some(TurnRules.Input.Cancel))
                                              => checked_ecast(staffAimCancel(scene))
        case (TurnPhase.Phase.ThrowAim,       Some(TurnRules.Input.Confirm))
                                              => checked_ecast(throwAimConfirm(scene))
        case (TurnPhase.Phase.ThrowAim,       None)
                                              => checked_ecast(staffAimDirection(key, scene))
        // TradeInventory 中は ←/→ と ↑↓ の両方を tradeInventoryDirection に渡す
        // (←/→ は左右ペイン切替、↑↓ は focus ペインの選択カーソル移動)。
        case (TurnPhase.Phase.TradeInventory, None)
                                              => checked_ecast(tradeInventoryDirection(key, scene))
        // ItemSelect 中の方向キー: ↑↓ はアイテムカーソル移動、←→ はカテゴリ切替（World-entity UI）。
        case (TurnPhase.Phase.ItemSelect,     None)
                                              => itemSelectDirection(key, scene)
        // ItemActionSelect（サブメニュー）中の ↑↓ で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.ItemActionSelect, None)
                                              => itemActionDirection(key, scene)
        // PlayerAttack = ターゲット選択 + 戦闘予測。Z で(カーソル上の敵に)攻撃確定、
        // X でメニューに戻る。BattlePanelUi が予報表示と対象同期を担う。
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Confirm))
                                              => BattlePanelUi.confirm(scene)
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Cancel))
                                              => checked_ecast(BattlePanelUi.cancel(scene))
        // ActionMenu の ↑↓（W/S）で選択カーソルを動かす（World-entity UI。
        // disabled 項目はスキップする）。
        case (TurnPhase.Phase.ActionSelect,   None)
                                              => checked_ecast(actionMenuDirection(key, scene))
        // 中断確認の ↑↓（W/S）で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.SuspendConfirm, None)
                                              => suspendConfirmDirection(key, scene)
        // 武器選択ウィンドウの ↑↓（W/S）で武器カーソルを動かす（disabled はスキップ。
        // ←→ の対象敵サイクルは CursorScene.physicsProcess が別途 polling する）。
        case (TurnPhase.Phase.WeaponSelect,   None)
                                              => checked_ecast(weaponSelectDirection(key, scene))
        // 全滅モーダルの ↑↓（W/S）で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.GameOver,       None)
                                              => gameOverDirection(key, scene)
        // 明示 case が無いフェーズの Z/X は TurnRules.decide にそのまま渡す
        case (_,                              Some(inp))
                                              => TurnInputBridge.handle(inp, scene)
        // 方向キーなどはここまで来る (各 Scene が physicsProcess で polling する)
        case (_,                              None) => scene
    }

/// 全滅モーダル中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（端で回り込む）。他キーは素通し。
def gameOverDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag] \ UiWorldState.State =
    match key {
        case GameEngine.Key.Up   => GameOverMenuUi.moveSelection(-1); scene
        case GameEngine.Key.W    => GameOverMenuUi.moveSelection(-1); scene
        case GameEngine.Key.Down => GameOverMenuUi.moveSelection(1); scene
        case GameEngine.Key.S    => GameOverMenuUi.moveSelection(1); scene
        case _                   => scene
    }

/// ActionMenu（行動選択ウィンドウ）中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（disabled をスキップ・端で回り込む）。他キーは素通し。
def actionMenuDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag]
        \ {UiWorldState.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
    match key {
        case GameEngine.Key.Up   => ActionMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.W    => ActionMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.Down => ActionMenuUi.moveSelection(1, scene)
        case GameEngine.Key.S    => ActionMenuUi.moveSelection(1, scene)
        case _                   => scene
    }

/// 中断確認モーダル中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（端で回り込む）。他キーは素通し。
def suspendConfirmDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag] \ UiWorldState.State =
    match key {
        case GameEngine.Key.Up   => SuspendConfirmUi.moveSelection(-1); scene
        case GameEngine.Key.W    => SuspendConfirmUi.moveSelection(-1); scene
        case GameEngine.Key.Down => SuspendConfirmUi.moveSelection(1); scene
        case GameEngine.Key.S    => SuspendConfirmUi.moveSelection(1); scene
        case _                   => scene
    }

/// 武器選択ウィンドウ中の方向キーを武器カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（disabled をスキップ・端で回り込む）。他キーは素通し。
def weaponSelectDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag]
        \ {UiWorldState.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
    match key {
        case GameEngine.Key.Up   => WeaponSelectUi.moveSelection(-1, scene)
        case GameEngine.Key.W    => WeaponSelectUi.moveSelection(-1, scene)
        case GameEngine.Key.Down => WeaponSelectUi.moveSelection(1, scene)
        case GameEngine.Key.S    => WeaponSelectUi.moveSelection(1, scene)
        case _                   => scene
    }

/// TradeInventory 中の方向キーを変換する（World-entity UI 化に伴い ↑↓ もここで扱う）。
/// Left / A → focus を 1 つ左へ、Right / D → 1 つ右へ（両端でラップ）。
/// Up / W → focus ペインの選択カーソルを 1 つ上、Down / S → 1 つ下（端で停止）。
def tradeInventoryDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag]
        \ {TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Left  => TradeMenuUi.setPaneFocusDelta(-1, scene)
        case GameEngine.Key.A     => TradeMenuUi.setPaneFocusDelta(-1, scene)
        case GameEngine.Key.Right => TradeMenuUi.setPaneFocusDelta(1, scene)
        case GameEngine.Key.D     => TradeMenuUi.setPaneFocusDelta(1, scene)
        case GameEngine.Key.Up    => TradeMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.W     => TradeMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.Down  => TradeMenuUi.moveSelection(1, scene)
        case GameEngine.Key.S     => TradeMenuUi.moveSelection(1, scene)
        case _                    => scene
    }

/// ItemSelect 中の方向キーを変換する。Up/Down/W/S → アイテムカーソル移動（窓スクロール）、
/// Left/A → 前カテゴリ、Right/D → 次カテゴリ（武器/消費/杖/指輪。空はスキップ）。
/// カーソル移動もカテゴリ切替も World-entity UI で完結する。
def itemSelectDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State,
                          PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Up    => ItemMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.W     => ItemMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.Down  => ItemMenuUi.moveSelection(1, scene)
        case GameEngine.Key.S     => ItemMenuUi.moveSelection(1, scene)
        case GameEngine.Key.Left  => ItemMenuUi.categoryPrev(scene)
        case GameEngine.Key.A     => ItemMenuUi.categoryPrev(scene)
        case GameEngine.Key.Right => ItemMenuUi.categoryNext(scene)
        case GameEngine.Key.D     => ItemMenuUi.categoryNext(scene)
        case _                    => scene
    }

/// ItemActionSelect（サブメニュー）中の方向キーを選択カーソル移動へ変換する。
/// Up/Down/W/S → 1 つ上下（disabled をスキップ・端で回り込む）。他キーは素通し。
def itemActionDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State,
                          PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Up    => ItemMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.W     => ItemMenuUi.moveSelection(-1, scene)
        case GameEngine.Key.Down  => ItemMenuUi.moveSelection(1, scene)
        case GameEngine.Key.S     => ItemMenuUi.moveSelection(1, scene)
        case _                    => scene
    }

def staffAimCancel(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
    TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
    scene

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さく切り出す。Camera2D 追従でビューが動く。横は左右余白も使うため 240 に拡張
    /// （行動メニュー＋武器ウィンドウを左に並べても、カメラ中心の戦闘キャラに被らないだけの幅）。
    /// この値はカメラのビューポートと投影行列の基準で、ウィンドウサイズに合わせて
    /// 引き伸ばし表示される（Godot の Stretch Mode = canvas_items 相当）。
    /// **project.json の "designWidth"/"designHeight" と必ず一致させること**（HUD の中央寄せ
    /// 計算がこの値を使うため、ずれると TopBar 等の帯が画面幅とずれる）。
    pub def designWi(): Int32 = 240
    pub def designHi(): Int32 = 128

    /// 起動時に World-entity UI の ui.json を spawnAsset で 1 回だけ組み込む。
    /// spawnAsset は sources 台帳への登録まで済ませるので、以後は F1 の reloadAll が拾う。
    /// 静的ツリーの読み込み失敗は設定ミスなので即 panic（fail-fast）。
    def spawnUiOrBug(path: String): Unit \ {Fs.FileRead, UiWorldState.State} =
        match UiSpec.spawnAsset(path, UiWorldState.State.get()) {
            case Err(_)       => bug!("spawnUiOrBug: failed to spawn ui from ${path}")
            case Ok((_, ui2)) => UiWorldState.State.put(ui2)
        }

    /// `spawnUiOrBug` の別名 root 版。同じ ui.json を `rootName` を差し替えて spawn する
    /// （ユニット簡易カードを味方=左 / 敵=右の 2 root で使うため）。読み込み失敗は即 panic。
    def spawnUiAsOrBug(path: String, rootName: String): Unit \ {Fs.FileRead, UiWorldState.State} =
        match UiSpec.spawnAssetAs(path, rootName, UiWorldState.State.get()) {
            case Err(_)       => bug!("spawnUiAsOrBug: failed to spawn ui from ${path} as ${rootName}")
            case Ok((_, ui2)) => UiWorldState.State.put(ui2)
        }

    /// ゲーム起動エントリ。Region と各 effect handler を立ち上げ、初回シーンを
    /// `SceneSetup.buildPlayingScene` で組み立てて `gameLoop` に入る。
    /// **配線役** に徹するため、ここにゲームロジックは書かない。
    pub def start(): Unit \ {GameEngine.Game, GameEngine.Audio,
                              Fs.FileRead, Fs.FileWrite, IO, Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            // BoardQuery handler が読む World の窓口（sceneRef と対称・毎フレーム頭で gameLoop が更新）。World は
            // 各 store の単一権威。
            let worldRef = Ref.fresh(rc, World.empty());
            // turn phase の Ref。TurnPhase.State handler を inline 化し、`put` でこの Ref と worldRef.turnPhase を
            // **同時更新（dual-write）**する＝全 put サイト（41 箇所）が自動で World へ command 反映される（per-site 改修ゼロ）。
            let turnPhaseRef = Ref.fresh(rc, TurnPhase.Phase.PlayerCursor);
            // ゲーム全体の進行状態（画面）。起動直後はタイトル画面（はじめから / 中断から再開）から始める。
            let phaseRef = Ref.fresh(rc, GamePhase.Title);
            // 試練型の部屋湧きクロック。WandererSpawnRequest が来るたび +1 し、
            // EnemyScene が周期判定（tick mod N）に使う。modulo 判定ゆえフロア跨ぎのリセット不要。
            let wanderClockRef = Ref.fresh(rc, 0);
            // 味方の死亡位置（id → セル）。GameOverRequest.markDeaths が除去前に蓄積し、女神の加護の
            // 「その場復活」で参照する。id でキーするので過去フロアの残骸は復活対象 id にだけ読まれ無害。
            let deathMarksRef = Ref.fresh(rc, (Map.empty(): Map[Int32, {x = Int32, y = Int32}]));
            // ユニットカタログをロード + schema 整合性検査（不正データを起動直後に検出して即終了する）。
            // 各 load() 内で失敗内容を panic に出して原因を即可視化する。
            // units.json の spriteFrames は格子インデックス形式で書かれているため、
            // load 直後は spriteFrames = None。GameEngine.Game effect が使えるここで
            // resolveSpriteFrames を呼んで texture 実寸から px 矩形に解決する。
            let weaponCatalog = WeaponCatalog.load();
            let catalog0 = UnitCatalog.load(AssetPath.resolve("resources/units.json"), weaponCatalog);
            let catalog = UnitCatalog.resolveSpriteFrames(AssetPath.resolve("resources/units.json"), catalog0);
            // 敵カタログをロード。味方（成長率あり）と別管理。
            // spriteFrames は味方と同じ格子→px 解決を通す。
            let enemyCatalog0 = EnemyCatalog.load();
            let enemyCatalog = EnemyCatalog.resolveSpriteFrames(AssetPath.resolve("resources/enemies.json"), enemyCatalog0);
            // フロア定義をロード。進行順は floors.json の "order" 配列で管理し、
            // 現在いるフロアは FloorProgress effect が保持する（初期値 = 先頭フロア）。
            // 階段で次階へ / 全滅で 1F へ / クリアで 1F ループ、はいずれも FloorProgress 経由。
            let floors = FloorCatalog.load();
            // 杖カタログをロード。
            let staffCatalog = Staff.load();
            // 消費アイテム（きずぐすり等）カタログをロード。
            let consumableCatalog = Consumable.load();
            // 宝箱カタログをロード（種別ごとの中身プールを持つ）。
            let chestCatalog = ChestCatalog.load();
            // 指輪カタログをロード。
            let ringCatalog = Ring.load();
            // カタログを 1 つの record に束ねて構築 / リビルド経路へ引き回す。
            let catalogs = {
                weapons     = weaponCatalog,
                players     = catalog,
                enemies     = enemyCatalog,
                floors      = floors,
                staves      = staffCatalog,
                consumables = consumableCatalog,
                chests      = chestCatalog,
                rings       = ringCatalog
            };
            run {
                // BGM は BgmScene の AudioStreamPlayer ノード (autoplay=true, loop=true,
                // volume=0.05) で applyAudioAttach 経由で再生される (= ここでは触らない)
                // SE は半分で鳴らす (Inspector 対応の Scene Node にしていない通常の SE 系)
                AudioStreamPlayer.setVolume("damage", 0.2625f32);
                AudioStreamPlayer.setVolume("down_enemy", 0.5f32);
                AudioStreamPlayer.setVolume("miss", 0.5f32);
                // 命中時の SE 出し分け: ダメージ 0 を防いだ "guard"、魔法武器の "magic"
                AudioStreamPlayer.setVolume("guard", 0.5f32);
                AudioStreamPlayer.setVolume("magic", 0.5f32);
                // 必殺発生時の SE
                AudioStreamPlayer.setVolume("critical", 0.5f32);
                AudioStreamPlayer.setVolume("find", 0.5f32);
                AudioStreamPlayer.setVolume("phase_change", 0.5f32);
                AudioStreamPlayer.setVolume("get_item", 0.5f32);
                // メニュー操作の UI 効果音 (決定 / キャンセル / カーソル移動)
                AudioStreamPlayer.setVolume("confirm", 0.5f32);
                AudioStreamPlayer.setVolume("cancel", 0.5f32);
                AudioStreamPlayer.setVolume("cursor", 0.5f32);
                // 回復成立音 (きずぐすり / 回復の杖)
                AudioStreamPlayer.setVolume("cure", 0.4f32);
                // 階段でフロア移動する音
                AudioStreamPlayer.setVolume("change_floor", 0.5f32);
                // "T1 味方のターン" のログは Playing 突入時（applyPhaseChange）に出す。
                // 全滅モーダルの World-entity UI を 1 回だけ spawn する（静的ツリー。以降は
                // UiRender が毎フレーム描き、GameOverMenuUi.frameStep が可視/選択を同期する）。
                spawnUiOrBug(GameOverMenuUi.specPath());
                // 上部フェイズバーの World-entity UI も 1 回だけ spawn する（初期は不可視。
                // フロア進入時に TopBarUi.enter が可視化する）。
                spawnUiOrBug(TopBarUi.specPath());
                // 行動選択ウィンドウ（コマンドメニュー）の World-entity UI を 1 回だけ spawn する
                // （初期は不可視。ActionSelect フェーズで ActionMenuUi.frameStep が可視化・項目流し込み）。
                spawnUiOrBug(ActionMenuUi.specPath());
                // 武器選択ウィンドウ（ActionMenu「攻撃」確定で右隣に出る）の World-entity UI を
                // 1 回だけ spawn する（初期は不可視。WeaponSelect フェーズで WeaponSelectUi.frameStep が可視化）。
                spawnUiOrBug(WeaponSelectUi.specPath());
                // アイテム選択ウィンドウ（ActionMenu「アイテム」確定で右隣に出る）の World-entity UI を
                // 1 回だけ spawn する（初期は不可視。ItemSelect/ItemActionSelect で ItemMenuUi.frameStep が可視化）。
                spawnUiOrBug(ItemMenuUi.specPath());
                // 物交換ウィンドウ（最大 4 ペイン。「こうかん」/ 集合「交換」確定で中央に出る）の
                // World-entity UI を 1 回だけ spawn する（初期は不可視。TradeInventory で TradeMenuUi.frameStep が可視化）。
                spawnUiOrBug(TradeMenuUi.specPath());
                // 中断確認モーダルの World-entity UI を 1 回だけ spawn する
                // （初期は不可視。SuspendConfirm フェーズで SuspendConfirmUi.frameStep が可視化）。
                spawnUiOrBug(SuspendConfirmUi.specPath());
                // タイトル画面の World-entity UI を 1 回だけ spawn する（初期は不可視。GamePhase.Title
                // 進入時に TitleMenuUi.enter が再開可否を確定して可視化する）。
                spawnUiOrBug(TitleMenuUi.specPath());
                // 出撃メンバー選択画面の World-entity UI を 1 回だけ spawn する（初期は不可視。
                // GamePhase.CharacterSelect 進入時に CharacterSelectUi.enter が候補を put して可視化し、
                // 以降 CharacterSelectUi.frameStep がカルーセルと選択の見た目を毎フレーム同期する）。
                spawnUiOrBug(CharacterSelectUi.specPath());
                // 右下の一時ログ HUD の World-entity UI を 1 回だけ spawn する（初期は不可視。
                // LogUi.step が GameLogger を drain して 5 行に流し込み、空でないフレームだけ可視化）。
                spawnUiOrBug(LogUi.specPath());
                // 中央アイテム取得ポップアップの World-entity UI を 1 回だけ spawn する（初期は不可視。
                // ItemPickupPopupUi.frameStep が段階演出のフェードを窓 alpha・文字色・可視へ反映する）。
                spawnUiOrBug(ItemPickupPopupUi.specPath());
                // ターンスキップ長押しゲージの World-entity UI を 1 回だけ spawn する（初期は不可視。
                // TurnEndHoldUi.frameStep が Shift 長押しを読み充填リングの頂点を毎フレーム塗り替える）。
                spawnUiOrBug(TurnEndHoldUi.specPath());
                // 攻撃前の戦闘予報ミニウィンドウの World-entity UI を 1 回だけ spawn する（初期は不可視。
                // BattlePanelUi.frameStep が対象の敵の近傍に命中/必殺/相性を出し panel を毎フレーム追従させる）。
                spawnUiOrBug(BattlePanelUi.specPath());
                // レベルアップ演出パネルの World-entity UI を 1 回だけ spawn する（初期は不可視。
                // LevelUpPanelUi.frameStep が LevelUpView 中に bonus → 各ステータス増分を順に出す）。
                spawnUiOrBug(LevelUpPanelUi.specPath());
                // ユニット簡易カードは 1 枚の UnitCard.ui.json を左右 2 root で spawn する
                // （味方カード=左 / 敵カード=右）。初期は不可視で、UnitCardUi.frameStep が対象解決で出す。
                spawnUiAsOrBug(UnitCardUi.specPath(), UnitCardUi.allyRootName());
                spawnUiAsOrBug(UnitCardUi.specPath(), UnitCardUi.enemyRootName());
                // 全 World-entity UI を spawn し終えてから起動画面を組む。タイトル画面（はじめから /
                // 中断から再開）から始める。はじめから → CharacterSelect、中断から再開 → Playing
                // （applyPhaseChange が snapshot から再構築）と遷移する。buildTitle は TitleMenuUi.enter で
                // Title root を可視化するため、spawn 後に呼ぶ必要がある（spawn 前だと不可視の no-op になる）。
                let scene = applyPhaseChange(GamePhase.Title, GamePhase.Title, catalogs, Scene.empty());
                // 初回 world は空で開始（タイトル画面はユニット/地形が無く、以降の全 store は
                // spawn/build choke の Cmd が seed する）。syncFromScene はテスト seed 専用に退役。
                gameLoop(catalogs, sceneRef, worldRef, GamePhase.Title, scene, World.empty())
            // handler の並び順 = effect 消費順 (構文上で後の `with` ほど **外側**)。
            // `GameOverRequest` の handler 本体は `GameLogger` / `EnemyTurn.Queue` /
            // `TurnPhase.State` / `SelectedPlayer.State` / `InitialSpawns.State` 等を
            // 使うため、これらより **内側** (= 構文上で先) に書く必要がある。
            } with handler CustomEffects.GameOverRequest {
                  // 死亡位置を蓄積（新しい位置を優先してマージ）。女神の加護の「その場復活」で参照。
                  def markDeaths(positions, k) = {
                      Ref.put(Map.union(positions, Ref.get(deathMarksRef)), deathMarksRef);
                      k()
                  }
                  // 全味方脱落: 即リビルドせず盤面をフリーズしてモーダル選択メニューを出す。
                  // モーダルは World-entity UI（UiWorldState）で保持するため scene は素通し。
                  def request(scene, k) = { GameOverMenuUi.show(); k(scene) }
                  // 「最初から」: フロアを 1F に戻し turn 系をリセットしてフルリビルド（新ラン）。
                  def restartBeginning(_scene, k) = k(GameLifecycle.resetForGameOver(catalogs))
                  // 「そのフロアの最初から」: 進入時スナップショットから同フロアを決定論再構築。
                  def restartFloor(_scene, k) = k(GameLifecycle.restartFromFloorSnapshot(catalogs))
                  // 「女神の加護」: 現フロアそのままに全員その場（死亡位置）復活・HP全快・3ターン無敵。
                  def reviveInPlace(scene, k) =
                      k(GameLifecycle.reviveWithGoddess(catalogs, Ref.get(deathMarksRef), scene))
              }
              with handler CustomEffects.FloorAdvanceRequest {
                  // 生存味方が全員階段を使ったら次フロアへ（最終フロアならクリア → 1F ループ）。
                  // HP / 武器 / 持ち物の引き継ぎを含め本体は GameLifecycle.advanceFloor 側。
                  def advance(scene, k) = k(GameLifecycle.advanceFloor(catalogs, scene))
              }
              with handler CustomEffects.SuspendRequest {
                  // 中断: 現フロアを slot に保存してタイトルへ戻す（本体は GameLifecycle.suspendAndQuit）。
                  def save(scene, k) = k(GameLifecycle.suspendAndQuit(catalogs, scene))
              }
              with handler CustomEffects.ResumeRequest {
                  // 中断から再開: slot を読み・状態を整え・セーブを消費して Playing へ遷移する
                  // （scene 構築は applyPhaseChange(Playing, from=Title) が担う）。本体は resumeFromSuspend。
                  def resume(scene, k) = k(GameLifecycle.resumeFromSuspend(catalogs, scene))
              }
              with handler CustomEffects.WandererSpawnRequest {
                  // 試練型の部屋湧き。呼ばれるたびクロックを +1 し、その tick を渡して
                  // 現在フロアを解決し EnemyScene に委ねる（周期・上限・湧くかの判断は EnemyScene 側）。
                  // catalog とクロック Ref をクロージャに閉じ込めて使う。
                  def maybeSpawn(scene, k) =
                      let tick = Ref.get(wanderClockRef) + 1;
                      Ref.put(tick, wanderClockRef);
                      k(GameLifecycle.maybeSpawnWanderer(catalogs, tick, scene))
              }
              with handler CustomEffects.RingTransformRequest {
                  // ringman の特殊行動。装備外アイテムを 1 つ指輪に変える（抽選・分布は GameLifecycle 側）。
                  // Ring カタログをクロージャに閉じ込めて使う。
                  def transform(enemyName, targetId, scene, k) =
                      k(GameLifecycle.applyRingTransform(catalogs, enemyName, targetId, scene))
              }
              with handler CustomEffects.ThiefDropRequest {
                  // 盗人の剣: 現在フロアの items ドロップ表から抽選してアイテムを cell に落とす。
                  // フロア表 + 各カタログをクロージャに閉じ込めて使う。
                  def drop(cell, scene, k) =
                      k(GameLifecycle.dropFloorItem(catalogs, cell, scene))
              }
              // World ランタイムの読み書き seam（BoardQuery / World.Command / StatusQuery /
              // PhaseQuery / WorldQuery / RngDraw）は WorldDriver.withWorld に集約。CustomEffects
              // handler（scene 深部の emit 元）より外側・PartyQuery/RosterQuery より内側に置く。
              with WorldDriver.withWorld(sceneRef, worldRef)
              with handler PlayerData.PartyQuery {
                  // read-flip: core field 権威は World。pos/hp/waited/在庫/progress/statuses 等は
                  // `dataFromWorld`＝World 由来で読む。residual（resource/classId/selectedItem/facing/
                  // pendingLevelUp/moveStepsTaken/usedStairs）は dataFromWorld が scene から読む。
                  // ★意味論: core=worldRef（emit で mid-frame 先行・即時 `Cmd` 適用）＝BoardQuery と同じ
                  //   mid-frame 権威、residual=frame-top scene（sceneRef は frame 頭のみ更新）。両者は「core 系
                  //   （座標/hp/在庫）と residual 系（resource/UI/render facing）を跨いで同一瞬間として相関させない」
                  //   限り整合。静的 residual（resource/classId）は不変、動的 residual（facing/selectedItem 等）は cosmetic。
                  // core store が未 seed で None gate に落ちた時のみ scene Data へ fallback＝退行ゼロ（[PLAYERDATA DIFF]
                  //   が World==scene を frame 末に保証＝fallback は実質不発）。
                  def get(id, k)           = {
                      let scene = Ref.get(sceneRef); let world = Ref.get(worldRef);
                      k(PlayerScene.get(id, scene) |> Option.map(d ->
                          World.dataFromWorld(id, world, scene) |> Option.getWithDefault(d)))
                  }
                  def getAll(k)            = {
                      let scene = Ref.get(sceneRef); let world = Ref.get(worldRef);
                      k(PlayerScene.getAll(scene) |> List.map(d ->
                          World.dataFromWorld(d#id, world, scene) |> Option.getWithDefault(d)))
                  }
              }
              with handler EnemyData.RosterQuery {
                  // read-flip: PartyQuery と同流儀で core 権威は World。get/getAll は
                  // `dataFromWorldEnemy`＝World 由来（residual=resourceId/homeModuleIdx/resource/acted は scene）・
                  // None gate は scene fallback。findIdAt/anyAttacking は World の pos/attackTarget を直読み
                  // （EnemyScene 版と等価・pos/dying/attackTarget は dual-write で [ATTACKTARGET DIFF] 等が保証）。
                  // 意味論は PartyQuery と同じ: core=worldRef mid-frame〔BoardQuery と同権威〕/ residual=frame-top scene。
                  def get(id, k)           = {
                      let scene = Ref.get(sceneRef); let world = Ref.get(worldRef);
                      k(EnemyScene.get(id, scene) |> Option.map(d ->
                          World.dataFromWorldEnemy(id, world, scene) |> Option.getWithDefault(d)))
                  }
                  def getAll(k)            = {
                      let scene = Ref.get(sceneRef); let world = Ref.get(worldRef);
                      k(EnemyScene.getAll(scene) |> List.map(d ->
                          World.dataFromWorldEnemy(d#id, world, scene) |> Option.getWithDefault(d)))
                  }
                  // ★注: findIdAt/anyAttacking は現状 RosterQuery 経由の実 consumer が無い（実 consumer は
                  //   `EnemyScene.findIdAt` を scene 直読み〔UnitCard/WeaponSelect/EnemyCard/BattlePanel/ItemMenu〕、
                  //   driver は `World.anyEnemyAttacking` を WorldQuery 直読み）。ここは handler の
                  //   coherence 用に用意した口で、実 consumer の flip 先になる。
                  def findIdAt(coord, k)   = k(World.enemyIdAt(coord, Ref.get(worldRef)))
                  def anyAttacking(k)      = k(World.anyEnemyAttacking(Ref.get(worldRef)))
              }
              with handler GamePhaseState {
                  // 画面（CharacterSelect / Playing）の現在値を region の Ref で保持する。
                  def get(k)         = k(Ref.get(phaseRef))
                  def put(target, k) = { Ref.put(target, phaseRef); k() }
              }
              with AnimationPlayer.withScheduler(rc)  // 名前付きアニメ + イベントドレイン
              with Pacing.withState(rc)           // 演出の溜め (hold)
              with LogState.withState(rc)         // ログ HUD の状態（queue/idleSince）を resource 化
              with BattlePanelState.withState(rc) // 戦闘予報パネルの点滅タイマーを resource 化
              with TurnEndHoldState.withState(rc) // ターンスキップ長押しゲージの状態を resource 化
              with LevelUpPanelState.withState(rc) // レベルアップ演出パネルの状態を resource 化
              with TopBarState.withState(rc) // 上部バーの状態を resource 化
              with TitleMenuState.withState(rc) // タイトル画面の状態を resource 化
              with UnitHPBarRender.withForecast(rc) // 攻撃予報（減る分点滅）の view 状態
              with ItemPickupPopupState.withState(rc) // 中央アイテム取得ポップアップの状態を resource 化
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with EnemyTurn.withQueue(rc)        // 敵ターンキュー（1 step / 1 frame 駆動）
              with handler TurnPhase.State {       // inline 化し put を World へ dual-write（全 put が World.turnPhase 反映）
                  def get(k) = k(Ref.get(turnPhaseRef))
                  def put(target, k) = {
                      Ref.put(target, turnPhaseRef);
                      Ref.put(World.applyCmd(World.Cmd.SetPhase(WorldDriver.simPhaseOf(target)), Ref.get(worldRef)), worldRef);
                      k()
                  }
              }
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with CursorState.withState(rc)      // 選択カーソルの論理状態（指しセル/加速/ホバー/描画位置/tween）を resource 化
              with CameraState.withState(rc)      // 追従カメラの視点状態（ターゲット/smoothPosition/追従パラメータ）を resource 化
              with RangeOverlayState.withState(rc) // 範囲オーバーレイ 7 種のセル集合（Option 在/不在=表示トグル）を resource 化
              with ArrowCursorState.withState(rc) // 杖/投擲の照準矢印の論理状態（anchor/direction/gridPos）を resource 化
              with GatherResume.withState(rc)     // 集合モードのターン跨ぎ自動継続フラグ
              with InitialSpawns.withState(rc)    // ゲームオーバー時に同じ敵 / 味方配置を復元
              with FloorSnapshot.withState(rc)    // 進入時フロアスナップショット（全滅時の「フロア最初から」用）
              with FloorProgress.withState(rc, FloorCatalog.firstFloorId(floors))  // 現在フロア id
              with PartySelection.withState(rc)   // 出撃メンバー（開始時に1回抽選、フロア間で維持）
              with CharacterSelectState.withState(rc) // 出撃メンバー選択画面の選択状態（注目/選択/サブモード/カルーセル）を resource 化
              with ItemMenuState.withState(rc)    // アイテム窓の選択状態（カテゴリ index / 一括選択マーク）を resource 化
              with TradeMenuState.withState(rc)   // 物交換窓のセッション状態（members/focus/pick/origin/marks）を resource 化
              with UiWorldState.withState(rc)     // World-entity UI（全滅モーダル）の状態を resource 化
              with MinimapState.withState(rc)     // ミニマップの表示トグル（M）状態を resource 化
        }

    /// GamePhase に応じて画面（Scene）を組み立てる。**配線役** に徹し、各画面の構築は
    /// `SceneSetup` の対応関数へ委譲するだけ（画面固有のロジックはここに書かない）。
    ///   Title           — タイトル画面（はじめから / 中断から再開）。
    ///   CharacterSelect — 出撃メンバー選択画面。
    ///   Playing         — 現在フロアのダンジョン（`prevPhase` で新規ラン / 中断再開を出し分け）。
    /// gameLoop が前フレームとの差分を見て、画面が変わったフレームだけ呼ぶ。
    def applyPhaseChange(phase: GamePhase, prevPhase: GamePhase, catalogs: GameLifecycle.Catalogs,
                          _scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, IO, Math.Random,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, CharacterSelectState.State, GameLogger.GameLogger, FloorSnapshot.State, World.Command,
                World.WorldQuery, TitleMenuState.State, TopBarState.State, UiWorldState.State, RangeOverlayState.State, CameraState.State} =
        match phase {
            case GamePhase.Title           => SceneSetup.buildTitle()
            case GamePhase.CharacterSelect => SceneSetup.buildCharacterSelect(catalogs)
            case GamePhase.Playing         => SceneSetup.buildPlaying(catalogs, prevPhase)
        }

    /// メインループ。phase で分岐せず、**固定パイプライン** を毎フレーム回す:
    ///   handleInput → physicsProcess → Tween → Animation → process → epilogue
    /// 各 process / input redef 内で「自分が今動くべきか」を phase で判断する (Godot 流)。
    /// 例: `EnemyTurnDriver.process` は phase=EnemyTurn / PlayerAttackHold で動作、
    ///     `PlayerMovementDriver.gatherStep` は phase=GatherMove で主人公(id 0)を動かす。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def gameLoop(catalogs: GameLifecycle.Catalogs,
                  sceneRef: Ref[Scene[NodeTag], r],
                  worldRef: Ref[World, r],   // BoardQuery handler が読む World の窓口（毎フレーム頭で更新）。
                  previousPhase: GamePhase,
                  scene: Scene[NodeTag],
                  world: World):           // 権威 World（各 store の単一権威）。gameLoop を貫通して次フレームへ持ち越す。
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         Fs.FileRead, IO,
                         BoardQuery,
                         PlayerData.PartyQuery, EnemyData.RosterQuery,
                         AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                         CustomEffects.GameOverRequest,
                         CustomEffects.FloorAdvanceRequest,
                         CustomEffects.WandererSpawnRequest,
                         CustomEffects.RingTransformRequest,
                         CustomEffects.ThiefDropRequest,
                         CustomEffects.SuspendRequest, CustomEffects.ResumeRequest,
                         FloorProgress.State, InitialSpawns.State,
                         GamePhaseState, PartySelection.State, CharacterSelectState.State,
                         Pacing.State, LogState.State, BattlePanelState.State, TurnEndHoldState.State,
                         LevelUpPanelState.State, ItemPickupPopupState.State, ItemMenuState.State, TradeMenuState.State,
                         TopBarState.State, TitleMenuState.State, UnitHPBarRender.ForecastState,
                         Math.Random, FloorSnapshot.State,
                         World.Command, World.StatusQuery, World.PhaseQuery, World.WorldQuery,
                         World.RngDraw, UiWorldState.State, MinimapState.State, RangeOverlayState.State, CameraState.State, r} =
        // Escape ではアプリ終了しない。ウィンドウの閉じる操作（shouldClose）だけで終了する。
        if (GameEngine.Game.shouldClose()) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene / world に更新する。
            // world は前フレーム末の権威 World（world2）＝各 store の単一権威。
            Ref.put(scene, sceneRef);
            Ref.put(world, worldRef);
            let dt = GameEngine.Game.getDeltaTime();
            // Pacing カウンタを 1 フレーム進める (各 Scene の process が gating で参照する)。
            // フレーム頭で進めるので「前フレーム末で hold した値を今フレームの判定で使う」
            // 形になり、Scene に紐づかないため gameLoop 内で 1 行のままにする。
            Pacing.State.tick(dt);
            let updated = scene
                |> GameEngine.handleInput
                |> GameEngine.physicsProcess(delta = dt, paused = false,
                                              gravity = Vec2.zero())
                // カーソルは scene ノードを持たず CursorState resource が権威なので engine 巡回では
                // 回らない。入力ポーリングを明示 System として 1 回呼ぶ（盤面がある画面のみ —
                // stepOnBoard が Map 存在をゲートする）。
                |> CursorScene.stepOnBoard(dt)
                |> AnimationPlayer.tickAll(dt)
                // カーソルのスライド補間・snag タイマーを dt 進めて renderPos を書く
                // （カーソルは engine Tween/AnimationPlayer を使わずここで直接進める。CameraScene.step より前）。
                |> CursorScene.stepVisual(dt)
                // Player / Enemy の戦闘シグナル解決を明示 System として回す（engine の process 巡回は
                // 使わず、この段が Player/Enemy の dispatch を担う）。
                |> CombatDriver.stepEntities
                // 表示系は明示 step で駆動する。
                // 順序制約: TopBar は EnemyTurnDriver が World 経由で読む 2 bool の dual-write 元なので
                // driver step より前に置く。TurnEndHold はログ帯を上書きするため LogUi.step より後に置く。
                // 他は独立。
                |> TopBarUi.step(dt)
                |> ItemPickupPopupUi.frameStep(dt)
                |> CharacterSelectUi.frameStep(dt)
                |> LogUi.step(dt)
                |> TurnEndHoldUi.frameStep(dt)
                |> CameraScene.step(dt)
                // ターン進行 LOGIC driver は frame-paced System としてパイプライン段で 1 回呼ぶ（gameLoop が駆動）。
                // process の後＝combat drain と TopBar 更新が確定した post-process scene を読む（前後依存は World 経由で順序非依存）。
                |> EnemyTurnDriver.step
                |> StairsExitDriver.step
                // view driver（Fog/Minimap）も per-node callback から外し明示 step 化
                // （dispatchDrivers 撤去＝対象 0）。process の後・render の前に post-process 状態を読んで
                // 同一フレームで描画されるため挙動不変。相互依存なし＝順序自由。
                // 照準矢印は step を持たず、描画（RenderWorld.renderArrowCursor）が phase から可視を決める。
                |> FogScene.step
                |> MinimapScene.step
                // 全滅モーダル UI の可視/選択ハイライトを phase から同期（旧 refreshItems の置換）。
                |> GameOverMenuUi.frameStep(dt)
                // 行動選択ウィンドウの可視/項目流し込み/選択ハイライトを phase から同期
                // （旧 ActionMenuScene.refreshItems + applyVisibility の置換）。
                |> ActionMenuUi.frameStep(dt)
                // 武器選択ウィンドウの可視/行流し込み/選択ハイライト/カーソルスナップを phase から同期。
                |> WeaponSelectUi.frameStep(dt)
                // アイテム選択ウィンドウ（ItemSelect/ItemActionSelect）の可視/窓流し込み/選択ハイライトを phase から同期。
                |> ItemMenuUi.frameStep(dt)
                // 物交換ウィンドウ（TradeInventory）の可視/中央寄せ/各ペインの窓流し込み/フォーカス表現を phase から同期。
                |> TradeMenuUi.frameStep(dt)
                // 中断確認モーダルの可視/選択ハイライトを phase から同期。
                |> SuspendConfirmUi.frameStep(dt)
                // タイトル画面の選択ハイライト/再開不可の淡色を毎フレーム同期（root 可視時のみ）。
                |> TitleMenuUi.frameStep(dt)
                // ユニット簡易カード（味方左 / 敵右）の表示対象を解決して流し込む（旧 process 2 case の置換）。
                |> UnitCardUi.frameStep(dt)
                // 攻撃前の戦闘予報ミニウィンドウの可視/数値/相性矢印/対象近傍への追従を phase から同期
                // （旧 BattlePanelScene.process の置換）。カーソルスナップ（WeaponSelectUi.frameStep）と
                // カメラ配置（CameraScene.step）の後に置き、対象の敵・画面座標を最新で読む。
                |> BattlePanelUi.frameStep(dt)
                // レベルアップ演出パネルの可視/本文の段階表示を phase から同期（旧 LevelUpPanelScene.process の置換）。
                |> LevelUpPanelUi.frameStep(dt);
            // 画面（GamePhase）が変わったフレームだけ、新しい画面を組み立て直す。
            // 例: 選択画面でリーダー確定 → Playing に切り替わり、ここでダンジョンが組まれる。
            let currentPhase = GamePhaseState.get();
            let next = if (currentPhase != previousPhase)
                           // `applyPhaseChange` は `Scene.empty()` から組むため prevKeyState が空に戻る。
                           // 直前 scene（handleInput 済み＝現在押下キー）の prevKeyState を引き継いで、
                           // 遷移を起こしたキー（例: 中断確定の Z）が新画面で「押し直し」と誤検知されて
                           // 即確定されるのを防ぐ（中断 → タイトルで「はじめから」が誤発火する事象の修正）。
                           applyPhaseChange(currentPhase, previousPhase, catalogs, updated)
                               |> Scene.setPrevKeyState(Scene.getPrevKeyState(updated))
                       else updated;
            // 毎フレームの World System パイプライン（attackTarget/player/enemy parity 検査 →
            // refreshMirror → tile bake（再構築時のみ）→ stepWorld → phase parity 検査 → marker 同期）は
            // `WorldDriver.stepFrame` に集約。current は mid-frame 権威（worldRef 値）、prev は前フレーム
            // World（`world` 引数・tileGen 差分判定用）。返す synced は marker 反映済みで次フレームへ永続。
            let (world2, synced) = WorldDriver.stepFrame(Ref.get(worldRef), world, dt, next);
            // render-from-World。scene-tree drawable に World 由来 drawable を合成して
            // 1 回の renderCommands で描く（renderCommands は毎回 clear ゆえ 2 回呼びは不可＝合成する）。
            // scene 側ユニット sprite を隠して描画 → ユニットは World 由来のみで描く。
            // 描画セクションは `renderFrame` へ抽出（gameLoop が JVM の 64KB メソッド上限を
            // 超えたため。挙動は同一）。
            renderFrame(catalogs, world2, synced);
            gameLoop(catalogs, sceneRef, worldRef, currentPhase, synced, world2)
        }
}

/// テスト専用の公開窓。本番の `renderFrame` をそのまま呼ぶ（複製しない＝本番と同一の描画合成）。
/// 描画リストは呼び出し側が `GameEngine.Game.renderCommands` を記録する handler で捕まえる。
/// production 経路（gameLoop）からは呼ばれない。
pub def renderFrameForCapture(catalogs: GameLifecycle.Catalogs, world: World, synced: Scene[NodeTag]):
        Unit \ {GameEngine.Game, SelectedPlayer.State, World.WorldQuery, UnitHPBarRender.ForecastState,
                UiWorldState.State, TurnPhase.State, ArrowCursorState.State, MinimapState.State,
                RangeOverlayState.State, CursorState.State, CameraState.State} =
    renderFrame(catalogs, world, synced)

/// フレーム描画（render-from-World の合流点）。gameLoop のサイズ削減のため関数分離。
/// fog・range・配置物・fx・minimap・HUD/menu はすべて World render System（各 render*）で描き、
/// scene-tree drawable（unit sprite 等）はそのまま合成する。camera ViewTransform はフレーム 1 回だけ計算して共有。
def renderFrame(catalogs: GameLifecycle.Catalogs, world2: World, synced: Scene[NodeTag]):
        Unit \ {GameEngine.Game, SelectedPlayer.State, World.WorldQuery, UnitHPBarRender.ForecastState,
                UiWorldState.State, TurnPhase.State, ArrowCursorState.State, MinimapState.State,
                RangeOverlayState.State, CursorState.State, CameraState.State} =
    let transform = RenderWorld.viewTransform(synced);
    // ミニマップは Drawable（矩形）と Polygon（マーカー円）の 2 チャンネルを 1 度に組む（画面固定）。
    let minimap = RenderWorld.renderMinimap(synced);
    // tileMaps は scene 走査由来（_sceneTileMaps）を捨て、World の bake 済ハンドルから組む
    // （camera 適用・instanced 維持）＝背景タイルも render-from-World。tileMaps は単一引数ゆえ二重描画なし。
    let (sprites, _sceneTileMaps, scenePolygons) = GameEngine.renderArgs(synced);
    // fog の明るい穴を frame に 1 回計算し、配置物直描きの lit ゲートで共有。
    let holesOpt = RenderWorld.fogHolesOpt(synced);
    // World-entity UI を 1 度のレイアウト解決で sprite（drawables）と polygon の 2 チャンネルへ射影。
    let uiRendered = UiHud.renderUi();
    let worldDrawables = RenderWorld.renderUnits(world2, transform, synced)
        // 配置物/fx/HP バー/武器アイコンは World store + catalog/定数から直描き（scene ノード無し）。
        |> List.append(RenderWorld.renderStairs(world2, holesOpt, transform))
        |> List.append(RenderWorld.renderChests(catalogs#chests, world2, holesOpt, transform))
        |> List.append(RenderWorld.renderItems(world2, holesOpt, transform))
        |> List.append(RenderWorld.renderPopups(world2, transform, synced))
        |> List.append(RenderWorld.renderExplosions(world2, transform, synced))
        |> List.append(UnitHPBarRender.renderBars(world2, transform, synced))
        |> List.append(WeaponIconRender.renderPlates(world2, transform, synced))
        |> List.append(RenderWorld.renderFog(transform, synced))
        |> List.append(RenderWorld.renderRangeOverlays(transform, synced))
        // 選択カーソルの四隅 L字（CursorState renderPos＋visible）と杖照準矢印（ArrowCursorState＋phase）を直描き。
        |> List.append(RenderWorld.renderCursor(transform, synced))
        |> List.append(RenderWorld.renderArrowCursor(transform))
        // ミニマップの部屋/床矩形（画面固定 HUD レイヤ）。
        |> List.append(minimap#drawables)
        // World-entity UI（全滅モーダル・TopBar 等）の box/text/sprite を HUD レイヤに合流（画面固定・camera 免除）。
        |> List.append(uiRendered#drawables);
    // polygon チャンネルは minimap のマーカー円 ＋ per-unit 武器グリフに、World-entity UI 由来 polygon
    //   （TopBar の集合中▶ / TurnEndHold の充填リング / BattlePanel の相性三角）を合流。
    GameEngine.Game.renderCommands(List.append(sprites, worldDrawables),
        RenderWorld.renderTileMaps(world2, transform, synced),
        List.append(scenePolygons,
            List.append(RenderWorld.renderFireShots(world2, transform, synced),
                List.append(minimap#polygons,
                    List.append(WeaponIconRender.renderGlyphs(world2, transform, synced),
                                uiRendered#polygons)))))
