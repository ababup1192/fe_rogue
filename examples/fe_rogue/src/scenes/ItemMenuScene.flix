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

    use JsonCompat.PathTag.Root

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// サブメニューの操作メタ。`onItemConfirmed` / `dispatchAction` がこの値で分岐する。
    /// Flix では型レベルの enum 定数より関数として定義する慣習のため、String リテラル直書きでなく
    /// ここに集約している（タイポを一か所で検知できる）。
    def equipMeta(): String = "equip"
    def dropMeta():  String = "drop"
    def useMeta():   String = "use"

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// scene.json 相対パス。プロジェクトルートから読まれる。
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/ItemMenuScene.scene.json")

    /// fontManifest で登録した name と一致させる。フォントは全 ItemList 系で共通の "ui" を使う。
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

    /// 詳細ウィンドウ（アイテムパネルの右隣）。選択中アイテムの性能と一言説明を出す。
    /// Panel "detail" の直下に「名前 / 性能 / 説明」の 3 ラベルを置く構造。
    def detailName():       String = "detail"
    def detailIconNode():   String = "detailIcon"
    def detailNameLabel():  String = "detailName"
    def detailStatsLabel(): String = "detailStats"
    def detailDescLabel():  String = "detailDesc"
    def detailPath():      NodePath = rootName() :: detailName() :: Nil
    def detailIconPath():  NodePath = rootName() :: detailName() :: detailIconNode() :: Nil
    def detailNamePath():  NodePath = rootName() :: detailName() :: detailNameLabel() :: Nil
    def detailStatsPath(): NodePath = rootName() :: detailName() :: detailStatsLabel() :: Nil
    def detailDescPath():  NodePath = rootName() :: detailName() :: detailDescLabel() :: Nil

    /// 説明文をこの文字数で折り返す（Label2D は自動折返ししないため `\n` を手で挿入する）。
    /// 詳細パネル幅 82px・fontSize 4 におよそ収まる文字数。
    def detailWrapWidth(): Int32 = 16

    /// 1 ページに並べる持ち物の最大数（アイテム window の表示行数と一致）。
    /// ロード職は 16 個持てるので 2 ページに分かれる。それ以外は 8 個＝1 ページに収まる。
    def itemsPerPage(): Int32 = 8

    /// 武器アイコンの表示サイズ（px）。fontSize 4 / itemHeight 6 の中に収まるよう 5px。
    def iconSize(): Float64 = 5.0

    /// アイコンとテキスト名の間の余白（px）
    def iconTextGap(): Float64 = 1.0

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ItemPanel")     => Ok(NodeTag.ItemPanel)
            case Some("ItemMenu")      => Ok(NodeTag.ItemMenu(0))
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"ItemMenuScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// ItemList を含むため FontAtlas が必須であり、`loadSceneWithFont` 経由でロードする。
    /// `SceneLoader.load` では FontAtlas を注入できないため、このラッパが必要。
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
        // 詳細ウィンドウはアイテム選択中とサブメニュー中だけ出す（攻撃中の武器リストでは出さない）。
        let detailVisible = phase == TurnPhase.Phase.ItemSelect
                         or phase == TurnPhase.Phase.ItemActionSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))
            |> Label2D.mapAt(pageLabelPath(), label ->
                if (pageLabelVisible) label else CanvasItem.setVisible(false, label))
            |> Panel.mapAt(detailPath(), CanvasItem.setVisible(detailVisible))
            |> Sprite2D.mapAt(detailIconPath(), CanvasItem.setVisible(detailVisible))
            |> Label2D.mapAt(detailNamePath(), CanvasItem.setVisible(detailVisible))
            |> Label2D.mapAt(detailStatsPath(), CanvasItem.setVisible(detailVisible))
            |> Label2D.mapAt(detailDescPath(), CanvasItem.setVisible(detailVisible))

    // ── 詳細ウィンドウ（性能 + 一言説明）──────────────────────

    /// 武器タイプの和名。詳細ウィンドウの性能表記に使う（JSON は英字なので別途用意）。
    def weaponTypeJp(weaponType: WeaponCatalog.WeaponType): String = match weaponType {
        case WeaponCatalog.WeaponType.Sword => "剣"
        case WeaponCatalog.WeaponType.Axe   => "斧"
        case WeaponCatalog.WeaponType.Lance => "槍"
        case WeaponCatalog.WeaponType.Bow   => "弓"
        case WeaponCatalog.WeaponType.Magic => "魔法"
    }

    /// 杖の効果の和名。詳細ウィンドウの性能表記に使う。
    def staffEffectJp(effect: Staff.StaffEffect): String = match effect {
        case Staff.StaffEffect.Heal     => "回復"
        case Staff.StaffEffect.Blowback => "ふきとばし"
        case Staff.StaffEffect.Swap     => "いれかえ"
    }

    /// 武器の性能 1 行（攻撃 / 命中 / 射程 / 種別）。stats から自動生成する。
    pub def weaponStatLine(weapon: UnitCatalog.WeaponResource): String =
        let range = weapon#range;
        let rangeText =
            if (range#min == range#max) "射${range#min}"
            else "射${range#min}-${range#max}";
        "攻${weapon#attack} 命${weapon#hit} ${rangeText} ${weaponTypeJp(weapon#weaponType)}"

    /// 杖の性能 1 行（効果 / 残り耐久）。
    pub def staffStatLine(staff: Staff.StaffResource): String =
        "効果:${staffEffectJp(staff#effect)} 耐久${staff#durability}"

    /// 消費アイテムの性能 1 行（回復量 / 残り使用回数）。
    pub def consumableStatLine(item: Consumable.ConsumableResource): String =
        "HP+${item#healAmount} 耐久${item#durability}"

    /// 文字のリストを先頭から `width` 文字ずつのまとまりに分ける。
    def chunkChars(width: Int32, chars: List[Char]): List[List[Char]] =
        if (List.isEmpty(chars)) Nil
        else List.take(width, chars) :: chunkChars(width, List.drop(width, chars))

    /// 文字のリストを 1 つの文字列に戻す。
    def charsToString(chars: List[Char]): String =
        List.foldLeft((acc, ch) -> "${acc}${ch}", "", chars)

    /// 改行のないテキストを `width` 文字ごとに `\n` で折り返す。
    /// Label2D は自動折返ししないので、説明文がパネル幅を超えないよう手で改行を入れる。
    pub def wrapText(width: Int32, text: String): String =
        if (width <= 0) text
        else
            chunkChars(width, String.toList(text))
                |> List.map(charsToString)
                |> List.foldRight((line, acc) ->
                    if (acc == "") line else "${line}\n${acc}", "")

    /// 詳細ウィンドウに出す 1 アイテムぶんの内容（名前 / 性能 1 行 / 一言説明 / アイコン sprite）。
    /// 名前の前にアイコンを出すため sprite も持ち回る。
    type alias ItemDetail = {
        name = String,
        stats = String,
        desc = String,
        sprite = Sprite.SpriteResource
    }

    /// 選択中アイテム種別から詳細内容を組む。
    /// index がリスト範囲外なら None（持ち物が無い・ずれた瞬間など）。
    def itemDetail(kind: PlayerData.ItemKind,
                   weapons: List[UnitCatalog.WeaponResource],
                   staves: List[Staff.StaffResource],
                   consumables: List[Consumable.ConsumableResource]):
            Option[ItemDetail] =
        match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                List.nth(idx, weapons) |> Option.map(weapon ->
                    {name = weapon#name, stats = weaponStatLine(weapon),
                     desc = weapon#description, sprite = weapon#sprite})
            case PlayerData.ItemKind.Staff(idx) =>
                List.nth(idx, staves) |> Option.map(staff ->
                    {name = staff#name, stats = staffStatLine(staff),
                     desc = staff#description, sprite = staff#sprite})
            case PlayerData.ItemKind.Consumable(idx) =>
                List.nth(idx, consumables) |> Option.map(item ->
                    {name = item#name, stats = consumableStatLine(item),
                     desc = item#description, sprite = item#sprite})
        }

    /// 詳細ウィンドウの 3 ラベル + アイコンに内容を流し込む（表示/非表示は applyVisibility が担う）。
    /// 説明文は幅で折り返す。アイコンは sprite の atlas 情報を Sprite2D に写し、表示にする。
    /// 全 item アトラスはセル 16×16 なので、Sprite2D 側の固定 scale で見た目サイズが揃う。
    def applyDetail(detail: ItemDetail, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Label2D.mapAt(detailNamePath(), Label2D.setText(detail#name))
            |> Label2D.mapAt(detailStatsPath(), Label2D.setText(detail#stats))
            |> Label2D.mapAt(detailDescPath(),
                Label2D.setText(wrapText(detailWrapWidth(), detail#desc)))
            |> Sprite2D.mapAt(detailIconPath(), sprite ->
                sprite
                    |> Sprite2D.setTexture(detail#sprite#texture)
                    |> Sprite2D.setHframes(detail#sprite#hframes)
                    |> Sprite2D.setVframes(detail#sprite#vframes)
                    |> Sprite2D.setFrame(detail#sprite#frame)
                    |> CanvasItem.setVisible(true))

    /// 選択が無いときは 3 ラベルを空にしアイコンを隠す。
    def blankDetail(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Label2D.mapAt(detailNamePath(), Label2D.setText(""))
            |> Label2D.mapAt(detailStatsPath(), Label2D.setText(""))
            |> Label2D.mapAt(detailDescPath(), Label2D.setText(""))
            |> Sprite2D.mapAt(detailIconPath(), CanvasItem.setVisible(false))

    /// 詳細を組めたら流し込み、組めなければ blank にする共通処理。
    def applyDetailOpt(detail: Option[ItemDetail], scene: Scene[NodeTag]): Scene[NodeTag] =
        match detail {
            case Some(itemDetail) => applyDetail(itemDetail, scene)
            case None             => blankDetail(scene)
        }

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ItemMenu の ItemList
    /// ノードに対して dispatch される（1 ノード 1 呼び出し。ItemList は 1 個のみなので 1 フレーム 1 回）。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State, PlayerData.PartyQuery} =
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
    ///
    /// 以下の薄ラッパ (`weaponsOf` / `stavesOf` / `consumablesOf`) は非 driver の在庫 read を
    /// effect 経由（PartyQuery）に寄せる設計上の境界線。
    /// `applyEquip` / `applyDrop` / `applyUse` 内部の「同フレーム write 直後 read」では
    /// scene 引数の最新値を直接読む必要があるため、これらは使わず scene-arg のまま据え置く
    /// （PartyQuery snapshot だと stale になる）。
    def weaponsOf(id: Int32): List[UnitCatalog.WeaponResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#weapons) |> Option.getWithDefault(Nil)

    def stavesOf(id: Int32): List[Staff.StaffResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#staves) |> Option.getWithDefault(Nil)

    def consumablesOf(id: Int32): List[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#consumables) |> Option.getWithDefault(Nil)

    def refreshItemList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                let weapons     = weaponsOf(playerId);
                let staves      = stavesOf(playerId);
                let consumables = consumablesOf(playerId);
                let pairs = itemSpritePairs(weapons, staves, consumables);
                let count = List.length(pairs);
                let page  = clampPage(getMenuPage(scene), count);
                let (items, icons) = pageSlice(pairs, page);
                let built = scene
                    |> Scene.setState(menuPath(), NodeTag.ItemMenu(page))
                    |> ItemList.mapAt(menuPath(), list ->
                        list
                            |> ItemList.setItems(items)
                            |> ItemList.setItemIcons(icons)
                            |> ItemList.setIconSize(iconSize())
                            |> ItemList.setIconTextGap(iconTextGap()))
                    |> applyPageLabel(page, count);
                // カーソルが乗っている行のアイテムを詳細ウィンドウに表示する。
                // 行の metadata（"w:idx" 等）から実体を引いて性能 + 説明を組む。
                let detail = List.nth(currentSelectedIndex(scene), items)
                    |> Option.flatMap(entry -> entry#metadata)
                    |> Option.flatMap(parseItemKind)
                    |> Option.flatMap(kind -> itemDetail(kind, weapons, staves, consumables));
                applyDetailOpt(detail, built)
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

    /// 攻撃中 (PlayerAttack) の武器選択リストを組む。攻撃は武器でしか行えないため
    /// **武器だけ**を並べる (杖・消費アイテムは出さない)。ロードは持ち物 2 倍だが武器は数本なので、
    /// 杖・薬を含めて全持ち物を出していた旧仕様で起きていた「リストがパネル下に溢れる」を解消する。
    /// カーソルが乗っている敵に届く武器だけアクティブ (disabled = false)、届かない武器は disabled。
    /// 選択 index は `activeAttackWeaponIndex` で「届く武器」に正規化する (engine の上下移動は
    /// disabled をスキップするので、左右でターゲットが変わって選択が射程外になったときの補正)。
    /// 武器のみなので weapons 内 index = 表示行 index となり、selIdx 正規化はそのまま使える。
    def refreshAttackWeaponList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                let weapons = weaponsOf(playerId);
                let dist    = cursorTargetDistance(playerId, scene);
                let items = List.mapWithIndex(idx -> w ->
                    attackWeaponEntry(idx, w, weaponActiveAt(dist, w)), weapons);
                let icons = rowIcons(List.map(w -> w#sprite, weapons));
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
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
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
    // 注: これはインベントリ read ではなくカーソル/位置の距離計算。player の gridPos・
    // カーソル位置・敵をすべて scene から読む（PartyQuery snapshot に寄せると player 不在時の
    // 短絡が崩れ、カーソル未配置の経路で CursorScene.getGridPos が None を bug! として
    // 扱い Err をスローする）。scene-arg のまま。
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
        let result = forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerScene.get(playerId, scene)
        ) yield {
            let items = actionItemsFor(player#selectedItem);
            let built = scene |> ItemList.mapAt(menuPath(), list ->
                list
                    |> ItemList.setItems(items)
                    |> ItemList.setItemIcons(Map.empty())
                    |> ItemList.setIconSize(iconSize())
                    |> ItemList.setIconTextGap(iconTextGap()));
            // サブメニュー中も、確定したアイテムの性能 + 説明を出し続ける。
            let detail = player#selectedItem
                |> Option.flatMap(kind ->
                    itemDetail(kind, player#weapons, player#staves, player#consumables));
            applyDetailOpt(detail, built)
        };
        Option.getWithDefault(scene, result)

    /// 選択中アイテム種別に応じたサブメニュー項目。
    ///   武器        → [そうび, すてる]
    ///   杖・消費品   → [つかう, すてる]
    ///   未選択       → []
    /// `refreshActionList` の判定本体を effect なしで切り出したもの（テスト容易化）。
    pub def actionItemsFor(sel: Option[PlayerData.ItemKind]): List[ItemEntry] =
        match sel {
            case Some(PlayerData.ItemKind.Weapon(_)) =>
                equipEntry() :: dropEntry() :: Nil
            // 杖・消費アイテムはどちらも「つかう / すてる」。
            case Some(PlayerData.ItemKind.Staff(_))      =>
                useEntry() :: dropEntry() :: Nil
            case Some(PlayerData.ItemKind.Consumable(_)) =>
                useEntry() :: dropEntry() :: Nil
            case None => Nil
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は `"w:<idx>"` 形式で種別と index を持つ。
    /// 「武器名 残耐久」の表記は WeaponMenuScene と統一している（一貫した見た目のため）。
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

    /// metadata の `"w:<idx>"` / `"s:<idx>"` を `PlayerData.ItemKind` にパースする。
    /// 不明形式は `None`。
    pub def parseItemKind(meta: String): Option[PlayerData.ItemKind] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerData.ItemKind.Weapon)
        else if (String.startsWith({prefix = "s:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerData.ItemKind.Staff)
        else if (String.startsWith({prefix = "c:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerData.ItemKind.Consumable)
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
        let result = forM (
            kind     <- entry#metadata |> Option.flatMap(parseItemKind);
            playerId <- SelectedPlayer.State.get()#id
        ) yield {
            let withItem = PlayerScene.setSelectedItem(playerId, kind, scene);
            TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
            // サブメニューは常に先頭（「そうび」/「つかう」）から始める。
            // ItemSelect での選択位置を引き継いで「すてる」に当たるのを防ぐ。
            withItem |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
        };
        Option.getWithDefault(scene, result)

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
        let result = forM (
            m        <- entry#metadata;
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerScene.get(playerId, scene);
            kind     <- player#selectedItem
        ) yield dispatchAction(m, playerId, kind, scene);
        Option.getWithDefault(scene, result)

    /// サブメニューの metadata 別に処理を分配する。`onActionConfirmed` の effect 宣言が
    /// 肥大化しないよう、分岐ロジックをここに委譲している。
    def dispatchAction(meta: String, playerId: Int32, kind: PlayerData.ItemKind,
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
    def applyEquip(playerId: Int32, kind: PlayerData.ItemKind,
                     scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State} =
        let equipped = match kind {
            case PlayerData.ItemKind.Weapon(idx)   =>
                // 実際に並びが変わるとき (0 < idx < 本数) だけ巻き戻しドラフトを積む。
                // idx=0 / 範囲外は equipWeapon が no-op なので積まない（誤巻き戻し防止）。
                let n = List.length(PlayerScene.getWeapons(playerId, scene));
                if (idx >= 1 and idx < n)
                    SelectedPlayer.pushDraft(MoveDraft.DraftAction.Equipped(playerId, idx))
                else ();
                PlayerScene.equipWeapon(playerId, idx, scene)
            case PlayerData.ItemKind.Staff(_)      => scene
            case PlayerData.ItemKind.Consumable(_) => scene
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, equipped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// `droppedScene` は呼び出し側で `dropXxx` 済みの scene（純粋変換）。
    def dropResolved(playerId: Int32, kind: PlayerData.ItemKind, name: String,
                      ground: ItemData.GroundItemKind, droppedScene: Scene[NodeTag]):
                     Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        GameLogger.playerLog("P${playerId} は ${name} をすてた");
        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(playerId, kind, ground));
        droppedScene

    /// 「すてる」: 武器なら `dropWeapon`、杖なら `dropStaff`。
    /// ターン消費せず ItemSelect に戻る（連続して捨てられる）。
    def applyDrop(playerId: Int32, kind: PlayerData.ItemKind,
                    scene: Scene[NodeTag]):
                   Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                                     SelectedPlayer.State} =
        // 削除前に実体を取得してから Dropped ドラフトを積む（誤巻き戻し防止）。
        // 該当アイテムが無ければ no-op。
        let dropped = match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                Option.getWithDefault(scene,
                    forM (w <- List.nth(idx, PlayerScene.getWeapons(playerId, scene)))
                        yield dropResolved(playerId, kind, w#name,
                                  ItemData.GroundItemKind.WeaponItem(w),
                                  PlayerScene.dropWeapon(playerId, idx, scene)))
            case PlayerData.ItemKind.Staff(idx) =>
                Option.getWithDefault(scene,
                    forM (s <- List.nth(idx, PlayerScene.getStaves(playerId, scene)))
                        yield dropResolved(playerId, kind, s#name,
                                  ItemData.GroundItemKind.StaffItem(s),
                                  PlayerScene.dropStaff(playerId, idx, scene)))
            case PlayerData.ItemKind.Consumable(idx) =>
                Option.getWithDefault(scene,
                    forM (c <- List.nth(idx, PlayerScene.getConsumables(playerId, scene)))
                        yield dropResolved(playerId, kind, c#name,
                                  ItemData.GroundItemKind.ConsumableItem(c),
                                  PlayerScene.dropConsumable(playerId, idx, scene)))
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, dropped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「つかう」: 杖の場合のみ実行（武器の場合は「装備」項目が出るのでここには来ない）。
    /// 杖の発動方向選択フェーズ `StaffAim` に進み、ログに方向キーの操作プロンプトを出す。
    /// selectedItem は保持しておき、`StaffAim` 中の方向入力で
    /// `StaffCastScene.applyStaffCast` が読む。
    def applyUse(playerId: Int32, kind: PlayerData.ItemKind,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, GameLogger.GameLogger,
                GameEngine.Audio} =
        match kind {
            case PlayerData.ItemKind.Staff(idx) =>
                let name = staffNameOf(playerId, idx, scene);
                GameLogger.playerLog("P${playerId} は ${name} の方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim(scene)
            // 消費アイテムは方向選択不要。その場で使用者を回復しターンを消費する。
            case PlayerData.ItemKind.Consumable(idx) =>
                StaffCastScene.applyConsumableUse(playerId, idx, scene)
            case PlayerData.ItemKind.Weapon(_) => scene
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
