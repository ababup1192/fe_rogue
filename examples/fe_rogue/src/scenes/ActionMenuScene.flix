/// ActionMenuScene — 行動選択ウィンドウ
///
/// PlayerMoving で Z を押した瞬間に `ActionSelect` フェーズに入り、画面に出る ItemList。
/// 文脈に応じて「こうげき」「たいき」を表示し、↑↓ で選択、Enter/Z で確定、X/Escape で
/// `PlayerMoving` に戻る (= もう一度動かし直せる)。
///
/// ノード構造（visible のとき）:
///   ActionMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.ActionPanel)
///           └─ menu (ItemList, NodeTag.ActionMenu)
///
/// 項目の出現条件 (`refreshItems` で毎フレーム再計算):
///   - 「こうげき」: 選択中プレイヤーの装備武器の射程内に生きている敵が居る
///   - 「たいき」  : 選択中プレイヤーのセルに別の味方が居ない
/// 両方とも条件不成立なら ItemList は空になり、Z 押下は no-op (X で戻るのみ)。
mod ActionMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/ActionMenuScene.scene.json"

    def fontName(): String = "ui"

    def rootName(): String = "ActionMenu"

    pub def panelName(): String = "panel"
    pub def menuName(): String = "menu"

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ActionPanel")   => Ok(NodeTag.ActionPanel)
            case Some("ActionMenu")    => Ok(NodeTag.ActionMenu)
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"ActionMenuScene tag (got: ${unknown})"}))
        }

    /// metadata の値。`onItemConfirmed` で再現するためのアクション識別子。
    def attackMeta(): String = "attack"
    def waitMeta(): String   = "wait"

    /// scene に ActionMenu ノードツリーを追加する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「行動メニューが現在 visible か」のヘルパー。gameLoop の Escape→quit 判定で使う。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(panelPath(), scene) {
            case Some(EngineNode.PanelWithState(panel, _)) => CanvasItem.isVisible(panel)
            case _                                          => false
        }

    /// フェーズ遷移時の visibility 適用。
    ///   - Panel : ActionSelect フェーズだけ visible
    ///   - Menu  : ActionSelect フェーズだけ visible + focused
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.ActionSelect;
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

    /// 毎フレーム呼ばれる process。ActionSelect 中に items を文脈に応じて再計算する。
    /// 文脈の判定は `buildItems` に閉じ込めて pure に近く保つ。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State} =
        match node {
            case EngineNode.ItemListWithState(list, NodeTag.ActionMenu) =>
                if (TurnPhase.State.get() != TurnPhase.Phase.ActionSelect) (node, scene)
                else {
                    let items = buildItems(scene);
                    let updated = ItemList.setItems(items, list);
                    (EngineNode.ItemListWithState(updated, NodeTag.ActionMenu), scene)
                }
            case _ => (node, scene)
        }

    /// 選択中プレイヤーの状況から「こうげき / たいき」のうち成立するものだけ返す。
    /// 順序は固定: こうげき → たいき (FE 流に攻撃が上)。
    def buildItems(scene: Scene[NodeTag]): List[ItemEntry] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None     => Nil
            case Some(id) =>
                match PlayerScene.get(id, scene) {
                    case None         => Nil
                    case Some(player) =>
                        let attackItem =
                            if (canAttackFrom(player, scene))
                                ({text     = "こうげき",
                                  disabled = false,
                                  metadata = Some(attackMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let waitItem =
                            if (canWaitOn(player, scene))
                                ({text     = "たいき",
                                  disabled = false,
                                  metadata = Some(waitMeta())}: ItemEntry) :: Nil
                            else Nil;
                        List.append(attackItem, waitItem)
                }
        }

    /// 装備武器の射程内に生きている敵が居るか。
    /// 武器なし / 全員 isDying なら false。
    def canAttackFrom(player: PlayerScene.Data, scene: Scene[NodeTag]): Bool =
        match List.head(player#weapons) {
            case None    => false
            case Some(w) =>
                List.exists(e ->
                    not e#isDying
                    and e#hp > 0
                    and Weapon.canReach(Weapon.manhattan(player#gridPos, e#gridPos), w),
                    EnemyScene.getAll(scene))
        }

    /// 自分の現在セルに「自分以外の味方」が居なければたいき可。
    /// 同じセルに別味方が居る (重なり) ときは false。
    def canWaitOn(player: PlayerScene.Data, scene: Scene[NodeTag]): Bool =
        not List.exists(d ->
            d#id != player#id
            and d#gridPos#x == player#gridPos#x
            and d#gridPos#y == player#gridPos#y,
            PlayerScene.getAll(scene))

    /// ItemList 項目が確定された (Enter) 瞬間に呼ばれる。metadata から
    /// 「attack」/「wait」を分岐して GameManager に委譲する。
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata {
            case Some(m) =>
                if (m == attackMeta())      GameManager.actionMenuConfirmAttack(scene)
                else if (m == waitMeta())   GameManager.actionMenuConfirmWait(scene)
                else                         scene
            case None    => scene
        }

    /// Escape / X 押下で呼ばれる。メニューを閉じて PlayerMoving に戻る。
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ TurnPhase.State =
        GameManager.closeActionMenu(scene)

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある項目を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State} =
        match Scene.getEngineNode(menuPath(), scene) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                match ItemList.getSelected(list) {
                    case Some(entry) => onActionConfirmed(entry, scene)
                    case None        => scene
                }
            case _ => scene
        }
}
