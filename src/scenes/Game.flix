/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
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
// 将来エッジ専用入力（決定ボタン等）が必要になればここに redef onKeyPressed を足す。
instance InputEvent.InputHandler[NodeTag] {
    type Aef = {}
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

    pub def start(): Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                              Chan, NonDet, IO, Fs.Glob, Fs.ModificationTime} =
        region rc {
            // BoardQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            run {
                let scene = Scene.empty()
                    |> MapScene.add
                    |> PlayerScene.add;
                gameLoop(sceneRef, scene)
            } with Editor.withState(rc)
              with Tween.withScheduler(rc)   // tweensRef は内部に隠蔽
              with handler BoardQuery {
                  def board(k) =
                      let curScene = Ref.get(sceneRef);
                      let layer = MapScene.getMapLayer(curScene);
                      let mapGlobal = Scene.globalPositionAt(MapScene.mapPath(), curScene);
                      let map: MapSnapshot = {
                          tileSize    = TileMapLayer.tileSize(layer),
                          usedRect    = TileMapLayer.getUsedRect(layer),
                          isWall      = coords -> TileMapLayer.isWall(coords, layer),
                          isFloor     = coords -> TileMapLayer.isFloor(coords, layer),
                          mapToLocal  = coords -> TileMapLayer.mapToLocal(coords, layer),
                          gridToWorld = coords ->
                              Vec2.add(mapGlobal, TileMapLayer.mapToLocal(coords, layer))
                      };
                      let player = PlayerScene.getGridPos(curScene);
                      k({
                          map    = map,
                          pieces = (Piece.Player, player) :: Nil
                      })
              }
        }

    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind,
                         BoardQuery, Tween.Scheduler, r} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            // BoardQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            // input/process/physics より前に置けば、handler はその後で常に
            // 「フレーム頭の scene」を読み返せる（タイル定義は不変のため十分）。
            Ref.put(scene, sceneRef);
            let dt = GameEngine.Game.getDeltaTime();
            let afterEditor = Editor.handleInput(scene);
            let updated = if (Editor.isOn()) afterEditor
                          else afterEditor
                              |> GameEngine.handleInput
                              |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                            gravity = Vec2.zero())
                              |> Tween.tickAll(dt);   // engine プラミング 1 行
            GameEngine.render(updated);
            gameLoop(sceneRef, updated)
        }
}
