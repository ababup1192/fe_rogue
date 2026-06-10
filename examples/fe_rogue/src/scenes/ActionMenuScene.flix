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

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/ActionMenuScene.scene.json")

    def fontName(): String = "ui"

    def rootName(): String = "ActionMenu"

    pub def panelName(): String = "panel"
    pub def menuName(): String = "menu"

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ActionPanel")   => Ok(NodeTag.ActionPanel)
            case Some("ActionMenu")    => Ok(NodeTag.ActionMenu)
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"ActionMenuScene tag (got: ${unknown})"}))
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
    /// 集合後の N 人持ち物交換 (RogueMove メニューの「交換」)。
    /// 通常ターン隣接 2 人交換の `exchangeMeta` とは別物。
    def gatherTradeMeta(): String = "gatherTrade"

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
    /// 順序は固定: ひろう → 階段 → こうげき → アイテム → こうかん → たいき。
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
                                ({text     = "攻撃",
                                  disabled = false,
                                  metadata = Some(attackMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let exchangeItem =
                            if (not List.isEmpty(PlayerScene.adjacentAllies(player)))
                                ({text     = "交換",
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
                                ({text     = "拾う",
                                  disabled = false,
                                  metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let stairsItem =
                            if (StairsScene.isAt(player#gridPos, scene))
                                ({text     = "階段",
                                  disabled = false,
                                  metadata = Some(stairsMeta())}: ItemEntry) :: Nil
                            else Nil;
                        let waitItem =
                            if (canWaitOn(player))
                                ({text     = "待機",
                                  disabled = false,
                                  metadata = Some(waitMeta())}: ItemEntry) :: Nil
                            else Nil;
                        List.flatten(pickupItem :: stairsItem :: attackItem :: itemItem ::
                                       exchangeItem :: waitItem :: Nil)
                }
        }

    /// ローグ移動モード中(合流済み)のメニュー項目。ロード足元にアイテムがあれば「ひろう」、
    /// ロードが階段に乗っていれば「かいだん」(パーティごと次フロアへ)、常に「かいさん」。
    /// 拾いはロード(id 0)を対象に既存の applyPickup を転用する。
    def rogueMenuItems(scene: Scene[NodeTag]): List[ItemEntry] =
        let lordPos = PlayerScene.getGridPos(0, scene);
        let pickup =
            if (Option.nonEmpty(ItemScene.findAt(lordPos, scene)))
                ({text = "拾う", disabled = false,
                  metadata = Some(pickupMeta())}: ItemEntry) :: Nil
            else Nil;
        let stairs =
            if (StairsScene.isAt(lordPos, scene))
                ({text = "階段", disabled = false,
                  metadata = Some(stairsMeta())}: ItemEntry) :: Nil
            else Nil;
        let trade =
            if (List.length(gatherTradeMembers(scene)) >= 2)
                ({text = "交換", disabled = false,
                  metadata = Some(gatherTradeMeta())}: ItemEntry) :: Nil
            else Nil;
        let disband =
            ({text = "解散", disabled = false,
              metadata = Some(disbandMeta())}: ItemEntry) :: Nil;
        List.flatten(pickup :: stairs :: trade :: disband :: Nil)

    /// 集合した生存メンバーの player id リスト (= 交換に参加できる面々)。
    /// ロード(id 0) + 退避中(hidden)の味方。死亡(hp<=0)・階段退場は除外し、id 昇順に並べる。
    /// (`hiddenAllies` が既に usedStairs を除外。`getAll` は hp<=0 を残すので hp フィルタ必須。)
    def gatherTradeMembers(scene: Scene[NodeTag]): List[Int32] =
        let lord   = PlayerScene.get(0, scene) |> Option.toList;
        let hidden = PlayerScene.hiddenAllies(scene);
        List.append(lord, hidden)
            |> List.filter(d -> d#hp > 0)
            |> List.map(d -> d#id)
            |> List.sort

    /// 合流対象の味方を全員集めるのに必要な「周囲マス数」。これ以内に全員居ないと「しゅうごう」は出さない。
    def gatherRange(): Int32 = 3

    /// 通常の空マスメニュー項目。ロードが敵に未検知(部屋外かつ索敵範囲外)で、合流可能な味方が
    /// 全員ロードの周囲 `gatherRange` マス以内に居れば「しゅうごう」、常に「ターンエンド」。
    def gatherMenuItems(scene: Scene[NodeTag]): List[ItemEntry] =
        let gather =
            if (not AutoMoveScene.lordDetected(scene)
                and not List.isEmpty(PlayerScene.mergeableAllies(scene))
                and PlayerScene.allMergeableWithin(gatherRange(), scene))
                ({text = "集合", disabled = false,
                  metadata = Some(gatherMeta())}: ItemEntry) :: Nil
            else Nil;
        let turnEnd =
            ({text = "ターンエンド", disabled = false,
              metadata = Some(turnEndMeta())}: ItemEntry) :: Nil;
        List.append(gather, turnEnd)

    /// インベントリのいずれかの武器の射程内に生きている敵が居るか。
    /// 装備中(先頭)だけでなく全武器を見る: 射程を変えれば(= 別の武器に持ち替えれば)
    /// 攻撃できる場合も「攻撃」を出すため。武器なし / 全員 isDying / どの武器も射程外なら false。
    /// 持ち替え後の実際の装備は `PlayerScene.enterAttackPhase` が行う。
    def canAttackFrom(player: PlayerScene.Data): Bool \ EnemyScene.RosterQuery =
        let enemies = EnemyScene.RosterQuery.getAll();
        List.exists(w -> weaponReachesAnyEnemy(player#gridPos, w, enemies), player#weapons)

    /// 指定位置から `weapon` の射程内に生きている敵 (hp > 0 かつ not isDying) が居るか。
    def weaponReachesAnyEnemy(pos: {x = Int32, y = Int32},
                               weapon: UnitCatalog.WeaponResource,
                               enemies: List[EnemyScene.Data]): Bool =
        List.exists(e -> {
            let ev = EnemyScene.unitView(e);
            ev#hp > 0 and not ev#isDying
                and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
        }, enemies)

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
    /// 「次セレクトか敵ターンか」の判定は Scene 跨ぎなので `TurnFlow.commitWaitedAndAdvance`
    /// を呼ぶ (Scene → GameManager 方向は許容)。
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                PlayerScene.PartyQuery, EnemyScene.RosterQuery,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                if (m == attackMeta())        PlayerScene.enterAttackPhase(scene)
                else if (m == exchangeMeta()) PhaseTransitions.enterTradeTargetSelect(scene)
                else if (m == itemMeta())     openItemMenu(scene)
                else if (m == waitMeta())     TurnFlow.commitWaitedAndAdvance(scene)
                else if (m == pickupMeta())   applyPickup(scene)
                else if (m == gatherMeta())   applyGather(scene)
                else if (m == turnEndMeta())  applyTurnEnd(scene)
                else if (m == disbandMeta())  AutoMoveScene.disband("解散", scene)
                else if (m == stairsMeta())   applyStairs(scene)
                else if (m == gatherTradeMeta()) openGatherTrade(scene)
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
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio} =
        // 階段を決定した瞬間にフロア移動音を鳴らす
        AudioStreamPlayer.play("change_floor");
        GameLogger.playerLog("階段を降りた");
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                let exited = PlayerScene.useStairs(id, scene);
                if (PlayerScene.allLivingUsedStairs(exited))
                    CustomEffects.FloorAdvanceRequest.advance(exited)
                else
                    TurnFlow.commitWaitedAndAdvance(exited)
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

    /// 「交換」確定 (集合後): 集合した生存メンバー全員の N 人持ち物交換画面を開く。
    /// TradeInventory フェーズ (origin = FromRogue) に入り、TradeMenuScene が 3 ペイン表示する。
    def openGatherTrade(scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        PhaseTransitions.enterGatherTrade(gatherTradeMembers(scene), scene)

    /// 「しゅうごう」確定: ローグ移動モードの合流を開始する (PlayerAutoMove フェーズへ)。
    /// 以降は AutoMoveScene の driver が味方をロードへ歩かせ、重なったら退避させる。
    /// SelectedPlayer は使わないのでクリアしておく。
    def applyGather(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State} =
        GameLogger.playerLog("集合");
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
                // 拾う主体の持ち物が満杯なら、床アイテムを取らずにポップアップだけ出す
                // （ドラフト記録も床撤去もしないので、アイテムは床に残る）。
                if (isPickerInventoryFull(info#playerId))
                    ItemPickupPopupScene.showFull(scene)
                else {
                    // 通常モード(退避中の味方が居ない)では拾得を SelectedPlayer の picked に
                    // ドラフト記録し、選択解除キャンセル(cancelSelection)で床へ巻き戻せるようにする。
                    // ローグ移動モードは選択が無く巻き戻し対象外なので即取得のまま。
                    let recorded =
                        if (List.isEmpty(PlayerScene.hiddenAllies(scene)))
                            recordPickupDraft(info, scene)
                        else scene;
                    pickupAt(info, recorded)
                }
        }

    /// 拾う主体 (playerId) の持ち物が満杯か。PartyQuery で現フレームの Data を読む。
    /// 見つからなければ満杯ではない扱い（防御的）。
    def isPickerInventoryFull(playerId: Int32): Bool \ PlayerScene.PartyQuery =
        match PlayerScene.PartyQuery.get(playerId) {
            case Some(player) => PlayerScene.isInventoryFull(player)
            case None         => false
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
                PlayerScene.addWeapon(playerId, weapon, scene)
                    |> ItemPickupPopupScene.show(weapon#name)
            case ItemScene.GroundItemKind.StaffItem(staff) =>
                GameLogger.playerLog("P${playerId} が ${staff#name} を拾った");
                PlayerScene.addStaff(playerId, staff, scene)
                    |> ItemPickupPopupScene.show(staff#name)
            case ItemScene.GroundItemKind.ConsumableItem(item) =>
                GameLogger.playerLog("P${playerId} が ${item#name} を拾った");
                PlayerScene.addConsumable(playerId, item, scene)
                    |> ItemPickupPopupScene.show(item#name)
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
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case Some(entry) => onActionConfirmed(entry, scene)
            case None        => scene
        }
}
