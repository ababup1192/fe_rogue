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
///   - 2 行目(subline): 性能「威力 ${攻} 命中 ${命} 射程 ${range} 耐久 ${耐久}」
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

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil
    def headerPath(): NodePath = rootName() :: panelName() :: headerName() :: Nil
    def headerBgPath(): NodePath = rootName() :: panelName() :: headerBgName() :: Nil

    /// 武器アイコンの表示サイズ（px）。ItemMenuScene と揃える。
    def iconSize(): Float64 = 5.0
    /// アイコンと名前テキストの間の余白（px）。
    def iconTextGap(): Float64 = 1.0

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
    ///   - Panel / header : WeaponSelect フェーズだけ visible
    ///   - Menu           : WeaponSelect フェーズだけ visible + focused
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.WeaponSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> Panel.mapAt(headerBgPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(headerPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))

    /// Game.flix の process dispatch から WeaponSelectMenu の ItemList に対して毎フレーム呼ばれる。
    /// visibility 更新と items 再計算を同一フレームで行う（ActionMenuScene と同じ理由）。
    /// WeaponSelect 中は選択中味方の武器一覧を組み、それ以外のフェーズではカーソルを先頭(0)に戻す。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State, PlayerData.PartyQuery,
                           EnemyData.RosterQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        // UX: 閉じている間はカーソルを先頭(0)に戻し、次に開いたとき常に 1 本目の武器から始める。
        let withItems = if (phase != TurnPhase.Phase.WeaponSelect)
                withVisibility
                    |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
            else
                refreshWeaponList(withVisibility);
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
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
    /// 例: "威力 2 命中 80 射程 1 耐久 10"
    pub def weaponSubline(weapon: UnitCatalog.WeaponResource): String =
        "威力 ${weapon#attack} 命中 ${weapon#hit} ${rangeText(weapon#range)} 耐久 ${weapon#durability}"

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

    /// 武器を Enter/Z で確定したとき。選んだ武器を装備 (weapons 先頭へ移動) してから
    /// 既存の攻撃フェーズ (`PlayerScene.enterAttackPhase`) に入る。
    /// `enterAttackPhase` はカーソル上の敵に届く武器へさらに持ち替えうるが、ここで先頭に置いた
    /// 武器が届くならそのまま使われる（届かなければ届く武器に正規化される＝既存仕様どおり）。
    pub def onConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                        Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                TurnPhase.State, SelectedPlayer.State,
                PlayerData.PartyQuery, EnemyData.RosterQuery} =
        let equipped = forM (
            playerId <- SelectedPlayer.State.get()#id;
            idx      <- entry#metadata |> Option.flatMap(parseWeaponIndex)
        ) yield PlayerScene.equipWeapon(playerId, idx, scene);
        let withEquip = Option.getWithDefault(scene, equipped);
        PlayerScene.enterAttackPhase(withEquip)

    /// X / Escape 押下で呼ばれる。武器ウィンドウを閉じて ActionSelect（コマンドメニュー）に戻る。
    /// SelectedPlayer はそのまま（同じ味方の行動選択に戻る）。
    pub def onCancelled(scene: Scene[NodeTag]):
                        Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある武器を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                TurnPhase.State, SelectedPlayer.State,
                PlayerData.PartyQuery, EnemyData.RosterQuery} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) => if (entry#disabled) scene else onConfirmed(entry, scene)
        }
}
