/// どうぐサブメニューシーン。 Panel + ItemList で構成、 `GamePhase.ItemSelect` のときだけ
/// visible + focused になる。 項目は BattleScene のインベントリから **毎フレーム** 動的に
/// 構築する（アイテム使用で quantity が減ったら表示も即座に更新される）。
/// 各項目の `metadata` に item_id を入れ、 確定時に `BattleScene.applyItem` を呼び出す。
mod ItemMenuScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = "src/scenes/ItemMenuScene.scene.json"

    pub def panelName(): String = "item_panel"
    pub def menuName(): String = "menu"
    pub def panelPath(): NodePath = BattleScene.uiLayerPath() ::: panelName() :: Nil
    pub def menuPath(): NodePath = panelPath() ::: menuName() :: Nil

    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                => Ok(NodeTag.NoTag)
            case Some("NoTag")       => Ok(NodeTag.NoTag)
            case Some("ItemPanel")   => Ok(NodeTag.ItemPanel)
            case Some("ItemMenu")    => Ok(NodeTag.ItemMenu)
            case Some(unknown)       => Err(JsonCompat.jsonError(Root, Set#{"ItemMenuScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFontAt(BattleScene.uiLayerPath(), sceneJsonPath(),
                                        fontAtlas, tagParser, scene)

    /// フェーズ遷移時の visibility 適用 (Push モデル)。
    ///   - Panel: ItemSelect フェーズだけ visible
    ///   - ItemList: ItemSelect フェーズだけ focused
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == GamePhase.ItemSelect;
        scene
            |> Panel.mapAt(panelPath(), panel ->
                CanvasItem.setVisible(visible, panel))
            |> ItemList.mapAt(menuPath(), list ->
                ItemList.setFocused(visible, list))

    /// 毎フレーム呼ばれる process。 inventory → items の追従だけ担当（visibility / focused
    /// は applyVisibility が担当）。 アイテム使用で quantity が変わったら即表示反映。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.ItemListWithState(list, NodeTag.ItemMenu) =>
                let data = BattleScene.readData(scene);
                let items = buildItems(data#current#inventory, data#itemCatalog);
                let updated = ItemList.setItems(items, list);
                (EngineNode.ItemListWithState(updated, NodeTag.ItemMenu), scene)
            case _ => (node, scene)
        }

    /// インベントリ → ItemList.ItemEntry のリストに変換する。
    /// 残数 0 のエントリは disabled で表示（カーソルもスキップ）。
    def buildItems(inventory: List[ItemCatalog.InventoryEntry],
                   catalog: ItemCatalog.Catalog): List[ItemEntry] =
        List.map(e -> {
            let item = ItemCatalog.get(e#id, catalog);
            ({
                text     = "${item#name} x${e#quantity}",
                disabled = e#quantity <= 0,
                metadata = Some(e#id)
            }: ItemEntry)
        }, inventory)

    /// どうぐ項目が確定されたときの処理。 metadata から item_id を取り出し、 BattleScene.applyItem
    /// で使用 → Resolving 遷移。
    pub def onItemConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                            Scene[NodeTag] \ GamePhaseState =
        match entry#metadata {
            case Some(itemId) =>
                let afterUse = BattleScene.applyItem(itemId, scene);
                GamePhaseState.put(GamePhase.Resolving);
                afterUse
            case None => scene
        }

    /// Escape で親メニュー (CommandSelect) に戻る。
    pub def onItemCancelled(scene: Scene[NodeTag]): Scene[NodeTag] \ GamePhaseState =
        GamePhaseState.put(GamePhase.CommandSelect); scene
}
