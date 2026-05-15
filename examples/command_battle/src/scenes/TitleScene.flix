/// タイトルシーン。黒背景に大きなタイトル文字と "[Enter] ですすむ" ヒント。
/// 全シーン常駐設計なので、自分の表示・非表示は `process` で GamePhase を読んで決める。
mod TitleScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/TitleScene.scene.json"

    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("TitleLayer")    => Ok(NodeTag.TitleLayer)
            case Some(unknown)         => Err(JsonError(Root, Set#{"TitleScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, tagParser, scene)

    /// Title 画面のルート CanvasLayer に対する process。`GamePhase.Title` のときだけ
    /// visible=true、それ以外は visible=false にする。
    pub def process(_delta: Duration.Duration, node: EngineNode[NodeTag],
                    _path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.CanvasLayerWithState(cl, NodeTag.TitleLayer) =>
                let visible = GamePhaseState.get() == GamePhase.Title;
                (EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), NodeTag.TitleLayer), scene)
            case _ => (node, scene)
        }
}
