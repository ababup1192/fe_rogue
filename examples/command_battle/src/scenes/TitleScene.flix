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

    /// フェーズ遷移時に呼ばれる Push モデルの visibility 適用関数。
    /// `GamePhase.Title` のときだけ Title CanvasLayer を visible にする。
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == GamePhase.Title;
        Scene.mapEngineNode("title" :: Nil, node -> match node {
            case EngineNode.CanvasLayerWithState(cl, tag) =>
                EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), tag)
            case other => other
        }, scene)
}
