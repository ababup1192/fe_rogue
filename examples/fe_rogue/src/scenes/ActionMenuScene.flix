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
    def pickupMeta(): String = "pickup"

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

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ActionMenu の ItemList
    /// ノードに対して dispatch される (per-node、ItemList は 1 個のみなので 1 フレーム 1 回)。
    /// 2 つの責務を 1 か所で処理:
    ///   1. **Panel + ItemList の visible/focused** を毎フレーム phase で再評価
    ///   2. **ActionSelect 中**に items を文脈に応じて再計算 (`buildItems`)
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State,
                           PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = if (phase != TurnPhase.Phase.ActionSelect) withVisibility
            else {
                let items = buildItems(withVisibility);
                Scene.mapEngineNode(menuPath(), n -> match n {
                    case EngineNode.ItemListWithState(list, tag) =>
                        EngineNode.ItemListWithState(ItemList.setItems(items, list), tag)
                    case other => other
                }, withVisibility)
            };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// 選択中プレイヤーの状況から「こうげき / ひろう / たいき」のうち成立するものだけ返す。
    /// 順序は固定: こうげき → ひろう → たいき (FE 流に攻撃が上、待機が末尾)。
    def buildItems(scene: Scene[NodeTag]): List[ItemEntry]
            \ {SelectedPlayer.State, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match SelectedPlayer.State.get()#id {
            case None     => Nil
            case Some(id) =>
                match PlayerScene.PartyQuery.get(id) {
                    case None         => Nil
                    case Some(player) =>
                        let attackItem =
                            if (canAttackFrom(player))
                                ({text     = "こうげき",
                                  disabled = false,
                                  metadata = Some(attackMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let pickupItem =
                            if (Option.nonEmpty(ItemScene.findAt(player#gridPos, scene)))
                                ({text     = "ひろう",
                                  disabled = false,
                                  metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let waitItem =
                            if (canWaitOn(player))
                                ({text     = "たいき",
                                  disabled = false,
                                  metadata = Some(waitMeta())}: ItemEntry) :: Nil
                            else Nil;
                        List.append(attackItem, List.append(pickupItem, waitItem))
                }
        }

    /// 装備武器の射程内に生きている敵が居るか。
    /// 武器なし / 全員 isDying なら false。
    def canAttackFrom(player: PlayerScene.Data): Bool \ EnemyScene.RosterQuery =
        match List.head(player#weapons) {
            case None    => false
            case Some(w) =>
                List.exists(e ->
                    not e#isDying
                    and e#hp > 0
                    and Weapon.canReach(Weapon.manhattan(player#gridPos, e#gridPos), w),
                    EnemyScene.RosterQuery.getAll())
        }

    /// 自分の現在セルに「自分以外の味方」が居なければたいき可。
    /// 同じセルに別味方が居る (重なり) ときは false。
    def canWaitOn(player: PlayerScene.Data): Bool \ PlayerScene.PartyQuery =
        not List.exists(d ->
            d#id != player#id
            and d#gridPos#x == player#gridPos#x
            and d#gridPos#y == player#gridPos#y,
            PlayerScene.PartyQuery.getAll())

    /// ItemList 項目が確定された (Enter) 瞬間に呼ばれる。metadata から
    /// 「attack」/「wait」/「pickup」を分岐して、それぞれの帰結を直接適用する。
    ///   - attack: 攻撃ターゲット選択フェーズへ (`PlayerScene.enterAttackPhase` に委譲)
    ///   - wait:   その場で waited 確定
    ///   - pickup: 床アイテムを拾って waited 確定 (拾うで 1 ターン使う)
    /// 「次セレクトか敵ターンか」の判定は Scene 跨ぎなので `PlayerScene.commitWaitedAndAdvance`
    /// を呼ぶ (Scene → GameManager 方向は許容)。
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                if (m == attackMeta())      PlayerScene.enterAttackPhase(scene)
                else if (m == waitMeta())   PlayerScene.commitWaitedAndAdvance(scene)
                else if (m == pickupMeta()) applyPickup(scene)
                else                         scene
        }

    /// 「ひろう」確定の本体。床アイテムを取得してインベントリに加え、
    /// ログを出してから waited 確定 (拾うで 1 ターン使う)。
    /// 何らかの理由で item が無い場合は no-op して即 wait に倒す (防御的)。
    def applyPickup(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              GameLogger.GameLogger,
                              EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                              PlayerScene.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None     => PlayerScene.commitWaitedAndAdvance(scene)
            case Some(id) =>
                match PlayerScene.PartyQuery.get(id) {
                    case None         => PlayerScene.commitWaitedAndAdvance(scene)
                    case Some(player) =>
                        let (afterTake, taken) = ItemScene.takeAt(player#gridPos, scene);
                        match taken {
                            case None    => PlayerScene.commitWaitedAndAdvance(afterTake)
                            case Some(w) =>
                                GameLogger.playerLog("P${id} が ${w#name} を拾った");
                                let withWeapon = PlayerScene.mapPlayer(id,
                                    d -> {weapons = List.append(d#weapons, w :: Nil) | d},
                                    afterTake);
                                PlayerScene.commitWaitedAndAdvance(withWeapon)
                        }
                }
        }

    /// PlayerMoving + Z 押下時の遷移: 行動選択ウィンドウを開く (フェーズ = ActionSelect)。
    /// 青マス表示はそのまま維持し、ItemList を visibility 適用で表示する。
    /// 「こうげき / たいき / ひろう」の項目は `refreshItems` が毎フレーム再構築。
    pub def openFromMoving(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// X / Escape 押下で呼ばれる。メニューを閉じて PlayerMoving に戻る。
    /// 青マス・カーソルは触らず、ユーザがもう一度動かし直せる状態に復帰する。
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
        scene

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある項目を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match Scene.getEngineNode(menuPath(), scene) {
            case Some(EngineNode.ItemListWithState(list, _)) =>
                match ItemList.getSelected(list) {
                    case Some(entry) => onActionConfirmed(entry, scene)
                    case None        => scene
                }
            case _ => scene
        }
}
