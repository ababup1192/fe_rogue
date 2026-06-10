/// じゅもんサブメニューシーン。 Panel + ItemList で構成、 `GamePhase.SpellSelect` のときだけ
/// visible + focused になる。 項目は `resources/spells.json` の `known` 一覧から動的に
/// 構築される。 各項目の `metadata` に spell_id を入れて、 確定時に MenuHandler が
/// `BattleScene.applySpell(spellId, scene)` を呼び出す。
mod SpellMenuScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = "src/scenes/SpellMenuScene.scene.json"
    def spellsJsonPath(): String = "resources/spells.json"

    pub def panelName(): String = "spell_panel"
    pub def menuName(): String = "menu"
    pub def panelPath(): NodePath = BattleScene.uiLayerPath() ::: panelName() :: Nil
    pub def menuPath(): NodePath = panelPath() ::: menuName() :: Nil

    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                 => Ok(NodeTag.NoTag)
            case Some("NoTag")        => Ok(NodeTag.NoTag)
            case Some("SpellPanel")   => Ok(NodeTag.SpellPanel)
            case Some("SpellMenu")    => Ok(NodeTag.SpellMenu)
            case Some(unknown)        => Err(JsonCompat.jsonError(Root, Set#{"SpellMenuScene tag (got: ${unknown})"}))
        }

    /// scene.json をロード + `resources/spells.json` から呪文項目を動的に構築 +
    /// ItemList.setItems で注入。 1 度だけ起動時に走る。
    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let loaded = SceneLoader.loadSceneWithFontAt(BattleScene.uiLayerPath(), sceneJsonPath(),
                                                     fontAtlas, tagParser, scene);
        let catalog = SpellCatalog.load(spellsJsonPath());
        let items = List.map(spell -> ({
            text     = spell#name,
            disabled = false,
            metadata = Some(spell#id)
        }: ItemEntry), SpellCatalog.knownSpells(catalog));
        Scene.mapEngineNode(menuPath(), node -> match node {
            case EngineNode.ItemListWithState(list, tag) =>
                EngineNode.ItemListWithState(ItemList.setItems(items, list), tag)
            case other => other
        }, loaded)

    /// フェーズ遷移時の visibility 適用 (Push モデル)。
    ///   - Panel: SpellSelect フェーズだけ visible
    ///   - ItemList: SpellSelect フェーズだけ focused
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == GamePhase.SpellSelect;
        scene
            |> Scene.mapEngineNode(panelPath(), node -> match node {
                case EngineNode.PanelWithState(panel, tag) =>
                    EngineNode.PanelWithState(CanvasItem.setVisible(visible, panel), tag)
                case other => other
            })
            |> Scene.mapEngineNode(menuPath(), node -> match node {
                case EngineNode.ItemListWithState(list, tag) =>
                    EngineNode.ItemListWithState(ItemList.setFocused(visible, list), tag)
                case other => other
            })

    /// じゅもん項目が確定された (Enter) ときの処理。 Game.flix の MenuHandler から呼ばれる。
    /// entry の metadata から spell_id を取り出し、 BattleScene.beginSpell に委譲（Heal なら
    /// 即発動、 Damage で敵が複数なら TargetSelect、 1 体なら即発動）。
    pub def onSpellConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {GamePhaseState, Math.Random, GameEngine.Audio} =
        match entry#metadata {
            case Some(spellId) => BattleScene.beginSpell(spellId, scene)
            case None => scene
        }

    /// じゅもんメニューでキャンセル (Escape) されたときの処理。 親メニュー (CommandSelect) に戻る。
    pub def onSpellCancelled(scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        GamePhaseState.put(GamePhase.CommandSelect); scene
}
