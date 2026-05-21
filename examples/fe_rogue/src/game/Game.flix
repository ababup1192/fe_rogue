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
    case NoTag
}

// physicsProcess はフェーズに応じて Player / Cursor のいずれか 1 体だけを
// dispatch する。`PlayerCursor` / `PlayerAttack` 中はカーソルだけ。
// `PlayerMoving` 中は **選択中の味方 1 体だけ** が方向キーを polling する。
// それ以外のフェーズ（`EnemyTurn`）では gameLoop 側が physicsProcess パイプライン
// 自体を呼ばないので no-op で良い。
instance Node[NodeTag] {
    // `ready` / `physicsProcess` 用の Aef (Player.physicsProcess / Cursor.physicsProcess
    // が要求する集合 + 共通)
    type Aef = {GameEngine.Game, BoardQuery,
                 Tween.Scheduler, AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State}
    // `process` 用の広い Aef (Player/Enemy の `process` が drainSignals 経由で
    // attack:hit / death_blink / attack_lunge を捌くため、Audio / EnemyTurn /
    // GameOverRequest / Pacing が追加される)
    type ProcessAef = {GameEngine.Game, GameEngine.Audio, BoardQuery,
                        Tween.Scheduler, AnimationPlayer.Scheduler,
                        GameLogger.GameLogger,
                        EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                        CustomEffects.GameOverRequest, Pacing.State}
    redef physicsProcess(delta: Duration.Duration,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {GameEngine.Game, BoardQuery,
                             Tween.Scheduler, AnimationPlayer.Scheduler,
                             GameLogger.GameLogger, TurnPhase.State,
                             SelectedPlayer.State} =
        let phase = TurnPhase.State.get();
        match (node, phase) {
            case (EngineNode.Marker2DWithState(_, NodeTag.Player(data)),
                  TurnPhase.Phase.PlayerMoving) =>
                // 選択中プレイヤーだけが移動を受け付ける
                if (SelectedPlayer.State.get()#id == Some(data#id))
                    PlayerScene.physicsProcess(delta, node, path, scene)
                else (node, scene)
            case (EngineNode.Marker2DWithState(_, NodeTag.Cursor(_)),
                  TurnPhase.Phase.PlayerCursor) =>
                CursorScene.physicsProcess(delta, node, path, scene)
            case (EngineNode.Marker2DWithState(_, NodeTag.Cursor(_)),
                  TurnPhase.Phase.PlayerAttack) =>
                CursorScene.physicsProcessAttack(delta, node, path, scene)
            case _ => (node, scene)
        }
    // 各 ノード固有の毎フレーム更新を dispatch する。各 Scene が「自分のノード」に対する
    // process redef を持ち、ここでは「どの NodeTag をどの Scene 関数に流すか」の対応表に徹する。
    // Player / Enemy は AnimationPlayer signal を自分で drain (Godot 流 per-AnimationPlayer)。
    // ForecastPanel の Label2D テキストはフェーズ入り時のワンショット更新なので process では触らない。
    redef process(delta: Duration.Duration, node: EngineNode[NodeTag],
                   path: NodePath, scene: Scene[NodeTag]):
                  (EngineNode[NodeTag], Scene[NodeTag])
                  \ {GameEngine.Game, GameEngine.Audio, BoardQuery,
                      Tween.Scheduler, AnimationPlayer.Scheduler,
                      GameLogger.GameLogger,
                      EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                      CustomEffects.GameOverRequest, Pacing.State} =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(_)) =>
                checked_ecast(PlayerScene.process(delta, node, path, scene))
            case EngineNode.Marker2DWithState(_, NodeTag.Enemy(_)) =>
                checked_ecast(EnemyScene.process(delta, node, path, scene))
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
            case EngineNode.ItemListWithState(_, NodeTag.WeaponMenu) =>
                checked_ecast(WeaponMenuScene.refreshItems(delta, node, path, scene))
            case EngineNode.ItemListWithState(_, NodeTag.ActionMenu) =>
                checked_ecast(ActionMenuScene.refreshItems(delta, node, path, scene))
            case EngineNode.PanelWithState(_, NodeTag.ForecastPanel) =>
                checked_ecast(ForecastPanelScene.process(delta, node, path, scene))
            case _ => (node, scene)
        }
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
                 TurnPhase.State, SelectedPlayer.State}
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
                                          SelectedPlayer.State} =
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
                                                  => checked_ecast(AutoMoveDriverScene.cancel(scene))
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
                 TurnPhase.State, SelectedPlayer.State}
    redef onItemConfirmed(_menuPath: NodePath, _idx: Int32, entry: ItemEntry,
                           state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State} =
        match state {
            case NodeTag.WeaponMenu => checked_ecast(WeaponMenuScene.onWeaponConfirmed(entry, scene))
            case NodeTag.ActionMenu => ActionMenuScene.onActionConfirmed(entry, scene)
            case _                  => scene
        }
    redef onItemCancelled(_menuPath: NodePath, state: NodeTag,
                           scene: Scene[NodeTag]):
                          Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                             GameLogger.GameLogger, EnemyTurn.Queue,
                                             TurnPhase.State, SelectedPlayer.State} =
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
                let scene = GameLifecycle.buildPlayingScene(catalog);
                // 初回 build 時の spawn を保存。ゲームオーバー時に同じ配置で復活させる
                InitialSpawns.State.put({
                    enemies = EnemyScene.snapshotSpawns(scene),
                    players = PlayerScene.snapshotSpawns(scene)
                });
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
                  // 全味方脱落でフルリビルド: マップ・敵・味方・アイテムを再ランダ生成。
                  // 起動時の `buildPlayingScene` と同じ手順 + InitialSpawns 更新。
                  def request(_scene, k) = {
                      GameLogger.gameOverLog("ゲームオーバー");
                      EnemyTurn.Queue.replace(Nil);
                      TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
                      SelectedPlayer.State.put(SelectedPlayer.cleared());
                      let rebuilt = GameLifecycle.buildPlayingScene(catalog);
                      InitialSpawns.State.put({
                          enemies = EnemyScene.snapshotSpawns(rebuilt),
                          players = PlayerScene.snapshotSpawns(rebuilt)
                      });
                      k(rebuilt)
                  }
              }
              with handler BoardQuery {
                  def board(k) = k(BoardSnapshot.fromScene(Ref.get(sceneRef)))
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

    /// メインループ。終了判定 → BoardQuery 窓口の更新 → 1 フレームぶんの処理 → 描画
    /// → 末尾再帰。フェーズに応じてフレームパイプラインを選び、その中で
    /// 「入力 → process → physicsProcess → Tween/Animation tick → signal dispatch →
    /// 共通エピローグ」を実行する。
    /// ゲームオーバー時のフルリビルドは `CustomEffects.GameOverRequest` handler が
    /// catalog をクロージャに閉じ込めて実行するため、ここで catalog を引き回す必要はない。
    def gameLoop(sceneRef: Ref[Scene[NodeTag], r],
                  scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
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
            let next = match phase {
                case TurnPhase.Phase.EnemyTurn      => tickEnemyTurnFrame(dt, scene)
                case TurnPhase.Phase.PlayerAutoMove => tickAutoMoveFrame(dt, scene)
                case _                               => tickInputFrame(dt, scene)
            };
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }

    /// 敵ターン中のフレーム: キューを 1 step 進めて Tween/Animation tick → engine の
    /// per-node `process` redef が各 Player/Enemy ノードで自分宛 signal を drain → エピローグ。
    def tickEnemyTurnFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery,
                               Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                               CustomEffects.GameOverRequest, Pacing.State} =
        scene
            |> EnemyTurnDriverScene.stepOnce
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> GameEngine.process(delta = dt, paused = false)  // per-Scene drainSignals
            |> commonEpilogue(dt)

    /// PlayerAutoMove 中のフレーム: 入力 (X/Esc キャンセル用) → AutoMove.step →
    /// Tween/Animation tick → engine の per-node process が signal drain → エピローグ。
    def tickAutoMoveFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State,
                               CustomEffects.GameOverRequest,
                               Pacing.State} =
        scene
            |> GameEngine.handleInput
            |> AutoMove.step
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> GameEngine.process(delta = dt, paused = false)  // per-Scene drainSignals
            |> commonEpilogue(dt)

    /// 通常入力フェーズ (PlayerCursor / PlayerMoving / WeaponSelect / PlayerAttack) の
    /// フレーム: 入力 → メニューイベント → 物理 → Tween/Animation → engine の per-node
    /// process が signal drain + UI refresh → PlayerAttackHold tick → メニュー visibility →
    /// エピローグ。
    def tickInputFrame(dt: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, GameEngine.Audio,
                               BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                               GameLogger.GameLogger,
                               EnemyTurn.Queue, TurnPhase.State,
                               SelectedPlayer.State,
                               CustomEffects.GameOverRequest,
                               Pacing.State} =
        scene
            |> GameEngine.handleInput
            |> GameEngine.handleMenus
            |> GameEngine.physicsProcess(delta = dt, paused = false,
                                          gravity = Vec2.zero())
            |> Tween.tickAll(dt)
            |> AnimationPlayer.tickAll(dt)
            |> GameEngine.process(delta = dt, paused = false)  // per-Scene drainSignals + UI refresh + Menu visibility
            |> EnemyTurnDriverScene.tickPlayerAttackHold
            |> commonEpilogue(dt)

    /// 全フェーズに共通する描画準備の尾部。Camera/DamagePopup/HPBar/Item/UnitInfoPanel/Log の
    /// 毎フレーム更新は各 Scene の `process` redef に分散済み (Game.flix 上の
    /// `Node[NodeTag] instance` の `process` match から dispatch される)。
    /// ここに残るのは Pacing の薄いカウンタ tick のみ (Scene に紐づかないため)。
    def commonEpilogue(dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ Pacing.State =
        Pacing.State.tick(dt);
        scene

}
