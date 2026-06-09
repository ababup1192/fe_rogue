/// ゲーム全体の進行状態。ノード単位の状態（NodeTag）や戦闘ターンのサブフェーズ（TurnPhase）
/// とは別レイヤーで、「今どの画面か」を表す。
///   CharacterSelect — 起動直後の出撃メンバー / リーダー選択画面。
///   Playing         — ダンジョン本編。
pub enum GamePhase with Eq {
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
    /// CharacterSelectScene のルート CanvasLayer（出撃メンバー選択画面の状態を持つ）
    case CharacterSelect(CharacterSelectScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case EnemyRange(EnemyRangeScene.Data)
    /// EnemyAttackRangeScene の赤マス overlay（敵の攻撃到達=脅威範囲。移動範囲の外側）
    case EnemyAttackRange(EnemyAttackRangeScene.Data)
    case PlayerAttackRange(PlayerAttackRangeScene.Data)
    case MoveAttackRange(MoveAttackRangeScene.Data)
    /// TradeRangeScene の緑マス overlay（「こうかん」確定後の隣接味方マス）
    case TradeRange(TradeRangeScene.Data)
    /// DangerZoneScene の紫マス overlay（Shift トグル: 全敵に攻撃されうるマスの統合）
    case DangerZone(DangerZoneScene.Data)
    case Cursor(CursorScene.Data)
    /// ArrowCursorScene の Marker2D（杖発射方向を視覚化する矢印カーソル）
    case ArrowCursor(ArrowCursorScene.Data)
    /// StairsScene の Marker2D（フロアの階段。床のランダムセルに 1 つ配置される）
    case Stairs(StairsScene.Data)
    case Log(LogScene.Data)
    /// ItemMenuScene の Panel ルート（外枠）
    case ItemPanel
    /// ItemMenuScene の ItemList（武器+杖の一覧 + サブメニュー兼用）。
    /// 内部の Int32 は現在表示中のページ番号（0 起点）。ロード職は 16 個 = 2 ページ持てるため、
    /// ←/→ でページを切り替えるとここが更新され、refreshItems がそのページぶんを並べ直す。
    case ItemMenu(Int32)
    /// TradeMenuScene の Panel ルート（members / focus / pick / origin を抱えるセッション状態）
    case TradePanel(TradeMenuScene.PanelData)
    /// TradeMenuScene の各ペイン ItemList。内部の Int32 はペイン index (0 起点、最大 3)。
    case TradeMenu(Int32)
    /// ActionMenuScene の Panel ルート（外枠）
    case ActionPanel
    /// ActionMenuScene の ItemList（こうげき / たいき）
    case ActionMenu
    /// BattlePanelScene の Panel ルート（戦闘予報の外枠）。
    /// 内部の Duration は HP シミュレーション点滅のサイクル内経過時間（process で進める）。
    case BattlePanel(Duration.Duration)
    /// BattlePanelScene の Label2D（HP / 威力 / 命中 を 2 列で表示）
    case BattleText
    /// LevelUpPanelScene の Panel ルート（レベルアップ時のステータス変化パネルの外枠）。
    /// 内部 state は演出の進行（bonus 再生済みか / 右側を出し終えた上昇ステータス数 / 次までの残り時間）。
    case LevelUpPanel(LevelUpPanelScene.PanelState)
    /// DamagePopupScene の Marker2D 親（World 直下に永続）
    case DamagePopupsRoot(DamagePopupScene.RootData)
    /// DamagePopupScene の Label2D 子（寿命を持つ）
    case DamagePopup(DamagePopupScene.PopupData)
    /// UnitHPBarScene の Marker2D 親（戦闘表示 timer + currentHp/maxHp を持つ）
    case HPBar(UnitHPBarScene.HPBarData)
    /// UnitInfoPopupScene の CanvasLayer 親（表示中ユニット識別子を持つ）
    case UnitInfoPanel(UnitInfoPopupScene.PanelState)
    /// PhaseBannerScene の CanvasLayer 親（ターン切替バナーのスライド演出状態を持つ）
    case PhaseBanner(PhaseBannerScene.BannerData)
    /// ItemPickupPopupScene の CanvasLayer 親（アイテム取得ポップアップのフェード演出状態を持つ）
    case ItemPickupPopup(ItemPickupPopupScene.PopupData)
    /// ItemScene の床に落ちている武器（拾える）
    case GroundItem(ItemScene.Data)
    /// `EnemyTurnDriverScene` の常駐タグ専用ノード (Marker2D)。process redef で phase を
    /// 見て EnemyTurn 中なら stepOnce、PlayerAttackHold 中なら hold 終了判定を行う。
    case EnemyTurnDriver
    /// `AutoMoveScene` の常駐タグ専用ノード (Marker2D)。
    /// `AutoMoveScene.process` redef で phase を見て PlayerAutoMove 中なら `step` を呼ぶ。
    case AutoMoveDriver
    /// `FogScene` の常駐タグ専用ノード (Marker2D)。process redef で毎フレーム、現在パーティの
    /// いる部屋/通路だけ明るくし、それ以外は薄暗いモヤ＋敵/アイテム/階段を非表示にする。
    case FogDriver
    /// `MinimapScene` の常駐タグノード (Marker2D)。process redef で毎フレーム、訪問済み
    /// module を蓄積 (Set[Int32]) し、M キーで全画面ミニマップを出し入れ・再描画する。
    case MinimapDriver(MinimapScene.DriverData)
    /// `ControlHintScene` の CanvasLayer 親。直近に表示した操作ガイド 1 行を保持し、
    /// process redef で毎フレーム文脈に合わせて Z/X ボタンの案内文を出し分ける。
    case ControlHint(String)
    case NoTag
}

// physicsProcess はフェーズに応じて Player / Cursor のいずれか 1 体だけを
// dispatch する。`PlayerMoving` 中は **選択中の味方 1 体だけ** が方向キーを polling する。
// Cursor は `PlayerCursor` / `PlayerAttack` の両方で動くため、ここでは
// NodeTag だけで dispatch して **phase 判定は `CursorScene.physicsProcess` の内部** に任せる。
// それ以外のフェーズ（`EnemyTurn` 等）では各関数が `(node, scene)` を返して no-op になる。
instance Node[NodeTag] {
    type Aef = FrameAef.T
    type ProcessAef = FrameAef.ProcessT
    redef physicsProcess(delta: Duration.Duration,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.T =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(data)) =>
                // 選択中プレイヤー & PlayerMoving フェーズだけが移動を受け付ける。
                // ローグ移動モード(RogueMove)ではロード(id 0)が移動力制限なしで自由歩行する。
                let phase = TurnPhase.State.get();
                if (phase == TurnPhase.Phase.PlayerMoving
                    and SelectedPlayer.State.get()#id == Some(data#id))
                    PlayerScene.physicsProcess(delta, node, path, scene)
                else if (phase == TurnPhase.Phase.RogueMove and data#id == 0)
                    PlayerScene.lordRoamProcess(delta, node, path, scene)
                else (node, scene)
            case EngineNode.Marker2DWithState(_, NodeTag.Cursor(_)) =>
                // PlayerCursor / PlayerAttack の場合分けは CursorScene 内部に閉じている
                CursorScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
    // 各 ノード固有の毎フレーム更新を dispatch する。各 Scene が「自分のノード」に対する
    // process redef を持ち、ここでは「どの NodeTag をどの Scene 関数に流すか」の対応表に徹する。
    // Player / Enemy は AnimationPlayer signal を自分で drain (Godot 流 per-AnimationPlayer)。
    // BattlePanel の Label2D テキストはフェーズ入り時のワンショット更新なので process では触らない。
    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                   path: NodePath, scene: Scene[NodeTag]):
                  (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
        // dispatch を 4 群に分割して呼ぶ。それぞれの本体は match で自分の担当
        // ノードタイプ以外は (node, scene) を返す (pass-through) ので、合計 1 回の
        // 巡回で各ノードが該当 1 関数に振り分けられる。
        // 分割理由: Flix の型推論で 1 つの match arm 数が増えすぎると複雑度上限を
        // 超えるため、各群を独立した signature で推論させる。
        let (n1, s1) = dispatchEntities(delta, node, path, scene);
        let (n2, s2) = dispatchTickables(delta, n1, path, s1);
        let (n3, s3) = dispatchDrivers(delta, n2, path, s2);
        dispatchMenus(delta, n3, path, s3)
}

/// Player / Enemy ノード (AnimationPlayer signal drain を持つエンティティ系)
def dispatchEntities(delta: Duration.Duration, node: EngineNode[NodeTag],
                      path: NodePath, scene: Scene[NodeTag]):
                     (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.Marker2DWithState(_, NodeTag.Player(_)) =>
            checked_ecast(PlayerScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.Enemy(_)) =>
            checked_ecast(EnemyScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// 毎フレーム tick が必要な表示系ノード (Popup / HPBar / Item / UnitInfoPanel / Camera / Log)
def dispatchTickables(delta: Duration.Duration, node: EngineNode[NodeTag],
                       path: NodePath, scene: Scene[NodeTag]):
                      (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.Marker2DWithState(_, NodeTag.DamagePopupsRoot(_)) =>
            checked_ecast(DamagePopupScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.HPBar(_)) =>
            checked_ecast(UnitHPBarScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.GroundItem(_)) =>
            checked_ecast(ItemScene.process(delta, node, path, scene))
        case EngineNode.CanvasLayerWithState(_, NodeTag.UnitInfoPanel(_)) =>
            checked_ecast(UnitInfoPopupScene.process(delta, node, path, scene))
        case EngineNode.CanvasLayerWithState(_, NodeTag.PhaseBanner(_)) =>
            checked_ecast(PhaseBannerScene.process(delta, node, path, scene))
        case EngineNode.CanvasLayerWithState(_, NodeTag.ControlHint(_)) =>
            checked_ecast(ControlHintScene.process(delta, node, path, scene))
        case EngineNode.CanvasLayerWithState(_, NodeTag.ItemPickupPopup(_)) =>
            checked_ecast(ItemPickupPopupScene.process(delta, node, path, scene))
        case EngineNode.CanvasLayerWithState(_, NodeTag.CharacterSelect(_)) =>
            checked_ecast(CharacterSelectScene.process(delta, node, path, scene))
        case EngineNode.Camera2DWithState(_, _) =>
            checked_ecast(CameraScene.process(delta, node, path, scene))
        case EngineNode.RichTextLabelWithState(_, NodeTag.Log(_)) =>
            checked_ecast(LogScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// フェーズ駆動の driver ノード (EnemyTurnDriver / AutoMoveDriver / ArrowCursor)
def dispatchDrivers(delta: Duration.Duration, node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.Marker2DWithState(_, NodeTag.EnemyTurnDriver) =>
            checked_ecast(EnemyTurnDriverScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.AutoMoveDriver) =>
            checked_ecast(AutoMoveScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.ArrowCursor(_)) =>
            checked_ecast(ArrowCursorScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.FogDriver) =>
            checked_ecast(FogScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.MinimapDriver(_)) =>
            checked_ecast(MinimapScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// メニュー系ノード (ItemMenu / ActionMenu の ItemList、BattlePanel の Panel)
def dispatchMenus(delta: Duration.Duration, node: EngineNode[NodeTag],
                   path: NodePath, scene: Scene[NodeTag]):
                  (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.ItemListWithState(_, NodeTag.ItemMenu(_)) =>
            checked_ecast(ItemMenuScene.refreshItems(delta, node, path, scene))
        case EngineNode.ItemListWithState(_, NodeTag.ActionMenu) =>
            checked_ecast(ActionMenuScene.refreshItems(delta, node, path, scene))
        case EngineNode.ItemListWithState(_, NodeTag.TradeMenu(_)) =>
            checked_ecast(TradeMenuScene.refreshItems(delta, node, path, scene))
        case EngineNode.PanelWithState(_, NodeTag.BattlePanel(_)) =>
            checked_ecast(BattlePanelScene.process(delta, node, path, scene))
        case EngineNode.PanelWithState(_, NodeTag.LevelUpPanel(_)) =>
            checked_ecast(LevelUpPanelScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

// 決定キー（Z / Space / Enter）/ キャンセルキー（X）の意味はフェーズで変わる。
// 判断ロジックは `TurnRules.decide` に集約してあり、ここでは
// 「キー → Input → 判断 → apply」という配線だけを行う（実体は `GameManager`）。
//
//   PlayerCursor + Z   : 味方マス → 選択 / それ以外 → しゅうごうメニュー
//   PlayerMoving + Z/X : Tween 中はガード。Z で攻撃フェーズ、X で origin へ戻して PlayerCursor
//   PlayerAttack + Z/X : 敵マスで Z → 攻撃モーション開始、X / 空マスで Z → 行動終了
//   EnemyTurn / PlayerAutoMove : 入力無視（自動進行）
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {GameEngine.Game, GameEngine.Audio, BoardQuery, Tween.Scheduler,
                 AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State,
                 PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                 CustomEffects.FloorAdvanceRequest,
                 GamePhaseState, PartySelection.State}
    // ActionMenu / ItemMenu / ItemActionMenu / AttackForecast フェーズでは
    // FERogue のキー慣習として Z（決定）/ X（ウィンドウを閉じる）でメニュー操作する。
    // ItemMenu と ItemActionMenu は同じ ItemMenuScene が扱い、`confirmCurrentSelection`
    // 内部で現在のフェーズに応じて分岐する。
    // PlayerCursor / PlayerAttack 中で UnitInfoPopup が表示中なら、**X は popup の
    // Status ↔ Items 切替**に取られる（通常のキャンセルは popup 非表示時のみ）。
    // それ以外のフェーズではこれまで通り TurnRules 経由で振る舞いを決める。
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                                          Tween.Scheduler,
                                          AnimationPlayer.Scheduler,
                                          GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State,
                                          SelectedPlayer.State,
                                          PlayerScene.PartyQuery,
                                          EnemyScene.RosterQuery,
                                          CustomEffects.FloorAdvanceRequest,
                                          GamePhaseState, PartySelection.State} =
        // 画面が選択中（CharacterSelect）なら、キー操作は選択画面に委譲する。
        // 本編（Playing）のときだけ下の戦闘用ルーティングを走らせる。
        match GamePhaseState.get() {
            case GamePhase.CharacterSelect => CharacterSelectScene.onKeyPressed(key, scene)
            case GamePhase.Playing         => onPlayingKeyPressed(key, scene)
        }
}

/// 本編（Playing）のキー処理。元の onKeyPressed 本体をそのまま関数に切り出したもの。
def onPlayingKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                           Tween.Scheduler, AnimationPlayer.Scheduler,
                           GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                           SelectedPlayer.State, PlayerScene.PartyQuery,
                           EnemyScene.RosterQuery, CustomEffects.FloorAdvanceRequest} =
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
        // Shift トグル: 危険範囲(紫 = 全敵に攻撃されうるマス)の表示/非表示。
        // メニューの効果音を鳴らし、PlayerCursor / PlayerMoving の地図プランニング中のみ反応する。
        if (key == GameEngine.Key.LeftShift)
            if (phase == TurnPhase.Phase.PlayerCursor or phase == TurnPhase.Phase.PlayerMoving) {
                AudioStreamPlayer.play("confirm");
                DangerZoneScene.toggle(scene)
            } else scene
        else {
            // プレイヤー操作のフィードバック効果音（決定 / キャンセル / メニューカーソル移動）。
            // onKeyPressed は物理キー押下ごとに 1 度だけ発火するので、ここで鳴らせば 1 押下 = 1 音。
            // 実際の処理分岐 (dispatchMenuKey 等) は別途行うが、音はこの単一地点に集約する。
            playInputSfx(phase, input, key);
            // ユニット情報ポップアップの X トグルは PlayerCursor の下見中のみ。
            // PlayerAttack 中はポップアップを出さず、X は戦闘予測のキャンセルに使う。
            let popupShown = UnitInfoPopupScene.isShown(scene)
                              and phase == TurnPhase.Phase.PlayerCursor;
            // メニュー系フェーズ (ActionMenu / ItemMenu / TradeMenu) の Z/X は別関数で処理。
            // Some が返ってくれば dispatcher が処理済みなのでその scene をそのまま返す。
            match input {
                case Some(inp) => match checked_ecast(dispatchMenuKey(phase, inp, scene)) {
                    case Some(after) => after
                    case None        => dispatchNonMenuKey(phase, input, key, popupShown, scene)
                }
                case None => dispatchNonMenuKey(phase, input, key, popupShown, scene)
            }
        }

/// MenuHandler instance — ItemList の Enter/Escape を各 MenuScene へ流す。
/// 入力キー固定: Up/Down=カーソル移動 / Enter=確定 / Escape=キャンセル（engine 規約）。
/// ItemMenu の Enter は「現在フェーズ（ItemSelect / ItemActionSelect）に応じた確定」、
/// Escape は「ItemSelect→ActionMenu / ItemActionSelect→ItemSelect」のように親へ戻る。
instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = {Tween.Scheduler, AnimationPlayer.Scheduler, GameEngine.Audio,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State,
                 PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                 CustomEffects.FloorAdvanceRequest}
    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, entry: ItemEntry,
                           state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameEngine.Audio,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             PlayerScene.PartyQuery,
                                             EnemyScene.RosterQuery,
                                             CustomEffects.FloorAdvanceRequest} =
        match state {
            case NodeTag.ItemMenu(_) =>
                // ItemSelect / ItemActionSelect いずれも同じ ItemList なので、
                // フェーズに応じて ItemMenuScene 内部で分岐させる。
                let phase = TurnPhase.State.get();
                match phase {
                    case TurnPhase.Phase.ItemSelect       =>
                        checked_ecast(ItemMenuScene.onItemConfirmed(entry, scene))
                    case TurnPhase.Phase.ItemActionSelect =>
                        checked_ecast(ItemMenuScene.onActionConfirmed(entry, scene))
                    case _                                 => scene
                }
            // onActionConfirmed は「かいだん」で CustomEffects.FloorAdvanceRequest を emit するため、
            // この instance の Aef にも FloorAdvanceRequest を含めてある（start で handler 注入済み）。
            case NodeTag.ActionMenu        => ActionMenuScene.onActionConfirmed(entry, scene)
            case NodeTag.TradeMenu(_)      => checked_ecast(TradeMenuScene.confirmCurrentSelection(scene))
            case _                         => scene
        }
    redef onItemCancelled(_menuPath: NodePath, state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameEngine.Audio,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             PlayerScene.PartyQuery,
                                             EnemyScene.RosterQuery,
                                             CustomEffects.FloorAdvanceRequest} =
        match state {
            case NodeTag.ItemMenu(_) =>
                let phase = TurnPhase.State.get();
                match phase {
                    case TurnPhase.Phase.ItemSelect       =>
                        checked_ecast(ItemMenuScene.onItemCancelled(scene))
                    case TurnPhase.Phase.ItemActionSelect =>
                        checked_ecast(ItemMenuScene.onActionCancelled(scene))
                    case _                                 => scene
                }
            case NodeTag.ActionMenu        => checked_ecast(ActionMenuScene.onActionCancelled(scene))
            case NodeTag.TradeMenu(_)      => checked_ecast(TradeMenuScene.cancelCurrent(scene))
            case _                         => scene
        }
}

// ────────────────────────────────────────────────────────
// StaffAim フェーズ用ヘルパー（方向キー → applyStaffCast、X/Esc → メニューに戻る）
// ────────────────────────────────────────────────────────

/// 方向キーを `Staff.Direction` に変換する。方向以外のキーは None。
def keyToStaffDirection(key: GameEngine.Key): Option[Staff.Direction] = match key {
    case GameEngine.Key.W     => Some(Staff.Direction.Up)
    case GameEngine.Key.Up    => Some(Staff.Direction.Up)
    case GameEngine.Key.S     => Some(Staff.Direction.Down)
    case GameEngine.Key.Down  => Some(Staff.Direction.Down)
    case GameEngine.Key.A     => Some(Staff.Direction.Left)
    case GameEngine.Key.Left  => Some(Staff.Direction.Left)
    case GameEngine.Key.D     => Some(Staff.Direction.Right)
    case GameEngine.Key.Right => Some(Staff.Direction.Right)
    case _                     => None
}

/// StaffAim フェーズで方向キーが押されたら `ArrowCursorScene.aim` で矢印の向きだけ更新する。
/// 発射は別キー (Z) で確定する。方向以外のキーは無視。
def staffAimDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] =
    match keyToStaffDirection(key) {
        case None      => scene
        case Some(dir) => ArrowCursorScene.aim(dir, scene)
    }

/// StaffAim フェーズで Z が押されたら、矢印が指している方向で applyStaffCast を呼ぶ。
def staffAimConfirm(scene: Scene[NodeTag]):
        Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                           BoardQuery, GameLogger.GameLogger,
                           EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                           GameEngine.Audio} =
    let dir = ArrowCursorScene.getDirection(scene);
    match SelectedPlayer.State.get()#id {
        case None           => scene
        case Some(playerId) =>
            match PlayerScene.get(playerId, scene) {
                case None         => scene
                case Some(player) =>
                    match player#selectedItem {
                        case Some(PlayerScene.ItemKind.Staff(idx)) =>
                            PlayerScene.applyStaffCast(playerId, idx, dir, scene)
                        case _ => scene
                    }
            }
    }

/// プレイヤー操作のフィードバック効果音を鳴らす。
///   - 決定 (Z / Space / Enter)        → "confirm"（メニューを開く / 項目を確定する操作も含む）
///   - キャンセル (X / Escape)         → "cancel"
///   - メニュー中の方向キー            → "cursor"（リストのカーソル移動 / 交換のペイン切替）
/// onKeyPressed から 1 押下につき 1 回だけ呼ばれる。確定/取消・カーソル音いずれも
/// 「その入力が実際に何かする」フェーズでだけ鳴らす（演出中・自動進行中など、ボタンを
/// 押しても無反応なフェーズで音だけ鳴るのを防ぐ）。判定は `confirmCancelMakesSound` /
/// `isMenuCursorMove` に集約。
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
        // 全入力を無視する演出フェーズ（攻撃モーション中 / 敵ターン / 発見演出 / 旧戦闘予報）
        case (TurnPhase.Phase.PlayerAttackHold, _) => false
        case (TurnPhase.Phase.EnemyTurn,        _) => false
        case (TurnPhase.Phase.RogueAlert,       _) => false
        case (TurnPhase.Phase.AttackForecast,   _) => false
        // 合流の自動歩行: X で中断できるが Z は無反応
        case (TurnPhase.Phase.PlayerAutoMove, TurnRules.Input.Confirm) => false
        // ローグ自由歩行: Z でメニューを開く / X(キャンセル) は無視
        case (TurnPhase.Phase.RogueMove,      TurnRules.Input.Cancel)  => false
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
        // ItemSelect は ↑↓ がアイテム選択、←→ がページ切替（ロード職の 2 ページ）。
        case TurnPhase.Phase.ItemSelect       => vertical or horizontal
        case TurnPhase.Phase.ItemActionSelect => vertical
        case TurnPhase.Phase.TradeInventory   => vertical or horizontal
        // 攻撃中: 上下=武器切り替え / 左右=ターゲット選択。どちらもカーソル移動音を鳴らす。
        case TurnPhase.Phase.PlayerAttack     => vertical or horizontal
        case _                                => false
    }

/// メニュー系フェーズ (ActionSelect / ItemSelect / ItemActionSelect / TradeInventory)
/// の Z/X dispatch をまとめる。`onKeyPressed` の match は phase 数 × bool パターンで
/// 型推論の複雑度が膨らみがちなので、メニュー dispatch を関数に切り出して肩代わりする。
/// 戻り値は「dispatcher が処理したら Some、対象外なら None」。
def dispatchMenuKey(phase: TurnPhase.Phase, input: TurnRules.Input, scene: Scene[NodeTag]):
        Option[Scene[NodeTag]] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                    GameLogger.GameLogger, EnemyTurn.Queue,
                                    TurnPhase.State, SelectedPlayer.State,
                                    PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                                    CustomEffects.FloorAdvanceRequest, GameEngine.Audio} =
    match (phase, input) {
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Confirm)
                                              => Some(ActionMenuScene.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ActionMenuScene.onActionCancelled(scene)))
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Confirm)
                                              => Some(checked_ecast(ItemMenuScene.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.ItemSelect,        TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ItemMenuScene.onItemCancelled(scene)))
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Confirm)
                                              => Some(checked_ecast(ItemMenuScene.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.ItemActionSelect,  TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ItemMenuScene.onActionCancelled(scene)))
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Confirm)
                                              => Some(checked_ecast(TradeMenuScene.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.TradeInventory,    TurnRules.Input.Cancel)
                                              => Some(checked_ecast(TradeMenuScene.cancelCurrent(scene)))
        // レベルアップのステータス変化パネルは Z / Enter / X いずれでも閉じる（確認するだけ）。
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Confirm)
                                              => Some(checked_ecast(LevelUpPanelScene.confirm(scene)))
        case (TurnPhase.Phase.LevelUpView,       TurnRules.Input.Cancel)
                                              => Some(checked_ecast(LevelUpPanelScene.confirm(scene)))
        case _                                => None
    }

/// メニュー以外のフェーズ (PlayerAutoMove / StaffAim / AttackForecast 等) の Z/X dispatch。
/// `onKeyPressed` から `dispatchMenuKey` で処理されなかったときに呼ばれる。
/// 方向キーなど input = None もここに来る (StaffAim 中の direction、ほかは no-op)。
def dispatchNonMenuKey(phase: TurnPhase.Phase, input: Option[TurnRules.Input],
                        key: GameEngine.Key, popupShown: Bool, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery, Tween.Scheduler,
                            AnimationPlayer.Scheduler,
                            GameLogger.GameLogger,
                            EnemyTurn.Queue, TurnPhase.State,
                            SelectedPlayer.State,
                            PlayerScene.PartyQuery,
                            EnemyScene.RosterQuery} =
    match (phase, input) {
        // popup 表示中の X は popup view 切替に上書き（通常のキャンセルは走らない）
        case (_,                              Some(TurnRules.Input.Cancel)) if popupShown
                                              => UnitInfoPopupScene.toggleView(scene)
        case (TurnPhase.Phase.PlayerAutoMove, Some(TurnRules.Input.Cancel))
                                              => checked_ecast(AutoMoveScene.cancel(scene))
        // ローグ自由歩行中の Z でメニュー(ひろう / かいさん)を開く。X は無視。
        case (TurnPhase.Phase.RogueMove,      Some(TurnRules.Input.Confirm))
                                              => checked_ecast(ActionMenuScene.openFromRogue(scene))
        case (TurnPhase.Phase.StaffAim,       Some(TurnRules.Input.Cancel))
                                              => checked_ecast(staffAimCancel(scene))
        case (TurnPhase.Phase.StaffAim,       Some(TurnRules.Input.Confirm))
                                              => checked_ecast(staffAimConfirm(scene))
        // StaffAim 中の方向キーは applyStaffCast へ
        case (TurnPhase.Phase.StaffAim,       None)
                                              => checked_ecast(staffAimDirection(key, scene))
        // TradeInventory 中の ←/→ は左右ペイン切替へ (↑↓ は handleMenus 側で
        // ItemList のカーソル移動に使われるので素通り)
        case (TurnPhase.Phase.TradeInventory, None)
                                              => checked_ecast(tradeInventoryDirection(key, scene))
        // ItemSelect 中の ←/→ はアイテム window のページ切替へ (↑↓ は handleMenus 側で
        // ItemList のカーソル移動に使われるので素通り)
        case (TurnPhase.Phase.ItemSelect,     None)
                                              => checked_ecast(itemSelectDirection(key, scene))
        // PlayerAttack = ターゲット選択 + 戦闘予測。Z で(カーソル上の敵に)攻撃確定、
        // X でメニューに戻る。BattlePanelScene が予報表示と対象同期を担う。
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Confirm))
                                              => BattlePanelScene.confirm(scene)
        case (TurnPhase.Phase.PlayerAttack,   Some(TurnRules.Input.Cancel))
                                              => checked_ecast(BattlePanelScene.cancel(scene))
        // 明示 case が無いフェーズの Z/X は TurnRules.decide にそのまま渡す
        case (_,                              Some(inp))
                                              => TurnInputBridge.handle(inp, scene)
        // 方向キーなどはここまで来る (各 Scene が physicsProcess で polling する)
        case (_,                              None) => scene
    }

/// TradeInventory 中の方向キーを左右ペイン切替に変換する。
/// Left / A → focus を 1 つ左へ、Right / D → 1 つ右へ (0..paneCount-1 にクランプ)。
/// Up / Down は handleMenus が ItemList カーソル移動に使うので、ここでは素通し。
def tradeInventoryDirection(key: GameEngine.Key, scene: Scene[NodeTag]): Scene[NodeTag] =
    match key {
        case GameEngine.Key.Left  => TradeMenuScene.setPaneFocusDelta(-1, scene)
        case GameEngine.Key.A     => TradeMenuScene.setPaneFocusDelta(-1, scene)
        case GameEngine.Key.Right => TradeMenuScene.setPaneFocusDelta(1, scene)
        case GameEngine.Key.D     => TradeMenuScene.setPaneFocusDelta(1, scene)
        case _                    => scene
    }

/// ItemSelect 中の方向キーをアイテム window のページ切替に変換する。
/// Left / A → 前ページ、Right / D → 次ページ。Up / Down は handleMenus が ItemList の
/// カーソル移動に使うので、ここでは素通し（ロード職以外は 1 ページなのでページ送りは効かない）。
def itemSelectDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ SelectedPlayer.State =
    match key {
        case GameEngine.Key.Left  => ItemMenuScene.pageLeft(scene)
        case GameEngine.Key.A     => ItemMenuScene.pageLeft(scene)
        case GameEngine.Key.Right => ItemMenuScene.pageRight(scene)
        case GameEngine.Key.D     => ItemMenuScene.pageRight(scene)
        case _                    => scene
    }

def staffAimCancel(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
    TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
    scene

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さく切り出す。Camera2D 追従でビューが動く。横は左右余白も使うため 170 に拡張。
    /// この値はカメラのビューポートと投影行列の基準で、ウィンドウサイズに合わせて
    /// 引き伸ばし表示される（Godot の Stretch Mode = canvas_items 相当）。
    /// **project.json の "designWidth"/"designHeight" と必ず一致させること**（HUD の中央寄せ
    /// 計算がこの値を使うため、ずれると PhaseBanner 等の帯が画面幅とずれる）。
    pub def designWi(): Int32 = 170
    pub def designHi(): Int32 = 128

    /// 初期ウィンドウサイズ（OS ピクセル単位）。design とは独立して指定でき、
    /// design 側がウィンドウいっぱいに引き伸ばし描画される
    pub def windowWi(): Int32 = 832
    pub def windowHi(): Int32 = 624

    /// ゲーム起動エントリ。Region と各 effect handler を立ち上げ、初回シーンを
    /// `GameLifecycle.buildPlayingScene` で組み立てて `gameLoop` に入る。
    /// **配線役** に徹するため、ここにゲームロジックは書かない。
    pub def start(): Unit \ {GameEngine.Game, GameEngine.Audio,
                              Fs.FileRead, IO, Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            // ゲーム全体の進行状態（画面）。起動直後はキャラクター選択画面から始める。
            let phaseRef = Ref.fresh(rc, GamePhase.CharacterSelect);
            // ユニットカタログをロード + schema 整合性検査（Z 戦略の安全網）。
            // 各段階で失敗内容を panic に出して原因を即可視化する。
            // units.json の spriteFrames は格子インデックス形式で書かれているため、
            // load 直後は spriteFrames = None。GameEngine.Game effect が使えるここで
            // resolveSpriteFrames を呼んで texture 実寸から px 矩形に解決する。
            // 段階 6 のリファクタで weapons は独立 catalog (`WeaponCatalog`) に分離された。
            // `WeaponCatalog.load()` 内部で schema 読込 + 整合性検査 + データ読込が完結するため、
            // ここでの schema 検査コードは不要になった。`UnitCatalog.load` には weaponCatalog を渡す。
            // 段階 9 のリファクタで schema 整合性検査は `UnitCatalog.load` 内部で完結する
            // (他 catalog の `CatalogContainer.loadWithCheck` と揃えた)。
            let weaponCatalog = WeaponCatalog.load();
            let catalog0 = UnitCatalog.load(AssetPath.resolve("resources/units.json"), weaponCatalog);
            let catalog = UnitCatalog.resolveSpriteFrames(AssetPath.resolve("resources/units.json"), catalog0);
            // 敵カタログをロード（段階 10 のリファクタで units.json から enemies.json に分離）。
            // 味方（成長率あり）と別管理。spriteFrames は味方と同じ格子→px 解決を通す。
            let enemyCatalog0 = EnemyCatalog.load();
            let enemyCatalog = EnemyCatalog.resolveSpriteFrames(AssetPath.resolve("resources/enemies.json"), enemyCatalog0);
            // フロア定義をロード。進行順は floors.json の "order" 配列で管理し、
            // 現在いるフロアは FloorProgress effect が保持する（初期値 = 先頭フロア）。
            // 階段で次階へ / 全滅で 1F へ / クリアで 1F ループ、はいずれも FloorProgress 経由。
            // 段階 8 のリファクタで schema 整合性検査は `FloorCatalog.load()` 内部で完結する。
            let floors = FloorCatalog.load();
            // 杖カタログをロード。段階 7 のリファクタで `CatalogContainer.loadWithCheck` 経由になり
            // schema 整合性検査も `Staff.load()` 内部で完結する。
            let staffCatalog = Staff.load();
            // 消費アイテム（きずぐすり等）カタログをロード。Staff と同じ
            // `CatalogContainer.loadWithCheck` 経由で schema 整合性検査まで完結する。
            let consumableCatalog = Consumable.load();
            // 6 カタログを 1 つの record に束ねて構築 / リビルド経路へ引き回す。
            let catalogs = {
                weapons     = weaponCatalog,
                players     = catalog,
                enemies     = enemyCatalog,
                floors      = floors,
                staves      = staffCatalog,
                consumables = consumableCatalog
            };
            run {
                // 起動直後はキャラクター選択画面を組む。本編（ダンジョン）は出撃メンバー確定後の
                // Playing 遷移時に applyPhaseChange(Playing) が buildCurrentFloor で組む。
                // BGM は BgmScene の AudioStreamPlayer ノード (autoplay=true, loop=true,
                // volume=0.05) で applyAudioAttach 経由で再生される (= ここでは触らない)
                let scene = applyPhaseChange(GamePhase.CharacterSelect, catalogs, Scene.empty());
                // SE は半分で鳴らす (Inspector 対応の Scene Node にしていない通常の SE 系)
                AudioStreamPlayer.setVolume("damage", 0.2625f32);
                AudioStreamPlayer.setVolume("down_enemy", 0.5f32);
                AudioStreamPlayer.setVolume("miss", 0.5f32);
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
                gameLoop(catalogs, sceneRef, GamePhase.CharacterSelect, scene)
            // handler の並び順 = effect 消費順 (構文上で後の `with` ほど **外側**)。
            // `GameOverRequest` の handler 本体は `GameLogger` / `EnemyTurn.Queue` /
            // `TurnPhase.State` / `SelectedPlayer.State` / `InitialSpawns.State` 等を
            // 使うため、これらより **内側** (= 構文上で先) に書く必要がある。
            // 同様に `BoardQuery` も `Ref` 経由で sceneRef を読むだけだが内側に置く。
            } with handler CustomEffects.GameOverRequest {
                  // 全味方脱落でフルリビルド: フロアを 1F に戻し turn 系 state をリセットしてから
                  // scene を作り直し、新しい spawn 一覧を InitialSpawns に書き戻す。本体は GameLifecycle 側。
                  def request(_scene, k) = k(GameLifecycle.resetForGameOver(catalogs))
              }
              with handler CustomEffects.FloorAdvanceRequest {
                  // 生存味方が全員階段を使ったら次フロアへ（最終フロアならクリア → 1F ループ）。
                  // HP / 武器 / 持ち物の引き継ぎを含め本体は GameLifecycle.advanceFloor 側。
                  def advance(scene, k) = k(GameLifecycle.advanceFloor(catalogs, scene))
              }
              with handler BoardQuery {
                  def board(k) = k(BoardSnapshot.fromScene(Ref.get(sceneRef)))
              }
              with handler PlayerScene.PartyQuery {
                  def get(id, k)           = k(PlayerScene.get(id, Ref.get(sceneRef)))
                  def getAll(k)            = k(PlayerScene.getAll(Ref.get(sceneRef)))
                  def getGridPos(id, k)    = k(PlayerScene.getGridPos(id, Ref.get(sceneRef)))
                  def getMoveTiles(id, k)  = k(PlayerScene.getMoveTiles(id, Ref.get(sceneRef)))
              }
              with handler EnemyScene.RosterQuery {
                  def get(id, k)           = k(EnemyScene.get(id, Ref.get(sceneRef)))
                  def getAll(k)            = k(EnemyScene.getAll(Ref.get(sceneRef)))
                  def findIdAt(coord, k)   = k(EnemyScene.findIdAt(coord, Ref.get(sceneRef)))
                  def anyAttacking(k)      = k(EnemyScene.anyAttacking(Ref.get(sceneRef)))
              }
              with handler GamePhaseState {
                  // 画面（CharacterSelect / Playing）の現在値を region の Ref で保持する。
                  def get(k)         = k(Ref.get(phaseRef))
                  def put(target, k) = { Ref.put(target, phaseRef); k() }
              }
              with Tween.withScheduler(rc)        // tween 一覧は内部に隠蔽
              with AnimationPlayer.withScheduler(rc)  // 名前付きアニメ + イベントドレイン
              with Pacing.withState(rc)           // 演出の溜め (hold)
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with EnemyTurn.withQueue(rc)        // 敵ターンキュー（1 step / 1 frame 駆動）
              with TurnPhase.withState(rc)        // 味方ターン内のサブフェーズ + 敵ターン
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with InitialSpawns.withState(rc)    // ゲームオーバー時に同じ敵 / 味方配置を復元
              with FloorProgress.withState(rc, FloorCatalog.firstFloorId(floors))  // 現在フロア id
              with PartySelection.withState(rc)   // 出撃メンバー（開始時に1回抽選、フロア間で維持）
        }

    /// GamePhase に応じて画面（Scene）を組み立てる。**配線役** に徹し、ここに画面固有の
    /// ロジックは書かない（各 Scene の構築関数を呼ぶだけ）。
    ///   CharacterSelect — 出撃メンバー選択画面を組む。
    ///   Playing         — 現在フロアのダンジョンを組む（出撃メンバーは選択画面で確定済み）。
    /// gameLoop が前フレームとの差分を見て、画面が変わったフレームだけ呼ぶ。
    def applyPhaseChange(phase: GamePhase, catalogs: GameLifecycle.Catalogs,
                          _scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, IO, Math.Random,
                SelectedPlayer.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, GameLogger.GameLogger} =
        match phase {
            case GamePhase.CharacterSelect =>
                CharacterSelectScene.add(UnitCatalog.pool("players", catalogs#players),
                                          Scene.empty())
            case GamePhase.Playing =>
                GameLogger.playerLog("T1 味方のターン");
                GameLifecycle.buildCurrentFloor(catalogs)
        }

    /// メインループ。phase で分岐せず、**固定パイプライン** を毎フレーム回す:
    ///   handleInput → handleMenus → physicsProcess → Tween → Animation → process → epilogue
    /// 各 process / input redef 内で「自分が今動くべきか」を phase で判断する (Godot 流)。
    /// 例: `EnemyTurnDriverScene.process` は phase=EnemyTurn / PlayerAttackHold で動作、
    ///     `AutoMoveScene.process` は phase=PlayerAutoMove で動作。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def gameLoop(catalogs: GameLifecycle.Catalogs,
                  sceneRef: Ref[Scene[NodeTag], r],
                  previousPhase: GamePhase,
                  scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         Fs.FileRead, IO,
                         BoardQuery,
                         PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                         Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State,
                         CustomEffects.GameOverRequest,
                         CustomEffects.FloorAdvanceRequest,
                         FloorProgress.State, InitialSpawns.State,
                         GamePhaseState, PartySelection.State,
                         Pacing.State, Math.Random, r} =
        // Escape ではアプリ終了しない。ウィンドウの閉じる操作（shouldClose）だけで終了する。
        if (GameEngine.Game.shouldClose()) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            Ref.put(scene, sceneRef);
            let dt = GameEngine.Game.getDeltaTime();
            // Pacing カウンタを 1 フレーム進める (各 Scene の process が gating で参照する)。
            // フレーム頭で進めるので「前フレーム末で hold した値を今フレームの判定で使う」
            // 形になり、Scene に紐づかないため gameLoop 内で 1 行のままにする。
            Pacing.State.tick(dt);
            let updated = scene
                |> GameEngine.handleInput
                |> GameEngine.handleMenus
                |> GameEngine.physicsProcess(delta = dt, paused = false,
                                              gravity = Vec2.zero())
                |> Tween.tickAll(dt)
                |> AnimationPlayer.tickAll(dt)
                |> GameEngine.process(delta = dt, paused = false);
            // 画面（GamePhase）が変わったフレームだけ、新しい画面を組み立て直す。
            // 例: 選択画面でリーダー確定 → Playing に切り替わり、ここでダンジョンが組まれる。
            let currentPhase = GamePhaseState.get();
            let next = if (currentPhase != previousPhase)
                           applyPhaseChange(currentPhase, catalogs, updated)
                       else updated;
            GameEngine.render(next);
            gameLoop(catalogs, sceneRef, currentPhase, next)
        }
}
