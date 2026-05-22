/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case EnemyRange(EnemyRangeScene.Data)
    case PlayerAttackRange(PlayerAttackRangeScene.Data)
    case MoveAttackRange(MoveAttackRangeScene.Data)
    case Cursor(CursorScene.Data)
    case Flag(FlagScene.Data)
    case Log(LogScene.Data)
    /// WeaponMenuScene の Panel ルート（外枠）
    case WeaponPanel
    /// WeaponMenuScene の ItemList（武器一覧表示）
    case WeaponMenu
    /// ActionMenuScene の Panel ルート（外枠）
    case ActionPanel
    /// ActionMenuScene の ItemList（こうげき / たいき）
    case ActionMenu
    /// ForecastPanelScene の Panel ルート（戦闘予報の外枠）
    case ForecastPanel
    /// ForecastPanelScene の Label2D（HP / 威力 / 命中 を 2 列で表示）
    case ForecastText
    /// DamagePopupScene の Marker2D 親（World 直下に永続）
    case DamagePopupsRoot(DamagePopupScene.RootData)
    /// DamagePopupScene の Label2D 子（寿命を持つ）
    case DamagePopup(DamagePopupScene.PopupData)
    /// UnitHPBarScene の Marker2D 親（戦闘表示 timer + currentHp/maxHp を持つ）
    case HPBar(UnitHPBarScene.HPBarData)
    /// UnitInfoPopupScene の CanvasLayer 親（表示中ユニット識別子を持つ）
    case UnitInfoPanel(UnitInfoPopupScene.PanelState)
    /// ItemScene の床に落ちている武器（拾える）
    case GroundItem(ItemScene.Data)
    /// `EnemyTurnDriverScene` の常駐タグ専用ノード (Marker2D)。process redef で phase を
    /// 見て EnemyTurn 中なら stepOnce、PlayerAttackHold 中なら hold 終了判定を行う。
    case EnemyTurnDriver
    /// `AutoMoveScene` の常駐タグ専用ノード (Marker2D)。
    /// `AutoMoveScene.process` redef で phase を見て PlayerAutoMove 中なら `step` を呼ぶ。
    case AutoMoveDriver
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
                // 選択中プレイヤー & PlayerMoving フェーズだけが移動を受け付ける
                if (TurnPhase.State.get() == TurnPhase.Phase.PlayerMoving
                    and SelectedPlayer.State.get()#id == Some(data#id))
                    PlayerScene.physicsProcess(delta, node, path, scene)
                else (node, scene)
            case EngineNode.Marker2DWithState(_, NodeTag.Cursor(_)) =>
                // PlayerCursor / PlayerAttack の場合分けは CursorScene 内部に閉じている
                CursorScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
    // 各 ノード固有の毎フレーム更新を dispatch する。各 Scene が「自分のノード」に対する
    // process redef を持ち、ここでは「どの NodeTag をどの Scene 関数に流すか」の対応表に徹する。
    // Player / Enemy は AnimationPlayer signal を自分で drain (Godot 流 per-AnimationPlayer)。
    // ForecastPanel の Label2D テキストはフェーズ入り時のワンショット更新なので process では触らない。
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
        case EngineNode.Camera2DWithState(_, _) =>
            checked_ecast(CameraScene.process(delta, node, path, scene))
        case EngineNode.RichTextLabelWithState(_, NodeTag.Log(_)) =>
            checked_ecast(LogScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// フェーズ駆動の driver ノード (EnemyTurnDriver / AutoMoveDriver)
def dispatchDrivers(delta: Duration.Duration, node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.Marker2DWithState(_, NodeTag.EnemyTurnDriver) =>
            checked_ecast(EnemyTurnDriverScene.process(delta, node, path, scene))
        case EngineNode.Marker2DWithState(_, NodeTag.AutoMoveDriver) =>
            checked_ecast(AutoMoveScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

/// メニュー系ノード (WeaponMenu / ActionMenu の ItemList、ForecastPanel の Panel)
def dispatchMenus(delta: Duration.Duration, node: EngineNode[NodeTag],
                   path: NodePath, scene: Scene[NodeTag]):
                  (EngineNode[NodeTag], Scene[NodeTag]) \ FrameAef.ProcessT =
    match node {
        case EngineNode.ItemListWithState(_, NodeTag.WeaponMenu) =>
            checked_ecast(WeaponMenuScene.refreshItems(delta, node, path, scene))
        case EngineNode.ItemListWithState(_, NodeTag.ActionMenu) =>
            checked_ecast(ActionMenuScene.refreshItems(delta, node, path, scene))
        case EngineNode.PanelWithState(_, NodeTag.ForecastPanel) =>
            checked_ecast(ForecastPanelScene.process(delta, node, path, scene))
        case _ => (node, scene)
    }

// 決定キー（Z / Space / Enter）/ キャンセルキー（X）の意味はフェーズで変わる。
// 判断ロジックは `TurnRules.decide` に集約してあり、ここでは
// 「キー → Input → 判断 → apply」という配線だけを行う（実体は `GameManager`）。
//
//   PlayerCursor + Z   : 味方マス → 選択 / 床マス → 旗を立てる / それ以外 → 何もしない
//   PlayerMoving + Z/X : Tween 中はガード。Z で攻撃フェーズ、X で origin へ戻して PlayerCursor
//   PlayerAttack + Z/X : 敵マスで Z → 攻撃モーション開始、X / 空マスで Z → 行動終了
//   EnemyTurn / PlayerAutoMove : 入力無視（自動進行）
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {GameEngine.Game, BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State,
                 PlayerScene.PartyQuery, EnemyScene.RosterQuery}
    // WeaponSelect フェーズでは engine の MenuEvent が Enter/Escape を処理する一方、
    // FERogue のキー慣習として Z（決定）/ X（ウィンドウを閉じる）も使えるよう、
    // フェーズに応じて分岐する:
    //   - Z / Space: メニューの現在選択中の武器を確定 → 攻撃モーション開始
    //   - X        : 武器選択ウィンドウを閉じて PlayerAttack に戻る（ターゲット選び直し可）
    // PlayerCursor / PlayerAttack 中で UnitInfoPopup が表示中なら、**X は popup の
    // Status ↔ Items 切替**に取られる（通常のキャンセルは popup 非表示時のみ）。
    // Z はそのまま選択/旗設置で従来通り。
    // それ以外のフェーズではこれまで通り TurnRules 経由で振る舞いを決める。
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GameEngine.Game, BoardQuery, Tween.Scheduler,
                                          AnimationPlayer.Scheduler,
                                          GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State,
                                          SelectedPlayer.State,
                                          PlayerScene.PartyQuery,
                                          EnemyScene.RosterQuery} =
        let isConfirm = key == GameEngine.Key.Z
                        or key == GameEngine.Key.Space
                        or key == GameEngine.Key.Enter;
        let isCancel  = key == GameEngine.Key.X or key == GameEngine.Key.Escape;
        let phase = TurnPhase.State.get();
        let popupShown = UnitInfoPopupScene.isShown(scene)
                          and (phase == TurnPhase.Phase.PlayerCursor
                                or phase == TurnPhase.Phase.PlayerAttack);
        match (phase, isConfirm, isCancel) {
            // popup 表示中の X は popup view 切替に上書き（通常のキャンセルは走らない）
            case (_,                              _,    true) if popupShown
                                                  => UnitInfoPopupScene.toggleView(scene)
            // PlayerAutoMove 中の X / Esc は AutoMove キャンセル
            case (TurnPhase.Phase.PlayerAutoMove, _,    true)
                                                  => checked_ecast(AutoMoveScene.cancel(scene))
            case (TurnPhase.Phase.ActionSelect,   true,  _)
                                                  => ActionMenuScene.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.ActionSelect,   _,    true)
                                                  => checked_ecast(ActionMenuScene.onActionCancelled(scene))
            case (TurnPhase.Phase.WeaponSelect,   true,  _)
                                                  => WeaponMenuScene.confirmCurrentSelection(scene)
            case (TurnPhase.Phase.WeaponSelect,   _,    true)
                                                  => checked_ecast(WeaponMenuScene.onWeaponCancelled(scene))
            case (TurnPhase.Phase.AttackForecast, true, _)
                                                  => ForecastPanelScene.confirm(scene)
            case (TurnPhase.Phase.AttackForecast, _,    true)
                                                  => checked_ecast(ForecastPanelScene.cancel(scene))
            case (_,                              true, _)
                                                  => TurnInputBridge.handle(TurnRules.Input.Confirm, scene)
            case (_,                              _,    true)
                                                  => TurnInputBridge.handle(TurnRules.Input.Cancel, scene)
            case _                                => scene
        }
}

/// MenuHandler instance — ItemList の Enter/Escape を WeaponMenuScene へ流す。
/// 入力キー固定: Up/Down=カーソル移動 / Enter=確定 / Escape=キャンセル（engine 規約）。
/// Enter は「武器確定 → 戦闘予報フェーズへ」、Escape は「ウィンドウを閉じて target 選択に戻る」。
instance MenuEvent.MenuHandler[NodeTag] {
    type Aef = {Tween.Scheduler, AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State,
                 PlayerScene.PartyQuery, EnemyScene.RosterQuery}
    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, entry: ItemEntry,
                           state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             PlayerScene.PartyQuery,
                                             EnemyScene.RosterQuery} =
        match state {
            case NodeTag.WeaponMenu => checked_ecast(WeaponMenuScene.onWeaponConfirmed(entry, scene))
            case NodeTag.ActionMenu => ActionMenuScene.onActionConfirmed(entry, scene)
            case _                  => scene
        }
    redef onItemCancelled(_menuPath: NodePath, state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State,
                                             PlayerScene.PartyQuery,
                                             EnemyScene.RosterQuery} =
        match state {
            case NodeTag.WeaponMenu => checked_ecast(WeaponMenuScene.onWeaponCancelled(scene))
            case NodeTag.ActionMenu => checked_ecast(ActionMenuScene.onActionCancelled(scene))
            case _                  => scene
        }
}

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さい 128×128（= 8×8 グリッド分）で切り出す。Camera2D 追従でビューが動く。
    /// この値はカメラのビューポートと投影行列の基準で、ウィンドウサイズに合わせて
    /// 引き伸ばし表示される（Godot の Stretch Mode = canvas_items 相当）
    pub def designWi(): Int32 = 128
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
            // ユニットカタログをロード + schema 整合性検査（Z 戦略の安全網）。
            // 各段階で失敗内容を panic に出して原因を即可視化する。
            let catalog = UnitCatalog.load("resources/units.json", "resources/weapons.json");
            let schema = match Resource.loadSchemaDiagnostic("resources/units.schema.json") {
                case Ok(s)    => s
                case Err(msg) => bug!("Resource.loadSchema failed :: ${msg}")
            };
            // checkConsistency は純粋なので let _ で式を明示的に消化する
            // （そうしないと "Useless expression: pure and discarded" になる）
            let _ = match Resource.checkConsistency(UnitCatalog.expectedUnitFields(), schema) {
                case Ok(_)    => ()
                case Err(msg) => bug!("UnitResource schema/type mismatch: ${msg}")
            };
            // 武器も同じ規格で schema を持ち、起動時に整合性検査だけ通す。
            // (IDE の resource エディタは weapons map 自体のフォーム編集に対応していないため、
            //  この schema は型と data の対応を保証するための「契約」として使う)
            let weaponsSchema = match Resource.loadSchemaDiagnostic("resources/weapons.schema.json") {
                case Ok(s)    => s
                case Err(msg) => bug!("Resource.loadSchema (weapons) failed :: ${msg}")
            };
            let _ = match Resource.checkConsistency(UnitCatalog.expectedWeaponFields(), weaponsSchema) {
                case Ok(_)    => ()
                case Err(msg) => bug!("WeaponResource schema/type mismatch: ${msg}")
            };
            run {
                // 初回 build と spawn snapshot 保存をまとめて行う (GameOver リビルドと同じ経路)
                let scene = GameLifecycle.buildAndRecord(catalog);
                // BGM は控えめに、SE は半分で鳴らす
                AudioStreamPlayer.setVolume("bgm",    0.05f32);
                AudioStreamPlayer.setVolume("damage", 0.5f32);
                AudioStreamPlayer.setVolume("bonus",  0.5f32);
                // BGM はゲーム開始時に再生（looping = true で曲が終わってもループする）
                AudioStreamPlayer.play("bgm");
                GameLogger.playerLog("T1 味方のターン");
                gameLoop(sceneRef, scene)
            // handler の並び順 = effect 消費順 (構文上で後の `with` ほど **外側**)。
            // `GameOverRequest` の handler 本体は `GameLogger` / `EnemyTurn.Queue` /
            // `TurnPhase.State` / `SelectedPlayer.State` / `InitialSpawns.State` 等を
            // 使うため、これらより **内側** (= 構文上で先) に書く必要がある。
            // 同様に `BoardQuery` も `Ref` 経由で sceneRef を読むだけだが内側に置く。
            } with handler CustomEffects.GameOverRequest {
                  // 全味方脱落でフルリビルド: turn 系 state をリセットしてから scene を作り直し、
                  // 新しい spawn 一覧を InitialSpawns に書き戻す。本体は GameLifecycle 側。
                  def request(_scene, k) = k(GameLifecycle.resetForGameOver(catalog))
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
              with Tween.withScheduler(rc)        // tween 一覧は内部に隠蔽
              with AnimationPlayer.withScheduler(rc)  // 名前付きアニメ + イベントドレイン
              with Pacing.withState(rc)           // 演出の溜め (hold)
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with EnemyTurn.withQueue(rc)        // 敵ターンキュー（1 step / 1 frame 駆動）
              with TurnPhase.withState(rc)        // 味方ターン内のサブフェーズ + 敵ターン
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with InitialSpawns.withState(rc)    // ゲームオーバー時に同じ敵 / 味方配置を復元
        }

    /// メインループ。phase で分岐せず、**固定パイプライン** を毎フレーム回す:
    ///   handleInput → handleMenus → physicsProcess → Tween → Animation → process → epilogue
    /// 各 process / input redef 内で「自分が今動くべきか」を phase で判断する (Godot 流)。
    /// 例: `EnemyTurnDriverScene.process` は phase=EnemyTurn / PlayerAttackHold で動作、
    ///     `AutoMoveScene.process` は phase=PlayerAutoMove で動作。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def gameLoop(sceneRef: Ref[Scene[NodeTag], r],
                  scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         BoardQuery,
                         PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                         Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State,
                         CustomEffects.GameOverRequest,
                         Pacing.State, r} =
        // Escape は通常はゲーム終了に使うが、武器選択メニュー / 戦闘予報パネル表示中は
        // engine の MenuEvent / InputHandler がそれぞれ「キャンセル」として消費するので、
        // ここでは終了させない。
        let phase = TurnPhase.State.get();
        let inSubMenu = phase == TurnPhase.Phase.ActionSelect
                         or phase == TurnPhase.Phase.WeaponSelect
                         or phase == TurnPhase.Phase.AttackForecast;
        let escapeQuit =
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)
            and not inSubMenu;
        if (GameEngine.Game.shouldClose() or escapeQuit) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            Ref.put(scene, sceneRef);
            let dt = GameEngine.Game.getDeltaTime();
            // Pacing カウンタを 1 フレーム進める (各 Scene の process が gating で参照する)。
            // フレーム頭で進めるので「前フレーム末で hold した値を今フレームの判定で使う」
            // 形になり、Scene に紐づかないため gameLoop 内で 1 行のままにする。
            Pacing.State.tick(dt);
            let next = scene
                |> GameEngine.handleInput
                |> GameEngine.handleMenus
                |> GameEngine.physicsProcess(delta = dt, paused = false,
                                              gravity = Vec2.zero())
                |> Tween.tickAll(dt)
                |> AnimationPlayer.tickAll(dt)
                |> GameEngine.process(delta = dt, paused = false);
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }
}
