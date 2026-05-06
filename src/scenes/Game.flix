/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case Enemy(EnemyScene.Data)
    case Map(MapScene.Data)
    case MoveRange(MoveRangeScene.Data)
    case EnemyRange(EnemyRangeScene.Data)
    case PlayerAttackRange(PlayerAttackRangeScene.Data)
    case Cursor(CursorScene.Data)
    case Log(LogScene.Data)
    case NoTag
}

// physicsProcess はフェーズに応じて Player / Cursor のいずれか 1 体だけを
// dispatch する。`PlayerCursor` / `PlayerAttack` 中はカーソルだけ。
// `PlayerMoving` 中は **選択中の味方 1 体だけ** が方向キーを polling する。
// それ以外のフェーズ（`EnemyTurn`）では gameLoop 側が physicsProcess パイプライン
// 自体を呼ばないので no-op で良い。
instance Node[NodeTag] {
    type Aef = {GameEngine.Game, BoardQuery, Tween.Scheduler,
                 GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State}
    redef physicsProcess(delta: Float64,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {GameEngine.Game, BoardQuery, Tween.Scheduler,
                             GameLogger.GameLogger, TurnPhase.State,
                             SelectedPlayer.State} =
        let phase = TurnPhase.State.get();
        match (node, phase) {
            case (EngineNode.Marker2DWithState(_, NodeTag.Player(data)),
                  TurnPhase.Phase.PlayerMoving) =>
                // 選択中プレイヤーだけが移動を受け付ける
                if (SelectedPlayer.State.get() == Some(data#id))
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

// 決定キー（Z / Space / Enter）とキャンセルキー（X）はフェーズで意味を変える:
//   PlayerCursor:
//     Z = カーソル位置の **アクティブな** 味方を選択
//         - waited な味方マス・敵マス・空マスは無視
//         - アクティブな味方なら SelectedPlayer をセット → PlayerMoving に遷移
//     X = 何もしない（キャンセル元の状態が無いため）
//   PlayerMoving:
//     Z = PlayerAttack に遷移（移動有無を問わず）
//     X = キャンセル → PlayerCursor に戻る（waited にはしない・選択もクリア）
//   PlayerAttack:
//     Z = カーソルが赤マス上の敵に乗っていればダメージ
//         → 選択中味方を waited にして次セレクトへ（全員 waited なら敵ターン）
//         空マスでは何もしない（攻撃成立せず行動も終わらない）
//     X = 攻撃スキップ
//         → 選択中味方を waited にして次セレクトへ（全員 waited なら敵ターン）
//   EnemyTurn: 入力は無視
// Tween 中（選択中味方の移動中）は Z/X を受け付けない。
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue,
                 TurnPhase.State, SelectedPlayer.State}
    redef onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                                          EnemyTurn.Queue, TurnPhase.State,
                                          SelectedPlayer.State} =
        let isConfirm = key == GameEngine.Key.Z
                        or key == GameEngine.Key.Space
                        or key == GameEngine.Key.Enter;
        let isCancel  = key == GameEngine.Key.X;
        // 選択中プレイヤーが Tween 中なら playerBusy = true
        let playerBusy = match SelectedPlayer.State.get() {
            case Some(id) => Tween.Scheduler.isActive(PlayerScene.playerPath(id))
            case None     => false
        };
        match TurnPhase.State.get() {
            case TurnPhase.Phase.PlayerCursor =>
                if (isConfirm) Game.handleConfirmInCursor(scene)
                else scene
            case TurnPhase.Phase.PlayerMoving =>
                if (isConfirm and not playerBusy) Game.handleEnterAttackPhase(scene)
                else if (isCancel and not playerBusy) Game.handleCancel(scene)
                else scene
            case TurnPhase.Phase.PlayerAttack =>
                if (isConfirm) Game.handleConfirmInAttack(scene)
                else if (isCancel) Game.handleCancelAttack(scene)
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

    /// `PlayerCursor` 中に Z が押されたときの処理。
    /// カーソル位置にアクティブな（waited = false）味方が居れば、その駒を選択して
    /// `PlayerMoving` に遷移する。waited 上・敵上・空マスでは何もしない。
    pub def handleConfirmInCursor(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        let cursorPos = CursorScene.getGridPos(scene);
        match PlayerScene.findActiveIdAt(cursorPos, scene) {
            case None     => scene
            case Some(id) =>
                SelectedPlayer.State.put(Some(id));
                TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
                scene
                    |> EnemyRangeScene.clear
                    |> MoveRangeScene.refresh   // 選択駒の青マスを構築
                    |> CursorScene.setVisible(false)
        }

    /// `PlayerMoving` 中に Z が押されたときの処理。攻撃フェーズに遷移する。
    /// 選択は維持。青マスを消して赤マスを出し、カーソルを選択中駒の位置にスナップする。
    pub def handleEnterAttackPhase(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, TurnPhase.State,
                              SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAttack);
        scene
            |> MoveRangeScene.clear
            |> PlayerAttackRangeScene.show
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// `PlayerAttack` 中に Z が押されたときの処理。
    /// カーソル位置に「生きている」敵が居ればダメージを適用、選択中駒を waited にして
    /// 次セレクトへ（全員 waited なら敵ターンへ）。空マスは何もしない（行動も終わらない）。
    pub def handleConfirmInAttack(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        let cursor = CursorScene.getGridPos(scene);
        match EnemyScene.findIdAt(cursor, scene) {
            case None     => scene
            case Some(id) =>
                applyPlayerAttack(id, scene)
                    |> commitWaitedAndAdvance
        }

    /// `PlayerAttack` 中に X が押されたときの処理。攻撃をスキップしてその駒を waited に。
    /// 全員 waited なら敵ターン、まだ残っていれば PlayerCursor に戻る。
    pub def handleCancelAttack(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        commitWaitedAndAdvance(scene)

    /// PlayerAttack を抜けるときの共通処理:
    ///   1) 選択中駒を waited に（灰色 modulate）
    ///   2) 選択クリア
    ///   3) 残ったアクティブが居れば PlayerCursor に戻り、次セレクト準備
    ///      居なければ goToEnemyTurn で敵ターン開始
    def commitWaitedAndAdvance(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              SelectedPlayer.State} =
        let withWaited = match SelectedPlayer.State.get() {
            case Some(id) => PlayerScene.setWaited(id, scene)
            case None     => scene   // 防御的（選択なしで Attack に入ることは想定外）
        };
        SelectedPlayer.State.put(None);
        if (PlayerScene.anyActive(withWaited)) {
            TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
            withWaited
                |> PlayerAttackRangeScene.clear
                |> CursorScene.setVisible(true)
                |> CursorScene.snapToPlayer
        }
        else goToEnemyTurn(withWaited)

    /// 敵 1 体に固定 1 ダメージを与える。HP が 0 以下になったら死亡演出を開始し、
    /// それ以外は HP を更新するだけ。両ケースともログに「ダメージ 残りHP」を残す。
    def applyPlayerAttack(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger} =
        match EnemyScene.get(id, scene) {
            case None       => scene   // 既に居ない（dying や削除済み）— 防御的 no-op
            case Some(data) =>
                let newHp = data#hp - 1;
                GameLogger.GameLogger.playerLog("敵${id}にダメージ 残りHP${newHp}");
                if (newHp <= 0) EnemyScene.startDeathAnimation(id, scene)
                else EnemyScene.mapEnemy(id, d -> {hp = newHp | d}, scene)
        }

    /// 敵ターン開始の共通処理。死亡演出中の敵はキューに含めない。
    def goToEnemyTurn(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State} =
        let steps = EnemyScene.getAll(scene)
            |> List.filter(e -> Option.isEmpty(e#dying))
            |> List.sortBy(e -> e#id)
            |> List.map(e -> ({id = e#id, remaining = e#moveTiles}: EnemyTurn.Step));
        EnemyTurn.Queue.replace(steps);
        TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
        GameLogger.GameLogger.enemyLog("敵のターン");
        scene |> PlayerAttackRangeScene.clear

    /// `PlayerMoving` 中に X が押されたときの処理。`PlayerCursor` に戻り、選択を解除する。
    /// **waited にはしない**（同じ駒を再度選び直して動かしたり別の駒を選べる）。
    pub def handleCancel(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, TurnPhase.State,
                              SelectedPlayer.State} =
        SelectedPlayer.State.put(None);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
            |> MoveRangeScene.clear   // 選択解除につき青マスを消す
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
                TurnPhase.State, InitialEnemies.State, InitialPlayers.State,
                SelectedPlayer.State} =
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
    /// pushFront、Attack なら指定 target プレイヤーの HP を 1 減らしてログ、Skip/Wait は
    /// 無動作（remaining も捨てる）。
    /// プレイヤー HP が 0 になった場合は `handlePlayerDeath` で同マップ初期状態にリセットする。
    def applyOneStep(step: EnemyTurn.Step, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, EnemyTurn.Queue,
                TurnPhase.State, InitialEnemies.State, InitialPlayers.State,
                SelectedPlayer.State} =
        match EnemyScene.get(step#id, scene) {
            case None       => scene   // 既に除外済み（死亡演出完了など）
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
                    case EnemyAI.EnemyAction.Attack(enemyId, targetId) =>
                        match PlayerScene.get(targetId, withAlert) {
                            case None    => withAlert
                            case Some(p) =>
                                let newHp = p#hp - 1;
                                GameLogger.GameLogger.enemyLog(
                                    "敵${enemyId}が味方${targetId}を攻撃 残りHP${newHp}");
                                let damaged = PlayerScene.mapPlayer(targetId,
                                    d -> {hp = newHp | d}, withAlert);
                                if (newHp <= 0) handlePlayerDeath(damaged) else damaged
                        }
                    case EnemyAI.EnemyAction.Wait(_) => withAlert
                    case EnemyAI.EnemyAction.Skip(_) => withAlert
                }
        }

    /// いずれかのプレイヤー HP が 0 になったときの処理。ログに濃赤の「ゲームオーバー」を残し、
    /// 同マップで初期状態（プレイヤー全員 HP=10・waited=false・初期位置、敵も初期 spawn）に戻す。
    /// 敵ターンキュー・選択もクリアして、次フレームから `PlayerCursor` で操作再開できるように。
    /// マップやログは保持される（GameLogger / Map のノードは scene を再構築しない）。
    def handlePlayerDeath(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State,
                              InitialEnemies.State, InitialPlayers.State,
                              SelectedPlayer.State} =
        GameLogger.GameLogger.gameOverLog("ゲームオーバー");
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        SelectedPlayer.State.put(None);
        scene
            |> PlayerScene.respawnFromInitial(InitialPlayers.State.get())
            |> EnemyScene.respawnFromInitial(InitialEnemies.State.get())
            |> MoveRangeScene.clear
            |> PlayerAttackRangeScene.clear
            |> EnemyRangeScene.clear
            |> CursorScene.setVisible(true)
            |> CursorScene.snapToPlayer

    /// 敵ターンの後始末: ターン番号繰り上げ + 全プレイヤーを `waited = false` にリセット +
    /// カーソル復活 + 味方ターン宣言。
    def finishEnemyTurn(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, GameLogger.GameLogger, TurnPhase.State,
                SelectedPlayer.State} =
        GameLogger.GameLogger.endTurn();
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        let next = scene
            |> PlayerScene.clearAllWaited        // 全員アクティブに戻す
            |> MoveRangeScene.clear              // 未選択につき青マスは無し
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
        let players = PlayerScene.getAll(scene)
            |> List.map(d -> (Piece.Player(d#id), d#gridPos));
        let enemies = EnemyScene.getAll(scene)
            |> List.map(e -> (Piece.Enemy(e#id), e#gridPos));
        {
            map    = map,
            pieces = List.append(players, enemies)
        }

    /// 初期ウィンドウサイズ（OS ピクセル単位）。design とは独立して指定でき、
    /// design 側がウィンドウいっぱいに引き伸ばし描画される
    pub def windowWi(): Int32 = 832
    pub def windowHi(): Int32 = 624

    /// 起動時 / ホットリロード時にプレイ用シーンを組み立てる。
    /// 順序が意味を持つ（後段が前段の登録結果を参照する）。
    /// MapScene.add が `IO` を要求するため戻り値の Aef にも `IO` を含める。
    def buildPlayingScene(): Scene[NodeTag]
            \ {GameEngine.Game, Fs.FileRead, Math.Random, IO,
                SelectedPlayer.State} =
        Scene.empty()
            |> MapScene.add
            |> PlayerScene.add
            |> EnemyScene.add
            |> MoveRangeScene.add       // SelectedPlayer 未設定なら no-op
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
                // 初回 build 時の spawn を保存。ゲームオーバー時に同じ配置で復活させる
                InitialEnemies.State.put(EnemyScene.snapshotSpawns(scene));
                InitialPlayers.State.put(PlayerScene.snapshotSpawns(scene));
                GameLogger.GameLogger.playerLog("T1 味方のターン");
                gameLoop(sceneRef, scene)
            } with Editor.withState(rc)
              with Tween.withScheduler(rc)        // tween 一覧は内部に隠蔽
              with GameLogger.withLogger(rc)      // ログエントリは内部に隠蔽
              with EnemyTurn.withQueue(rc)        // 敵ターンキュー（1 step / 1 frame 駆動）
              with TurnPhase.withState(rc)        // 味方ターン内のサブフェーズ + 敵ターン
              with SelectedPlayer.withState(rc)   // 操作中プレイヤー id の保持
              with InitialEnemies.withState(rc)   // ゲームオーバー時に同じ敵配置を復元
              with InitialPlayers.withState(rc)   // ゲームオーバー時に同じ味方配置を復元
              with handler BoardQuery {
                  def board(k) = k(buildBoard(Ref.get(sceneRef)))
              }
        }

    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind,
                         BoardQuery, Tween.Scheduler, GameLogger.GameLogger,
                         EnemyTurn.Queue, TurnPhase.State,
                         SelectedPlayer.State,
                         InitialEnemies.State, InitialPlayers.State,
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
            // それ以外（PlayerCursor / PlayerMoving / PlayerAttack）は通常の
            // handleInput / physicsProcess。死亡演出（tickDeaths）は Tween 後に挟むので、
            // フェーズに関係なく毎フレーム進む（敵ターン跨ぎでも点滅が継続する）。
            let inEnemyPhase = TurnPhase.State.get() == TurnPhase.Phase.EnemyTurn;
            let updated = if (Editor.isOn()) afterEditor
                          else if (inEnemyPhase)
                              afterEditor
                                  |> stepEnemyTurn
                                  |> Tween.tickAll(dt)
                                  |> EnemyScene.tickDeaths
                                  |> CameraScene.update
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll
                          else
                              afterEditor
                                  |> GameEngine.handleInput
                                  |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                                gravity = Vec2.zero())
                                  |> Tween.tickAll(dt)   // engine プラミング 1 行
                                  |> EnemyScene.tickDeaths
                                  |> CameraScene.update
                                  |> LogScene.flushFromEffect
                                  |> LogScene.tickScroll;
            // scene.json が変わったらシーンを丸ごと組み直す（プレイ中状態はリセット）
            let next = if (Editor.pollReload()) {
                           // ホットリロード時は敵ターンキュー / 各 State をリセット
                           EnemyTurn.Queue.replace(Nil);
                           TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
                           SelectedPlayer.State.put(None);
                           let rebuilt = buildPlayingScene();
                           // 再構築後の配置を初期 spawn として保存し直す
                           InitialEnemies.State.put(EnemyScene.snapshotSpawns(rebuilt));
                           InitialPlayers.State.put(PlayerScene.snapshotSpawns(rebuilt));
                           rebuilt
                       }
                       else updated;
            GameEngine.render(next);
            gameLoop(sceneRef, next)
        }
}
