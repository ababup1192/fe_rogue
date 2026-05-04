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
    type Aef = {}
    redef onKeyPressed(key: GameEngine.Key,
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        let dir =
            if      (key == GameEngine.Key.W or key == GameEngine.Key.Up)    Some((0, -1))
            else if (key == GameEngine.Key.S or key == GameEngine.Key.Down)  Some((0,  1))
            else if (key == GameEngine.Key.A or key == GameEngine.Key.Left)  Some((-1, 0))
            else if (key == GameEngine.Key.D or key == GameEngine.Key.Right) Some((1,  0))
            else None;
        match dir {
            case Some((dCol, dRow)) => PlayerScene.requestMove(dCol, dRow, scene)
            case None => scene
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
            run {
                let scene = Scene.empty()
                    |> MapScene.add
                    |> PlayerScene.add;
                gameLoop(scene)
            } with Editor.withState(rc)
        }

    def gameLoop(scene: Scene[NodeTag]):
                 Unit \ {GameEngine.Game, Fs.FileRead, Fs.FileWrite,
                         Editor.EditorState, EditHistory.Rewind} =
        if (GameEngine.Game.shouldClose() or
            GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
        else {
            let dt = GameEngine.Game.getDeltaTime();
            let afterEditor = Editor.handleInput(scene);
            let updated = if (Editor.isOn()) afterEditor
                          else afterEditor
                              |> GameEngine.handleInput
                              |> GameEngine.physicsProcess(delta = dt, paused = false,
                                                            gravity = Vec2.zero());
            GameEngine.render(updated);
            gameLoop(updated)
        }
}
