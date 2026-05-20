/// WeaponMenuScene — 武器選択ウィンドウ
///
/// PlayerMoving + Z で `WeaponSelect` フェーズに入った瞬間に表示される ItemList。
/// 選択中プレイヤーの `weapons` インベントリを列挙し、↑↓ でカーソル移動、Enter で確定、
/// Escape でキャンセルできる。確定で選んだ武器の index を `PlayerScene.setSelectedWeaponIdx`
/// に書き、`GameManager.enterAttackPhaseAfterWeaponSelect` で PlayerAttack に進む。
///
/// ノード構造（visible のとき）:
///   WeaponMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.WeaponPanel)
///           └─ menu (ItemList, NodeTag.WeaponMenu)
///
/// visibility / focused 制御:
///   - `applyVisibility(phase)` を gameLoop がフェーズ遷移時に 1 度だけ呼ぶ。
///     WeaponSelect 中だけ panel が visible + menu が focused になる。
mod WeaponMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    /// scene.json 相対パス。プロジェクトルートから読まれる。
    def sceneJsonPath(): String = "src/scenes/WeaponMenuScene.scene.json"

    /// fontManifest で登録した name と一致させる（LogScene と同じ "ui" を使う）。
    def fontName(): String = "ui"

    /// CanvasLayer ルート名
    def rootName(): String = "WeaponMenu"

    /// Panel 子ノード名
    pub def panelName(): String = "panel"

    /// ItemList 子ノード名
    pub def menuName(): String = "menu"

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("WeaponPanel")   => Ok(NodeTag.WeaponPanel)
            case Some("WeaponMenu")    => Ok(NodeTag.WeaponMenu)
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"WeaponMenuScene tag (got: ${unknown})"}))
        }

    /// scene に WeaponMenu ノードツリーを追加する。
    /// `loadSceneWithFont` は ItemList を含むので FontAtlas 必須。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「武器メニューが現在 visible か」のヘルパー。
    /// gameLoop の Escape→quit 判定で「メニュー表示中は Escape を quit に流さない」用途。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(panelPath(), scene) {
            case Some(EngineNode.PanelWithState(panel, _)) => CanvasItem.isVisible(panel)
            case _                                          => false
        }

    /// フェーズ遷移時の visibility 適用（Push モデル）。
    ///   - Panel  : WeaponSelect フェーズだけ visible
    ///   - Menu   : WeaponSelect フェーズだけ visible + focused
    /// ItemList の `visible` を Panel と一緒に切り替えるのは、`MenuEvent.updateMenus` が
    /// ItemList 自体の visible で gate していて、`visible=true` のまま放置すると
    /// 非表示中も `toDrawables` が走って毎フレーム glyph 生成してしまうため。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.WeaponSelect;
        scene
            |> Scene.mapEngineNode(panelPath(), node -> match node {
                case EngineNode.PanelWithState(panel, tag) =>
                    EngineNode.PanelWithState(CanvasItem.setVisible(visible, panel), tag)
                case other => other
            })
            |> Scene.mapEngineNode(menuPath(), node -> match node {
                case EngineNode.ItemListWithState(list, tag) =>
                    let withVisible = CanvasItem.setVisible(visible, list);
                    EngineNode.ItemListWithState(ItemList.setFocused(visible, withVisible), tag)
                case other => other
            })

    /// 武器アイコンの表示サイズ（px）。fontSize 4 / itemHeight 6 の中に収まるよう 5px に。
    def iconSize(): Float64 = 5.0

    /// アイコンとテキスト名の間の余白（px）
    def iconTextGap(): Float64 = 1.0

    /// 毎フレーム呼ばれる process。**WeaponSelect フェーズのときだけ** 選択中プレイヤーの
    /// weapons を ItemList.items + itemIcons に同期する。それ以外のフェーズでは前回の状態を温存して
    /// 何もしない（毎フレーム同じ List を再構築するコストを避ける）。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State} =
        match node {
            case EngineNode.ItemListWithState(list, NodeTag.WeaponMenu) =>
                if (TurnPhase.State.get() != TurnPhase.Phase.WeaponSelect) (node, scene)
                else {
                    let weapons = match SelectedPlayer.State.get()#id {
                        case None     => Nil
                        case Some(id) => PlayerScene.getWeapons(id, scene)
                    };
                    let items = buildItems(weapons);
                    let icons = buildIcons(weapons);
                    let updated = list
                        |> ItemList.setItems(items)
                        |> ItemList.setItemIcons(icons)
                        |> ItemList.setIconSize(iconSize())
                        |> ItemList.setIconTextGap(iconTextGap());
                    (EngineNode.ItemListWithState(updated, NodeTag.WeaponMenu), scene)
                }
            case _ => (node, scene)
        }

    /// プレイヤーの weapons リストから ItemList.ItemEntry 列を作る。
    /// 表示は「武器名 残り耐久」。metadata に index を文字列で詰めて、確定時に取り出す。
    def buildItems(weapons: List[UnitCatalog.WeaponResource]): List[ItemEntry] =
        weapons
            |> List.mapWithIndex(idx -> w ->
                ({
                    text     = "${w#name} ${w#durability}",
                    disabled = false,
                    metadata = Some(Int32.toString(idx))
                }: ItemEntry))

    /// 各武器の sprite から ItemList の itemIcons Map を組み立てる（行 index → ItemIcon）。
    def buildIcons(weapons: List[UnitCatalog.WeaponResource]):
            Map[Int32, ItemIcon] =
        List.foldLeft((acc, pair) -> {
            let (idx, w) = pair;
            let icon: ItemIcon = {
                texture = w#sprite#texture,
                hframes = w#sprite#hframes,
                vframes = w#sprite#vframes,
                frame   = w#sprite#frame
            };
            Map.insert(idx, icon, acc)
        }, Map.empty(), List.zipWithIndex(weapons))

    /// ItemList 項目が確定された（Enter）瞬間に呼ばれる。
    /// metadata から weapon index を取り出し、`AttackForecast` フェーズへ進める
    /// （実際の攻撃モーション開始は予報パネル確認後）。
    pub def onWeaponConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata |> Option.flatMap(Int32.fromString) {
            case Some(idx) =>
                GameManager.confirmAttackWithWeapon(idx, scene)
            case None => scene
        }

    /// Escape 押下で呼ばれる。武器選択ウィンドウを閉じて PlayerAttack の
    /// ターゲット選択に戻る（別の敵を狙い直すか、X で待機できる）。
    pub def onWeaponCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        GameManager.closeWeaponMenu(scene)

    /// InputHandler の Z 押下から呼ばれる。Engine の MenuEvent は Enter で確定するが、
    /// FERogue のキー慣習（Z = 決定）に合わせて手動で「今カーソルがある武器を確定」する。
    /// 内部では `ItemList.getSelected` で現在の選択項目を取り、`onWeaponConfirmed` に流す。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        match Scene.getEngineNode(menuPath(), scene) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                match ItemList.getSelected(list) {
                    case Some(entry) => onWeaponConfirmed(entry, scene)
                    case None        => scene
                }
            case _ => scene
        }
}
