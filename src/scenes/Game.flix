/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case EnemyRange(EnemyRangeScene.Data)
    case Cursor(CursorScene.Data)
    case Log(LogScene.Data)
    case NoTag
}

// physicsProcess はフェーズに応じて Player / Cursor のいずれか 1 体だけを
// dispatch する。`PlayerCursor` 中はカーソルだけ・`PlayerMoving` 中は味方だけが
// 方向キーを polling する。それ以外のフェーズ（`EnemyTurn`）では
// gameLoop 側が physicsProcess パイプライン自体を呼ばないので no-op で良い。
instance Node[NodeTag] {
    type Aef = {GameEngine.Game, BoardQuery, Tween.Scheduler,
                 GameLogger.GameLogger, TurnPhase.State}
    redef physicsProcess(delta: Float64,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {GameEngine.Game, BoardQuery, Tween.Scheduler,
                             GameLogger.GameLogger, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        match (node, phase) {
            case (EngineNode.Marker2DWithState(_, NodeTag.Player(_)),
                  TurnPhase.Phase.PlayerMoving) =>
                PlayerScene.physicsProcess(delta, node, path, scene)
            case (EngineNode.Marker2DWithState(_, NodeTag.Cursor(_)),
                  TurnPhase.Phase.PlayerCursor) =>
                CursorScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
}

// 決定キー（Z / Space / Enter）とキャンセルキー（X）はフェーズで意味を変える:
//   PlayerCursor:
//     Z = カーソル位置の駒を確定
//         - 味方マスなら PlayerMoving に遷移（カーソル非表示・味方の WASD 移動開始）
//         - 敵マス / 空マスは無視（敵情報は hover で既に表示済み）
//     X = 何もしない（キャンセル元の状態が無いため）
//   PlayerMoving:
//     Z = ターンエンド（敵ターンキュー populate + 敵ターン宣言）
//     X = キャンセル → PlayerCursor に戻し、カーソルを味方位置にスナップ
//   EnemyTurn: 入力は無視（gameLoop 側で handleInput を呼ばないので普通は到達しない）
// Tween 中（味方移動中）は Z/X を受け付けない。
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State}
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State} =
        let isConfirm = key == GameEngine.Key.Z
                        or key == GameEngine.Key.Space
                        or key == GameEngine.Key.Enter;
        let isCancel  = key == GameEngine.Key.X;
        let playerBusy = Tween.Scheduler.isActive(PlayerScene.playerPath());
        match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerCursor =>
                if (isConfirm) Game.handleConfirmInCursor(scene)
                else scene
            case TurnPhase.Phase.PlayerMoving =>
                if (isConfirm and not playerBusy) Game.handleEndPlayerTurn(scene)
                else if (isCancel and not playerBusy) Game.handleCancel(scene)
                else scene
            case TurnPhase.Phase.EnemyTurn => scene
        }
}

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さい 128×128（= 8×8 グリッド分）で切り出す。Camera2D 追従でビューが動く。
    /// この値はカメラのビューポートと投影行列の基準で、ウィンドウサイズに合わせて
    /// 引き伸ばし表示される（Godot の Stretch Mode = canvas_items 相当）
    pub def designWi(): Int32 = 128
    pub def designHi(): Int32 = 128

    // ────────────────────────────────────────────────────────
    // フェーズ遷移ハンドラ — 入力ハンドラから呼ばれる「フェーズ + Scene の同期更新」
    // ────────────────────────────────────────────────────────

    /// `PlayerCursor` 中に Z が押されたときの処理。カーソル位置が味方マスなら
    /// `PlayerMoving` に遷移、そうでなければ何もしない（敵 hover 表示は既に出ている）。
    pub def handleConfirmInCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State} =
        let cursorPos = CursorScene.getGridPos(scene);
        let playerPos = PlayerScene.getGridPos(scene);
        if (cursorPos#x == playerPos#x and cursorPos#y == playerPos#y) {
            TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
            scene
                |> EnemyRangeScene.clear   // 念のため（カーソルが味方マスなら無いはずだが）
                |> CursorScene.setVisible(false)
        }
        else scene

    /// `PlayerMoving` 中に Z が押されたときの処理。敵ターンキューを populate して
    /// `EnemyTurn` に遷移する。`finishEnemyTurn` で `PlayerCursor` に戻る。
    pub def handleEndPlayerTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State} =
        let steps = EnemyScene.getAll(scene)
            |> List.sortBy(e -> e#id)
            |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
        EnemyTurn.Queue.replace(steps);
        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
        GameLogger.GameLogger.enemyLog("敵のターン");
        scene

    /// `PlayerMoving` 中に X が押されたときの処理。`PlayerCursor` に戻し、
    /// カーソルを味方位置にスナップする（次の選択開始点を整える）。
    /// MoveRange は維持して「同じターン中はもう一度味方を選んで動かせる」状態を保つ。
    pub def handleCancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, TurnPhase.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    // ────────────────────────────────────────────────────────
    // 敵ターン進行 — gameLoop が毎フレーム 1 step ずつ呼ぶ
    // ────────────────────────────────────────────────────────

    /// 敵ターンキューの先頭 step を 1 つ進める。Tween がアクティブなら何もしない。
    /// gameLoop が毎フレーム呼ぶ。
    /// 動作:
    ///   1) キュー先頭が居る敵の Tween がアクティブ（前の step が再生中）なら待つ
    ///   2) 先頭 step を pop して `EnemyAI.decideAction` で 1 マス分の行動を決める
    ///   3) 行動を適用（Move なら Tween 開始 + remaining-1 で pushFront、Attack なら
    ///      ログのみ、Skip/Wait は無動作）
    ///   4) キューが空になったらターン終了処理（フェーズを PlayerCursor に戻す）
    pub def stepEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State} =
        match EnemyTurn.Queue.peekFront() {
            case None       => scene   // 敵ターンではない
            case Some(step) =>
                if (Tween.Scheduler.isActive(EnemyScene.enemyPath(step#id))) scene
                else
                    // 先頭 step を消費して 1 マス進める
                    let _ = EnemyTurn.Queue.popFront();
                    let next = applyOneStep(step, scene);
                    // キューが空 = 全敵の全 step が完了した = ターン終了
                    if (EnemyTurn.Queue.isEmpty()) finishEnemyTurn(next)
                    else next
        }

    /// step 1 つぶんの行動を適用する。Move なら Tween で 1 マス進めて remaining-1 を
    /// pushFront、Attack ならログ、Skip/Wait は無動作（remaining も捨てる）。
    def applyOneStep(step: EnemyTurn.Step, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み（将来の死亡時など）
            case Some(data) =>
                let board = buildBoard(scene);
                let (action, updated) = EnemyAI.decideAction(board, data);
                let withAlert = EnemyScene.mapEnemy(step#id,
                    d -> {alerted = updated#alerted | d}, scene);
                match action {
                    case EnemyAI.EnemyAction.Move(id, target) =>
                        let moved = EnemyScene.moveTo(id, target, board#map, withAlert);
                        // 残り step があれば次の 1 マス分を継続して pushFront
                        if (step#remaining > 1)
                            EnemyTurn.Queue.pushFront({id = id,
                                                        remaining = step#remaining - 1})
                        else ();
                        moved
                    case EnemyAI.EnemyAction.Attack(id) =>
                        GameLogger.GameLogger.enemyLog("敵${id}の攻撃");
                        withAlert
                    case EnemyAI.EnemyAction.Wait(_) => withAlert
                    case EnemyAI.EnemyAction.Skip(_) => withAlert
                }
        }

    /// 敵ターンの後始末: ターン番号繰り上げ + MoveRange 再構築 + カーソル復活 +
    /// 味方ターン宣言。フェーズを `PlayerCursor` に戻すことで次フレームから
    /// カーソル選択フローに復帰する。
    def finishEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, TurnPhase.State} =
        GameLogger.GameLogger.endTurn();
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        let next = scene
            |> MoveRangeScene.refresh
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer;
        GameLogger.GameLogger.playerLog("味方のターン");
        next

    /// 現在の scene から Board (MapSnapshot + 駒一覧) を組み立てる。
    /// BoardQuery handler と「敵ターン処理（onKeyPressed）」の双方が呼ぶ。
    /// 後者は 1 体動かすたびに最新の scene から組み直して、駒の更新を反映させる。
    pub def buildBoard(scene: Scene[NodeTag]): Board =
        let layer       = MapScene.getMapLayer(scene);
        let mapGlobal   = Scene.globalPositionAt(MapScene.mapPath(), scene);
        let placements  = MapScene.getPlacements(scene);
        let map: MapSnapshot = {
            tileSize     = TileMapLayer.tileSize(layer),
            usedRect     = TileMapLayer.getUsedRect(layer),
            isWall       = c -> TileMapLayer.isWall(c, layer),
            isFloor      = c -> TileMapLayer.isFloor(c, layer),
            mapToLocal   = c -> TileMapLayer.mapToLocal(c, layer),
            gridToWorld  = c -> Vec2.add(mapGlobal, TileMapLayer.mapToLocal(c, layer)),
            moduleOfCell = c -> MapScene.moduleOfCellIn(c, placements)
        };
        let player  = PlayerScene.getGridPos(scene);
        let enemies = EnemyScene.getAll(scene)
            |> List.map(e -> (Piece.Enemy(e#id), e#gridPos));
        {
            map    = map,
            pieces = (Piece.Player, player) :: enemies
        }

    /// 初期ウィンドウサイズ（OS ピクセル単位）。design とは独立して指定でき、
    /// design 側がウィンドウいっぱいに引き伸ばし描画される
    pub def windowWi(): Int32 = 832
    pub def windowHi(): Int32 = 624

    /// 起動時 / ホットリロード時にプレイ用シーンを組み立てる。
    /// 順序が意味を持つ（後段が前段の登録結果を参照する）。
    /// MapScene.add が `IO` を要求するため戻り値の Aef にも `IO` を含める。
    def buildPlayingScene(): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO} =
        Scene.empty()
            |> MapScene.add
            |> PlayerScene.add
            |> EnemyScene.add
            |> MoveRangeScene.add
            |> CursorScene.add
            |> CameraScene.add
            |> LogScene.add

    pub def start(): Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                              Chan, NonDet, IO, Fs.Glob, Fs.ModificationTime,
                              Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            run {
                let scene = buildPlayingScene();
                GameLogger.GameLogger.playerLog("T1 味方のターン");
                gameLoop(sceneRef, scene)
            } with Editor.withState(rc)
              with Tween.withScheduler(rc)   // tweensRef は内部に隠蔽
              with GameLogger.withLogger(rc) // entriesRef は内部に隠蔽
              with EnemyTurn.withQueue(rc)   // 敵ターンキュー（1 step / 1 frame 駆動）
              with TurnPhase.withState(rc)   // 味方ターン内のサブフェーズ + 敵ターン
              with handler BoardQuery {
                  def board(k) = k(buildBoard(Ref.get(sceneRef)))
              }
        }

    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind,
                         BoardQuery, Tween.Scheduler, GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         Math.Random, IO, r} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            // input/process/physics より前に置けば、handler はその後で常に
            // 「フレーム頭の scene」を読み返せる（タイル定義は不変のため十分）。
            Ref.put(scene, sceneRef);
            let dt = GameEngine.Game.getDeltaTime();
            let afterEditor = Editor.handleInput(scene);
            // 敵ターン中は入力をブロックして 1 step ずつ進める。
            // それ以外（PlayerCursor / PlayerMoving）は通常の handleInput / physicsProcess。
            let inEnemyPhase = TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn;
            let updated = if (Editor.isOn()) afterEditor
                          else if (inEnemyPhase)
                              afterEditor
                                  |> stepEnemyTurn
                                  |> Tween.tickAll(dt)
                                  |> CameraScene.update
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll
                          else
                              afterEditor
                                  |> GameEngine.handleInput
                                  |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                                gravity = Vec2.zero())
                                  |> Tween.tickAll(dt)   // engine プラミング 1 行
                                  |> CameraScene.update
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll;
            // scene.json が変わったらシーンを丸ごと組み直す（プレイ中状態はリセット）
            let next = if (Editor.pollReload()) {
                           // ホットリロード時は敵ターンキューと TurnPhase もリセット
                           EnemyTurn.Queue.replace(Nil);
                           TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
                           buildPlayingScene()
                       }
                       else updated;
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }
}
