/// シーンノードに紐づくゲーム状態タグ。各 Scene 固有の Data 型を内部に持つ。
pub enum NodeTag {
    case Player(PlayerScene.Data)
    case NoTag
}

instance Node[NodeTag] {
    type Aef = {}
    redef physicsProcess(delta: Float64,
                          node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.Body2DWithState(_, NodeTag.Player(_)) =>
                PlayerScene.physicsProcess(delta, node, path, scene)
            case _ => (node, scene)
        }
}

instance InputEvent.InputHandler[NodeTag] {
    type Aef = MapQuery
    redef onKeyPressed(key: GameEngine.Key,
                        scene: Scene[NodeTag]): Scene[NodeTag] \ MapQuery =
        let dir: Option[Vec2.Vec2i] =
            if      (key == GameEngine.Key.W or key == GameEngine.Key.Up)    Some(Vec2.upI())
            else if (key == GameEngine.Key.S or key == GameEngine.Key.Down)  Some(Vec2.downI())
            else if (key == GameEngine.Key.A or key == GameEngine.Key.Left)  Some(Vec2.leftI())
            else if (key == GameEngine.Key.D or key == GameEngine.Key.Right) Some(Vec2.rightI())
            else None;
        match dir {
            case Some(d) => PlayerScene.requestMove(d, scene)
            case None    => scene
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

    pub def start(): Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                              Chan, NonDet, IO, Fs.Glob, Fs.ModificationTime} =
        region rc {
            // MapQuery handler が現在のシーンを読むための窓口（毎フレーム gameLoop が更新）
            let sceneRef = Ref.fresh(rc, Scene.empty());
            run {
                let scene = Scene.empty()
                    |> MapScene.add
                    |> PlayerScene.add;
                gameLoop(sceneRef, scene)
            } with Editor.withState(rc)
              with handler MapQuery {
                  def tileSize(k) =
                      k(TileMapLayer.tileSize(MapScene.getMapLayer(Ref.get(sceneRef))))
                  def getUsedRect(k) =
                      k(TileMapLayer.getUsedRect(MapScene.getMapLayer(Ref.get(sceneRef))))
                  def isWall(coords, k) =
                      k(TileMapLayer.isWall(coords, MapScene.getMapLayer(Ref.get(sceneRef))))
                  def isFloor(coords, k) =
                      k(TileMapLayer.isFloor(coords, MapScene.getMapLayer(Ref.get(sceneRef))))
                  def mapToLocal(coords, k) =
                      k(TileMapLayer.mapToLocal(coords, MapScene.getMapLayer(Ref.get(sceneRef))))
              }
        }

    def gameLoop(sceneRef: Ref[Scene[NodeTag], r], scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind, MapQuery, r} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            // MapQuery handler が読む窓口を毎フレーム最新の scene に更新する。
            // input/process/physics より前に置けば、handler はその後で常に
            // 「フレーム頭の scene」を読み返せる（タイル定義は不変のため十分）。
            Ref.put(scene, sceneRef);
            let dt = GameEngine.Game.getDeltaTime();
            let afterEditor = Editor.handleInput(scene);
            let updated = if (Editor.isOn()) afterEditor
                          else afterEditor
                              |> GameEngine.handleInput
                              |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                            gravity = Vec2.zero());
            GameEngine.render(updated);
            gameLoop(sceneRef, updated)
        }
}
