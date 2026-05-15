/// コマンドメニューシーン（たたかう / じゅもん / どうぐ）。
/// 全シーン常駐設計。`process` で GamePhase を読み:
///   - ルート Panel: Title 以外で visible=true
///   - ItemList: GamePhase.CommandSelect のときだけ focused=true、それ以外は false
mod CommandScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/CommandScene.scene.json"

    pub def name(): String = "command_panel"
    pub def menuName(): String = "menu"
    pub def menuPath(): NodePath = name() :: menuName() :: Nil

    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                   => Ok(NodeTag.NoTag)
            case Some("NoTag")          => Ok(NodeTag.NoTag)
            case Some("CommandPanel")   => Ok(NodeTag.CommandPanel)
            case Some("CommandMenu")    => Ok(NodeTag.CommandMenu)
            case Some(unknown)          => Err(JsonError(Root, Set#{"CommandScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFont(sceneJsonPath(), fontAtlas, tagParser, scene)

    /// ルート Panel に対する process。Title 以外で visible=true。
    pub def processPanel(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.PanelWithState(panel, NodeTag.CommandPanel) =>
                let visible = GamePhaseState.get() != GamePhase.Title;
                (EngineNode.PanelWithState(CanvasItem.setVisible(visible, panel), NodeTag.CommandPanel), scene)
            case _ => (node, scene)
        }

    /// ItemList (CommandMenu) に対する process。`GamePhase.CommandSelect` のとき focused=true、
    /// それ以外で focused=false。ItemList.setFocused は false→true 切替時に prev*Down を全 true
    /// に初期化するので、 直前フェーズで押されていたキー（Title→Enter 等）は自動的に消費される。
    pub def processMenu(_delta: Duration.Duration, node: EngineNode[NodeTag],
                        _path: NodePath,
                        scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.ItemListWithState(list, NodeTag.CommandMenu) =>
                let focused = GamePhaseState.get() == GamePhase.CommandSelect;
                (EngineNode.ItemListWithState(ItemList.setFocused(focused, list), NodeTag.CommandMenu), scene)
            case _ => (node, scene)
        }

    /// コマンド項目が確定された (Enter) ときの処理。 Game.flix の MenuHandler から呼ばれる。
    /// PR3 範囲: たたかうのみ実装。 じゅもん/どうぐは PR4 で `GamePhase.SpellSelect` /
    /// `GamePhase.ItemSelect` 遷移を追加する。
    pub def onCommandConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {GamePhaseState, Math.Random} =
        match entry#text {
            case "たたかう" =>
                let afterAttack = BattleScene.applyPlayerAttack(scene);
                GamePhaseState.put(GamePhase.Resolving);
                afterAttack
            case _ =>
                // じゅもん / どうぐは PR4 で実装。 PR3 では何もしない。
                scene
        }
}
