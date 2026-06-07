/// ActionMenuScene — 行動選択ウィンドウ
///
/// PlayerMoving / PlayerCursor で Z を押した瞬間に `ActionSelect` フェーズに入り、
/// 画面に出る ItemList。文脈 (= SelectedPlayer の有無) で項目が切り替わる:
///   - PlayerMoving 由来 (SelectedPlayer あり) → こうげき / アイテム / ひろう / たいき
///   - PlayerCursor 由来・空マス (SelectedPlayer なし) → しゅうごう (確定でロードへ合流開始)
/// ↑↓ で選択、Enter/Z で確定、X/Escape で元のフェーズ (PlayerMoving / PlayerCursor) に戻る。
///
/// ノード構造（visible のとき）:
///   ActionMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.ActionPanel)
///           └─ menu (ItemList, NodeTag.ActionMenu)
///
/// 項目の出現条件 (`refreshItems` で毎フレーム再計算):
///   - 「こうげき」: 選択中プレイヤーの装備武器の射程内に生きている敵が居る
///   - 「ひろう」  : 選択中プレイヤーのセルに床アイテムが落ちている
///   - 「たいき」  : 選択中プレイヤーのセルに別の味方が居ない
///   - 「しゅうごう」: SelectedPlayer が None (PlayerCursor + 空マス) のとき常時表示
/// 全条件不成立なら ItemList は空になり、Z 押下は no-op (X で戻るのみ)。
///
/// 「行動継続」と「行動終了」:
///   - 行動終了 (確定で waited 化 → 次セレクト or 敵ターン)
///       こうげき (PlayerAttack を経由してから commit) / たいき / ターンエンド
///   - 行動継続 (確定後 ActionSelect に戻り、ActionMenu の項目が再構築される)
///       ひろう (拾うとセルから消えるので次フレームの `refreshItems` で項目から外れる)
///       しゅうごう (PlayerAutoMove に移ってロードへ合流開始。これは別フローの遷移)
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
    def attackMeta(): String    = "attack"
    def exchangeMeta(): String  = "exchange"
    def itemMeta(): String      = "item"
    def waitMeta(): String      = "wait"
    def pickupMeta(): String    = "pickup"
    def gatherMeta(): String    = "gather"
    def turnEndMeta(): String   = "turnEnd"
    def disbandMeta(): String   = "disband"
    def stairsMeta(): String    = "stairs"

    /// scene に ActionMenu ノードツリーを追加する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「行動メニューが現在 visible か」のヘルパー。gameLoop の Escape→quit 判定で使う。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    /// フェーズ遷移時の visibility 適用。
    ///   - Panel : ActionSelect フェーズだけ visible
    ///   - Menu  : ActionSelect フェーズだけ visible + focused
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.ActionSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))

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
        // メニューが閉じている間は選択カーソルを先頭(0)に戻しておく。これにより
        // 次に開いたときは記憶された位置ではなく常に最初の項目から始まる。
        // 表示中(ActionSelect)はリセットしないので ↑↓ のカーソル移動は維持される。
        let withItems = if (phase != TurnPhase.Phase.ActionSelect)
                withVisibility
                    |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
            else {
                let items = buildItems(withVisibility);
                withVisibility
                    |> ItemList.mapAt(menuPath(), ItemList.setItems(items))
                    |> fitMenuToItems(List.length(items))
            };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// ItemList 1 項目の高さ (px)。scene.json の menu `itemHeight` と一致させること。
    def menuItemHeight(): Float64 = 6.0
    /// panel 内での menu の上下パディング (px)。scene.json の menu `pos` の y と一致させる。
    def menuPadding(): Float64 = 2.0

    /// メニュー項目数 `count` に合わせて ItemList と Panel の高さを詰める。
    /// 幅は scene.json の値を `getSize` で保持し、高さだけ `count` 行ぶんに変える。
    /// これにより「たいき」などの項目が増減してもウィンドウがピッタリ収まる。
    /// 項目 0 でも最低 1 行ぶんの高さは残す (空ウィンドウが潰れて見えないように)。
    def fitMenuToItems(count: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let rows   = Int32.max(1, count);
        let menuH  = Int32.toFloat64(rows) * menuItemHeight();
        let panelH = menuH + 2.0 * menuPadding();
        scene
            |> ItemList.mapAt(menuPath(), l ->
                ItemList.setSize({x = ItemList.getSize(l)#x, y = menuH}, l))
            |> Panel.mapAt(panelPath(), p ->
                Panel.setSize({x = Panel.getSize(p)#x, y = panelH}, p))

    /// 選択中プレイヤーの状況から「こうげき / こうかん / アイテム / ひろう / たいき」の
    /// うち成立するものだけ返す。
    /// 順序は固定: こうげき → こうかん → アイテム → ひろう → たいき (FE 流の並び)。
    /// SelectedPlayer が None のときは PlayerCursor から空マスで開かれた「集合メニュー」
    /// として「しゅうごう」だけを返す (確定でロードへ合流開始)。
    def buildItems(scene: Scene[NodeTag]): List[ItemEntry]
            \ {SelectedPlayer.State, PlayerScene.PartyQuery, EnemyScene.RosterQuery} =
        match SelectedPlayer.State.get()#id {
            case None     =>
                // SelectedPlayer = None の空マスメニュー。ローグ移動モード中
                // (合流して退避中の味方が居る) なら「ひろう / かいさん」、
                // 通常時は「しゅうごう(条件付き) / ターンエンド」。
                if (not List.isEmpty(PlayerScene.hiddenAllies(scene)))
                    rogueMenuItems(scene)
                else
                    gatherMenuItems(scene)
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
                        let exchangeItem =
                            if (not List.isEmpty(PlayerScene.adjacentAllies(player)))
                                ({text     = "こうかん",
                                  disabled = false,
                                  metadata = Some(exchangeMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let itemItem =
                            if (not (List.isEmpty(player#weapons)
                                       and List.isEmpty(player#staves)))
                                ({text     = "アイテム",
                                  disabled = false,
                                  metadata = Some(itemMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let pickupItem =
                            if (Option.nonEmpty(ItemScene.findAt(player#gridPos, scene)))
                                ({text     = "ひろう",
                                  disabled = false,
                                  metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let stairsItem =
                            if (StairsScene.isAt(player#gridPos, scene))
                                ({text     = "かいだん",
                                  disabled = false,
                                  metadata = Some(stairsMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let waitItem =
                            if (canWaitOn(player))
                                ({text     = "たいき",
                                  disabled = false,
                                  metadata = Some(waitMeta())}: ItemEntry) :: Nil
                            else Nil;
                        List.flatten(attackItem :: exchangeItem :: itemItem ::
                                       pickupItem :: stairsItem :: waitItem :: Nil)
                }
        }

    /// ローグ移動モード中(合流済み)のメニュー項目。ロード足元にアイテムがあれば「ひろう」、
    /// ロードが階段に乗っていれば「かいだん」(パーティごと次フロアへ)、常に「かいさん」。
    /// 拾いはロード(id 0)を対象に既存の applyPickup を転用する。
    def rogueMenuItems(scene: Scene[NodeTag]): List[ItemEntry] =
        let lordPos = PlayerScene.getGridPos(0, scene);
        let pickup =
            if (Option.nonEmpty(ItemScene.findAt(lordPos, scene)))
                ({text = "ひろう", disabled = false,
                  metadata = Some(pickupMeta())}: ItemEntry) :: Nil
            else Nil;
        let stairs =
            if (StairsScene.isAt(lordPos, scene))
                ({text = "かいだん", disabled = false,
                  metadata = Some(stairsMeta())}: ItemEntry) :: Nil
            else Nil;
        let disband =
            ({text = "かいさん", disabled = false,
              metadata = Some(disbandMeta())}: ItemEntry) :: Nil;
        List.flatten(pickup :: stairs :: disband :: Nil)

    /// 合流対象の味方を全員集めるのに必要な「周囲マス数」。これ以内に全員居ないと「しゅうごう」は出さない。
    def gatherRange(): Int32 = 3

    /// 通常の空マスメニュー項目。ロードが敵に未検知(部屋外かつ索敵範囲外)で、合流可能な味方が
    /// 全員ロードの周囲 `gatherRange` マス以内に居れば「しゅうごう」、常に「ターンエンド」。
    def gatherMenuItems(scene: Scene[NodeTag]): List[ItemEntry] =
        let gather =
            if (not AutoMoveScene.lordDetected(scene)
                and not List.isEmpty(PlayerScene.mergeableAllies(scene))
                and PlayerScene.allMergeableWithin(gatherRange(), scene))
                ({text = "しゅうごう", disabled = false,
                  metadata = Some(gatherMeta())}: ItemEntry) :: Nil
            else Nil;
        let turnEnd =
            ({text = "ターンエンド", disabled = false,
              metadata = Some(turnEndMeta())}: ItemEntry) :: Nil;
        List.append(gather, turnEnd)

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
    /// 「attack」/「wait」/「pickup」/「gather」を分岐して、それぞれの帰結を直接適用する。
    ///   - attack: 攻撃ターゲット選択フェーズへ (`PlayerScene.enterAttackPhase` に委譲)
    ///   - wait:   その場で waited 確定
    ///   - pickup: 床アイテムを拾って waited 確定 (拾うで 1 ターン使う)
    ///   - gather: しゅうごう。PlayerAutoMove へ移ってロードへ合流開始 (`applyGather`)
    /// 「次セレクトか敵ターンか」の判定は Scene 跨ぎなので `PlayerScene.commitWaitedAndAdvance`
    /// を呼ぶ (Scene → GameManager 方向は許容)。
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                CustomEffects.FloorAdvanceRequest} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                if (m == attackMeta())        PlayerScene.enterAttackPhase(scene)
                else if (m == exchangeMeta()) PhaseTransitions.enterTradeTargetSelect(scene)
                else if (m == itemMeta())     openItemMenu(scene)
                else if (m == waitMeta())     PlayerScene.commitWaitedAndAdvance(scene)
                else if (m == pickupMeta())   applyPickup(scene)
                else if (m == gatherMeta())   applyGather(scene)
                else if (m == turnEndMeta())  applyTurnEnd(scene)
                else if (m == disbandMeta())  AutoMoveScene.disband("かいさん", scene)
                else if (m == stairsMeta())   applyStairs(scene)
                else                          scene
        }

    /// 「かいだん」確定。文脈で 2 通り:
    ///   - 通常（選択中の味方あり）: その味方を階段で退場させる。生存味方が全員退場したら
    ///     `FloorAdvanceRequest` で次フロアへ、まだ動ける味方が残っていれば `commitWaitedAndAdvance`。
    ///   - しゅうごう中（ローグ移動・選択なし）: 合流したパーティ全員で降りる → そのまま次フロアへ。
    ///     退避中(hidden)の味方も生存していれば `snapshotCarry` で引き継がれる。
    def applyStairs(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                CustomEffects.FloorAdvanceRequest} =
        GameLogger.playerLog("階段を降りた");
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                let exited = PlayerScene.useStairs(id, scene);
                if (PlayerScene.allLivingUsedStairs(exited))
                    CustomEffects.FloorAdvanceRequest.advance(exited)
                else
                    PlayerScene.commitWaitedAndAdvance(exited)
            case None =>
                // しゅうごう状態でロードが階段に乗っている → パーティごと次フロアへ。
                CustomEffects.FloorAdvanceRequest.advance(scene)
        }

    /// 「アイテム」確定で ItemMenuScene を開く。選択中味方の id が必要。
    def openItemMenu(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(playerId) => ItemMenuScene.openFor(playerId, scene)
        }

    /// 「しゅうごう」確定: ローグ移動モードの合流を開始する (PlayerAutoMove フェーズへ)。
    /// 以降は AutoMoveScene の driver が味方をロードへ歩かせ、重なったら退避させる。
    /// SelectedPlayer は使わないのでクリアしておく。
    def applyGather(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State} =
        GameLogger.playerLog("しゅうごう");
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        PhaseTransitions.enterPlayerAutoMove(scene)

    /// 「ターンエンド」確定: 全アクティブ味方を行動済みにして即敵ターンへ進む。
    /// SelectedPlayer が None（空マスメニュー）のときだけ選択肢に出るので、
    /// 選択中プレイヤーのクリアも行う。
    def applyTurnEnd(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State} =
        let ids = PlayerScene.getAll(scene)
                    |> List.filter(d -> not d#waited)
                    |> List.map(d -> d#id);
        let afterWait = List.foldLeft((sc, id) -> PlayerScene.setWaited(id, sc), scene, ids);
        SelectedPlayer.State.put(SelectedPlayer.cleared());
        EnemyTurnDriverScene.beginTurn(afterWait)

    /// 「ひろう」確定の本体。床アイテムを取得してインベントリに加え、
    /// ログを出して **ActionSelect フェーズに留まる**（行動継続。ターン消費しない）。
    /// 次フレームの `refreshItems` が「床に何もなくなった」状態を見て自動的に
    /// 「ひろう」をメニューから外す。
    /// 武器なら weapons の末尾に、杖なら staves の末尾に追加する。
    /// 何らかの理由で item が無い場合は no-op（防御的）。
    def applyPickup(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger,
                              SelectedPlayer.State, PlayerScene.PartyQuery} =
        match pickupTarget(scene) {
            case None       => scene
            case Some(info) =>
                // 通常モード(退避中の味方が居ない)では拾得を SelectedPlayer の picked に
                // ドラフト記録し、選択解除キャンセル(cancelSelection)で床へ巻き戻せるようにする。
                // ローグ移動モードは選択が無く巻き戻し対象外なので即取得のまま。
                let recorded =
                    if (List.isEmpty(PlayerScene.hiddenAllies(scene)))
                        recordPickupDraft(info, scene)
                    else scene;
                pickupAt(info, recorded)
        }

    /// `info` のセルにある床アイテムを SelectedPlayer の巻き戻しドラフトに積む。
    /// 床に何も無ければ no-op。実際の在庫追加 / 床撤去は後続の `pickupAt` が行う。
    def recordPickupDraft(info: {playerId = Int32, gridPos = {x = Int32, y = Int32}},
                            scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match ItemScene.dataAt(info#gridPos, scene) {
            case None    => scene
            case Some(d) =>
                SelectedPlayer.pushDraft(
                    MoveDraft.DraftAction.PickedUp(info#playerId, d#gridPos,
                                                    d#itemKey, d#item));
                scene
        }

    /// 拾う主体(playerId)と拾う位置(gridPos)を決める。ローグ移動モード中(合流済み)は
    /// ロード(id 0)がロード足元のアイテムを拾う。通常時は選択中の味方が足元のを拾う。
    def pickupTarget(scene: Scene[NodeTag]):
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerScene.PartyQuery} =
        if (not List.isEmpty(PlayerScene.hiddenAllies(scene)))
            Some({playerId = 0, gridPos = PlayerScene.getGridPos(0, scene)})
        else
            selectedPlayerInfo()

    /// 選択中の味方の id と現在位置をまとめて返す。
    /// SelectedPlayer 未選択 / PartyQuery で見つからないいずれでも None。
    def selectedPlayerInfo():
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerScene.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerScene.PartyQuery.get(playerId)
        ) yield {playerId = playerId, gridPos = player#gridPos}

    /// 指定セルで床アイテムを 1 個取って selectedPlayer のインベントリに追加する。
    /// アイテムがなければ takeAt 後の scene をそのまま返す（防御的）。
    def pickupAt(info: {playerId = Int32, gridPos = {x = Int32, y = Int32}},
                  scene: Scene[NodeTag]):
                  Scene[NodeTag] \ GameLogger.GameLogger =
        let (afterTake, taken) = ItemScene.takeAt(info#gridPos, scene);
        taken
            |> Option.map(kind -> addPickedItem(info#playerId, kind, afterTake))
            |> Option.getWithDefault(afterTake)

    /// 拾ったアイテムをプレイヤーのインベントリに追加し、ログも出す。
    /// 武器は weapons の末尾（= 装備中の後ろ）、杖は staves の末尾に積む。
    def addPickedItem(playerId: Int32, kind: ItemScene.GroundItemKind,
                        scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameLogger.GameLogger =
        match kind {
            case ItemScene.GroundItemKind.WeaponItem(weapon) =>
                GameLogger.playerLog("P${playerId} が ${weapon#name} を拾った");
                PlayerScene.mapPlayer(playerId,
                    d -> {weapons = List.append(d#weapons, weapon :: Nil) | d},
                    scene)
            case ItemScene.GroundItemKind.StaffItem(staff) =>
                GameLogger.playerLog("P${playerId} が ${staff#name} を拾った");
                PlayerScene.mapPlayer(playerId,
                    d -> {staves = List.append(d#staves, staff :: Nil) | d},
                    scene)
            case ItemScene.GroundItemKind.ConsumableItem(item) =>
                GameLogger.playerLog("P${playerId} が ${item#name} を拾った");
                PlayerScene.mapPlayer(playerId,
                    d -> {consumables = List.append(d#consumables, item :: Nil) | d},
                    scene)
        }

    /// PlayerMoving + Z 押下時の遷移: 行動選択ウィンドウを開く (フェーズ = ActionSelect)。
    /// 青マス表示はそのまま維持し、ItemList を visibility 適用で表示する。
    /// 「こうげき / たいき / ひろう」の項目は `refreshItems` が毎フレーム再構築。
    pub def openFromMoving(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// PlayerCursor + Z 押下時 (空マス) の遷移: 集合メニュー (しゅうごう) を開く。
    /// SelectedPlayer は None のままなので `buildItems` がしゅうごうのみを返す。
    /// カーソルは PlayerCursor で visible のまま据え置く。
    pub def openFromCursor(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// RogueMove (ローグ自由歩行) + Z 押下時の遷移: メニュー (ひろう / かいさん) を開く。
    /// SelectedPlayer は None のまま。`buildItems` が「退避中の味方が居る」ことを手掛かりに
    /// ローグ用メニューを返す。X で `onActionCancelled` が RogueMove に戻す。
    pub def openFromRogue(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// X / Escape 押下で呼ばれる。メニューを閉じて元のフェーズに戻る:
    ///   - SelectedPlayer あり (PlayerMoving からの ActionMenu) → PlayerMoving
    ///   - SelectedPlayer なし (PlayerCursor からの集合メニュー) → PlayerCursor
    /// 青マス・カーソルは触らず、ユーザがもう一度操作し直せる状態に復帰する。
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        let target = match SelectedPlayer.State.get()#id {
            case Some(_) => TurnPhase.Phase.PlayerMoving
            case None    =>
                // 退避中の味方が居る = ローグ移動モード由来のメニュー → RogueMove に戻す。
                // それ以外は通常の空マスメニュー由来 → PlayerCursor に戻す。
                if (not List.isEmpty(PlayerScene.hiddenAllies(scene)))
                    TurnPhase.Phase.RogueMove
                else
                    TurnPhase.Phase.PlayerCursor
        };
        TurnPhase.State.put(target);
        scene

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある項目を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                CustomEffects.FloorAdvanceRequest} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case Some(entry) => onActionConfirmed(entry, scene)
            case None        => scene
        }
}
