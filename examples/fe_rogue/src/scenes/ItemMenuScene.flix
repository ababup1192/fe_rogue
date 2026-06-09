/// ItemMenuScene — アイテム選択ウィンドウ（武器 + 杖の統合インベントリ）
///
/// ActionMenu「アイテム」確定で `ItemSelect` フェーズに入り、選択中プレイヤーの
/// `weapons` と `staves` を 1 つの ItemList にまとめて並べる。↑↓ で選択、Enter
/// で確定すると `ItemActionSelect` フェーズに進み、同じ ItemList を「使う / 装備 /
/// 捨てる」のサブメニューに差し替える。
///
/// 表示するサブメニュー項目は選択中アイテムの種別で出し分ける:
///   - 武器: `[装備, 捨てる]`
///   - 杖  : `[使う, 捨てる]`
///
/// 「使う」だけがターン消費アクション（杖発動 → 通常ターン進行）。
/// 「装備」「捨てる」はターン消費せず、ItemMenu に戻って続けて操作できる。
///
/// ノード構造（visible のとき）:
///   ItemMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.ItemPanel)
///           └─ menu (ItemList, NodeTag.ItemMenu)
mod ItemMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// サブメニューの操作メタ。`onItemConfirmed` がこの値で分岐する。
    def equipMeta(): String = "equip"
    def dropMeta():  String = "drop"
    def useMeta():   String = "use"

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// scene.json 相対パス。プロジェクトルートから読まれる。
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/ItemMenuScene.scene.json")

    /// fontManifest で登録した name と一致させる（WeaponMenuScene と同じ "ui"）。
    def fontName(): String = "ui"

    /// CanvasLayer ルート名
    def rootName(): String = "ItemMenu"

    /// Panel 子ノード名
    pub def panelName(): String = "panel"

    /// ItemList 子ノード名
    pub def menuName(): String = "menu"

    /// ページ表示ラベル（"1/2" など）の子ノード名。1 ページしか無いときは非表示。
    def pageLabelName(): String = "pageLabel"

    pub def rootPath():  NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath():  NodePath = rootName() :: panelName() :: menuName() :: Nil
    def pageLabelPath(): NodePath = rootName() :: panelName() :: pageLabelName() :: Nil

    /// 1 ページに並べる持ち物の最大数（アイテム window の表示行数と一致）。
    /// ロード職は 16 個持てるので 2 ページに分かれる。それ以外は 8 個＝1 ページに収まる。
    def itemsPerPage(): Int32 = 8

    /// 武器アイコンの表示サイズ（px）。fontSize 4 / itemHeight 6 の中に収まるよう 5px。
    def iconSize(): Float64 = 5.0

    /// アイコンとテキスト名の間の余白（px）
    def iconTextGap(): Float64 = 1.0

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ItemPanel")     => Ok(NodeTag.ItemPanel)
            case Some("ItemMenu")      => Ok(NodeTag.ItemMenu(0))
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"ItemMenuScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// scene に ItemMenu ノードツリーを追加する。
    /// `loadSceneWithFont` は ItemList を含むので FontAtlas 必須。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「アイテムメニューが現在 visible か」のヘルパー。
    /// gameLoop の Escape→quit 判定で「メニュー表示中は Escape を quit に流さない」用途。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用（Push モデル）。
    /// `ItemSelect` / `ItemActionSelect` / `PlayerAttack`（攻撃中の武器選択リスト）で
    /// visible + focused、それ以外のフェーズでは hidden。
    /// PlayerAttack でも focused にするのは、武器リストの上下移動 (engine の ItemList ナビ)
    /// とカーソルglyph を有効にするため。Enter/Escape は MenuHandler 側で PlayerAttack 時
    /// no-op なので、実際の攻撃確定/取消 (Z/X) と干渉しない。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.ItemSelect
                    or phase == TurnPhase.Phase.ItemActionSelect
                    or phase == TurnPhase.Phase.PlayerAttack;
        // ページ表示は ItemSelect のときだけ意味を持つ（サブメニュー/攻撃中は隠す）。
        // ItemSelect 中の実際の表示/文言は refreshItemList が総ページ数を見て設定する。
        let pageLabelVisible = visible and phase == TurnPhase.Phase.ItemSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))
            |> Label2D.mapAt(pageLabelPath(), label ->
                if (pageLabelVisible) label else CanvasItem.setVisible(false, label))

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ItemMenu の ItemList
    /// ノードに対して dispatch される (per-node、ItemList は 1 個のみなので 1 フレーム 1 回)。
    /// 責務:
    ///   1. Panel + ItemList の visible/focused を毎フレーム phase で再評価
    ///   2. `ItemSelect` フェーズなら weapons + staves を items + icons に同期
    ///   3. `ItemActionSelect` フェーズなら選択中アイテムに応じてサブメニュー項目を組む
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = match phase {
            case TurnPhase.Phase.ItemSelect =>
                refreshItemList(withVisibility)
            case TurnPhase.Phase.ItemActionSelect =>
                refreshActionList(withVisibility)
            case TurnPhase.Phase.PlayerAttack =>
                refreshAttackWeaponList(withVisibility)
            // メニューが閉じている間はカーソルとページを先頭(0)に戻しておく。これで次に
            // ItemSelect を開いたときは記憶位置ではなく常に 1 ページ目の最初の項目から始まる。
            // 表示中のフェーズではリセットしないので ↑↓ のカーソル移動・←→ のページ送りは維持される。
            case _ => setMenuPage(0, withVisibility)
        };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    // ── ページング（ロード職は 16 個 = 2 ページ持てる）──

    /// アイテム total 個を 1 ページ itemsPerPage 件で割ったときの総ページ数（最低 1）。
    pub def totalPages(count: Int32): Int32 =
        if (count <= 0) 1
        else (count + itemsPerPage() - 1) / itemsPerPage()

    /// ページ番号を有効範囲 [0, 総ページ数 - 1] に収める。
    def clampPage(page: Int32, count: Int32): Int32 =
        Int32.max(0, Int32.min(page, totalPages(count) - 1))

    /// ItemMenu ノードに積んである現在ページ番号。未設定なら 0。
    def getMenuPage(scene: Scene[NodeTag]): Int32 =
        match Scene.getState(menuPath(), scene) {
            case Some(NodeTag.ItemMenu(page)) => page
            case _                            => 0
        }

    /// 現在ページ番号を ItemMenu ノードに書き戻し、選択カーソルを先頭(0)に戻す。
    def setMenuPage(page: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.setState(menuPath(), NodeTag.ItemMenu(page))
            |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))

    /// 全持ち物（武器 → 杖 → 消費アイテム）の「表示エントリ」と「アイコン用 sprite」を
    /// 並び順を保ったまま組にして返す。metadata は各リスト内の絶対 index（`w:idx` など）の
    /// ままなので、ページで切り出しても確定・装備・破棄ロジックはそのまま動く。
    def itemSpritePairs(weapons: List[UnitCatalog.WeaponResource],
                         staves: List[Staff.StaffResource],
                         consumables: List[Consumable.ConsumableResource]):
            List[(ItemEntry, Sprite.SpriteResource)] =
        let weaponPairs = List.mapWithIndex(idx -> w ->
            (weaponEntry(idx, w), w#sprite), weapons);
        let staffPairs = List.mapWithIndex(idx -> s ->
            (staffEntry(idx, s), s#sprite), staves);
        let consumablePairs = List.mapWithIndex(idx -> c ->
            (consumableEntry(idx, c), c#sprite), consumables);
        List.append(weaponPairs, List.append(staffPairs, consumablePairs))

    /// 全アイテムの組から指定ページ（0 起点）の最大 itemsPerPage 件を取り出し、
    /// ItemList 用の (items, アイコン Map) に変換する。アイコン Map のキーは
    /// 切り出したページ内で 0..件数-1 に振り直す（ItemList は表示行 index でアイコンを引くため）。
    pub def pageSlice(pairs: List[(ItemEntry, Sprite.SpriteResource)], page: Int32):
            (List[ItemEntry], Map[Int32, ItemIcon]) =
        let pageItems = pairs
            |> List.drop(page * itemsPerPage())
            |> List.take(itemsPerPage());
        let items   = List.map(fst, pageItems);
        let sprites = List.map(snd, pageItems);
        (items, rowIcons(sprites))

    /// 選択中プレイヤーの weapons + staves + consumables を ItemList に並べる（ItemSelect 中）。
    /// 順序は「武器（先頭が装備中）→ 杖 → 消費アイテム」。ロード職など 8 個を超える持ち物は
    /// 現在ページぶん（最大 8 件）だけを表示し、`pageLabel` に "現在/総数" を出す。
    def refreshItemList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                let weapons     = PlayerScene.getWeapons(playerId, scene);
                let staves      = PlayerScene.getStaves(playerId, scene);
                let consumables = PlayerScene.getConsumables(playerId, scene);
                let pairs = itemSpritePairs(weapons, staves, consumables);
                let count = List.length(pairs);
                let page  = clampPage(getMenuPage(scene), count);
                let (items, icons) = pageSlice(pairs, page);
                scene
                    |> Scene.setState(menuPath(), NodeTag.ItemMenu(page))
                    |> ItemList.mapAt(menuPath(), list ->
                        list
                            |> ItemList.setItems(items)
                            |> ItemList.setItemIcons(icons)
                            |> ItemList.setIconSize(iconSize())
                            |> ItemList.setIconTextGap(iconTextGap()))
                    |> applyPageLabel(page, count)
        }

    /// `pageLabel` に "現在ページ/総ページ" を表示する。総ページが 1 のときは隠す。
    def applyPageLabel(page: Int32, count: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let pages = totalPages(count);
        let visible = pages > 1;
        scene |> Label2D.mapAt(pageLabelPath(), label ->
            label
                |> Label2D.setText("${page + 1}/${pages}")
                |> CanvasItem.setVisible(visible))

    /// ←（前ページ）。ItemSelect 中の Left / A から呼ばれる。
    pub def pageLeft(scene: Scene[NodeTag]): Scene[NodeTag] \ SelectedPlayer.State =
        changePage(-1, scene)

    /// →（次ページ）。ItemSelect 中の Right / D から呼ばれる。
    pub def pageRight(scene: Scene[NodeTag]): Scene[NodeTag] \ SelectedPlayer.State =
        changePage(1, scene)

    /// 現在ページを `direction`（-1 / +1）ぶん動かす。対象プレイヤーの持ち物総数から
    /// 総ページ数を出して範囲内にクランプするので、端では頭打ち（ループしない）。
    def changePage(direction: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(playerId) =>
                let count = inventoryCount(playerId, scene);
                let next  = clampPage(getMenuPage(scene) + direction, count);
                setMenuPage(next, scene)
        }

    /// 指定プレイヤーの持ち物総数（武器 + 杖 + 消費アイテムの合計）。見つからなければ 0。
    def inventoryCount(playerId: Int32, scene: Scene[NodeTag]): Int32 =
        match PlayerScene.get(playerId, scene) {
            case Some(data) => PlayerScene.itemCount(data)
            case None       => 0
        }

    /// 攻撃中 (PlayerAttack) の武器選択リストを組む。`refreshItemList` と同じ並び
    /// (武器 → 杖 → 消費アイテム) ・アイコンだが、**カーソルが乗っている敵に届く武器だけ
    /// アクティブ (disabled = false)**、それ以外の武器と道具 (杖・消費アイテム) は disabled。
    /// 選択 index は `activeAttackWeaponIndex` で「届く武器」に正規化する (engine の上下移動は
    /// disabled をスキップするので、左右でターゲットが変わって選択が射程外になったときの補正)。
    def refreshAttackWeaponList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                let weapons     = PlayerScene.getWeapons(playerId, scene);
                let staves      = PlayerScene.getStaves(playerId, scene);
                let consumables = PlayerScene.getConsumables(playerId, scene);
                let dist        = cursorTargetDistance(playerId, scene);
                let weaponEntries = List.mapWithIndex(idx -> w ->
                    attackWeaponEntry(idx, w, weaponActiveAt(dist, w)), weapons);
                let staffEntries = List.mapWithIndex(idx -> s ->
                    attackStaffEntry(idx, s), staves);
                let consumableEntries = List.mapWithIndex(idx -> c ->
                    attackConsumableEntry(idx, c), consumables);
                let items = List.append(weaponEntries,
                    List.append(staffEntries, consumableEntries));
                let iconSprites = List.append(List.map(w -> w#sprite, weapons),
                    List.append(List.map(s -> s#sprite, staves),
                                List.map(c -> c#sprite, consumables)));
                let icons = rowIcons(iconSprites);
                let selIdx = activeAttackWeaponIndex(scene) |> Option.getWithDefault(0);
                scene |> ItemList.mapAt(menuPath(), list ->
                    list
                        |> ItemList.setItems(items)
                        |> ItemList.setItemIcons(icons)
                        |> ItemList.setIconSize(iconSize())
                        |> ItemList.setIconTextGap(iconTextGap())
                        |> ItemList.setSelectedIndex(selIdx))
        }

    /// 攻撃中に「選択すべき武器」の index (weapons 内) を返す。真理点として
    /// `BattlePanelScene` (予測) と `refreshAttackWeaponList` (リスト正規化) が共用する。
    /// 現在の選択 index の武器がカーソル上の敵に届けばそのまま、届かなければ届く先頭武器。
    /// カーソルが敵に乗っていない / 届く武器が無いなら None。
    pub def activeAttackWeaponIndex(scene: Scene[NodeTag]): Option[Int32]
            \ SelectedPlayer.State =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerScene.get(playerId, scene);
            d        <- cursorTargetDistance(playerId, scene);
            idx      <- chooseAttackWeaponIdx(player, currentSelectedIndex(scene), d)
        ) yield idx

    /// 現在の選択 index `cur` の武器が距離 `d` に届けば `cur`、でなければ `d` に届く先頭武器。
    def chooseAttackWeaponIdx(player: PlayerScene.Data, cur: Int32, d: Int32): Option[Int32] =
        let curReaches = match List.nth(cur, player#weapons) {
            case Some(w) => Weapon.inRange(d, w#range)
            case None    => false
        };
        if (curReaches) Some(cur)
        else PlayerScene.firstWeaponIdxReaching(player, d)

    /// カーソルが乗っている敵と選択中味方とのマンハッタン距離。敵が居なければ None。
    def cursorTargetDistance(playerId: Int32, scene: Scene[NodeTag]): Option[Int32] =
        forM (
            player <- PlayerScene.get(playerId, scene);
            eid    <- EnemyScene.findIdAt(CursorScene.getGridPos(scene), scene);
            enemy  <- EnemyScene.get(eid, scene)
        ) yield Weapon.manhattan(player#gridPos, enemy#gridPos)

    /// ItemMenu リストの現在の選択 index。未登録なら 0。
    def currentSelectedIndex(scene: Scene[NodeTag]): Int32 =
        ItemList.getAt(menuPath(), scene)
            |> Option.map(ItemList.getSelectedIndex)
            |> Option.getWithDefault(0)

    /// 距離 `dist`（カーソル上の敵）に対し、武器 `w` がアクティブ (射程が届く) か。
    /// 敵に乗っていない (dist = None) ならどの武器も非アクティブ。
    def weaponActiveAt(dist: Option[Int32], w: UnitCatalog.WeaponResource): Bool =
        match dist {
            case Some(d) => Weapon.inRange(d, w#range)
            case None    => false
        }

    /// 攻撃中の武器エントリ。`active = false` で disabled (灰)。表記は `weaponEntry` と同じ。
    def attackWeaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource,
                           active: Bool): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = not active,
        metadata = Some("w:${idx}")
    }

    /// 攻撃中の杖エントリ。武器ではないので常に disabled。
    def attackStaffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = true,
        metadata = Some("s:${idx}")
    }

    /// 攻撃中の消費アイテムエントリ。武器ではないので常に disabled。
    def attackConsumableEntry(idx: Int32, item: Consumable.ConsumableResource): ItemEntry = {
        text     = "${item#name} ${item#durability}",
        disabled = true,
        metadata = Some("c:${idx}")
    }

    /// 「そうび」項目（武器のみ）。
    def equipEntry(): ItemEntry =
        {text = "装備", disabled = false, metadata = Some(equipMeta())}

    /// 「つかう」項目（杖・消費アイテム）。
    def useEntry(): ItemEntry =
        {text = "使う", disabled = false, metadata = Some(useMeta())}

    /// 「すてる」項目（武器・杖・消費アイテム共通）。
    def dropEntry(): ItemEntry =
        {text = "捨てる", disabled = false, metadata = Some(dropMeta())}

    /// サブメニュー項目を組む（ItemActionSelect 中）。
    /// 武器なら `[そうび, すてる]`、杖・消費アイテムなら `[つかう, すてる]`。
    def refreshActionList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                match PlayerScene.get(playerId, scene) {
                    case None         => scene
                    case Some(player) =>
                        let items = match player#selectedItem {
                            case Some(PlayerScene.ItemKind.Weapon(_))     =>
                                equipEntry() :: dropEntry() :: Nil
                            case Some(PlayerScene.ItemKind.Staff(_))      =>
                                useEntry() :: dropEntry() :: Nil
                            case Some(PlayerScene.ItemKind.Consumable(_)) =>
                                useEntry() :: dropEntry() :: Nil
                            case None => Nil
                        };
                        scene |> ItemList.mapAt(menuPath(), list ->
                            list
                                |> ItemList.setItems(items)
                                |> ItemList.setItemIcons(Map.empty())
                                |> ItemList.setIconSize(iconSize())
                                |> ItemList.setIconTextGap(iconTextGap()))
                }
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は `"w:<idx>"` 形式で種別と index を持つ。
    /// 「武器名 残耐久」の表記は WeaponMenuScene と同じ。
    def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。metadata は `"s:<idx>"` 形式。
    def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 消費アイテム 1 個ぶんの ItemEntry。metadata は `"c:<idx>"` 形式。残り使用回数を表示する。
    def consumableEntry(idx: Int32, item: Consumable.ConsumableResource): ItemEntry = {
        text     = "${item#name} ${item#durability}",
        disabled = false,
        metadata = Some("c:${idx}")
    }

    /// SpriteResource から ItemList 用の ItemIcon を作る。
    def spriteIcon(sprite: Sprite.SpriteResource): ItemIcon = {
        texture = sprite#texture,
        hframes = sprite#hframes,
        vframes = sprite#vframes,
        frame   = sprite#frame
    }

    /// 表示順に並んだ sprite 列を「行 index → ItemIcon」の Map にする。
    /// items の並び（武器 → 杖 → 消費アイテム）と同じ順序で渡すこと。
    def rowIcons(sprites: List[Sprite.SpriteResource]): Map[Int32, ItemIcon] =
        List.foldLeft((acc, pair) ->
            let (idx, sprite) = pair;
            Map.insert(idx, spriteIcon(sprite), acc),
            Map.empty(), List.zipWithIndex(sprites))

    /// metadata の `"w:<idx>"` / `"s:<idx>"` を `PlayerScene.ItemKind` にパースする。
    /// 不明形式は `None`。
    pub def parseItemKind(meta: String): Option[PlayerScene.ItemKind] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerScene.ItemKind.Weapon)
        else if (String.startsWith({prefix = "s:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerScene.ItemKind.Staff)
        else if (String.startsWith({prefix = "c:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerScene.ItemKind.Consumable)
        else None

    // ────────────────────────────────────────────────────────
    // (E) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// ActionMenu「アイテム」確定で呼ばれる。`ItemSelect` フェーズに遷移する。
    /// PhaseTransitions が overlay 片付け + カーソル非表示も合わせて行う。
    pub def openFor(_playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        // 常に 1 ページ目から開く。
        setMenuPage(0, PhaseTransitions.enterItemSelect(scene))

    /// ItemSelect で項目を Enter 確定したとき。選択中アイテム種別を Data に書いて
    /// `ItemActionSelect` フェーズに進む（サブメニュー表示へ）。
    pub def onItemConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                            Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata |> Option.flatMap(parseItemKind) {
            case None      => scene
            case Some(kind) =>
                match SelectedPlayer.State.get()#id {
                    case None           => scene
                    case Some(playerId) =>
                        let withItem = PlayerScene.setSelectedItem(playerId, kind, scene);
                        TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
                        // サブメニューは常に先頭（「そうび」/「つかう」）から始める。
                        // ItemSelect での選択位置を引き継いで「すてる」に当たるのを防ぐ。
                        withItem |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
                }
        }

    /// ItemSelect で X / Escape 押下: ActionMenu に戻る（= ActionSelect フェーズ）。
    pub def onItemCancelled(scene: Scene[NodeTag]):
                            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        // 閉じる時にページを 1 ページ目へ戻す（次に開いたとき先頭から始まるように）。
        setMenuPage(0, scene)

    /// ItemActionSelect でサブメニュー項目を Enter 確定したとき。
    ///   - 装備: weapons リスト先頭に移動、ItemSelect に戻る（ターン消費なし）
    ///   - 捨てる: 該当アイテム削除、ItemSelect に戻る（ターン消費なし）
    ///   - 使う: 杖の場合のみ。StaffAim フェーズへ（方向選択を待つ）
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State,
                GameEngine.Audio} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                match SelectedPlayer.State.get()#id {
                    case None           => scene
                    case Some(playerId) =>
                        match PlayerScene.get(playerId, scene) {
                            case None         => scene
                            case Some(player) =>
                                match player#selectedItem {
                                    case None       => scene
                                    case Some(kind) =>
                                        dispatchAction(m, playerId, kind, scene)
                                }
                        }
                }
        }

    /// サブメニューの metadata 別に処理を分配する。
    def dispatchAction(meta: String, playerId: Int32, kind: PlayerScene.ItemKind,
                        scene: Scene[NodeTag]):
                       Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State,
                GameEngine.Audio} =
        if (meta == equipMeta())
            applyEquip(playerId, kind, scene)
        else if (meta == dropMeta())
            applyDrop(playerId, kind, scene)
        else if (meta == useMeta())
            applyUse(playerId, kind, scene)
        else scene

    /// 「そうび」: 武器の場合のみ実行（杖は装備という概念がないので no-op）。
    /// `equipWeapon` で対象武器を weapons の先頭に移動 → `ItemSelect` フェーズに戻る。
    def applyEquip(playerId: Int32, kind: PlayerScene.ItemKind,
                     scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        let equipped = match kind {
            case PlayerScene.ItemKind.Weapon(idx)   =>
                // 実際に並びが変わるとき (0 < idx < 本数) だけ巻き戻しドラフトを積む。
                // idx=0 / 範囲外は equipWeapon が no-op なので積まない（誤巻き戻し防止）。
                let n = List.length(PlayerScene.getWeapons(playerId, scene));
                if (idx >= 1 and idx < n)
                    SelectedPlayer.pushDraft(MoveDraft.DraftAction.Equipped(playerId, idx))
                else ();
                PlayerScene.equipWeapon(playerId, idx, scene)
            case PlayerScene.ItemKind.Staff(_)      => scene
            case PlayerScene.ItemKind.Consumable(_) => scene
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, equipped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「すてる」: 武器なら `dropWeapon`、杖なら `dropStaff`。
    /// ターン消費せず ItemSelect に戻る（連続して捨てられる）。
    def applyDrop(playerId: Int32, kind: PlayerScene.ItemKind,
                    scene: Scene[NodeTag]):
                   Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                                     SelectedPlayer.State} =
        // 捨てる前に実体を取り、巻き戻し用に Dropped(元 idx, 実体) を積んでから削除する。
        // 該当アイテムが無ければ no-op。
        let dropped = match kind {
            case PlayerScene.ItemKind.Weapon(idx) =>
                match List.nth(idx, PlayerScene.getWeapons(playerId, scene)) {
                    case None    => scene
                    case Some(w) =>
                        GameLogger.playerLog("P${playerId} は ${w#name} をすてた");
                        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(
                            playerId, kind, ItemScene.GroundItemKind.WeaponItem(w)));
                        PlayerScene.dropWeapon(playerId, idx, scene)
                }
            case PlayerScene.ItemKind.Staff(idx) =>
                match List.nth(idx, PlayerScene.getStaves(playerId, scene)) {
                    case None    => scene
                    case Some(s) =>
                        GameLogger.playerLog("P${playerId} は ${s#name} をすてた");
                        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(
                            playerId, kind, ItemScene.GroundItemKind.StaffItem(s)));
                        PlayerScene.dropStaff(playerId, idx, scene)
                }
            case PlayerScene.ItemKind.Consumable(idx) =>
                match List.nth(idx, PlayerScene.getConsumables(playerId, scene)) {
                    case None    => scene
                    case Some(c) =>
                        GameLogger.playerLog("P${playerId} は ${c#name} をすてた");
                        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(
                            playerId, kind, ItemScene.GroundItemKind.ConsumableItem(c)));
                        PlayerScene.dropConsumable(playerId, idx, scene)
                }
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, dropped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「つかう」: 杖の場合のみ実行（武器の場合は「装備」項目が出るのでここには来ない）。
    /// 杖の発動方向選択フェーズ `StaffAim` に進み、ログに方向キーの操作プロンプトを出す。
    /// selectedItem は保持しておき、`StaffAim` 中の方向入力で
    /// `PlayerScene.applyStaffCast` が読む。
    def applyUse(playerId: Int32, kind: PlayerScene.ItemKind,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, GameLogger.GameLogger,
                GameEngine.Audio} =
        match kind {
            case PlayerScene.ItemKind.Staff(idx) =>
                let name = staffNameOf(playerId, idx, scene);
                GameLogger.playerLog("P${playerId} は ${name} の方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim(scene)
            // 消費アイテムは方向選択不要。その場で使用者を回復しターンを消費する。
            case PlayerScene.ItemKind.Consumable(idx) =>
                PlayerScene.applyConsumableUse(playerId, idx, scene)
            case PlayerScene.ItemKind.Weapon(_) => scene
        }

    /// 指定プレイヤーの staves[idx] の名前を返す。範囲外なら "つえ" フォールバック。
    def staffNameOf(playerId: Int32, idx: Int32, scene: Scene[NodeTag]): String =
        match List.nth(idx, PlayerScene.getStaves(playerId, scene)) {
            case Some(staff) => staff#name
            case None        => "杖"
        }

    /// ItemActionSelect で X / Escape 押下: ItemSelect に戻る（アイテム一覧画面）。
    /// 選択中アイテムをクリアしてサブメニューを抜ける。
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        let cleared = match SelectedPlayer.State.get()#id {
            case Some(playerId) => PlayerScene.clearSelectedItem(playerId, scene)
            case None           => scene
        };
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// InputHandler の Z 押下から呼ばれる。現在のフェーズに応じて
    /// ItemSelect の Enter なら `onItemConfirmed`、ItemActionSelect の Enter なら
    /// `onActionConfirmed` に流す（共通エントリ）。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State,
                GameEngine.Audio} =
        let phase = TurnPhase.State.get();
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) =>
                match phase {
                    case TurnPhase.Phase.ItemSelect       => onItemConfirmed(entry, scene)
                    case TurnPhase.Phase.ItemActionSelect => onActionConfirmed(entry, scene)
                    case _                                 => scene
                }
        }
}
