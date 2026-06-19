/// WeaponSelectScene — 武器選択ウィンドウ（攻撃フローの武器持ち替え）
///
/// ActionMenu「攻撃」確定で `WeaponSelect` フェーズに入り、ActionMenu の **右隣に少し重ねて**
/// 出る ItemList。コマンドメニュー (ActionMenu) は表示したまま「攻撃」行のハイライトを残し、
/// focus だけこの武器ウィンドウに移る（`ActionMenuScene.applyVisibility` が担う）。
///
/// 各行（ActionMenu と同じパネル/配色のコマンドメニュー風）:
///   - 左          : 武器タイプのアイコン（武器 sprite。ItemMenuScene の rowIcons と同方式）
///   - 1 行目       : 武器名。右端のバッジ「不得意」は、その武器タイプを **苦手** とするときだけ出す
///                    （得意なら何も出さない＝「得意」バッジは出さない）。
///   - 2 行目(subline): 性能「威力 ${攻} 耐久 ${耐久}」（命中・射程は戦闘予報ミニ窓で見せる）
///
/// 操作:
///   - ↑↓ で武器を選び Enter/Z で確定 → 選んだ武器を装備 (weapons 先頭へ移動) してから
///     既存の攻撃フロア (`PlayerScene.enterAttackPhase`) に入る（赤マス→敵選択→予報→攻撃）。
///   - X/Escape でウィンドウを閉じて ActionSelect（コマンドメニュー）に戻る。
///
/// ノード構造（visible のとき）:
///   WeaponSelect (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.WeaponSelectPanel)
///           └─ menu (ItemList, NodeTag.WeaponSelectMenu)
mod WeaponSelectScene {

    use JsonCompat.PathTag.Root

    // ────────────────────────────────────────────────────────
    // (A) 定数・パス
    // ────────────────────────────────────────────────────────

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/WeaponSelectScene.scene.json")

    /// 全 ItemList 系で共通の "ui" フォント。
    def fontName(): String = "ui"

    def rootName(): String = "WeaponSelect"
    pub def panelName(): String = "panel"
    pub def menuName(): String = "menu"
    def headerName(): String = "header"
    def headerBgName(): String = "headerBg"
    /// 見出し帯の底面の角丸を塗りつぶす重ね板（ActionMenuScene と同作法・「上だけ丸／底面四角」）。
    def headerBgFillName(): String = "headerBgFill"
    def hintName(): String = "hint"

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil
    def headerPath(): NodePath = rootName() :: panelName() :: headerName() :: Nil
    def headerBgPath(): NodePath = rootName() :: panelName() :: headerBgName() :: Nil
    def headerBgFillPath(): NodePath = rootName() :: panelName() :: headerBgFillName() :: Nil
    def hintPath(): NodePath = rootName() :: panelName() :: hintName() :: Nil

    /// 武器アイコンの表示サイズ（px）。ItemMenuScene と揃える。
    def iconSize(): Float64 = 5.0
    /// アイコンと名前テキストの間の余白（px）。色紙チップ（iconBgPad ぶん外側に出る）に
    /// テキストが被らないよう、pad より広めに取る。
    def iconTextGap(): Float64 = 3.0

    /// 不得意（苦手）な武器の行に出すバッジ文字。得意な武器には付けない。
    def weakBadge(): String = "不得意"

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                       => Ok(NodeTag.NoTag)
            case Some("NoTag")              => Ok(NodeTag.NoTag)
            case Some("WeaponSelectPanel")  => Ok(NodeTag.WeaponSelectPanel)
            case Some("WeaponSelectMenu")   => Ok(NodeTag.WeaponSelectMenu)
            case Some(unknown)              =>
                Err(JsonCompat.jsonError(Root, Set#{"WeaponSelectScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (B) 構築
    // ────────────────────────────────────────────────────────

    /// scene に WeaponSelect ノードツリーを追加する。ItemList を含むため FontAtlas が要る。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「武器選択ウィンドウが現在 visible か」のヘルパー。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    // ────────────────────────────────────────────────────────
    // (C) 表示・ロジック
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用。
    ///   - Panel / header : WeaponSelect フェーズだけ visible（コマンドメニュー横の武器リスト窓）
    ///   - Menu           : WeaponSelect フェーズだけ visible + focused
    /// 命中/必殺/すくみは盤面の戦闘予報ミニウィンドウ `BattlePanelScene` が併せて出す。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.WeaponSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> Panel.mapAt(headerBgPath(), CanvasItem.setVisible(visible))
            |> Panel.mapAt(headerBgFillPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(headerPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(hintPath(), CanvasItem.setVisible(visible))  // ↔ 敵選択 ヒント
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))

    /// WeaponSelect 中、カーソルが乗っている武器の weapons 内 index（`BattlePanelScene` が読む）。
    /// 選択行の metadata `"w:<idx>"` をパースして返す。未登録 / 無選択なら None。
    pub def hoveredWeaponIndex(scene: Scene[NodeTag]): Option[Int32] =
        ItemList.getAt(menuPath(), scene)
            |> Option.flatMap(ItemList.getSelected)
            |> Option.flatMap(e -> e#metadata)
            |> Option.flatMap(parseWeaponIndex)

    /// Game.flix の process dispatch から WeaponSelectMenu の ItemList に対して毎フレーム呼ばれる。
    /// visibility 更新と items 再計算を同一フレームで行う（ActionMenuScene と同じ理由）。
    /// WeaponSelect 中は選択中味方の武器一覧を組み、それ以外のフェーズではカーソルを先頭(0)に戻す。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                           SelectedPlayer.State, TurnPhase.State, PlayerData.PartyQuery,
                           EnemyData.RosterQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        // UX: 閉じている間はカーソルを先頭(0)に戻し、次に開いたとき常に 1 本目の武器から始める。
        let withItems = if (phase != TurnPhase.Phase.WeaponSelect)
                withVisibility
                    |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
            else
                refreshWeaponList(withVisibility)
                    |> positionBesideActionMenu
                    |> snapCursorToTarget;   // 武器フォーカス中、対象の敵へカーソルを寄せる
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// WeaponSelect 中、カーソルを「フォーカス武器が届く敵」の上に置いてカーソルを表示する。
    /// 既に届く敵に乗っているならその位置を保つ（左右での敵選択を維持。`CursorScene` が巡回する）。
    /// 乗っていない（初回 / 武器を切り替えて今の対象が届かなくなった）ときだけ最寄りの敵へスナップ。
    /// 届く敵が居なければカーソルは触らない。戦闘予報はこのカーソル上の敵で出る。
    def snapCursorToTarget(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                              SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
        match focusedPlayerWeapon(scene) {
            case None                  => scene
            case Some((player, weapon)) =>
                if (isReachableEnemyCell(CursorScene.getGridPos(scene), player#gridPos, weapon, scene))
                    CursorScene.setVisible(true, scene)   // 既に対象上 → 位置は保持（左右選択を維持）
                else match nearestReachableEnemy(player#gridPos, weapon) {
                    case Some(e) => scene |> CursorScene.setVisible(true) |> CursorScene.snapToCell(e#gridPos)
                    case None    => scene
                }
        }

    /// 選択中味方とフォーカス中の武器。揃わなければ None。
    def focusedPlayerWeapon(scene: Scene[NodeTag]):
            Option[(PlayerScene.Data, UnitCatalog.WeaponResource)]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            player <- selectedPlayer();
            widx   <- hoveredWeaponIndex(scene);
            weapon <- List.nth(widx, player#weapons)
        ) yield (player, weapon)

    /// `cell` に居る敵が `weapon` の射程内の生存敵か（カーソルが有効な対象に乗っているかの判定）。
    def isReachableEnemyCell(cell: {x = Int32, y = Int32}, pos: {x = Int32, y = Int32},
                             weapon: UnitCatalog.WeaponResource, scene: Scene[NodeTag]): Bool =
        EnemyScene.findIdAt(cell, scene)
            |> Option.flatMap(id -> EnemyScene.get(id, scene))
            |> Option.map(e -> {
                let ev = EnemyScene.unitView(e);
                ev#hp > 0 and not ev#isDying
                    and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
            })
            |> Option.getWithDefault(false)

    /// `pos` から `weapon` の射程内に居る生存敵のうち、最も近い 1 体（マンハッタン最小）。
    /// 届く敵が居なければ None。`weaponReachesAnyEnemy` と同じ到達判定で個体を選ぶ版。
    def nearestReachableEnemy(pos: {x = Int32, y = Int32},
                              weapon: UnitCatalog.WeaponResource):
            Option[EnemyScene.Data] \ EnemyData.RosterQuery =
        EnemyData.RosterQuery.getAll()
            |> List.filter(e -> {
                let ev = EnemyScene.unitView(e);
                ev#hp > 0 and not ev#isDying
                    and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
            })
            |> List.sortBy(e -> Weapon.manhattan(pos, e#gridPos))
            |> List.head

    /// コマンドメニュー (ActionMenu) に重ねる px 量。右端から少しだけ食い込ませて
    /// 「攻撃」を選んでいる文脈を見せつつ、深く被って読みづらくならないようにする。
    def panelOverlapPx(): Float64 = 5.0

    /// 武器ウィンドウを ActionMenu（コマンドメニュー）の右端基準で配置する。
    /// ActionMenu の幅は項目に合わせて毎フレーム可変なので、その右端を読んで追従し、
    /// `panelOverlapPx()` だけ左に食い込ませる（y は scene.json の値を保つ）。
    def positionBesideActionMenu(scene: Scene[NodeTag]): Scene[NodeTag] =
        match Panel.getAt(ActionMenuScene.panelPath(), scene) {
            case None         => scene
            case Some(action) =>
                let actionRight = Node2D.getPosition(action)#x + Panel.getSize(action)#x;
                let newX = actionRight - panelOverlapPx();
                scene |> Panel.mapAt(panelPath(), p ->
                    Node2D.setPosition({x = newX, y = Node2D.getPosition(p)#y}, p))
        }

    /// 選択中味方の武器を ItemList に並べる（WeaponSelect 中）。
    /// 行テキスト = 武器名、subline = 性能、badge = 不得意のときだけ、icon = 武器 sprite。
    /// **その武器の射程内に生きている敵が居ない行は disabled**（淡色 + カーソルがスキップ + 確定不可）。
    /// 例: 弓と剣を持ち、弓でしか届かない敵を狙うとき、剣の行は選べない。
    /// 非 driver だが敵 read は ActionMenuScene.canAttackFrom と同じく `EnemyData.RosterQuery` 経由。
    def refreshWeaponList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
        match selectedPlayer() {
            case None         => scene
            case Some(player) =>
                let enemies  = EnemyData.RosterQuery.getAll();
                let weapons  = player#weapons;
                let items    = List.mapWithIndex(idx -> w ->
                    weaponEntry(idx, w,
                        not weaponReachesAnyEnemy(player#gridPos, w, enemies)), weapons);
                let sublines = weaponSublines(weapons);
                let badges   = weaponBadges(player#resource, weapons);
                let icons    = rowIcons(List.map(w -> w#sprite, weapons));
                let firstEnabled = firstEnabledIndex(items);
                scene |> ItemList.mapAt(menuPath(), list -> {
                    let withItems = list
                        |> ItemList.setItems(items)
                        |> ItemList.setItemSublines(sublines)
                        |> ItemList.setItemBadges(badges)
                        |> ItemList.setItemIcons(icons)
                        |> ItemList.setIconSize(iconSize())
                        |> ItemList.setIconTextGap(iconTextGap());
                    // カーソルが届かない武器(disabled)に乗っていたら、選択可能な先頭武器へ寄せる。
                    if (selectedIsDisabled(items, withItems))
                        ItemList.setSelectedIndex(firstEnabled, withItems)
                    else withItems
                })
        }

    /// 指定位置から `weapon` の射程内に生きている敵 (hp > 0 かつ not isDying) が居るか。
    /// ActionMenuScene.weaponReachesAnyEnemy と同じ判定（攻撃可否＝届く武器があるか、を行単位に分解）。
    pub def weaponReachesAnyEnemy(pos: {x = Int32, y = Int32},
                               weapon: UnitCatalog.WeaponResource,
                               enemies: List[EnemyScene.Data]): Bool =
        List.exists(e -> {
            let ev = EnemyScene.unitView(e);
            ev#hp > 0 and not ev#isDying
                and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
        }, enemies)

    /// items の最初の「選択可能（not disabled）」行 index。全部 disabled なら 0。
    def firstEnabledIndex(items: List[ItemEntry]): Int32 =
        items
            |> List.zipWithIndex
            |> List.findLeft(pair -> not snd(pair)#disabled)
            |> Option.map(fst)
            |> Option.getWithDefault(0)

    /// 現在カーソルが乗っている行が disabled か（範囲外なら false）。
    def selectedIsDisabled(items: List[ItemEntry], list: ItemList): Bool =
        match List.nth(ItemList.getSelectedIndex(list), items) {
            case Some(e) => e#disabled
            case None    => false
        }

    /// 選択中味方の Data（PartyQuery 経由）。未選択 / 見つからなければ None。
    def selectedPlayer(): Option[PlayerScene.Data]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            id     <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(id)
        ) yield player

    /// 武器 1 本ぶんの ItemEntry。1 行目は武器名のみ（性能は subline、不得意は badge）。
    /// `disabled` はその武器の射程内に敵が居ないとき true（淡色・選択不可）。
    /// metadata は `"w:<idx>"` 形式で、確定時に weapons 内 index を引くために持つ。
    def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource, disabled: Bool): ItemEntry = {
        text     = weapon#name,
        disabled = disabled,
        metadata = Some("w:${idx}")
    }

    /// 武器の射程表記。min == max なら「射程 ${min}」、違えば「射程 ${min}-${max}」。
    /// ItemMenuScene.weaponStatLine の rangeText ロジックを 2 行目用に流用する。
    pub def rangeText(range: WeaponCatalog.WeaponRange): String =
        if (range#min == range#max) "射程 ${range#min}"
        else "射程 ${range#min}-${range#max}"

    /// 武器 1 本ぶんの 2 行目（性能）。残り使用回数を含む。
    /// 命中・射程は戦闘予報ミニウィンドウで見せるのでここでは省く（窓を狭めるため）。
    /// 例: "威力 2 耐久 10"
    pub def weaponSubline(weapon: UnitCatalog.WeaponResource): String =
        "威力 ${weapon#attack} 耐久 ${weapon#durability}"

    /// 行 index → subline 文字列の Map（全行ぶん）。
    def weaponSublines(weapons: List[UnitCatalog.WeaponResource]): Map[Int32, String] =
        List.foldLeft((acc, pair) ->
            let (idx, w) = pair;
            Map.insert(idx, weaponSubline(w), acc),
            Map.empty(), List.zipWithIndex(weapons))

    /// 行 index → バッジ文字の Map。**苦手な武器の行だけ**「不得意」を入れる
    /// （得意な武器はキー自体を入れない＝バッジ非表示）。`UnitCatalog.proficientWith` で判定。
    pub def weaponBadges(resource: UnitCatalog.PlayerResource,
                          weapons: List[UnitCatalog.WeaponResource]): Map[Int32, String] =
        List.foldLeft((acc, pair) ->
            let (idx, w) = pair;
            if (UnitCatalog.proficientWith(resource, w#weaponType)) acc
            else Map.insert(idx, weakBadge(), acc),
            Map.empty(), List.zipWithIndex(weapons))

    /// SpriteResource から ItemList 用の ItemIcon を作る（ItemMenuScene.spriteIcon と同形）。
    def spriteIcon(sprite: Sprite.SpriteResource): ItemIcon = {
        texture = sprite#texture,
        hframes = sprite#hframes,
        vframes = sprite#vframes,
        frame   = sprite#frame
    }

    /// 表示順に並んだ sprite 列を「行 index → ItemIcon」の Map にする。
    def rowIcons(sprites: List[Sprite.SpriteResource]): Map[Int32, ItemIcon] =
        List.foldLeft((acc, pair) ->
            let (idx, sprite) = pair;
            Map.insert(idx, spriteIcon(sprite), acc),
            Map.empty(), List.zipWithIndex(sprites))

    /// metadata の `"w:<idx>"` を weapons 内 index にパースする。不明形式は None。
    pub def parseWeaponIndex(meta: String): Option[Int32] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
        else None

    // ────────────────────────────────────────────────────────
    // (D) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// 武器を Enter/Z で確定したとき。**選んだ武器を装備して、カーソルが指している敵に
    /// そのまま攻撃を開始する**（武器フォーカスで対象も選べるので、ここから別の対象選択
    /// フェーズには進まず直接バトルへ）。遷移先は入力ロックの `PlayerAttackHold`。
    /// カーソルが敵に乗っていない（届く敵が無い）ときは何もしない。
    pub def onConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                        Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, GameLogger.GameLogger,
                TurnPhase.State, SelectedPlayer.State, EnemyData.RosterQuery} =
        let started = forM (
            pid   <- SelectedPlayer.State.get()#id;
            idx   <- entry#metadata |> Option.flatMap(parseWeaponIndex);
            eid   <- EnemyScene.findIdAt(CursorScene.getGridPos(scene), scene);
            enemy <- EnemyData.RosterQuery.get(eid)
        ) yield {
            let equipped = PlayerScene.equipWeapon(pid, idx, scene);
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("${PlayerScene.displayName(pid, equipped)}の攻撃");
            CombatScene.startAttack(Faction.Player, pid, eid, enemy#gridPos, equipped)
        };
        Option.getWithDefault(scene, started)

    /// X / Escape 押下で呼ばれる。武器ウィンドウを閉じて ActionSelect（コマンドメニュー）に戻る。
    /// SelectedPlayer はそのまま（同じ味方の行動選択に戻る）。WeaponSelect 中に対象の敵へ出して
    /// いたカーソルは隠す（ActionSelect / PlayerMoving はカーソル非表示が既定）。
    pub def onCancelled(scene: Scene[NodeTag]):
                        Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        CursorScene.setVisible(false, scene)

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある武器を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, GameLogger.GameLogger,
                TurnPhase.State, SelectedPlayer.State, EnemyData.RosterQuery} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) => if (entry#disabled) scene else onConfirmed(entry, scene)
        }
}
