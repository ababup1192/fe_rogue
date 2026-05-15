/// バトル背景シーン。黒背景 + 敵テキスト + 勇者ステータス。
/// 全シーン常駐設計なので、表示・非表示は `process` で GamePhase を読んで決める。
/// `GamePhase.Title` 以外で visible=true。
mod BattleScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/BattleScene.scene.json"

    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("BattleLayer")   => Ok(NodeTag.BattleLayer)
            case Some("EnemyLabel")    => Ok(NodeTag.EnemyLabel)
            case Some("StatusLabel")   => Ok(NodeTag.StatusLabel)
            case Some(unknown)         => Err(JsonError(Root, Set#{"BattleScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, tagParser, scene)

    /// バトル画面のルート CanvasLayer に対する process。Title 以外で visible=true。
    pub def process(_delta: Duration.Duration, node: EngineNode[NodeTag],
                    _path: NodePath,
                    scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.CanvasLayerWithState(cl, NodeTag.BattleLayer) =>
                let visible = GamePhaseState.get() != GamePhase.Title;
                (EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), NodeTag.BattleLayer), scene)
            case _ => (node, scene)
        }
}
