/// コマンドメニューシーン（たたかう / じゅもん / どうぐ）。
/// 全シーン常駐設計。`process` で GamePhase を読み:
///   - ルート Panel: Title 以外で visible=true
///   - ItemList: GamePhase.CommandSelect のときだけ focused=true、それ以外は false
mod CommandScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = "src/scenes/CommandScene.scene.json"

    pub def name(): String = "command_panel"
    pub def menuName(): String = "menu"
    pub def panelPath(): NodePath = BattleScene.uiLayerPath() ::: name() :: Nil
    pub def menuPath(): NodePath = panelPath() ::: menuName() :: Nil

    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                   => Ok(NodeTag.NoTag)
            case Some("NoTag")          => Ok(NodeTag.NoTag)
            case Some("CommandPanel")   => Ok(NodeTag.CommandPanel)
            case Some("CommandMenu")    => Ok(NodeTag.CommandMenu)
            case Some(unknown)          => Err(JsonCompat.jsonError(Root, Set#{"CommandScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFontAt(BattleScene.uiLayerPath(), sceneJsonPath(),
                                        fontAtlas, tagParser, scene)

    /// フェーズ遷移時に呼ばれる Push モデルの visibility 適用関数。
    /// CommandPanel 自体の visible は親の battle CanvasLayer の visible 切替に任せる
    /// （親子伝播で Title 時には自動的に hidden になる）ので、 ここでは ItemList の
    /// focused だけを切り替える。 ItemList.setFocused は false→true 切替時に prev*Down
    /// を全 true 初期化するので、 直前フェーズで押されていたキーは自動的に消費される
    /// （Enter 連鎖防止）。
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let focused = phase == GamePhase.CommandSelect;
        Scene.mapEngineNode(menuPath(), node -> match node {
            case EngineNode.ItemListWithState(list, tag) =>
                EngineNode.ItemListWithState(ItemList.setFocused(focused, list), tag)
            case other => other
        }, scene)

    /// コマンド項目が確定された (Enter) ときの処理。 Game.flix の MenuHandler から呼ばれる。
    /// 「たたかう」 は BattleScene.beginAttack に委譲（敵が複数なら TargetSelect、 1 体なら
    /// 即攻撃）。 サブメニュー遷移はフェーズ put のみ。
    pub def onCommandConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                                Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        match entry#text {
            case "たたかう" => BattleScene.beginAttack(scene)
            case "じゅもん" =>
                GamePhaseState.put(GamePhase.SpellSelect); scene
            case "どうぐ" =>
                GamePhaseState.put(GamePhase.ItemSelect); scene
            case _ => scene
        }
}
