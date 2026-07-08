/// GamePhase（進行画面・型は `World.GamePhase` に定義）の読み書き effect。どの handler からでも
/// `put` で遷移を要求でき、World の `screen` field（単一権威）へ facade が書く。gameLoop が
/// 前フレームとの差分を見て `applyPhaseChange` で画面を組み替える。
pub eff GamePhaseState {
    def get(): GamePhase
    def put(target: GamePhase): Unit
}

// 手動移動の入力ポーリングは `PlayerMovementDriver.step`（明示 System）が担う。
// `PlayerMoving` 中は **選択中の味方 1 体だけ** が方向キーを polling し、`GatherMove` 中は
// 主人公(id 0)が動く。カーソルの入力ポーリングは gameLoop が `CursorScene.stepOnBoard` を
// 明示 System として 1 回呼ぶ（phase 判定は CursorScene 内部）。

// 決定キー（Z / Space / Enter）/ キャンセルキー（X）の意味はフェーズで変わる。
// 判断ロジックは `TurnRules.decide` に集約してあり、ここでは
// 「キー → Input → 判断 → apply」という配線だけを行う。
//
//   PlayerCursor + Z   : 味方マス → 選択 / それ以外 → 集合メニュー
//   PlayerMoving + Z/X : Tween 中はガード。Z で攻撃フェーズ、X で origin へ戻して PlayerCursor
//   PlayerAttack + Z/X : 敵マスで Z → 攻撃モーション開始、X / 空マスで Z → 行動終了
//   GatherMove + Z/X   : Z で隣接メニュー（交換/全員待機/キャンセル）、X で開始位置へ巻き戻し
//   EnemyTurn          : 入力無視（自動進行）
//
// エッジ検出（押しっぱなしは押された最初のフレームだけ発火）は gameLoop が前フレームの押下キー集合
// （prevKeys）をループ引数で持ち回り、`handleInput` が現在集合との差分から新規押下を拾う。
// prevKeys は画面（GamePhase）の組み替えでも持ち回りが切れないため、遷移を起こしたキー
// （例: 中断確定の Z）が新画面で「押し直し」と誤検知されて即確定されることはない。

// ActionMenu / ItemMenu / ItemActionMenu / AttackForecast フェーズでは
// FERogue のキー慣習として Z（決定）/ X（ウィンドウを閉じる）でメニュー操作する。
// ItemMenu と ItemActionMenu は同じ ItemMenuUi が扱い、`confirmCurrentSelection`
// 内部で現在のフェーズに応じて分岐する。
// それ以外のフェーズはこれまで通り TurnRules 経由で振る舞いを決める。
def onKeyPressed(key: GameEngine.Key):
                   Unit \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
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
                            LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State,
                            StairsExitDriver.State} =
    // F1: World-entity UI の ui.json を sources 台帳ごとホットリロードする（デバッグ用・画面問わず）。
    if (key == GameEngine.Key.F1) UiWorldState.State.put(UiSpec.reloadAll(UiWorldState.State.get()))
    // 画面がタイトル / 選択中なら各画面へ委譲。本編（Playing）のときだけ戦闘用ルーティングを走らせる。
    else match GamePhaseState.get() {
        case GamePhase.Title           => TitleMenuUi.onKeyPressed(key)
        case GamePhase.CharacterSelect => CharacterSelectUi.onKeyPressed(key)
        case GamePhase.Playing         => onPlayingKeyPressed(key)
    }

/// 入力のエッジ検出。gameLoop が焼いた `Frame` の `justPressed`（このフレームで新たに押されたキー）
/// を各キー `onKeyPressed` ルータへ流す。前フレームとの差分計算・キー集合の持ち回りは gameLoop が担う。
def handleInput(frame: App.Frame):
                 Unit
                 \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
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
                    LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State,
                    StairsExitDriver.State} =
    Set.foldLeft((_acc, key) -> onKeyPressed(key), (), frame#justPressed)

/// Playing フェーズのキー処理。GamePhase 分岐を onKeyPressed から分離し推論複雑度を下げる。
def onPlayingKeyPressed(key: GameEngine.Key):
        Unit \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                 GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                 SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State, PlayerData.PartyQuery,
                 EnemyData.RosterQuery, CustomEffects.FloorAdvanceRequest,
                 CustomEffects.SuspendRequest,
                 Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery,
                 UiWorldState.State,
                 LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State,
                 StairsExitDriver.State} =
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
                    DangerZoneScene.toggle()
                case TurnPhase.Phase.PlayerMoving =>
                    AudioStreamPlayer.play("confirm");
                    DangerZoneScene.toggle()
                case TurnPhase.Phase.ItemSelect =>
                    AudioStreamPlayer.play("confirm");
                    ItemMenuUi.toggleMarkAtCursor()
                case TurnPhase.Phase.TradeInventory =>
                    AudioStreamPlayer.play("confirm");
                    TradeMenuUi.toggleTradeMarkAtCursor()
                case _ => ()
            }
        // C キー / ゲームパッド Y: 集合モードのトグル。
        //   PlayerCursor … 集合可能(他に生存味方が居て主人公が未行動、かつ敵が見えていない)なら
        //                  「集合」を直接確定。
        //   GatherMove   … 一歩も動いていない（手動確定直後 / 継続でターン開始した状態）なら
        //                  集合を解いて個別行動モード(PlayerCursor)へ戻す。移動を始めたら不可。
        else if (key == GameEngine.Key.C)
            if (phase == TurnPhase.Phase.PlayerCursor and ActionMenuUi.gatherEnabled()) {
                AudioStreamPlayer.play("confirm");
                ActionMenuUi.gatherShortcut()
            } else if (phase == TurnPhase.Phase.GatherMove and PlayerScene.gatherNotMovedYet()) {
                // 何も動いていないので cancelSelection の巻き戻しは実質 no-op。gatherActive を
                // 解いてカーソル選択（個別行動）へ復帰する。
                AudioStreamPlayer.play("cancel");
                PlayerScene.cancelSelection()
            } else ()
        else {
            // プレイヤー操作のフィードバック効果音（決定 / キャンセル / メニューカーソル移動）。
            // onKeyPressed は物理キー押下ごとに 1 度だけ発火するので、ここで鳴らせば 1 押下 = 1 音。
            // 実際の処理分岐 (dispatchMenuKey 等) は別途行うが、音はこの単一地点に集約する。
            playInputSfx(phase, input, key);
            // メニュー系フェーズ (ActionMenu / ItemMenu / TradeMenu) の Z/X は別関数で処理。
            // true が返れば dispatcher が処理済み。入力なし・未処理は非メニュー処理へ。
            let handled = match input {
                case Some(inp) => checked_ecast(dispatchMenuKey(phase, inp))
                case None      => false
            };
            if (handled) () else dispatchNonMenuKey(phase, input, key)
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
def staffAimDirection(key: GameEngine.Key): Unit \ ArrowCursorState.State =
    match keyToStaffDirection(key) {
        case None      => ()
        case Some(dir) => ArrowCursorScene.aim(dir)
    }

/// StaffAim フェーズで Z が押されたら、矢印が指している方向で applyStaffCast を呼ぶ。
def staffAimConfirm(): Unit \ {RangeOverlayState.State,
                                BoardQuery, GameLogger.GameLogger,
                                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                                ArrowCursorState.State,
                                GameEngine.Audio, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection();
    // 選択中プレイヤー → selectedItem（World store）を forM で 1 本に畳み、
    // 杖(Staff)を選んでいるときだけ発射する（3 段の match ネストを解消）。
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        item     <- World.selectedItemOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
    ) yield (playerId, item);
    match selected {
        case Some((playerId, PlayerData.ItemKind.Staff(idx))) =>
            StaffCast.applyStaffCast(playerId, idx, dir)
        // 投擲系の消費アイテム（目潰し薬 / 鈍足薬）も同じ StaffAim 経路で方向投擲する。
        case Some((playerId, PlayerData.ItemKind.Consumable(idx))) =>
            StaffCast.applyConsumableDirectional(playerId, idx, dir)
        case _ => ()
    }

/// ThrowAim フェーズで Z が押されたら、矢印が指している方向で選択中アイテムを投げる。
/// 種別（武器/杖/薬/指輪）に依らず `applyThrow` が振り分ける。
def throwAimConfirm(): Unit \ {RangeOverlayState.State,
                                BoardQuery, GameLogger.GameLogger,
                                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                                ArrowCursorState.State,
                                GameEngine.Audio, Math.Random,
                                CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection();
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        item     <- World.selectedItemOf(World.EntityRef.Player(playerId), World.WorldQuery.get())
    ) yield (playerId, item);
    match selected {
        case Some((playerId, kind)) =>
            StaffCast.applyThrow(playerId, kind, dir)
        case None => ()
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
/// 戻り値は「dispatcher が処理したら true、対象外なら false」。
def dispatchMenuKey(phase: TurnPhase.Phase, input: TurnRules.Input):
        Bool \ {
                  GameLogger.GameLogger, EnemyTurn.Queue,
                  TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State, GatherResume.State,
                  PlayerData.PartyQuery, EnemyData.RosterQuery,
                  CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                  CustomEffects.GameOverRequest, CustomEffects.SuspendRequest, World.Command, World.WorldQuery, BoardQuery,
                  UiWorldState.State,
                  LevelUpPanelState.State, ItemPickupPopupState.State, TitleMenuState.State, ItemMenuState.State, TradeMenuState.State, RangeOverlayState.State,
                  StairsExitDriver.State} =
        match (phase, input) {
        // 全滅メニュー: Z/Enter で選択確定（restart を emit）、X は無反応（必ず選ばせる）。
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Confirm)
                                              => { GameOverMenuUi.confirmSelection(); true }
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Cancel)
                                              => true
        // 中断確認: Z/Enter で「はい/いいえ」確定、X で中断をやめて PlayerCursor へ。
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Confirm)
                                              => { SuspendConfirmUi.confirmCurrentSelection(); true }
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Cancel)
                                              => { SuspendConfirmUi.cancel(); true }
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Confirm)
                                              => { ActionMenuUi.confirmCurrentSelection(); true }
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Cancel)
                                              => { checked_ecast(ActionMenuUi.onActionCancelled()); true }
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Confirm)
                                              => { checked_ecast(WeaponSelectUi.confirmCurrentSelection()); true }
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Cancel)
                                              => { checked_ecast(WeaponSelectUi.onCancelled()); true }
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Confirm)
                                              => { checked_ecast(ItemMenuUi.confirmCurrentSelection()); true }
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Cancel)
                                              => { checked_ecast(ItemMenuUi.onItemCancelled()); true }
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Confirm)
                                              => { checked_ecast(ItemMenuUi.confirmCurrentSelection()); true }
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Cancel)
                                              => { checked_ecast(ItemMenuUi.onActionCancelled()); true }
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Confirm)
                                              => { checked_ecast(TradeMenuUi.confirmCurrentSelection()); true }
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Cancel)
                                              => { checked_ecast(TradeMenuUi.cancelCurrent()); true }
        // レベルアップのステータス変化パネルは Z / Enter / X いずれでも閉じる（確認するだけ）。
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Confirm)
                                              => { checked_ecast(LevelUpPanelUi.confirm()); true }
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Cancel)
                                              => { checked_ecast(LevelUpPanelUi.confirm()); true }
        case _                                => false
    }

/// メニュー以外のフェーズ (GatherMove / StaffAim / AttackForecast 等) の Z/X dispatch。
/// `onKeyPressed` から `dispatchMenuKey` で処理されなかったときに呼ばれる。
/// 方向キーなど input = None もここに来る (StaffAim 中の direction、ほかは no-op)。
def dispatchNonMenuKey(phase: TurnPhase.Phase, input: Option[TurnRules.Input],
                        key: GameEngine.Key):
        Unit \ {RangeOverlayState.State, GameEngine.Audio, BoardQuery,
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
                                              => checked_ecast(staffAimCancel())
        case (TurnPhase.Phase.StaffAim,       Some(TurnRules.Input.Confirm))
                                              => checked_ecast(staffAimConfirm())
        // StaffAim 中の方向キーは applyStaffCast へ
        case (TurnPhase.Phase.StaffAim,       None)
                                              => checked_ecast(staffAimDirection(key))
        // ThrowAim（アイテム投擲）。StaffAim と同じ矢印 UI を共用し、Z で投げ確定。
        case (TurnPhase.Phase.ThrowAim,       Some(TurnRules.Input.Cancel))
                                              => checked_ecast(staffAimCancel())
        case (TurnPhase.Phase.ThrowAim,       Some(TurnRules.Input.Confirm))
                                              => checked_ecast(throwAimConfirm())
        case (TurnPhase.Phase.ThrowAim,       None)
                                              => checked_ecast(staffAimDirection(key))
        // TradeInventory 中は ←/→ と ↑↓ の両方を tradeInventoryDirection に渡す
        // (←/→ は左右ペイン切替、↑↓ は focus ペインの選択カーソル移動)。
        case (TurnPhase.Phase.TradeInventory, None)
                                              => checked_ecast(tradeInventoryDirection(key))
        // ItemSelect 中の方向キー: ↑↓ はアイテムカーソル移動、←→ はカテゴリ切替（World-entity UI）。
        case (TurnPhase.Phase.ItemSelect,     None)
                                              => itemSelectDirection(key)
        // ItemActionSelect（サブメニュー）中の ↑↓ で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.ItemActionSelect, None)
                                              => itemActionDirection(key)
        // PlayerAttack = ターゲット選択 + 戦闘予測。Z で(カーソル上の敵に)攻撃確定、
        // X でメニューに戻る。BattlePanelUi が予報表示と対象同期を担う。
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Confirm))
                                              => BattlePanelUi.confirm()
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Cancel))
                                              => checked_ecast(BattlePanelUi.cancel())
        // ActionMenu の ↑↓（W/S）で選択カーソルを動かす（World-entity UI。
        // disabled 項目はスキップする）。
        case (TurnPhase.Phase.ActionSelect,   None)
                                              => checked_ecast(actionMenuDirection(key))
        // 中断確認の ↑↓（W/S）で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.SuspendConfirm, None)
                                              => suspendConfirmDirection(key)
        // 武器選択ウィンドウの ↑↓（W/S）で武器カーソルを動かす（disabled はスキップ。
        // ←→ の対象敵サイクルは CursorScene.step が別途 polling する）。
        case (TurnPhase.Phase.WeaponSelect,   None)
                                              => checked_ecast(weaponSelectDirection(key))
        // 全滅モーダルの ↑↓（W/S）で選択カーソルを動かす（World-entity UI）。
        case (TurnPhase.Phase.GameOver,       None)
                                              => gameOverDirection(key)
        // 明示 case が無いフェーズの Z/X は TurnRules.decide にそのまま渡す
        case (_,                              Some(inp))
                                              => TurnInputBridge.handle(inp)
        // 方向キーなどはここまで来る (各 System が polling で扱う)
        case (_,                              None) => ()
    }

/// 全滅モーダル中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（端で回り込む）。他キーは素通し。
def gameOverDirection(key: GameEngine.Key): Unit \ UiWorldState.State =
    match key {
        case GameEngine.Key.Up   => GameOverMenuUi.moveSelection(-1)
        case GameEngine.Key.W    => GameOverMenuUi.moveSelection(-1)
        case GameEngine.Key.Down => GameOverMenuUi.moveSelection(1)
        case GameEngine.Key.S    => GameOverMenuUi.moveSelection(1)
        case _                   => ()
    }

/// ActionMenu（行動選択ウィンドウ）中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（disabled をスキップ・端で回り込む）。他キーは素通し。
def actionMenuDirection(key: GameEngine.Key): Unit
        \ {UiWorldState.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
    match key {
        case GameEngine.Key.Up   => ActionMenuUi.moveSelection(-1)
        case GameEngine.Key.W    => ActionMenuUi.moveSelection(-1)
        case GameEngine.Key.Down => ActionMenuUi.moveSelection(1)
        case GameEngine.Key.S    => ActionMenuUi.moveSelection(1)
        case _                   => ()
    }

/// 中断確認モーダル中の方向キーを選択カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（端で回り込む）。他キーは素通し。
def suspendConfirmDirection(key: GameEngine.Key): Unit \ UiWorldState.State =
    match key {
        case GameEngine.Key.Up   => SuspendConfirmUi.moveSelection(-1)
        case GameEngine.Key.W    => SuspendConfirmUi.moveSelection(-1)
        case GameEngine.Key.Down => SuspendConfirmUi.moveSelection(1)
        case GameEngine.Key.S    => SuspendConfirmUi.moveSelection(1)
        case _                   => ()
    }

/// 武器選択ウィンドウ中の方向キーを武器カーソル移動へ変換する。
/// Up / W → 1 つ上、Down / S → 1 つ下（disabled をスキップ・端で回り込む）。他キーは素通し。
def weaponSelectDirection(key: GameEngine.Key): Unit
        \ {UiWorldState.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
    match key {
        case GameEngine.Key.Up   => WeaponSelectUi.moveSelection(-1)
        case GameEngine.Key.W    => WeaponSelectUi.moveSelection(-1)
        case GameEngine.Key.Down => WeaponSelectUi.moveSelection(1)
        case GameEngine.Key.S    => WeaponSelectUi.moveSelection(1)
        case _                   => ()
    }

/// TradeInventory 中の方向キーを変換する（World-entity UI 化に伴い ↑↓ もここで扱う）。
/// Left / A → focus を 1 つ左へ、Right / D → 1 つ右へ（両端でラップ）。
/// Up / W → focus ペインの選択カーソルを 1 つ上、Down / S → 1 つ下（端で停止）。
def tradeInventoryDirection(key: GameEngine.Key): Unit
        \ {TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Left  => TradeMenuUi.setPaneFocusDelta(-1)
        case GameEngine.Key.A     => TradeMenuUi.setPaneFocusDelta(-1)
        case GameEngine.Key.Right => TradeMenuUi.setPaneFocusDelta(1)
        case GameEngine.Key.D     => TradeMenuUi.setPaneFocusDelta(1)
        case GameEngine.Key.Up    => TradeMenuUi.moveSelection(-1)
        case GameEngine.Key.W     => TradeMenuUi.moveSelection(-1)
        case GameEngine.Key.Down  => TradeMenuUi.moveSelection(1)
        case GameEngine.Key.S     => TradeMenuUi.moveSelection(1)
        case _                    => ()
    }

/// ItemSelect 中の方向キーを変換する。Up/Down/W/S → アイテムカーソル移動（窓スクロール）、
/// Left/A → 前カテゴリ、Right/D → 次カテゴリ（武器/消費/杖/指輪。空はスキップ）。
/// カーソル移動もカテゴリ切替も World-entity UI で完結する。
def itemSelectDirection(key: GameEngine.Key):
        Unit \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State,
                PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Up    => ItemMenuUi.moveSelection(-1)
        case GameEngine.Key.W     => ItemMenuUi.moveSelection(-1)
        case GameEngine.Key.Down  => ItemMenuUi.moveSelection(1)
        case GameEngine.Key.S     => ItemMenuUi.moveSelection(1)
        case GameEngine.Key.Left  => ItemMenuUi.categoryPrev()
        case GameEngine.Key.A     => ItemMenuUi.categoryPrev()
        case GameEngine.Key.Right => ItemMenuUi.categoryNext()
        case GameEngine.Key.D     => ItemMenuUi.categoryNext()
        case _                    => ()
    }

/// ItemActionSelect（サブメニュー）中の方向キーを選択カーソル移動へ変換する。
/// Up/Down/W/S → 1 つ上下（disabled をスキップ・端で回り込む）。他キーは素通し。
def itemActionDirection(key: GameEngine.Key):
        Unit \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State,
                PlayerData.PartyQuery, UiWorldState.State} =
    match key {
        case GameEngine.Key.Up    => ItemMenuUi.moveSelection(-1)
        case GameEngine.Key.W     => ItemMenuUi.moveSelection(-1)
        case GameEngine.Key.Down  => ItemMenuUi.moveSelection(1)
        case GameEngine.Key.S     => ItemMenuUi.moveSelection(1)
        case _                    => ()
    }

def staffAimCancel(): Unit \ TurnPhase.State =
    TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect)

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さく切り出す。Camera 追従でビューが動く。横は左右余白も使うため 240 に拡張
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

    /// ゲーム起動エントリ。Region と各 effect handler を立ち上げ、初回画面を
    /// `applyPhaseChange` で組み立てて `gameLoop` に入る。
    /// **配線役** に徹するため、ここにゲームロジックは書かない。
    pub def start(): Unit \ {GameEngine.Game, GameEngine.Audio,
                              Fs.FileRead, Fs.FileWrite, IO, Math.Random} =
        region rc {
            // BoardQuery handler が読む World の窓口（毎フレーム頭で gameLoop が更新）。World は
            // 各 store の単一権威。
            let worldRef = Ref.fresh(rc, World.empty());
            // 試練型の部屋湧きクロック。WandererSpawnRequest が来るたび +1 し、
            // EnemyScene が周期判定（tick mod N）に使う。modulo 判定ゆえフロア跨ぎのリセット不要。
            let wanderClockRef = Ref.fresh(rc, 0);
            // 味方の死亡位置（id → セル）。GameOverRequest.markDeaths が除去前に蓄積し、女神の加護の
            // 「その場復活」で参照する。id でキーするので過去フロアの残骸は復活対象 id にだけ読まれ無害。
            let deathMarksRef = Ref.fresh(rc, (Map.empty(): Map[Int32, {x = Int32, y = Int32}]));
            // 選択カーソルの視覚部（描画位置/tween/引っかかり/可視）の shell 保持。論理部（指しセル等）は
            // World.cursorLogical が単一権威で、下の CursorState facade が両者を合成/分割する。
            let cursorVisualRef = Ref.fresh(rc,
                {renderPos = Vec2.zero(),
                 tweens = (Map.empty(): EcsTween.Tweens[Int32, CursorState.Channel]),
                 snagRemaining = 0.0, visible = true});
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
                // BGM の音量 / ループは WorldSetup.attachBgm がフロア構築時に設定する (= ここでは触らない)
                // SE は半分で鳴らす
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
                applyPhaseChange(GamePhase.Title, GamePhase.Title, catalogs);
                // 初回 world は setup 後の worldRef を引き継ぐ: 起動時に spawn した World-entity UI と
                // screen=Title を含む（これらは worldRef 上に組まれるので、フレーム頭の Ref.put で消えないよう
                // 引き継ぐ）。ユニット/地形はまだ無く、以降の全 store は spawn/build choke の Cmd が seed する。
                // floorId だけは先頭フロアで初期化する: フロア build（`WorldSetup.buildCurrentFloor`）が floorId を
                // 読むのは新規ゲームの put より前になり得るため（""だと「unknown floor id」で落ちる）。
                let initialWorld =
                    World.applyCmd(World.Cmd.SetFloorId(FloorCatalog.firstFloorId(floors)), Ref.get(worldRef));
                // App 家族の宣言で走らせる: 出発点 World に「1 フレーム = frameStep」を繋ぎ、App.drive が
                // ウィンドウ・時計・入力(Frame)・終了判定・末尾再帰を担う。描画は frameStep 内で 3 チャンネル
                // （drawable/tile/polygon）を直接組むため view は None（App には描かせない）。終了は
                // ウィンドウの閉じる操作（shouldClose）だけ＝Escape ではアプリ終了しないので quit は常に false。
                let app =
                    App.make(initialWorld)
                        |> App.addSystem((frame, world) -> frameStep(catalogs, worldRef, frame, world))
                        |> App.quitWhen((_frame, _world) -> checked_ecast(false));
                App.launch(app)
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
                  // モーダルは World-entity UI（UiWorldState）で保持する。
                  def request(k) = { GameOverMenuUi.show(); k() }
                  // 「最初から」: フロアを 1F に戻し turn 系をリセットしてフルリビルド（新ラン）。
                  def restartBeginning(k) = { GameLifecycle.resetForGameOver(catalogs); k() }
                  // 「そのフロアの最初から」: 進入時スナップショットから同フロアを決定論再構築。
                  def restartFloor(k) = { GameLifecycle.restartFromFloorSnapshot(catalogs); k() }
                  // 「女神の加護」: 現フロアそのままに全員その場（死亡位置）復活・HP全快。
                  def reviveInPlace(k) = { GameLifecycle.reviveWithGoddess(catalogs, Ref.get(deathMarksRef)); k() }
              }
              with handler CustomEffects.FloorAdvanceRequest {
                  // 生存味方が全員階段を使ったら次フロアへ（最終フロアならクリア → 1F ループ）。
                  // HP / 武器 / 持ち物の引き継ぎを含め本体は GameLifecycle.advanceFloor 側。
                  def advance(k) = { GameLifecycle.advanceFloor(catalogs); k() }
              }
              with handler CustomEffects.SuspendRequest {
                  // 中断: 現フロアを slot に保存してタイトルへ戻す（本体は GameLifecycle.suspendAndQuit）。
                  def save(k) = { GameLifecycle.suspendAndQuit(catalogs); k() }
              }
              with handler CustomEffects.ResumeRequest {
                  // 中断から再開: slot を読み・状態を整え・セーブを消費して Playing へ遷移する
                  // （画面構築は applyPhaseChange(Playing, from=Title) が担う）。本体は resumeFromSuspend。
                  def resume(k) = { GameLifecycle.resumeFromSuspend(catalogs); k() }
              }
              with handler CustomEffects.WandererSpawnRequest {
                  // 試練型の部屋湧き。呼ばれるたびクロックを +1 し、その tick を渡して
                  // 現在フロアを解決し EnemyScene に委ねる（周期・上限・湧くかの判断は EnemyScene 側）。
                  // catalog とクロック Ref をクロージャに閉じ込めて使う。
                  def maybeSpawn(k) = {
                      let tick = Ref.get(wanderClockRef) + 1;
                      Ref.put(tick, wanderClockRef);
                      GameLifecycle.maybeSpawnWanderer(catalogs, tick);
                      k()
                  }
              }
              with handler CustomEffects.RingTransformRequest {
                  // ringman の特殊行動。装備外アイテムを 1 つ指輪に変える（抽選・分布は GameLifecycle 側）。
                  // Ring カタログをクロージャに閉じ込めて使う。
                  def transform(enemyName, targetId, k) = {
                      GameLifecycle.applyRingTransform(catalogs, enemyName, targetId);
                      k()
                  }
              }
              with handler CustomEffects.ThiefDropRequest {
                  // 盗人の剣: 現在フロアの items ドロップ表から抽選してアイテムを cell に落とす。
                  // フロア表 + 各カタログをクロージャに閉じ込めて使う。
                  def drop(cell, k) = { GameLifecycle.dropFloorItem(catalogs, cell); k() }
              }
              // World ランタイムの読み書き seam（BoardQuery / World.Command / StatusQuery /
              // PhaseQuery / WorldQuery / RngDraw）は WorldDriver.withWorld に集約。CustomEffects
              // handler（深部の emit 元）より外側・PartyQuery/RosterQuery より内側に置く。
              with WorldDriver.withWorld(worldRef)
              with handler PlayerData.PartyQuery {
                  // 全 field・在籍列挙とも権威は World。`dataFromWorld`（store 群からの再構築）で読む。
                  // ★意味論: worldRef は emit で mid-frame 先行（即時 `Cmd` 適用）＝BoardQuery と同じ mid-frame 権威。
                  def get(id, k)           = k(World.dataFromWorld(id, Ref.get(worldRef)))
                  def getAll(k)            = {
                      let world = Ref.get(worldRef);
                      k(World.playerIdsOf(world) |> List.filterMap(id -> World.dataFromWorld(id, world)))
                  }
              }
              with handler EnemyData.RosterQuery {
                  // PartyQuery と同流儀で全 field・在籍列挙とも権威は World（`dataFromWorldEnemy`）。
                  // findIdAt/anyAttacking は World の pos/attackTarget を直読み。
                  def get(id, k)           = k(World.dataFromWorldEnemy(id, Ref.get(worldRef)))
                  def getAll(k)            = {
                      let world = Ref.get(worldRef);
                      k(World.enemyIdsOf(world) |> List.filterMap(id -> World.dataFromWorldEnemy(id, world)))
                  }
                  def findIdAt(coord, k)   = k(World.enemyIdAt(coord, Ref.get(worldRef)))
                  def anyAttacking(k)      = k(World.anyEnemyAttacking(Ref.get(worldRef)))
              }
              with handler GamePhaseState {
                  // 進行画面の単一権威は World.screen。get/put とも facade で World 経由（呼び出し側 4+4 は無改修）。
                  def get(k)         = k(World.screenOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetScreen(target), Ref.get(worldRef)), worldRef); k() }
              }
                with Pacing.withState(rc)           // 演出の溜め (hold)
              with LogState.withState(rc)         // ログ HUD の状態（queue/idleSince）を resource 化
              with BattlePanelState.withState(rc) // 戦闘予報パネルの点滅タイマーを resource 化
              with TurnEndHoldState.withState(rc) // ターンスキップ長押しゲージの状態を resource 化
              with LevelUpPanelState.withState(rc) // レベルアップ演出パネルの状態を resource 化
              with TopBarState.withState(rc) // 上部バーの状態を resource 化
              with handler TitleMenuState.State {
                  // タイトル画面状態（2択カーソル/再開可否）の単一権威は World.titleMenu。
                  def get(k)         = k(World.titleMenuOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetTitleMenu(target), Ref.get(worldRef)), worldRef); k() }
              }
              with UnitHPBarRender.withForecast(rc) // 攻撃予報（減る分点滅）の view 状態
              with ItemPickupPopupState.withState(rc) // 中央アイテム取得ポップアップの状態を resource 化
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with handler EnemyTurn.Queue {
                  // 敵ターン step キューの単一権威は World.enemyTurnQueue。各 op を worldRef+applyCmd で実装
                  // （呼び出し側 TurnFlow/EnemyTurnDriver/CameraScene は無改修・test は withQueue の Ref）。
                  def popFront(k) =
                      match World.enemyTurnQueueOf(Ref.get(worldRef)) {
                          case Nil    => k(None)
                          case h :: t =>
                              Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(t), Ref.get(worldRef)), worldRef);
                              k(Some(h))
                      }
                  def pushFront(step, k) = {
                      Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(step :: World.enemyTurnQueueOf(Ref.get(worldRef))), Ref.get(worldRef)), worldRef);
                      k()
                  }
                  def replace(steps, k) = {
                      Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(steps), Ref.get(worldRef)), worldRef);
                      k()
                  }
                  def peekFront(k) =
                      match World.enemyTurnQueueOf(Ref.get(worldRef)) {
                          case Nil    => k(None)
                          case h :: _ => k(Some(h))
                      }
                  def isEmpty(k) = k(List.isEmpty(World.enemyTurnQueueOf(Ref.get(worldRef))))
              }
              with handler TurnPhase.State {       // World 単一権威への facade（get/put とも World.turnPhase 経由・呼び出し側 38+31 は無改修）
                  def get(k) = k(World.turnPhaseOf(Ref.get(worldRef)))
                  def put(target, k) = {
                      Ref.put(World.applyCmd(World.Cmd.SetPhase(target), Ref.get(worldRef)), worldRef);
                      k()
                  }
              }
              with handler SelectedPlayer.State {
                  // 操作中プレイヤーの選択状態（id / 移動ドラフト / 集合モード）の単一権威は World.selection。
                  // get/put とも facade で World 経由（呼び出し側 get51/put9 は無改修・test は各 SelectedPlayer handler）。
                  def get(k)         = k(World.selectionOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetSelection(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler CursorState.State {
                  // 論理部（指しセル/ホバー/加速の hold）の単一権威は World.cursorLogical。視覚部（描画位置/
                  // tween/引っかかり/可視）は shell の cursorVisualRef 残置。get は両者を合成し、put は
                  // 論理→World・視覚→Ref に分けて書く（呼び出し側は whole Data のまま無改修・test は CursorState.withState の Ref）。
                  def get(k) = {
                      let lg = World.cursorLogicalOf(Ref.get(worldRef));
                      let vs = Ref.get(cursorVisualRef);
                      k({gridPos = lg#gridPos, lastHoveredEnemyId = lg#lastHoveredEnemyId,
                         holdDir = lg#holdDir, holdSteps = lg#holdSteps,
                         renderPos = vs#renderPos, tweens = vs#tweens,
                         snagRemaining = vs#snagRemaining, visible = vs#visible})
                  }
                  def put(target, k) = {
                      Ref.put(World.applyCmd(World.Cmd.SetCursorLogical(
                          {gridPos = target#gridPos, lastHoveredEnemyId = target#lastHoveredEnemyId,
                           holdDir = target#holdDir, holdSteps = target#holdSteps}),
                          Ref.get(worldRef)), worldRef);
                      Ref.put({renderPos = target#renderPos, tweens = target#tweens,
                               snagRemaining = target#snagRemaining, visible = target#visible}, cursorVisualRef);
                      k()
                  }
              }
              with CameraState.withState(rc)      // 追従カメラの視点状態（ターゲット/smoothPosition/追従パラメータ）を resource 化
              with handler RangeOverlayState.State {
                  // 範囲オーバーレイ 7 種のセル集合（Option 在/不在=表示トグル）の単一権威は World.rangeOverlay。
                  // get/put とも facade で World 経由（呼び出し側 20 ファイルは無改修・test は withState の Ref）。
                  def get(k)         = k(World.rangeOverlayOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetRangeOverlay(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler ArrowCursorState.State {
                  // 照準矢印の論理状態（anchor/direction/gridPos）の単一権威は World.arrowCursor。
                  // get/put とも facade で World 経由（呼び出し側 get3/put2 は無改修・test は withState の Ref）。
                  def get(k)         = k(World.arrowCursorOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetArrowCursor(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler StairsExitDriver.State {
                  // 集合「階段」の順次退場ドライバ状態（退場キュー/停滞カウンタ）の単一権威は World.stairsExit。
                  def get(k)         = k(World.stairsExitOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetStairsExit(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler GatherResume.State {
                  // 集合モードのターン跨ぎ自動継続フラグの単一権威は World.gatherResume。
                  // get/put とも facade で World 経由（呼び出し側 TurnFlow/EnemyTurnDriver は無改修・test は withState の Ref）。
                  def get(k)         = k(World.gatherResumeOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetGatherResume(target), Ref.get(worldRef)), worldRef); k() }
              }
              with InitialSpawns.withState(worldRef)    // ゲームオーバー時に同じ敵 / 味方配置を復元 World.initialSpawns 単一権威
              with FloorSnapshot.withState(worldRef)    // 進入時フロアスナップショット（全滅時の「フロア最初から」用）World.floorSnapshot 単一権威
              with FloorProgress.withState(worldRef)  // 現在フロア id World.floorId 単一権威
              with PartySelection.withState(worldRef)   // 出撃メンバー（開始時に1回抽選、フロア間で維持）World.party 単一権威
              with handler CharacterSelectState.State {
                  // 出撃メンバー選択画面の選択状態の単一権威は World.characterSelect。
                  def get(k)         = k(World.characterSelectOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetCharacterSelect(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler ItemMenuState.State {
                  // アイテム窓の選択状態（カテゴリ index / 一括選択マーク）の単一権威は World.itemMenu。
                  // get/put とも facade で World 経由（呼び出し側 3 ファイルは無改修・test は withState の Ref）。
                  def get(k)         = k(World.itemMenuOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetItemMenu(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler TradeMenuState.State {
                  // 物交換窓のセッション状態（members/focus/pick/origin/marks/markPane）の単一権威は World.tradeMenu。
                  // get/put とも facade で World 経由（呼び出し側 5 ファイルは無改修・test は withState の Ref）。
                  def get(k)         = k(World.tradeMenuOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetTradeMenu(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler UiWorldState.State {
                  // World-entity UI（全滅モーダル等）の状態の単一権威は World.uiWorld。
                  // get/put とも facade で World 経由（呼び出し側 20 ファイルは無改修・test は withState の Ref）。
                  def get(k)         = k(World.uiWorldOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetUiWorld(target), Ref.get(worldRef)), worldRef); k() }
              }
              with handler MinimapState.State {
                  // ミニマップ表示トグル（M）状態の単一権威は World.minimap。
                  def get(k)         = k(World.minimapOf(Ref.get(worldRef)))
                  def put(target, k) = { Ref.put(World.applyCmd(World.Cmd.SetMinimap(target), Ref.get(worldRef)), worldRef); k() }
              }
        }

    /// GamePhase に応じて画面を組み立てる。**配線役** に徹し、各画面の構築は
    /// `WorldSetup` の対応関数へ委譲するだけ（画面固有のロジックはここに書かない）。
    ///   Title           — タイトル画面（はじめから / 中断から再開）。
    ///   CharacterSelect — 出撃メンバー選択画面。
    ///   Playing         — 現在フロアのダンジョン（`prevPhase` で新規ラン / 中断再開を出し分け）。
    /// gameLoop が前フレームとの差分を見て、画面が変わったフレームだけ呼ぶ。
    def applyPhaseChange(phase: GamePhase, prevPhase: GamePhase, catalogs: GameLifecycle.Catalogs):
            Unit
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, IO, Math.Random,
                SelectedPlayer.State, CursorState.State, ArrowCursorState.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, CharacterSelectState.State, GameLogger.GameLogger, FloorSnapshot.State, World.Command,
                World.WorldQuery, TitleMenuState.State, TopBarState.State, UiWorldState.State, RangeOverlayState.State, CameraState.State} =
        match phase {
            case GamePhase.Title           => WorldSetup.buildTitle()
            case GamePhase.CharacterSelect => WorldSetup.buildCharacterSelect(catalogs)
            case GamePhase.Playing         => WorldSetup.buildPlaying(catalogs, prevPhase)
        }

    /// メインループ。phase で分岐せず、**固定パイプライン** を毎フレーム回す:
    ///   handleInput → 移動/カーソル polling → 戦闘シグナル解決 → 各 UI frameStep → World step → 描画
    /// 各 System 内で「自分が今動くべきか」を phase で判断する。
    /// 例: `EnemyTurnDriver.step` は phase=EnemyTurn / PlayerAttackHold で動作、
    ///     `PlayerMovementDriver.step` は phase=GatherMove で主人公(id 0)を動かす。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def frameStep(catalogs: GameLifecycle.Catalogs,
                  worldRef: Ref[World, r],   // BoardQuery handler が読む World の窓口（フレーム頭で更新）。
                  frame: App.Frame,          // App が焼いたこのフレームの入力（down / justPressed / dt）。
                  world: World):             // 前フレーム末の権威 World（App がスレッド）。screen から前フレーム画面を導く。
                 World \ {GameEngine.Game, GameEngine.Audio,
                         Fs.FileRead, IO,
                         BoardQuery,
                         PlayerData.PartyQuery, EnemyData.RosterQuery,
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
                         World.Command, World.PhaseQuery, World.WorldQuery,
                         World.RngDraw, UiWorldState.State, MinimapState.State, RangeOverlayState.State, CameraState.State,
                         StairsExitDriver.State, r} = {
            // BoardQuery handler が読む窓口を最新の world に更新する。
            // world は前フレーム末の権威 World（world2）＝各 store の単一権威。
            Ref.put(world, worldRef);
            // 前フレームの画面は incoming world の screen（World 権威）から導く（App がスレッドした world）。
            let previousPhase = World.screenOf(world);
            // dt は App が焼いた frame#dt（秒）から Duration へ戻す。getDeltaTime はフレーム内で状態を
            // 進めるため二度読みせず、App が読んだ 1 回ぶんの値（frame#dt）を使う。
            let dt = Duration.seconds(frame#dt);
            // Pacing カウンタを 1 フレーム進める (各 System が gating で参照する)。
            // フレーム頭で進めるので「前フレーム末で hold した値を今フレームの判定で使う」
            // 形になる。
            Pacing.State.tick(dt);
            // 入力のエッジ検出（frame#justPressed → onKeyPressed ルータ）。frame は App が焼いて渡す
            // （生キー読み・prevKeys 持ち回りは App.drive が担う＝App 家族の入力モデル）。
            handleInput(frame);
            // 手動移動の入力ポーリングを明示 System として 1 回呼ぶ
            // （PlayerMoving=選択中の味方 / GatherMove=主人公。phase 判定は step 内部）。
            PlayerMovementDriver.step(frame);
            // カーソルの入力ポーリングも明示 System として 1 回呼ぶ（盤面がある画面のみ —
            // stepOnBoard が Map 存在をゲートする）。
            CursorScene.stepOnBoard(frame, dt);
            // 戦闘演出クロック（lunge の往復・死亡点滅の完了）を dt 進め、中点 Hit / 完了 Done の
            // signal を取り出して worldRef へ確定する。入力処理の後・stepEntities の前＝
            // 入力で始まった lunge は同フレームから進む。GameOver 中は進めない（盤面フリーズ）。
            let animSignals =
                if (TurnPhase.State.get() == TurnPhase.Phase.GameOver) Nil
                else {
                    let (wA, sigs) = World.stepAnimClocks(Duration.toSeconds(dt),
                                         EnemyScene.deathBlinkTotalSeconds(), Ref.get(worldRef));
                    Ref.put(wA, worldRef);
                    sigs
                };
            // カーソルのスライド補間・snag タイマーを dt 進めて renderPos を書く
            // （カーソルは engine Tween を使わずここで直接進める。CameraScene.step より前）。
            CursorScene.stepVisual(dt);
            // Player / Enemy の戦闘シグナル解決を明示 System として回す。
            CombatDriver.stepEntities(animSignals);
            // 表示系は明示 step で駆動する。
            // 順序制約: TopBar は EnemyTurnDriver が World 経由で読む 2 bool の dual-write 元なので
            // driver step より前に置く。TurnEndHold はログ帯を上書きするため LogUi.step より後に置く。
            // 他は独立。
            TopBarUi.step(dt);
            ItemPickupPopupUi.frameStep(dt);
            CharacterSelectUi.frameStep(dt);
            LogUi.step(dt);
            TurnEndHoldUi.frameStep(frame, dt);
            CameraScene.step(dt);
            // ターン進行 LOGIC driver は frame-paced System としてパイプライン段で 1 回呼ぶ（gameLoop が駆動）。
            // 戦闘シグナル解決と TopBar 更新が確定した後に置く（前後依存は World 経由で順序非依存）。
            EnemyTurnDriver.step();
            StairsExitDriver.step();
            // view driver（Minimap の訪問記憶蓄積/M トグル）は明示 step 化のまま。フォグは
            // step を持たず、敵可視・暗幕・lit ゲートは描画時に `FogScene.holesNow` から導出する。
            // 照準矢印も step を持たず、描画（RenderWorld.renderArrowCursor）が phase から可視を決める。
            MinimapScene.step(frame);
            // 全滅モーダル UI の可視/選択ハイライトを phase から同期。
            GameOverMenuUi.frameStep(dt);
            // 行動選択ウィンドウの可視/項目流し込み/選択ハイライトを phase から同期。
            ActionMenuUi.frameStep(dt);
            // 武器選択ウィンドウの可視/行流し込み/選択ハイライト/カーソルスナップを phase から同期。
            WeaponSelectUi.frameStep(dt);
            // アイテム選択ウィンドウ（ItemSelect/ItemActionSelect）の可視/窓流し込み/選択ハイライトを phase から同期。
            ItemMenuUi.frameStep(dt);
            // 物交換ウィンドウ（TradeInventory）の可視/中央寄せ/各ペインの窓流し込み/フォーカス表現を phase から同期。
            TradeMenuUi.frameStep(dt);
            // 中断確認モーダルの可視/選択ハイライトを phase から同期。
            SuspendConfirmUi.frameStep(dt);
            // タイトル画面の選択ハイライト/再開不可の淡色を毎フレーム同期（root 可視時のみ）。
            TitleMenuUi.frameStep(dt);
            // ユニット簡易カード（味方左 / 敵右）の表示対象を解決して流し込む。
            UnitCardUi.frameStep(dt);
            // 攻撃前の戦闘予報ミニウィンドウの可視/数値/相性矢印/対象近傍への追従を phase から同期。
            // カーソルスナップ（WeaponSelectUi.frameStep）とカメラ配置（CameraScene.step）の後に置き、
            // 対象の敵・画面座標を最新で読む。
            BattlePanelUi.frameStep(dt);
            // レベルアップ演出パネルの可視/本文の段階表示を phase から同期。
            LevelUpPanelUi.frameStep(dt);
            // 画面（GamePhase）が変わったフレームだけ、新しい画面を組み立て直す。
            // 例: 選択画面でリーダー確定 → Playing に切り替わり、ここでダンジョンが組まれる。
            // 押下キー集合（currentKeys）はループ引数で持ち回るため、画面を組み替えても失われない
            // ＝遷移を起こしたキー（例: 中断確定の Z）が新画面で「押し直し」と誤検知されて
            // 即確定されることはない。
            if (currentPhaseChanged(previousPhase))
                applyPhaseChange(GamePhaseState.get(), previousPhase, catalogs)
            else ();
            // 毎フレームの World System パイプライン（refreshMirror → stepWorld → phase parity 検査）は
            // `WorldDriver.stepFrame` に集約。current は mid-frame 権威（worldRef 値）。
            let world2 = WorldDriver.stepFrame(Ref.get(worldRef), dt);
            // render-from-World。全チャンネル（drawable/tile/polygon）を World 由来で組み、
            // 1 回の renderCommands で描く。描画セクションは `renderFrame` へ抽出（メソッドサイズ上限対策）。
            renderFrame(catalogs, world2);
            // このフレームの権威 World を App へ返す（App が次フレームへスレッドし、終了判定・
            // prevKeys 持ち回り・末尾再帰を担う）。
            world2
        }

    /// 画面（GamePhase）がこのフレームで変わったか。
    def currentPhaseChanged(previousPhase: GamePhase): Bool \ GamePhaseState =
        GamePhaseState.get() != previousPhase
}

/// テスト専用の公開窓。本番の `renderFrame` をそのまま呼ぶ（複製しない＝本番と同一の描画合成）。
/// 描画リストは呼び出し側が `GameEngine.Game.renderCommands` を記録する handler で捕まえる。
/// production 経路（gameLoop）からは呼ばれない。
pub def renderFrameForCapture(catalogs: GameLifecycle.Catalogs, world: World):
        Unit \ {GameEngine.Game, SelectedPlayer.State, World.WorldQuery, UnitHPBarRender.ForecastState,
                UiWorldState.State, TurnPhase.State, ArrowCursorState.State, MinimapState.State,
                RangeOverlayState.State, CursorState.State, CameraState.State} =
    renderFrame(catalogs, world)

/// フレーム描画（render-from-World の合流点）。gameLoop のサイズ削減のため関数分離。
/// fog・range・配置物・fx・minimap・HUD/menu はすべて World render System（各 render*）で描く。
/// camera ViewTransform はフレーム 1 回だけ計算して共有。
def renderFrame(catalogs: GameLifecycle.Catalogs, world2: World):
        Unit \ {GameEngine.Game, SelectedPlayer.State, World.WorldQuery, UnitHPBarRender.ForecastState,
                UiWorldState.State, TurnPhase.State, ArrowCursorState.State, MinimapState.State,
                RangeOverlayState.State, CursorState.State, CameraState.State} =
    let transform = RenderWorld.viewTransform();
    // ミニマップは Drawable（矩形）と Polygon（マーカー円）の 2 チャンネルを 1 度に組む（画面固定）。
    let minimap = RenderWorld.renderMinimap();
    // fog の明るい穴を frame に 1 回計算し、ユニット/HP バー/武器アイコンの敵可視ゲートと
    // 配置物直描きの lit ゲートで共有。
    let holesOpt = FogScene.holesNow();
    // World-entity UI を 1 度のレイアウト解決で sprite（drawables）と polygon の 2 チャンネルへ射影。
    let uiRendered = UiHud.renderUi();
    let worldDrawables = RenderWorld.renderUnits(world2, holesOpt, transform)
        // 配置物/fx/HP バー/武器アイコンは World store + catalog/定数から直描き。
        |> List.append(RenderWorld.renderStairs(world2, holesOpt, transform))
        |> List.append(RenderWorld.renderChests(catalogs#chests, world2, holesOpt, transform))
        |> List.append(RenderWorld.renderItems(world2, holesOpt, transform))
        |> List.append(RenderWorld.renderPopups(world2, transform))
        |> List.append(RenderWorld.renderExplosions(world2, transform))
        |> List.append(UnitHPBarRender.renderBars(world2, holesOpt, transform))
        |> List.append(WeaponIconRender.renderPlates(world2, holesOpt, transform))
        |> List.append(RenderWorld.renderFog(holesOpt, transform))
        |> List.append(RenderWorld.renderRangeOverlays(transform))
        // 選択カーソルの四隅 L字（CursorState renderPos＋visible）と杖照準矢印（ArrowCursorState＋phase）を直描き。
        |> List.append(RenderWorld.renderCursor(world2, transform))
        |> List.append(RenderWorld.renderArrowCursor(transform))
        // ミニマップの部屋/床矩形（画面固定 HUD レイヤ）。
        |> List.append(minimap#drawables)
        // World-entity UI（全滅モーダル・TopBar 等）の box/text/sprite を HUD レイヤに合流（画面固定・camera 免除）。
        |> List.append(uiRendered#drawables);
    // polygon チャンネルは minimap のマーカー円 ＋ per-unit 武器グリフに、World-entity UI 由来 polygon
    //   （TopBar の集合中▶ / TurnEndHold の充填リング / BattlePanel の相性三角）を合流。
    GameEngine.Game.renderCommands(worldDrawables,
        RenderWorld.renderTileMaps(world2, transform),
        List.append(RenderWorld.renderFireShots(world2, transform),
            List.append(minimap#polygons,
                List.append(WeaponIconRender.renderGlyphs(world2, holesOpt, transform),
                            uiRendered#polygons))))
