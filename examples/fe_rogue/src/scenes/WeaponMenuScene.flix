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

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から WeaponMenu の ItemList
    /// ノードに対して dispatch される (per-node、ItemList は 1 個のみなので 1 フレーム 1 回)。
    /// 2 つの責務を 1 か所で処理:
    ///   1. **Panel + ItemList の visible/focused** を毎フレーム phase で再評価
    ///   2. **WeaponSelect フェーズのときだけ** 選択中プレイヤーの weapons を items + icons に同期
    ///      (それ以外のフェーズでは前回の items を温存)
    /// scene 全体を mapEngineNode で更新するため、戻り値 node は scene から取り直す。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = if (phase != TurnPhase.Phase.WeaponSelect) withVisibility
            else {
                let weapons = match SelectedPlayer.State.get()#id {
                    case None     => Nil
                    case Some(id) => PlayerScene.getWeapons(id, withVisibility)
                };
                let items = buildItems(weapons);
                let icons = buildIcons(weapons);
                Scene.mapEngineNode(menuPath(), n -> match n {
                    case EngineNode.ItemListWithState(list, tag) =>
                        let updated = list
                            |> ItemList.setItems(items)
                            |> ItemList.setItemIcons(icons)
                            |> ItemList.setIconSize(iconSize())
                            |> ItemList.setIconTextGap(iconTextGap());
                        EngineNode.ItemListWithState(updated, tag)
                    case other => other
                }, withVisibility)
            };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
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

    /// PlayerAttack + Z (敵に乗ったカーソル): 武器選択ウィンドウを開く。
    /// 攻撃対象 id を Data#attackTargetId に記録し、WeaponSelect フェーズに遷移する。
    /// 赤マス / カーソルは消さない (メニューを閉じたとき即座に target 選択に戻せるよう)。
    pub def openFor(attackerId: Int32, defenderId: Int32,
                     scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.WeaponSelect);
        PlayerScene.setAttackTargetId(attackerId, defenderId, scene)

    /// ItemList 項目が確定された (Enter) 瞬間に呼ばれる。
    /// metadata から weapon index を取り出し、選択中武器 idx を Data に書き込み、
    /// `AttackForecast` フェーズに進む (戦闘予報パネルを表示)。
    /// 予報テキストは `ForecastPanelScene.process` が AttackForecast 中に毎フレーム
    /// scene から再構築するため、ここで push する必要はない。
    /// 実際の攻撃モーション開始は `ForecastPanelScene.confirm` で行う。
    pub def onWeaponConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata |> Option.flatMap(Int32.fromString) {
            case None      => scene
            case Some(idx) =>
                TurnPhase.State.put(TurnPhase.Phase.AttackForecast);
                match SelectedPlayer.State.get()#id {
                    case None             => scene
                    case Some(attackerId) =>
                        PlayerScene.setSelectedWeaponIdx(attackerId, idx, scene)
                }
        }

    /// X / Escape 押下で呼ばれる。武器選択ウィンドウを閉じて PlayerAttack の
    /// ターゲット選択に戻る (別の敵を狙い直すか、X で待機できる)。
    /// `attackTargetId` をクリアして別の敵を選び直せるようにする。
    pub def onWeaponCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        TurnPhase.State.put(TurnPhase.Phase.PlayerAttack);
        match SelectedPlayer.State.get()#id {
            case None             => scene
            case Some(attackerId) => PlayerScene.clearAttackTargetId(attackerId, scene)
        }

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
