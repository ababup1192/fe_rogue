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
    /// Int32 は現在表示中のページ番号（0 起点）。ロード職は 16 個 = 2 ページ持てるため、
    /// ←/→ でページを切り替えるとここが更新され、refreshItems がそのページぶんを並べ直す。
    /// Set[ItemKind] は Shift で複数選択したアイテムの印。ページをまたいでも保持し、
    /// 「捨てる」で一括破棄する。表示行ではなく種別+絶対 index で持つのでページ送りに強い。
    case ItemMenu(Int32, Set[PlayerData.ItemKind])
    /// TradeMenuScene の Panel ルート（members / focus / pick / origin を抱えるセッション状態）
    case TradePanel(TradeMenuScene.PanelData)
    /// TradeMenuScene の各ペイン ItemList。内部の Int32 はペイン index (0 起点、最大 3)。
    case TradeMenu(Int32)
    /// ActionMenuScene の Panel ルート（外枠）
    case ActionPanel
    /// ActionMenuScene の ItemList（こうげき / たいき）
    case ActionMenu
    /// WeaponSelectScene の Panel ルート（ActionMenu「攻撃」確定で右隣に出る武器選択ウィンドウ外枠）
    case WeaponSelectPanel
    /// WeaponSelectScene の ItemList（選択中味方の武器一覧。確定で装備→攻撃フェーズへ）
    case WeaponSelectMenu
    /// GameOverMenuScene の Panel ルート（全滅時のモーダル選択ウィンドウ外枠）
    case GameOverPanel
    /// GameOverMenuScene の ItemList（最初から / そのフロアの最初から）
    case GameOverMenu
    /// BattlePanelScene の CanvasLayer ルート（画面空間の戦闘予報ミニウィンドウ）。
    /// 内部 Duration は未使用（将来の演出用に枠だけ残す）。panel とその子（丸/ラベル/三角）は
    /// `NodeTag.NoTag` でぶら下げ、process がパス経由で更新・対象近傍へ移動する。
    case BattlePanel(Duration.Duration)
    /// LevelUpPanelScene の Panel ルート（レベルアップ時のステータス変化パネルの外枠）。
    /// 内部 state は演出の進行（bonus 再生済みか / 右側を出し終えた上昇ステータス数 / 次までの残り時間）。
    case LevelUpPanel(LevelUpPanelScene.PanelState)
    /// DamagePopupScene の Marker2D 親（World 直下に永続）
    case DamagePopupsRoot(DamagePopupScene.RootData)
    /// DamagePopupScene の Label2D 子（寿命を持つ）
    case DamagePopup(DamagePopupScene.PopupData)
    /// ExplosionScene の Marker2D 親（World 直下に永続）
    case ExplosionsRoot(ExplosionScene.RootData)
    /// ExplosionScene の Sprite2D 子（爆発エフェクト・寿命を持つ）
    case Explosion(ExplosionScene.ExpData)
    /// UnitHPBarScene の Marker2D 親（戦闘表示 timer + currentHp/maxHp を持つ）
    case HPBar(UnitHPBarScene.HPBarData)
    /// UnitInfoPopupScene の CanvasLayer 親（表示中ユニット識別子を持つ）
    case UnitInfoPanel(UnitInfoPopupScene.PanelState)
    /// UnitCardScene の CanvasLayer 親（左サイドの選択ユニット簡易カード）。
    case UnitCard
    /// EnemyCardScene の CanvasLayer 親（右サイドの攻撃対象敵カード。UnitCard と左右対称）。
    case EnemyCard
    /// TopBarScene の CanvasLayer 親（上部フェイズバー。陣営・敵ターンの「間」を持つ）
    case TopBar(TopBarScene.Data)
    /// ItemPickupPopupScene の CanvasLayer 親（アイテム取得ポップアップのフェード演出状態を持つ）
    case ItemPickupPopup(ItemPickupPopupScene.PopupData)
    /// TurnEndHoldScene の CanvasLayer 親（Shift 長押しゲージの経過時間と発火済みフラグを持つ）
    case HoldGauge(TurnEndHoldScene.GaugeData)
    /// ItemScene の床に落ちている武器（拾える）
    case GroundItem(ItemScene.Data)
    /// ChestScene の床に置かれた宝箱（ローグだけが開けられる。中身は配置時に確定済み）
    case Chest(ChestScene.Data)
    /// `EnemyTurnDriverScene` の常駐タグ専用ノード (Marker2D)。process redef で phase を
    /// 見て EnemyTurn 中なら stepOnce、PlayerAttackHold 中なら hold 終了判定を行う。
    case EnemyTurnDriver
    /// `StairsExitScene` の常駐タグノード (Marker2D)。phase==StairsExit のとき
    /// 退場 id 列(queue)を 1 体ずつ階段へ歩かせて退場させる。
    case StairsExitDriver(StairsExitScene.Data)
    /// `FogScene` の常駐タグ専用ノード (Marker2D)。process redef で毎フレーム、現在パーティの
    /// いる部屋/通路だけ明るくし、それ以外は薄暗いモヤ＋敵/アイテム/階段を非表示にする。
    case FogDriver
    /// `MinimapScene` の常駐タグノード (Marker2D)。process redef で毎フレーム、訪問済み
    /// module を蓄積 (Set[Int32]) し、M キーで全画面ミニマップを出し入れ・再描画する。
    case MinimapDriver(MinimapScene.DriverData)
    /// 起動時のタイトル画面のルート（カーソル位置・再開可否を保持）。
    case Title(TitleMenuScene.Data)
    /// 中断確認ダイアログ（「本当に中断しますか？ はい / いいえ」）の Panel / ItemList。
    case SuspendConfirmPanel
    case SuspendConfirmMenu
    /// 追従カメラ（Camera2D）。process でフェーズに応じた追従先へ動かす。
    case Camera
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
        match EngineNode.getState(node) {
            case NodeTag.Player(data) =>
                // 選択中プレイヤー & PlayerMoving フェーズだけが移動を受け付ける。
                // 集合(GatherMove)では主人公(id 0)が移動範囲内で動き、味方が追従する。
                let phase = TurnPhase.State.get();
                if (phase == TurnPhase.Phase.PlayerMoving
                    and SelectedPlayer.State.get()#id == Some(data#id))
                    PlayerMovementScene.physicsStep(delta, node, path, scene)
                // 集合(行軍)中は主人公(id 0)を移動範囲内で動かし、味方が 1 歩ずつ追従する。
                else if (phase == TurnPhase.Phase.GatherMove and data#id == 0)
                    PlayerMovementScene.gatherStep(delta, node, path, scene)
                else (node, scene)
            case NodeTag.Cursor(_) =>
                // PlayerCursor / WeaponSelect / PlayerAttack の場合分けは CursorScene 内部に閉じている
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

/// Player / Enemy ノード (AnimationPlayer signal drain を持つエンティティ系)。
/// 戦闘シグナルの解決は CombatScene.process が攻守共通で受ける。
def dispatchEntities(delta: Duration.Duration, node: EngineNode[NodeTag],
                      path: NodePath, scene: Scene[NodeTag]):
                     (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match EngineNode.getState(node) {
        case NodeTag.Player(_) =>
            checked_ecast(CombatScene.process(delta, node, path, scene))
        case NodeTag.Enemy(_) =>
            checked_ecast(CombatScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// 毎フレーム tick が必要な表示系ノード (Popup / HPBar / Item / UnitInfoPanel / Camera / Log)
def dispatchTickables(delta: Duration.Duration, node: EngineNode[NodeTag],
                       path: NodePath, scene: Scene[NodeTag]):
                      (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match EngineNode.getState(node) {
        case NodeTag.DamagePopupsRoot(_) =>
            checked_ecast(DamagePopupScene.process(delta, node, path, scene))
        case NodeTag.ExplosionsRoot(_) =>
            checked_ecast(ExplosionScene.process(delta, node, path, scene))
        case NodeTag.HPBar(_) =>
            checked_ecast(UnitHPBarScene.process(delta, node, path, scene))
        case NodeTag.GroundItem(_) =>
            checked_ecast(ItemScene.process(delta, node, path, scene))
        case NodeTag.UnitInfoPanel(_) =>
            checked_ecast(UnitInfoPopupScene.process(delta, node, path, scene))
        case NodeTag.TopBar(_) =>
            checked_ecast(TopBarScene.process(delta, node, path, scene))
        case NodeTag.ItemPickupPopup(_) =>
            checked_ecast(ItemPickupPopupScene.process(delta, node, path, scene))
        case NodeTag.HoldGauge(_) =>
            checked_ecast(TurnEndHoldScene.process(delta, node, path, scene))
        case NodeTag.CharacterSelect(_) =>
            checked_ecast(CharacterSelectScene.process(delta, node, path, scene))
        case NodeTag.Log(_) =>
            checked_ecast(LogScene.process(delta, node, path, scene))
        case NodeTag.Camera =>
            checked_ecast(CameraScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// フェーズ駆動の driver ノード (EnemyTurnDriver / ArrowCursor / Fog / Minimap)
def dispatchDrivers(delta: Duration.Duration, node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match EngineNode.getState(node) {
        // F8: EnemyTurnDriver / StairsExitDriver（=ターン進行 LOGIC driver）は per-node callback から
        // 外し、gameLoop が明示的に呼ぶ frame-paced System（`step`）へ移設。前後順序依存は slice1/2 で
        // World 経由＝順序非依存。Fog/Minimap/ArrowCursor は view 描画ゆえ per-node 残置（gate 許容）。
        case NodeTag.ArrowCursor(_) =>
            checked_ecast(ArrowCursorScene.process(delta, node, path, scene))
        case NodeTag.FogDriver =>
            checked_ecast(FogScene.process(delta, node, path, scene))
        case NodeTag.MinimapDriver(_) =>
            checked_ecast(MinimapScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// メニュー系ノード (ItemMenu / ActionMenu の ItemList、戦闘予報ミニウィンドウ等)。
/// BattlePanel は World 配下の Marker2D（盤面追従の戦闘予報）だが、effect 推論の都合で
/// tickables ではなくこの群で dispatch する（dispatchTickables に移すと FrameAef.ProcessT の
/// 効果が未使用と判定されるため）。
def dispatchMenus(delta: Duration.Duration, node: EngineNode[NodeTag],
                   path: NodePath, scene: Scene[NodeTag]):
                  (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match EngineNode.getState(node) {
        case NodeTag.ItemMenu(_, _) =>
            checked_ecast(ItemMenuScene.refreshItems(delta, node, path, scene))
        case NodeTag.ActionMenu =>
            checked_ecast(ActionMenuScene.refreshItems(delta, node, path, scene))
        case NodeTag.WeaponSelectMenu =>
            checked_ecast(WeaponSelectScene.refreshItems(delta, node, path, scene))
        case NodeTag.GameOverMenu =>
            checked_ecast(GameOverMenuScene.refreshItems(delta, node, path, scene))
        case NodeTag.SuspendConfirmMenu =>
            checked_ecast(SuspendConfirmScene.refreshItems(delta, node, path, scene))
        case NodeTag.TradeMenu(_) =>
            checked_ecast(TradeMenuScene.refreshItems(delta, node, path, scene))
        case NodeTag.UnitCard =>
            checked_ecast(UnitCardScene.process(delta, node, path, scene))
        case NodeTag.EnemyCard =>
            checked_ecast(EnemyCardScene.process(delta, node, path, scene))
        case NodeTag.BattlePanel(_) =>
            checked_ecast(BattlePanelScene.process(delta, node, path, scene))
        case NodeTag.LevelUpPanel(_) =>
            checked_ecast(LevelUpPanelScene.process(delta, node, path, scene))
        case _ => (node, scene)
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
    type Aef = {GameEngine.Game, GameEngine.Audio, BoardQuery, Tween.Scheduler,
                 AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                 PlayerData.PartyQuery, EnemyData.RosterQuery,
                 CustomEffects.FloorAdvanceRequest, CustomEffects.ResumeRequest,
                 CustomEffects.SuspendRequest,
                 GamePhaseState, PartySelection.State,
                 // アイテム投擲の命中ロール（Math.Random）と誤射による味方脱落のゲームオーバー判定。
                 Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery}
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
                                          SelectedPlayer.State, GatherResume.State,
                                          PlayerData.PartyQuery,
                                          EnemyData.RosterQuery,
                                          CustomEffects.FloorAdvanceRequest,
                                          CustomEffects.ResumeRequest,
                                          CustomEffects.SuspendRequest,
                                          GamePhaseState, PartySelection.State,
                                          Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        // 画面がタイトル / 選択中なら各画面へ委譲。本編（Playing）のときだけ戦闘用ルーティングを走らせる。
        match GamePhaseState.get() {
            case GamePhase.Title           => TitleMenuScene.onKeyPressed(key, scene)
            case GamePhase.CharacterSelect => CharacterSelectScene.onKeyPressed(key, scene)
            case GamePhase.Playing         => onPlayingKeyPressed(key, scene)
        }
}

/// Playing フェーズのキー処理。GamePhase 分岐を onKeyPressed から分離し推論複雑度を下げる。
def onPlayingKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                           Tween.Scheduler, AnimationPlayer.Scheduler,
                           GameLogger.GameLogger, EnemyTurn.Queue, TurnPhase.State,
                           SelectedPlayer.State, GatherResume.State, PlayerData.PartyQuery,
                           EnemyData.RosterQuery, CustomEffects.FloorAdvanceRequest,
                           CustomEffects.SuspendRequest,
                           Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
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
                    ItemMenuScene.toggleMarkAtCursor(scene)
                case TurnPhase.Phase.TradeInventory =>
                    AudioStreamPlayer.play("confirm");
                    TradeMenuScene.toggleTradeMarkAtCursor(scene)
                case _ => scene
            }
        // C キー / ゲームパッド Y: 集合モードのトグル。
        //   PlayerCursor … 集合可能(他に生存味方が居て主人公が未行動)なら「集合」を直接確定。
        //   GatherMove   … 一歩も動いていない（手動確定直後 / 継続でターン開始した状態）なら
        //                  集合を解いて個別行動モード(PlayerCursor)へ戻す。移動を始めたら不可。
        else if (key == GameEngine.Key.C)
            if (phase == TurnPhase.Phase.PlayerCursor and ActionMenuScene.gatherEnabled()) {
                AudioStreamPlayer.play("confirm");
                ActionMenuScene.gatherShortcut(scene)
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
            // ユニット情報ポップアップの X トグルは PlayerCursor の下見中のみ。
            // PlayerAttack 中はポップアップを出さず、X は戦闘予測のキャンセルに使う。
            let popupShown = UnitInfoPopupScene.isShown(scene)
                              and phase == TurnPhase.Phase.PlayerCursor;
            // メニュー系フェーズ (ActionMenu / ItemMenu / TradeMenu) の Z/X は別関数で処理。
            // Some が返ってくれば dispatcher が処理済みなのでその scene をそのまま返す。
            // 入力があればメニュー dispatcher に渡す。処理済み(Some)ならその scene、
            // 未処理(None)・入力なしは非メニュー処理へ。2 段の match を flatMap + 1 match に畳む。
            match input |> Option.flatMap(inp -> checked_ecast(dispatchMenuKey(phase, inp, scene))) {
                case Some(after) => after
                case None        => dispatchNonMenuKey(phase, input, key, popupShown, scene)
            }
        }

/// MenuHandler instance — ItemList の Enter/Escape を各 MenuScene へ流す。
/// 入力キー固定: Up/Down=カーソル移動 / Enter=確定 / Escape=キャンセル（engine 規約）。
instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = {Tween.Scheduler, AnimationPlayer.Scheduler, GameEngine.Audio,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                 PlayerData.PartyQuery, EnemyData.RosterQuery,
                 CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery}
    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, entry: ItemEntry,
                           state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameEngine.Audio,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             GatherResume.State,
                                             PlayerData.PartyQuery,
                                             EnemyData.RosterQuery,
                                             CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery} =
        match state {
            case NodeTag.ItemMenu(_, _) =>
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
            case NodeTag.WeaponSelectMenu  => checked_ecast(WeaponSelectScene.onConfirmed(entry, scene))
            case NodeTag.TradeMenu(_)      => checked_ecast(TradeMenuScene.confirmCurrentSelection(scene))
            case _                         => scene
        }
    redef onItemCancelled(_menuPath: NodePath, state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameEngine.Audio,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             GatherResume.State,
                                             PlayerData.PartyQuery,
                                             EnemyData.RosterQuery,
                                             CustomEffects.FloorAdvanceRequest, World.Command, BoardQuery} =
        match state {
            case NodeTag.ItemMenu(_, _) =>
                let phase = TurnPhase.State.get();
                match phase {
                    case TurnPhase.Phase.ItemSelect       =>
                        checked_ecast(ItemMenuScene.onItemCancelled(scene))
                    case TurnPhase.Phase.ItemActionSelect =>
                        checked_ecast(ItemMenuScene.onActionCancelled(scene))
                    case _                                 => scene
                }
            case NodeTag.ActionMenu        => checked_ecast(ActionMenuScene.onActionCancelled(scene))
            case NodeTag.WeaponSelectMenu  => checked_ecast(WeaponSelectScene.onCancelled(scene))
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
                           GameEngine.Audio, GameEngine.Game, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection(scene);
    // 選択中プレイヤー → その Data → selectedItem を forM で 1 本に畳み、
    // 杖(Staff)を選んでいるときだけ発射する（3 段の match ネストを解消）。
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        player   <- PlayerScene.get(playerId, scene);
        item     <- player#selectedItem
    ) yield (playerId, item);
    match selected {
        case Some((playerId, PlayerData.ItemKind.Staff(idx))) =>
            StaffCastScene.applyStaffCast(playerId, idx, dir, scene)
        // 投擲系の消費アイテム（目潰し薬 / 鈍足薬）も同じ StaffAim 経路で方向投擲する。
        case Some((playerId, PlayerData.ItemKind.Consumable(idx))) =>
            StaffCastScene.applyConsumableDirectional(playerId, idx, dir, scene)
        case _ => scene
    }

/// ThrowAim フェーズで Z が押されたら、矢印が指している方向で選択中アイテムを投げる。
/// 種別（武器/杖/薬/指輪）に依らず `applyThrow` が振り分ける。
def throwAimConfirm(scene: Scene[NodeTag]):
        Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                           BoardQuery, GameLogger.GameLogger,
                           EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                           GameEngine.Audio, GameEngine.Game, Math.Random,
                           CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        let dir = ArrowCursorScene.getDirection(scene);
    let selected = forM (
        playerId <- SelectedPlayer.State.get()#id;
        player   <- PlayerScene.get(playerId, scene);
        item     <- player#selectedItem
    ) yield (playerId, item);
    match selected {
        case Some((playerId, kind)) =>
            StaffCastScene.applyThrow(playerId, kind, dir, scene)
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
        Option[Scene[NodeTag]] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                    GameLogger.GameLogger, EnemyTurn.Queue,
                                    TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                                    PlayerData.PartyQuery, EnemyData.RosterQuery,
                                    CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                                    CustomEffects.GameOverRequest, CustomEffects.SuspendRequest, World.Command, BoardQuery} =
        match (phase, input) {
        // 全滅メニュー: Z/Enter で選択確定（restart を emit）、X は無反応（必ず選ばせる）。
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Confirm)
                                              => Some(GameOverMenuScene.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.GameOver, TurnRules.Input.Cancel)
                                              => Some(scene)
        // 中断確認: Z/Enter で「はい/いいえ」確定、X で中断をやめて PlayerCursor へ。
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Confirm)
                                              => Some(SuspendConfirmScene.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.SuspendConfirm, TurnRules.Input.Cancel)
                                              => Some(SuspendConfirmScene.cancel(scene))
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Confirm)
                                              => Some(ActionMenuScene.confirmCurrentSelection(scene))
        case (TurnPhase.Phase.ActionSelect,      TurnRules.Input.Cancel)
                                              => Some(checked_ecast(ActionMenuScene.onActionCancelled(scene)))
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Confirm)
                                              => Some(checked_ecast(WeaponSelectScene.confirmCurrentSelection(scene)))
        case (TurnPhase.Phase.WeaponSelect,      TurnRules.Input.Cancel)
                                              => Some(checked_ecast(WeaponSelectScene.onCancelled(scene)))
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

/// メニュー以外のフェーズ (GatherMove / StaffAim / AttackForecast 等) の Z/X dispatch。
/// `onKeyPressed` から `dispatchMenuKey` で処理されなかったときに呼ばれる。
/// 方向キーなど input = None もここに来る (StaffAim 中の direction、ほかは no-op)。
def dispatchNonMenuKey(phase: TurnPhase.Phase, input: Option[TurnRules.Input],
                        key: GameEngine.Key, popupShown: Bool, scene: Scene[NodeTag]):
        Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio, BoardQuery, Tween.Scheduler,
                            AnimationPlayer.Scheduler,
                            GameLogger.GameLogger,
                            EnemyTurn.Queue, TurnPhase.State,
                            SelectedPlayer.State,
                            PlayerData.PartyQuery,
                            EnemyData.RosterQuery,
                            Math.Random, CustomEffects.GameOverRequest, World.Command, World.WorldQuery} =
        match (phase, input) {
        // popup 表示中の X は popup view 切替に上書き（通常のキャンセルは走らない）
        case (_,                              Some(TurnRules.Input.Cancel)) if popupShown
                                              => UnitInfoPopupScene.toggleView(scene)
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
/// Left / A → 前カテゴリ、Right / D → 次カテゴリ（武器/消費/杖/指輪。空はスキップ）。
/// Up / Down は handleMenus が ItemList のスクロール（カーソル移動）に使うので素通し。
def itemSelectDirection(key: GameEngine.Key, scene: Scene[NodeTag]):
        Scene[NodeTag] \ SelectedPlayer.State =
    match key {
        case GameEngine.Key.Left  => ItemMenuScene.categoryPrev(scene)
        case GameEngine.Key.A     => ItemMenuScene.categoryPrev(scene)
        case GameEngine.Key.Right => ItemMenuScene.categoryNext(scene)
        case GameEngine.Key.D     => ItemMenuScene.categoryNext(scene)
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
    /// 計算がこの値を使うため、ずれると PhaseBanner 等の帯が画面幅とずれる）。
    /// 縦横比は windowWi/windowHi と一致させる（240:128 = 1170:624）。ずらすと引き伸ばし歪みになる。
    pub def designWi(): Int32 = 240
    pub def designHi(): Int32 = 128

    /// 初期ウィンドウサイズ（OS ピクセル単位）。design とは独立して指定でき、
    /// design 側がウィンドウいっぱいに引き伸ばし描画される。
    /// design と同じ縦横比（240:128）にしてピクセル等倍・歪みなしで表示する。
    pub def windowWi(): Int32 = 1170
    pub def windowHi(): Int32 = 624

    /// ゲーム起動エントリ。Region と各 effect handler を立ち上げ、初回シーンを
    /// `GameLifecycle.buildPlayingScene` で組み立てて `gameLoop` に入る。
    /// **配線役** に徹するため、ここにゲームロジックは書かない。
    pub def start(): Unit \ {GameEngine.Game, GameEngine.Audio,
                              Fs.FileRead, Fs.FileWrite, IO, Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            // S4: BoardQuery handler が読む World の窓口（sceneRef と対称・毎フレーム頭で gameLoop が更新）。
            // frame-head の world は scene の faithful mirror なので toBoard は fromScene と同値（挙動不変）。
            let worldRef = Ref.fresh(rc, World.empty());
            // F2b: turn phase の Ref。TurnPhase.State handler を inline 化し、`put` でこの Ref と worldRef.turnPhase を
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
                // 起動直後はタイトル画面を組む。はじめから → CharacterSelect、中断から再開 →
                // Playing（applyPhaseChange が snapshot から再構築）と遷移する。
                // BGM は BgmScene の AudioStreamPlayer ノード (autoplay=true, loop=true,
                // volume=0.05) で applyAudioAttach 経由で再生される (= ここでは触らない)
                let scene = applyPhaseChange(GamePhase.Title, GamePhase.Title, catalogs, Scene.empty());
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
                // 初回 world は scene の mirror（frame-1 で handler が呼ばれても faithful＝空 pieces を返さない）。
                gameLoop(catalogs, sceneRef, worldRef, GamePhase.Title, scene,
                         World.syncFromScene(scene, World.empty()))
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
                  def request(scene, k) = k(GameOverMenuScene.freezeAndShow(scene))
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
              with handler BoardQuery {
                  // 盤面読み取りを World 由来に（位置権威＝World）。pieces は worldRef（`Cmd.Move` のみ由来・
                  // mid-frame 最新）、map（地形）は sceneRef から。P3 で位置 mirror を撤去済みゆえ pieces は
                  // command 由来。write 漏れの恒久ガードは gameLoop 末尾の `[P3 WRITE-MISS]`（フレーム末・通常無音）。
                  def board(k) = k(World.toBoard(Ref.get(worldRef), Ref.get(sceneRef)))
              }
              with handler World.Command {
                  // statuses 書き込み（Bevy Commands）。深い scene コードの emit を worldRef へ即時適用。
                  def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(worldRef)), worldRef); k() }
              }
              with handler World.StatusQuery {
                  // statusEffects 読み込み（Bevy Query）。EntityRef で引く faction 非依存の read seam。
                  def statusEffects(ref, k) = k(World.statusEffectsOf(ref, Ref.get(worldRef)))
              }
              with handler World.PhaseQuery {
                  // F2c: turn phase（sim-phase 3-case）を worldRef から読む read seam。
                  def phase(k) = k(World.turnPhaseOf(Ref.get(worldRef)))
              }
              with handler World.WorldQuery {
                  // F7: 現 World スナップショット（worldRef）を返す汎用 read seam。フラグ reader 共通窓口。
                  def get(k) = k(Ref.get(worldRef))
              }
              with handler World.RngDraw {
                  // slice `rng-world`: live combat ロールの chokepoint。0..99 reduction は
                  // `Prng.unitToPercent` 一本に集約（live も Prng/oracle も同一本体＝数値 bit-identical を
                  // 型で保証。式が複製されると live と golden が無言で乖離する）。source だけ live=Math.Random。
                  // worldRef の seeded PRNG は進めない（PRNG は test/trace 専用）。
                  def nextPercent(k) = k(Prng.unitToPercent(Math.Random.randomFloat64()))
              }
              with handler PlayerData.PartyQuery {
                  def get(id, k)           = k(PlayerScene.get(id, Ref.get(sceneRef)))
                  def getAll(k)            = k(PlayerScene.getAll(Ref.get(sceneRef)))
              }
              with handler EnemyData.RosterQuery {
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
              with handler TurnPhase.State {       // F2b: inline 化し put を World へ dual-write（全 put が World.turnPhase 反映）
                  def get(k) = k(Ref.get(turnPhaseRef))
                  def put(target, k) = {
                      Ref.put(target, turnPhaseRef);
                      Ref.put(World.applyCmd(World.Cmd.SetPhase(simPhaseOf(target)), Ref.get(worldRef)), worldRef);
                      k()
                  }
              }
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with GatherResume.withState(rc)     // 集合モードのターン跨ぎ自動継続フラグ
              with InitialSpawns.withState(rc)    // ゲームオーバー時に同じ敵 / 味方配置を復元
              with FloorSnapshot.withState(rc)    // 進入時フロアスナップショット（全滅時の「フロア最初から」用）
              with FloorProgress.withState(rc, FloorCatalog.firstFloorId(floors))  // 現在フロア id
              with PartySelection.withState(rc)   // 出撃メンバー（開始時に1回抽選、フロア間で維持）
        }

    /// GamePhase に応じて画面（Scene）を組み立てる。**配線役** に徹し、ここに画面固有の
    /// ロジックは書かない（各 Scene の構築関数を呼ぶだけ）。
    ///   CharacterSelect — 出撃メンバー選択画面を組む。
    ///   Playing         — 現在フロアのダンジョンを組む（出撃メンバーは選択画面で確定済み）。
    /// gameLoop が前フレームとの差分を見て、画面が変わったフレームだけ呼ぶ。
    def applyPhaseChange(phase: GamePhase, prevPhase: GamePhase, catalogs: GameLifecycle.Catalogs,
                          _scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, GameEngine.Audio, Fs.FileRead, IO, Math.Random,
                SelectedPlayer.State, InitialSpawns.State, FloorProgress.State,
                PartySelection.State, GameLogger.GameLogger, FloorSnapshot.State, World.Command} =
        match phase {
            case GamePhase.Title =>
                TitleMenuScene.add(Scene.empty())
            case GamePhase.CharacterSelect =>
                CharacterSelectScene.add(UnitCatalog.pool("players", catalogs#players),
                                          Scene.empty())
            case GamePhase.Playing =>
                // タイトル由来 ＋ スナップショット有り ＝ 中断再開。`FloorSnapshot.State` の snapshot から
                // **乱数なし** で決定論再構築する（`buildCurrentFloor` は乱数を消費して別マップになるため通さない）。
                // それ以外（CharacterSelect 由来 ＝ 新規ラン、または防御的に snapshot 無し）は通常生成。
                match (prevPhase, FloorSnapshot.State.get()) {
                    case (GamePhase.Title, Some(snap)) =>
                        GameLogger.playerLog("中断データから再開");
                        GameLifecycle.rebuildFloorFromSnapshot(catalogs, snap)
                    case _ =>
                        GameLogger.playerLog("T1 味方のターン");
                        GameLifecycle.buildCurrentFloor(catalogs)
                }
        }

    /// メインループ。phase で分岐せず、**固定パイプライン** を毎フレーム回す:
    ///   handleInput → handleMenus → physicsProcess → Tween → Animation → process → epilogue
    /// F2a: 19-case `TurnPhase.Phase` を World の 3-case `SimPhase` に写す（境界の写像）。
    /// メニュー遷移・演出待ち系は全て「味方ターン」配下＝`PlayerTurn`（細分は UiState.modalMode / anim-queue）。
    def simPhaseOf(phase: TurnPhase.Phase): SimPhase = match phase {
        case TurnPhase.Phase.EnemyTurn => SimPhase.EnemyTurn
        case TurnPhase.Phase.GameOver  => SimPhase.GameOver
        case _                          => SimPhase.PlayerTurn
    }

    /// 各 process / input redef 内で「自分が今動くべきか」を phase で判断する (Godot 流)。
    /// 例: `EnemyTurnDriverScene.process` は phase=EnemyTurn / PlayerAttackHold で動作、
    ///     `PlayerMovementScene.gatherStep` は phase=GatherMove で主人公(id 0)を動かす。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def gameLoop(catalogs: GameLifecycle.Catalogs,
                  sceneRef: Ref[Scene[NodeTag], r],
                  worldRef: Ref[World, r],   // S4: BoardQuery handler が読む World の窓口（毎フレーム頭で更新）。
                  previousPhase: GamePhase,
                  scene: Scene[NodeTag],
                  world: World):           // S0: ハイブリッド ECS 足場。scene→World 並走 sync。描画に無影響。
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         Fs.FileRead, IO,
                         BoardQuery,
                         PlayerData.PartyQuery, EnemyData.RosterQuery,
                         Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State, GatherResume.State,
                         CustomEffects.GameOverRequest,
                         CustomEffects.FloorAdvanceRequest,
                         CustomEffects.WandererSpawnRequest,
                         CustomEffects.RingTransformRequest,
                         CustomEffects.ThiefDropRequest,
                         CustomEffects.SuspendRequest, CustomEffects.ResumeRequest,
                         FloorProgress.State, InitialSpawns.State,
                         GamePhaseState, PartySelection.State,
                         Pacing.State, Math.Random, FloorSnapshot.State,
                         World.Command, World.StatusQuery, World.PhaseQuery, World.WorldQuery,
                         World.RngDraw, r} =
        // Escape ではアプリ終了しない。ウィンドウの閉じる操作（shouldClose）だけで終了する。
        if (GameEngine.Game.shouldClose()) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene / world に更新する。
            // world は前フレーム末の syncFromScene(next) ＝ この scene の faithful mirror（整合ペア）。
            Ref.put(scene, sceneRef);
            Ref.put(world, worldRef);
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
                |> GameEngine.process(delta = dt, paused = false)
                // F8: ターン進行 LOGIC driver を OOP node callback から外し、明示的な frame-paced System
                // としてパイプライン段で 1 回呼ぶ（per-node 巡回でなく gameLoop が駆動）。process の後＝combat
                // drain と TopBar 更新が確定した post-process scene を読む（前後依存は World 経由で順序非依存）。
                |> EnemyTurnDriverScene.step
                |> StairsExitScene.step;
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
            // P3/Phase B（位置・hp・isDying・alerted・progress を World 権威化・scene 派生）: これらは refreshMirror が
            // command 由来を preserve し、frame-end の `syncTreeFromWorld` が scene へ一方向 derive する（dual-write 解消）。
            // legacy 無音を run 確認済みゆえ旧 DIFF 検出器（F6 HP / ALERTED / DYING / PROGRESS / COMBATVIEW）は撤去した
            // （write 漏れは「hp が動かない / 敵が死なない / exp が増えない」可視バグとして現れる＝位置 P3 WRITE-MISS 撤去と同じ）。
            // S6: bottleUsed を World 権威化（scene 直書き撤去・syncTree derive）したため [BOTTLE DIFF] は撤去。
            // S6: prevPos を World 権威化（scene 直書き撤去・syncTree derive）したため [PREVPOS DIFF] は撤去。
            // S6: followUpUsed を World 権威化（scene 直書き撤去・syncTree derive）したため [FOLLOWUP DIFF] は撤去。
            // S6: waited は World 権威化（scene 直書き撤去・syncTreeFromWorld で derive）したため、
            // pre-sync の dual-write 等値を前提にした [WAITED DIFF] 検出器は撤去（gridPos/hp と同様）。
            // 後段 post-sync の [PLAYERDATA/UNITVIEW DIFF] が waited を含む twin parity を担保する。
            // write 漏れ（Cmd.SetWaited 抜け）は「駒が灰色にならない/行動済みにならない」可視バグとして現れる。
            match World.attackTargetMismatches(Ref.get(worldRef), next) {  // F8-slice1
                case Nil => ()
                case ms  => println("[ATTACKTARGET DIFF] ${ms}")
            };
            // 🏁 A完成 sweep（2026-06-30）: dual-write 足場の runtime DIFF 検出器は ATTACKTARGET（attackTargetId は
            // combat 解決の同期キャリア＝Phase C/B まで恒久 dual-write ゆえ invariant guard を残す）のみ残し全撤去。
            // usedStairs/acted/topbar は包括 run 検証で無音確認後に撤去（他 store は §G S2.3〜S4.4b batch 済）。
            // invariant は unit test(testXxxMismatchesEmptyWhenSynced/DetectsDrift)＋spawn-seed test で継続検証。
            let world1 = World.refreshMirror(next, Ref.get(worldRef));
            // F0（OOP→ECS 移行の足場）: **System パイプライン段**。ロジックを OOP callback でなく
            // `World -> World` の System で回す将来形の seam。S3 以後 stepWorld は identity（statusEffects は
            // command-authoritative ＝ターン境界の Seed で tick 反映・frame-paced tick は二重 tick になるため撤去）。
            // 以後の World→World System はここに足していく。
            // B/m2: moveAnim を実時間 dt（既存の dt: Duration を秒換算）で進める＝engine tween と lockstep 同期。
            let world2 = World.stepWorld(world1, Duration.toSeconds(dt));
            // F2b（turn phase 書込を Cmd 化）: phase は `TurnPhase.State` handler が `put` のたび `Cmd.SetPhase` で
            // worldRef へ dual-write 済み＝**World.turnPhase は command 由来**（全 41 put サイトを handler 1 箇所で被覆）。
            // よって frame-end の mirror は不要。並走 assert は command 由来 phase と State の乖離（write 漏れ）を検出する
            // ＝dual-write ゆえ無音だが、将来 dual-write を割る時のガード。phase 権威は当面 TurnPhase.State（read は未 flip）。
            if (World.turnPhaseOf(world2) != simPhaseOf(TurnPhase.State.get()))
                println("[F2 PHASE DIFF] world=${World.turnPhaseOf(world2)} state=${simPhaseOf(TurnPhase.State.get())}")
            else ();
            // S5b（§A 完成・World→scene 一方向 sync）: scene の gridPos を **World の位置で derive** する
            // （move 関数は gridPos を直書きしなくなった＝`Cmd.Move` が唯一の位置 source）。これで
            // scene は World の純粋な派生ビューになり、dual-write は解消。write 漏れは「ユニットが動かない」
            // 可視バグとして現れるので、旧 `[P3 WRITE-MISS]` 検出器（独立 dual-write 前提）は撤去した。
            let synced = World.syncTreeFromWorld(world2, next);
            // S4 twin parity 検査は **syncTreeFromWorld の後**に置く（scene が World から派生し終えた点）。
            // pre-sync だと gridPos が 1 フレーム遅延（World pos=当フレーム / scene gridPos=前フレームの派生）、
            // hidden/equippedRing が re-mirror stale で false-positive を出していた。post-sync では gridPos=World 派生・
            // read-model も refreshMirror 済みで揃う。dual-write 系(weapons/staves/statuses 等・syncTree 非派生)は
            // scene が process 値のままゆえ「World store == scene」の coverage を維持する。
            match World.unitViewMismatches(world2, synced) {  // S4.1
                case Nil => ()
                case ms  => println("[UNITVIEW DIFF] ${ms}")
            };
            match World.playerDataMismatches(world2, synced) {  // S4.4
                case Nil => ()
                case ms  => println("[PLAYERDATA DIFF] ${ms}")
            };
            match World.enemyDataMismatches(world2, synced) {  // S4.4b
                case Nil => ()
                case ms  => println("[ENEMYDATA DIFF] ${ms}")
            };
            // B1-m1a: render-from-World overlay。on で scene-tree drawable に World 由来 box を重ねて
            // 1 回の renderCommands で描く（renderCommands は毎回 clear ゆえ 2 回呼びは不可＝合成する）。
            // これで通常ゲーム（メニュー/マップ/ユニット）は見えたまま World box が重なる＝位置一致を実証。
            if (RenderWorld.useRenderFromWorld()) {
                // m1c: scene 側ユニット sprite を隠して描画 → ユニットは World 由来のみで描く。
                // ※ marker(武器/HPバー)は engine 駆動のまま（移動 tween + 攻撃 lunge 等を全部保持）。
                // B/fog: scene 側 fog 暗幕プールも隠し、暗幕は renderFog（World render System）で描く。
                let prepped = RenderWorld.hideUnitSprites(synced) |> FogScene.hideHaze;
                let (sprites, tileMaps, polygons) = GameEngine.renderArgs(prepped);
                let worldDrawables = List.append(RenderWorld.renderUnits(world2, synced), RenderWorld.renderFog(synced));
                GameEngine.Game.renderCommands(List.append(sprites, worldDrawables), tileMaps, polygons)
            } else
                GameEngine.render(synced);
            gameLoop(catalogs, sceneRef, worldRef, currentPhase, synced, world2)
        }
}
