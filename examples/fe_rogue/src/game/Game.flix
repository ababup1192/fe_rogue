/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case EnemyRange(EnemyRangeScene.Data)
    case PlayerAttackRange(PlayerAttackRangeScene.Data)
    case Cursor(CursorScene.Data)
    case Flag(FlagScene.Data)
    case Log(LogScene.Data)
    case NoTag
}

// physicsProcess はフェーズに応じて Player / Cursor のいずれか 1 体だけを
// dispatch する。`PlayerCursor` / `PlayerAttack` 中はカーソルだけ。
// `PlayerMoving` 中は **選択中の味方 1 体だけ** が方向キーを polling する。
// それ以外のフェーズ（`EnemyTurn`）では gameLoop 側が physicsProcess パイプライン
// 自体を呼ばないので no-op で良い。
instance Node[NodeTag] {
    type Aef = {GameEngine.Game, BoardQuery,
                 Tween.Scheduler, AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State}
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
    type Aef = {BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                 GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State}
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {BoardQuery, Tween.Scheduler,
                                          AnimationPlayer.Scheduler,
                                          GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State,
                                          SelectedPlayer.State} =
        let isConfirm = key == GameEngine.Key.Z
                        or key == GameEngine.Key.Space
                        or key == GameEngine.Key.Enter;
        let isCancel  = key == GameEngine.Key.X;
        if (isConfirm) GameManager.handleInput(TurnRules.Input.Confirm, scene)
        else if (isCancel) GameManager.handleInput(TurnRules.Input.Cancel, scene)
        else scene
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
    /// `GameManager.buildPlayingScene` で組み立てて `gameLoop` に入る。
    /// **配線役** に徹するため、ここにゲームロジックは書かない。
    pub def start(): Unit \ {GameEngine.Game, GameEngine.Audio,
                              Fs.FileRead, IO, Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            // ユニットカタログをロード + schema 整合性検査（Z 戦略の安全網）。
            // 各段階で失敗内容を panic に出して原因を即可視化する。
            let catalog = UnitCatalog.load("resources/units.json");
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
            run {
                let scene = GameManager.buildPlayingScene(catalog);
                // 初回 build 時の spawn を保存。ゲームオーバー時に同じ配置で復活させる
                InitialSpawns.State.put({
                    enemies = EnemyScene.snapshotSpawns(scene),
                    players = PlayerScene.snapshotSpawns(scene)
                });
                // BGM はゲーム開始時に再生（looping = true で曲が終わってもループする）
                AudioStreamPlayer.play("bgm");
                GameLogger.playerLog("T1 味方のターン");
                gameLoop(sceneRef, scene)
            } with Tween.withScheduler(rc)        // tween 一覧は内部に隠蔽
              with AnimationPlayer.withScheduler(rc)  // 名前付きアニメ + イベントドレイン
              with Pacing.withState(rc)           // 演出の溜め (hold)
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with EnemyTurn.withQueue(rc)        // 敵ターンキュー（1 step / 1 frame 駆動）
              with TurnPhase.withState(rc)        // 味方ターン内のサブフェーズ + 敵ターン
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with InitialSpawns.withState(rc)    // ゲームオーバー時に同じ敵 / 味方配置を復元
              with handler BoardQuery {
                  def board(k) = k(GameManager.buildBoard(Ref.get(sceneRef)))
              }
        }

    /// メインループ。終了判定 → BoardQuery 窓口の更新 → 1 フレームぶんの処理 → 描画
    /// → 末尾再帰、という固定パイプラインだけを担う **配線役**。
    /// フレーム処理の実体は `GameManager.runFrame` に閉じている。
    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, GameEngine.Audio,
                         Fs.FileRead,
                         BoardQuery, Tween.Scheduler, AnimationPlayer.Scheduler,
                         GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State, InitialSpawns.State,
                         Pacing.State,
                         Math.Random, IO, r} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            // 各 handler はその後で常に「フレーム頭の scene」を読み返せる
            // （タイル定義は不変のため十分）。
            Ref.put(scene, sceneRef);
            let next = GameManager.runFrame(scene);
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }
}
