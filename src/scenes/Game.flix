/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case Log(LogScene.Data)
    case NoTag
}

// physicsProcess は方向キーの押しっぱなし polling を Player に dispatch する。
// 補間自体は engine の Tween モジュールが担うので、ここではゲーム固有のロジック
// （held key → moveTo の連鎖）だけを Scene 側に委譲する。
instance Node[NodeTag] {
    type Aef = {GameEngine.Game, BoardQuery, Tween.Scheduler}
    redef physicsProcess(delta: Float64,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {GameEngine.Game, BoardQuery, Tween.Scheduler} =
        match node {
            case EngineNode.Marker2DWithState(_, NodeTag.Player(_)) =>
                PlayerScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
}

// 方向移動は PlayerScene.physicsProcess が key state を polling して処理する
// （onKeyPressed は押下エッジ専用で押しっぱなしを検知できないため）。
// 決定キー (Z / Space / Enter) のエッジで「ターンエンド」扱い ＝ 敵ターンキューに
// 全敵の step を populate するだけ。実際の敵移動処理は gameLoop が毎フレーム
// 1 step ずつ進めるので、敵は 1 体ずつ・1 マスずつ動くように見える。
// Tween 中（味方移動中）は受け付けない。敵ターン中（キュー非空）は gameLoop 側で
// 入力ハンドリング自体をスキップするので、ここで再チェックする必要はない。
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue}
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                                          EnemyTurn.Queue} =
        let isConfirm = key == GameEngine.Key.Z
                        or key == GameEngine.Key.Space
                        or key == GameEngine.Key.Enter;
        if (isConfirm and not Tween.Scheduler.isActive(PlayerScene.playerPath())) {
            // キューに全敵分の step を積む。各敵の初期 remaining = moveTiles。
            let steps = EnemyScene.getAll(scene)
                |> List.sortBy(e -> e#id)
                |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
            EnemyTurn.Queue.replace(steps);
            GameLogger.GameLogger.enemyLog("敵のターン");
            scene
        }
        else scene
}

mod Game {

    /// デザイン解像度。プレイヤーをズームインで見せるため、マップ全体（208×208）より
    /// 小さい 128×128（= 8×8 グリッド分）で切り出す。Camera2D 追従でビューが動く。
    /// この値はカメラのビューポートと投影行列の基準で、ウィンドウサイズに合わせて
    /// 引き伸ばし表示される（Godot の Stretch Mode = canvas_items 相当）
    pub def designWi(): Int32 = 128
    pub def designHi(): Int32 = 128

    /// 敵ターンキューの先頭 step を 1 つ進める。Tween がアクティブなら何もしない。
    /// gameLoop が毎フレーム呼ぶ。
    /// 動作:
    ///   1) キュー先頭が居る敵の Tween がアクティブ（前の step が再生中）なら待つ
    ///   2) 先頭 step を pop して `EnemyAI.decideAction` で 1 マス分の行動を決める
    ///   3) 行動を適用（Move なら Tween 開始 + remaining-1 で pushFront、Attack なら
    ///      ログのみ、Skip/Wait は無動作）
    ///   4) キューが空になったらターン終了処理（MoveRange 再構築 + 味方ターン宣言）
    pub def stepEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue} =
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

    /// 敵ターンの後始末: ターン番号繰り上げ + MoveRange 再構築 + 味方ターン宣言。
    def finishEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameLogger.GameLogger} =
        GameLogger.GameLogger.endTurn();
        let next = MoveRangeScene.refresh(scene);
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

    pub def start(): Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                              Chan, NonDet, IO, Fs.Glob, Fs.ModificationTime,
                              Math.Random} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            run {
                let scene = Scene.empty()
                    |> MapScene.add
                    |> PlayerScene.add
                    |> EnemyScene.add
                    |> MoveRangeScene.add
                    |> LogScene.add;
                GameLogger.GameLogger.playerLog("T1 味方のターン");
                gameLoop(sceneRef, scene)
            } with Editor.withState(rc)
              with Tween.withScheduler(rc)   // tweensRef は内部に隠蔽
              with GameLogger.withLogger(rc) // entriesRef は内部に隠蔽
              with EnemyTurn.withQueue(rc)   // 敵ターンキュー（1 step / 1 frame 駆動）
              with handler BoardQuery {
                  def board(k) = k(buildBoard(Ref.get(sceneRef)))
              }
        }

    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind,
                         BoardQuery, Tween.Scheduler, GameLogger.GameLogger,
                         EnemyTurn.Queue,
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
            // 敵ターン（キュー非空）中は入力をブロックして 1 step ずつ進める。
            // プレイヤーターン中は通常の handleInput / physicsProcess を回す。
            let inEnemyPhase = not EnemyTurn.Queue.isEmpty();
            let updated = if (Editor.isOn()) afterEditor
                          else if (inEnemyPhase)
                              afterEditor
                                  |> stepEnemyTurn
                                  |> Tween.tickAll(dt)
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll
                          else
                              afterEditor
                                  |> GameEngine.handleInput
                                  |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                                gravity = Vec2.zero())
                                  |> Tween.tickAll(dt)   // engine プラミング 1 行
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll;
            // scene.json が変わったらシーンを丸ごと組み直す（プレイ中状態はリセット）
            let next = if (Editor.pollReload()) {
                           // ホットリロード時は敵ターンキューも空にしてプレイヤーターンに戻す
                           EnemyTurn.Queue.replace(Nil);
                           Scene.empty() |> MapScene.add |> PlayerScene.add
                                         |> EnemyScene.add
                                         |> MoveRangeScene.add |> LogScene.add
                       }
                       else updated;
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }
}
