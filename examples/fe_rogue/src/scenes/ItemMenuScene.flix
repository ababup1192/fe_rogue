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
    def equipMeta():   String = "equip"
    def unequipMeta(): String = "unequip"
    def dropMeta():    String = "drop"
    def useMeta():     String = "use"
    def throwMeta():   String = "throw"

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

    /// 見出し帯 / 見出し「アイテム」/ カテゴリヒント「◀ 武器 ▶」の子ノード名（武器メニュー準拠）。
    def headerBgName(): String = "headerBg"
    /// 見出し帯の底面の角丸を塗りつぶす重ね板（ActionMenuScene と同作法・「上だけ丸／底面四角」）。
    def headerBgFillName(): String = "headerBgFill"
    def headerName(): String = "header"
    def hintName(): String = "hint"

    pub def rootPath():  NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath():  NodePath = rootName() :: panelName() :: menuName() :: Nil
    def headerBgPath(): NodePath = rootName() :: panelName() :: headerBgName() :: Nil
    def headerBgFillPath(): NodePath = rootName() :: panelName() :: headerBgFillName() :: Nil
    def headerPath():   NodePath = rootName() :: panelName() :: headerName() :: Nil
    def hintPath():     NodePath = rootName() :: panelName() :: hintName() :: Nil

    /// アイコンの表示サイズ / アイコンと名前の間の余白（武器メニューと揃える）。
    def iconSize(): Float64 = 5.0
    def iconTextGap(): Float64 = 3.0

    /// アイテム窓を ActionMenu の右端基準に重ねる量（武器メニューと同じ）。
    def panelOverlapPx(): Float64 = 5.0

    // ── カテゴリ（左右で切替。順序 = 武器 → 消費 → 杖 → 指輪）──
    def catWeapon(): Int32 = 0
    def catConsumable(): Int32 = 1
    def catStaff(): Int32 = 2
    def catRing(): Int32 = 3
    /// 全カテゴリ index を表示順で。
    def allCategories(): List[Int32] =
        catWeapon() :: catConsumable() :: catStaff() :: catRing() :: Nil
    /// カテゴリの和名（ヒント表示用）。
    def categoryLabel(c: Int32): String =
        if (c == catWeapon()) "武器"
        else if (c == catConsumable()) "消費"
        else if (c == catStaff()) "杖"
        else "指輪"
    /// 装備中（武器/指輪の先頭）に出すバッジ文字。
    def equippedBadge(): String = "装備"

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。ItemMenu の Int32 は現在カテゴリ index。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ItemPanel")     => Ok(NodeTag.ItemPanel)
            case Some("ItemMenu")      => Ok(NodeTag.ItemMenu(0, Set#{}))
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

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用（Push モデル）。
    /// `ItemSelect` / `ItemActionSelect` では窓を visible + focused にする。
    /// `PlayerAttack`（攻撃対象選択中の武器リスト）では **窓は出さず**（命中/必殺は盤面の
    /// 戦闘予報ミニウィンドウ `BattlePanelScene` で見せるため、旧来の武器リスト窓は冗長で隠す）、
    /// 武器の上下持ち替えだけ活かすため ItemList の focused は true に保つ。
    /// `BattlePanelScene` は PlayerAttack 中 `activeAttackWeaponIndex`（= この ItemList の
    /// 選択 index）で現在武器を読むので、不可視のままでも予報は持ち替えに追従する。
    /// それ以外のフェーズでは hidden + unfocused。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        // 窓そのものを出すのはアイテム選択系の 2 フェーズだけ（PlayerAttack では出さない）。
        let windowVisible = phase == TurnPhase.Phase.ItemSelect
                         or phase == TurnPhase.Phase.ItemActionSelect;
        // PlayerAttack 中も武器の上下持ち替えを受けるため focused は維持する。
        let listFocused = windowVisible or phase == TurnPhase.Phase.PlayerAttack;
        // カテゴリ切替ヒントは ItemSelect のときだけ（サブメニュー中は出さない）。
        let hintVisible = phase == TurnPhase.Phase.ItemSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(windowVisible))
            |> Panel.mapAt(headerBgPath(), CanvasItem.setVisible(windowVisible))
            |> Panel.mapAt(headerBgFillPath(), CanvasItem.setVisible(windowVisible))
            |> Label2D.mapAt(headerPath(), CanvasItem.setVisible(windowVisible))
            |> Label2D.mapAt(hintPath(), CanvasItem.setVisible(hintVisible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(windowVisible) |> ItemList.setFocused(listFocused))

    // ── カテゴリ別サブライン（旧・右詳細パネルの代替。各行の 2 行目に出す）──────

    /// 杖の効果の和名（サブライン表記に使う）。
    def staffEffectJp(effect: Staff.StaffEffect): String = match effect {
        case Staff.StaffEffect.Heal     => "回復"
        case Staff.StaffEffect.Blowback => "ふきとばし"
        case Staff.StaffEffect.Swap     => "いれかえ"
        case Staff.StaffEffect.Bind     => "かなしばり"
        case Staff.StaffEffect.Stopgap  => "一時しのぎ"
    }

    /// 符号つき数値表記（+3 / -1）。
    def signed(n: Int32): String = if (n >= 0) "+${n}" else "${n}"

    /// 消費アイテムのサブライン（効果要約 + 残り使用回数 + 重さ）。例「HP+10 ・残 3 ・重 0.5」。
    pub def consumableSubline(item: Consumable.ConsumableResource): String =
        "${consumableEffectSummary(item)} ・残 ${item#durability} ・重 ${Encumbrance.weightText(Encumbrance.consumableWeight(item))}"

    /// 杖のサブライン（効果 + 残り使用回数 + 重さ）。例「回復 ・残 5 ・重 0.8」。
    pub def staffSubline(staff: Staff.StaffResource): String =
        "${staffEffectJp(staff#effect)} ・残 ${staff#durability} ・重 ${Encumbrance.weightText(Encumbrance.staffWeight(staff))}"

    /// 指輪の効果 1 行（サブライン）に重さを添える。
    pub def ringStatLine(ring: Ring.RingResource): String =
        "${ringEffectLine(ring)} ・重 ${Encumbrance.weightText(Encumbrance.ringWeight(ring))}"

    /// 指輪の効果文（重さを除く本体）。
    def ringEffectLine(ring: Ring.RingResource): String = match ring#effect {
        case Ring.RingEffect.Pursuit   => "速+3で追撃15%"
        case Ring.RingEffect.Power     => "攻撃${signed(ring#power)}"
        case Ring.RingEffect.Swift     => "速さ${signed(ring#power)}"
        case Ring.RingEffect.Guard     => "防御${signed(ring#power)}"
        case Ring.RingEffect.Mend      => "毎ターンHP+${ring#power}"
        case Ring.RingEffect.Lifesteal => "撃破でHP+${ring#power}"
        case Ring.RingEffect.Finisher  => "瀕死(${ring#power}%以下)に必殺"
        case Ring.RingEffect.Trivial   => "効果なし"
        case Ring.RingEffect.Levitate  => "持つだけで荷が軽い"
    }

    /// 効果ごとの要約表記（耐久を除く本体）。`magnitude` / `duration` を効果の意味に沿って出す。
    def consumableEffectSummary(item: Consumable.ConsumableResource): String =
        let n = item#magnitude;
        let t = item#duration;
        match item#effect {
            case Consumable.ConsumableEffect.Heal       => "HP+${n}"
            case Consumable.ConsumableEffect.FullHeal   => "HP全回復"
            case Consumable.ConsumableEffect.MaxHpUp    => "最大HP+${n}"
            case Consumable.ConsumableEffect.AutoRevive => "復活"
            case Consumable.ConsumableEffect.BlindHit   => "命中-${n}% ${t}T"
            case Consumable.ConsumableEffect.SpdDownHit => "速-${n} ${t}T"
            case Consumable.ConsumableEffect.AtkUp      => "攻+${n} ${t}T"
            case Consumable.ConsumableEffect.SpdUp      => "速+${n} ${t}T"
            case Consumable.ConsumableEffect.FireBottle  => "${n}ダメージ"
            case Consumable.ConsumableEffect.BlastBottle => "爆発${n}"
            // TODO(throw feature): DefDownHit の表記は実装側の意味に合わせて調整する（暫定）。
            case Consumable.ConsumableEffect.DefDownHit  => "防-${n} ${t}T"
        }

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ItemMenu の ItemList
    /// ノードに対して dispatch される（1 ノード 1 呼び出し。ItemList は 1 個のみなので 1 フレーム 1 回）。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, CursorState.State, TurnPhase.State, PlayerData.PartyQuery, World.WorldQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = match phase {
            case TurnPhase.Phase.ItemSelect =>
                refreshItemList(withVisibility)
            case TurnPhase.Phase.ItemActionSelect =>
                refreshActionList(withVisibility)
            case TurnPhase.Phase.PlayerAttack =>
                refreshAttackWeaponList(withVisibility)
            // メニューが閉じている間はカーソルとカテゴリを先頭に戻しておく。これで次に
            // ItemSelect を開いたときは記憶位置ではなく常に先頭カテゴリ・先頭項目から始まる。
            // 表示中のフェーズではリセットしないので ↑↓ の移動・←→ のカテゴリ切替は維持される。
            case _ => setCategoryIdx(catWeapon(), withVisibility)
        };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    // ── 状態（現在カテゴリ index + 複数選択マーク）──

    /// ItemMenu ノードに積んである現在カテゴリ index。未設定なら 0（武器）。
    def getCategoryIdx(scene: Scene[NodeTag]): Int32 =
        match Scene.getState(menuPath(), scene) {
            case Some(NodeTag.ItemMenu(c, _)) => c
            case _                            => 0
        }

    /// 現在カテゴリを書き戻し、選択カーソルを先頭(0)に戻す。印は保持する。
    def setCategoryIdx(c: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> Scene.setState(menuPath(), NodeTag.ItemMenu(c, getMarks(scene)))
            |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))

    /// ItemMenu ノードに積んである複数選択の印。未設定なら空集合。
    def getMarks(scene: Scene[NodeTag]): Set[PlayerData.ItemKind] =
        match Scene.getState(menuPath(), scene) {
            case Some(NodeTag.ItemMenu(_, marks)) => marks
            case _                                => Set#{}
        }

    /// 印だけ差し替える（カテゴリは保持する）。
    def setMarks(marks: Set[PlayerData.ItemKind], scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> Scene.setState(menuPath(), NodeTag.ItemMenu(getCategoryIdx(scene), marks))

    /// 複数選択した行の強調色（黄系）。交換メニューの pick 色と見た目を揃える。
    def markColor(): Color = {r = 1.0f32, g = 0.85f32, b = 0.2f32}

    // ── カテゴリ（左右で切替・空はスキップ）──

    /// 指定カテゴリの所持数（プレイヤーの在庫を scene から読む）。
    def categoryCount(cat: Int32, player: PlayerScene.Data): Int32 =
        if (cat == catWeapon()) List.length(player#weapons)
        else if (cat == catConsumable()) List.length(player#consumables)
        else if (cat == catStaff()) List.length(player#staves)
        else List.length(player#rings)

    /// アイテムが 1 つ以上あるカテゴリだけを表示順で返す。
    /// 在庫読みは PartyQuery（World.dataFromWorld オーバーレイ）経由＝メニューの読みは World から取る。
    def nonEmptyCategories(playerId: Int32): List[Int32] \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(playerId) {
            case None         => Nil
            case Some(player) => List.filter(c -> categoryCount(c, player) > 0, allCategories())
        }

    /// `cats` の中で `cur` から `dir`(-1/+1) 隣のカテゴリへ（端はループ）。
    /// `cur` が `cats` に無ければ先頭を返す。空なら `cur` のまま。
    pub def nextCategoryIn(cats: List[Int32], cur: Int32, dir: Int32): Int32 =
        let len = List.length(cats);
        if (len == 0) cur
        else {
            let curPos = List.zipWithIndex(cats)
                |> List.findLeft(p -> snd(p) == cur)
                |> Option.map(fst)
                |> Option.getWithDefault(0);
            let nextPos = Int32.modulo(curPos + dir + len, len);
            List.nth(nextPos, cats) |> Option.getWithDefault(cur)
        }

    /// ←（前カテゴリ）/ →（次カテゴリ）。ItemSelect 中の Left/A・Right/D から呼ばれる。
    /// 在庫のあるカテゴリだけを巡回する（空はスキップ）。
    pub def categoryPrev(scene: Scene[NodeTag]): Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        cycleCategory(-1, scene)
    pub def categoryNext(scene: Scene[NodeTag]): Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        cycleCategory(1, scene)
    def cycleCategory(dir: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(playerId) =>
                let cats = nonEmptyCategories(playerId);
                let next = nextCategoryIn(cats, getCategoryIdx(scene), dir);
                setCategoryIdx(next, scene)
        }

    // ── 行（アイコン色紙 + 名前 + サブライン + 装備バッジ）──

    /// 1 カテゴリの行を汎用に組む。`equipHead` が true なら先頭行に「装備」バッジを付ける。
    /// metadata は `"${prefix}:${idx}"` 形式で、確定・装備・捨て・マークの解決に使う。
    def buildRows(prefix: String, xs: List[a],
                  nameOf: a -> String, sublineOf: a -> String,
                  spriteOf: a -> Sprite.SpriteResource, equipHead: Bool):
            (List[ItemEntry], Map[Int32, String], Map[Int32, String], Map[Int32, ItemIcon]) =
        let indexed = List.zipWithIndex(xs);
        let items = List.map(p -> {
            let (idx, x) = p;
            ({text = nameOf(x), disabled = false, metadata = Some("${prefix}:${idx}")}: ItemEntry)
        }, indexed);
        let sublines = List.foldLeft((acc, p) ->
            let (idx, x) = p; Map.insert(idx, sublineOf(x), acc), Map.empty(), indexed);
        let icons = List.foldLeft((acc, p) ->
            let (idx, x) = p; Map.insert(idx, spriteIcon(spriteOf(x)), acc), Map.empty(), indexed);
        let badges = if (equipHead and not List.isEmpty(xs))
                Map.insert(0, equippedBadge(), Map.empty())
            else Map.empty();
        (items, sublines, badges, icons)

    /// 現在カテゴリの (items, sublines, badges, icons) を組む。サブラインは種別ごとに出し分ける。
    def categoryRows(cat: Int32, player: PlayerScene.Data):
            (List[ItemEntry], Map[Int32, String], Map[Int32, String], Map[Int32, ItemIcon]) =
        if (cat == catWeapon())
            buildRows("w", player#weapons,
                w -> w#name, w -> WeaponSelectScene.weaponSubline(w), w -> w#sprite, true)
        else if (cat == catConsumable())
            buildRows("c", player#consumables,
                c -> c#name, consumableSubline, c -> c#sprite, false)
        else if (cat == catStaff())
            buildRows("s", player#staves,
                s -> s#name, staffSubline, s -> s#sprite, false)
        else
            buildRows("r", player#rings,
                r -> r#name, ringStatLine, r -> r#sprite, player#ringEquipped)

    /// 現在カテゴリの行のうち、印付き行を強調色で塗る（毎回全消ししてから塗る）。
    def applyMarkColors(marks: Set[PlayerData.ItemKind], items: List[ItemEntry],
                        scene: Scene[NodeTag]): Scene[NodeTag] =
        let rows = List.zipWithIndex(items)
            |> List.filterMap(p -> {
                let (row, entry) = p;
                let marked = entry#metadata
                    |> Option.flatMap(parseItemKind)
                    |> Option.map(k -> Set.memberOf(k, marks))
                    |> Option.getWithDefault(false);
                if (marked) Some(row) else None
            });
        scene |> ItemList.mapAt(menuPath(), list ->
            List.foldLeft((acc, row) -> ItemList.setItemColor(row, markColor(), acc),
                ItemList.clearItemColors(list), rows))

    /// ヒントラベルを現在カテゴリ名にする。切替先が複数あるときだけ ◀ ▶ を付ける。
    def setHintLabel(cat: Int32, multi: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let txt = if (multi) "◀ ${categoryLabel(cat)} ▶" else categoryLabel(cat);
        scene |> Label2D.mapAt(hintPath(), Label2D.setText(txt))

    /// ヘッダを「重さ X.X/Y.Y」の重量ゲージにし、積載段階で色を変える
    /// （通常=ヘッダ色 / 80%+=黄 / 100%+=橙 / 110%+=赤）。角括弧を含まないので Label2D で安全。
    def setWeightHeader(player: PlayerScene.Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        let load = PlayerScene.loadOf(player);
        let txt = "重 ${Encumbrance.weightText(load#total)}/${Encumbrance.weightText(load#capacity)}";
        scene
            |> Label2D.mapAt(headerPath(), Label2D.setText(txt))
            |> Label2D.mapAt(headerPath(), CanvasItem.setModulate(UITheme.encumbranceTierColor(load#tier)))

    /// アイテム窓を ActionMenu の右端基準に重ねて配置する（武器メニューと同じ）。
    def positionBesideActionMenu(scene: Scene[NodeTag]): Scene[NodeTag] =
        match Panel.getAt(ActionMenuScene.panelPath(), scene) {
            case None         => scene
            case Some(action) =>
                let actionRight = Node2D.getPosition(action)#x + Panel.getSize(action)#x;
                let newX = actionRight - panelOverlapPx();
                scene |> Panel.mapAt(panelPath(), p ->
                    Node2D.setPosition({x = newX, y = Node2D.getPosition(p)#y}, p))
        }

    /// 攻撃中 (PlayerAttack) の武器リスト用に在庫を読む薄ラッパ（PartyQuery 経由）。
    def weaponsOf(id: Int32): List[UnitCatalog.WeaponResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#weapons) |> Option.getWithDefault(Nil)

    /// 杖/消費/指輪も PartyQuery（World オーバーレイ）経由の薄ラッパで読む（weaponsOf と同型）。
    def stavesOf(id: Int32): List[Staff.StaffResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#staves) |> Option.getWithDefault(Nil)

    def consumablesOf(id: Int32): List[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#consumables) |> Option.getWithDefault(Nil)

    def ringsOf(id: Int32): List[Ring.RingResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#rings) |> Option.getWithDefault(Nil)

    /// 選択中プレイヤーの「現在カテゴリ」を ItemList に並べる（ItemSelect 中）。
    /// 現在カテゴリが空ならアイテムのある先頭カテゴリへスナップする。窓は ActionMenu の右隣へ。
    def refreshItemList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None => scene
            // 在庫読みは PartyQuery（World オーバーレイ）経由。
            case Some(playerId) => match PlayerData.PartyQuery.get(playerId) {
                case None         => scene
                case Some(player) =>
                    let cats = nonEmptyCategories(playerId);
                    let cur0 = getCategoryIdx(scene);
                    let cur  = if (List.memberOf(cur0, cats)) cur0
                               else List.head(cats) |> Option.getWithDefault(catWeapon());
                    let marks = getMarks(scene);
                    let (items, sublines, badges, icons) = categoryRows(cur, player);
                    scene
                        |> Scene.setState(menuPath(), NodeTag.ItemMenu(cur, marks))
                        |> ItemList.mapAt(menuPath(), list ->
                            list
                                |> ItemList.setItems(items)
                                |> ItemList.setItemSublines(sublines)
                                |> ItemList.setItemBadges(badges)
                                |> ItemList.setItemIcons(icons)
                                |> ItemList.setIconSize(iconSize())
                                |> ItemList.setIconTextGap(iconTextGap()))
                        |> setHintLabel(cur, List.length(cats) > 1)
                        |> setWeightHeader(player)
                        |> positionBesideActionMenu
                        |> applyMarkColors(marks, items)
            }
        }

    /// 攻撃中 (PlayerAttack) の武器選択リストを組む。攻撃は武器でしか行えないため
    /// **武器だけ**を並べる (杖・消費アイテムは出さない)。ロードは持ち物 2 倍だが武器は数本なので、
    /// 杖・薬を含めて全持ち物を出していた旧仕様で起きていた「リストがパネル下に溢れる」を解消する。
    /// カーソルが乗っている敵に届く武器だけアクティブ (disabled = false)、届かない武器は disabled。
    /// 選択 index は `activeAttackWeaponIndex` で「届く武器」に正規化する (engine の上下移動は
    /// disabled をスキップするので、左右でターゲットが変わって選択が射程外になったときの補正)。
    /// 武器のみなので weapons 内 index = 表示行 index となり、selIdx 正規化はそのまま使える。
    def refreshAttackWeaponList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, World.WorldQuery} =
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
                        // 直前の ItemSelect で付いたサブライン/バッジを消す（攻撃中は名前のみ）。
                        |> ItemList.setItemSublines(Map.empty())
                        |> ItemList.setItemBadges(Map.empty())
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
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, World.WorldQuery} =
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
    def cursorTargetDistance(playerId: Int32, scene: Scene[NodeTag]): Option[Int32] \ {World.WorldQuery, CursorState.State} =
        forM (
            player <- PlayerScene.get(playerId, scene);
            eid    <- EnemyScene.findIdAt(CursorScene.getGridPos(), scene);
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

    /// 「そうび」項目（武器・指輪）。
    def equipEntry(): ItemEntry =
        {text = "装備", disabled = false, metadata = Some(equipMeta())}

    /// 「はずす」項目（装備中の指輪のみ）。
    def unequipEntry(): ItemEntry =
        {text = "外す", disabled = false, metadata = Some(unequipMeta())}

    /// 「つかう」項目（杖・消費アイテム）。
    def useEntry(): ItemEntry =
        {text = "使う", disabled = false, metadata = Some(useMeta())}

    /// 「なげる」項目（全種別共通）。方向を選んで投擲する。
    def throwEntry(): ItemEntry =
        {text = "投げる", disabled = false, metadata = Some(throwMeta())}

    /// 「すてる」項目（武器・杖・消費アイテム共通）。
    def dropEntry(): ItemEntry =
        {text = "捨てる", disabled = false, metadata = Some(dropMeta())}

    /// サブメニュー項目を組む（ItemActionSelect 中）。
    /// 武器なら `[そうび, すてる]`、杖・消費アイテムなら `[つかう, すてる]`。
    /// 選択中アイテムが「持つだけ」系（浮雲など装備も使用もできず捨てるのみ）か。
    /// 現状は指輪カテゴリの Levitate（浮雲）のみ。サブメニュー出し分けに使う。
    def isSelectedPassiveHold(player: PlayerScene.Data): Bool =
        match player#selectedItem {
            case Some(PlayerData.ItemKind.Ring(idx)) =>
                List.nth(idx, player#rings)
                    |> Option.map(Ring.isPassiveHold)
                    |> Option.getWithDefault(false)
            case _ => false
        }

    def refreshActionList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        let bulkMode = not Set.isEmpty(getMarks(scene));
        // 在庫読み（rings/ringEquipped/selectedItem）は PartyQuery（World オーバーレイ）経由。
        let result = forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield {
            let holdOnly = isSelectedPassiveHold(player);
            let items = actionItemsFor(player#selectedItem, player#ringEquipped, bulkMode, holdOnly);
            // 複数選択中は唯一有効な「捨てる」へカーソルを寄せる。
            let dropRow = List.zipWithIndex(items)
                |> List.findLeft(p -> snd(p)#metadata == Some(dropMeta()))
                |> Option.map(fst);
            // サブメニューはテキスト行のみ（アイコン/サブライン/バッジは消す）。
            // ItemSelect で付いた複数選択マークの黄色（itemColors）も消す。これで無効な
            // 「使う/投げる」は黄色でなく disabledColor（コマンドの射程外「攻撃」と同じ灰）で出る。
            scene |> ItemList.mapAt(menuPath(), list -> {
                let withItems = list
                    |> ItemList.setItems(items)
                    |> ItemList.clearItemColors
                    |> ItemList.setItemSublines(Map.empty())
                    |> ItemList.setItemBadges(Map.empty())
                    |> ItemList.setItemIcons(Map.empty())
                    |> ItemList.setIconSize(iconSize())
                    |> ItemList.setIconTextGap(iconTextGap());
                match (bulkMode, dropRow) {
                    case (true, Some(r)) => ItemList.setSelectedIndex(r, withItems)
                    case _               => withItems
                }
            })
        };
        Option.getWithDefault(scene, result)

    /// 選択中アイテム種別に応じたサブメニュー項目。
    ///   武器           → [そうび, なげる, すてる]
    ///   杖・消費品      → [つかう, なげる, すてる]
    ///   指輪(未装備)    → [そうび, なげる, すてる]
    ///   指輪(装備中)    → [はずす, なげる, すてる]
    ///   未選択          → []
    /// `ringEquipped` は選択中味方の指輪装備フラグ。装備中の指輪（先頭 = index 0）を選んだときだけ
    /// 「外す」に差し替える。
    /// `bulkMode`（Shift 複数選択中）が true のときは「捨てる」だけ有効にし、他は disabled（淡色・
    /// カーソルスキップ・確定不可）にする＝複数選択でできるのは一括「捨てる」だけ。
    /// `refreshActionList` の判定本体を effect なしで切り出したもの（テスト容易化）。
    /// `holdOnly` が true（浮雲など「持つだけ」系）のときは装備も使用も投擲もできず「捨てる」だけ。
    pub def actionItemsFor(sel: Option[PlayerData.ItemKind], ringEquipped: Bool,
                           bulkMode: Bool, holdOnly: Bool): List[ItemEntry] =
        // 並び順は「使う/装備 → 投げる → 捨てる」。投げるは全種別で出す（一律投擲可）。
        // ただし holdOnly のアイテムは所持効果のみ＝「捨てる」だけ出す。
        let base = if (holdOnly) dropEntry() :: Nil else match sel {
            case Some(PlayerData.ItemKind.Weapon(_)) =>
                equipEntry() :: throwEntry() :: dropEntry() :: Nil
            case Some(PlayerData.ItemKind.Staff(_))      =>
                useEntry() :: throwEntry() :: dropEntry() :: Nil
            case Some(PlayerData.ItemKind.Consumable(_)) =>
                useEntry() :: throwEntry() :: dropEntry() :: Nil
            // 指輪: 装備中（先頭かつ ringEquipped）なら「外す」、それ以外は「装備」。
            case Some(PlayerData.ItemKind.Ring(idx)) =>
                let equipOrUnequip =
                    if (ringEquipped and idx == 0) unequipEntry() else equipEntry();
                equipOrUnequip :: throwEntry() :: dropEntry() :: Nil
            case None => Nil
        };
        // 複数選択中は「捨てる」以外を無効化する（できるのは一括「捨てる」だけ）。
        if (bulkMode)
            List.map(e -> if (e#metadata == Some(dropMeta())) e else {disabled = true | e}, base)
        else base

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
        else if (String.startsWith({prefix = "r:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerData.ItemKind.Ring)
        else None

    // ────────────────────────────────────────────────────────
    // (E) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// ActionMenu「アイテム」確定で呼ばれる。`ItemSelect` フェーズに遷移する。
    /// PhaseTransitions が overlay 片付け + カーソル非表示も合わせて行う。
    pub def openFor(playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, PlayerData.PartyQuery} =
        // 常に「アイテムのある先頭カテゴリ」・印なし・カーソル先頭から開く。
        let entered = setMarks(Set#{}, PhaseTransitions.enterItemSelect(scene));
        let firstCat = nonEmptyCategories(playerId)
            |> List.head
            |> Option.getWithDefault(catWeapon());
        setCategoryIdx(firstCat, entered)

    /// ItemSelect 中に Shift が押されたとき、カーソル位置のアイテムの印を付け外しする。
    /// カーソル行の metadata（"w:idx" 等）から種別+index を取り、マーク集合をトグルして書き戻す。
    /// アイテム以外（空など）に乗っているときは何もしない。
    pub def toggleMarkAtCursor(scene: Scene[NodeTag]): Scene[NodeTag] =
        let kindOpt = ItemList.getAt(menuPath(), scene)
            |> Option.flatMap(ItemList.getSelected)
            |> Option.flatMap(entry -> entry#metadata)
            |> Option.flatMap(parseItemKind);
        kindOpt
            |> Option.map(kind -> setMarks(PlayerData.toggleMark(kind, getMarks(scene)), scene))
            |> Option.getWithDefault(scene)

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
        // 閉じる時に先頭カテゴリへ戻し、複数選択の印も消す（次に開いたとき先頭・印なし）。
        setCategoryIdx(catWeapon(), setMarks(Set#{}, scene))

    /// ItemActionSelect でサブメニュー項目を Enter 確定したとき。
    ///   - 装備: weapons リスト先頭に移動、ItemSelect に戻る（ターン消費なし）
    ///   - 捨てる: 該当アイテム削除、ItemSelect に戻る（ターン消費なし）
    ///   - 使う: 杖の場合のみ。StaffAim フェーズへ（方向選択を待つ）
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                GameEngine.Audio, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        // selectedItem 読みは PartyQuery（World オーバーレイ）経由。
        let result = forM (
            m        <- entry#metadata;
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
            kind     <- player#selectedItem
        ) yield dispatchAction(m, playerId, kind, scene);
        Option.getWithDefault(scene, result)

    /// サブメニューの metadata 別に処理を分配する。`onActionConfirmed` の effect 宣言が
    /// 肥大化しないよう、分岐ロジックをここに委譲している。
    def dispatchAction(meta: String, playerId: Int32, kind: PlayerData.ItemKind,
                        scene: Scene[NodeTag]):
                       Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                GameEngine.Audio, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        if (meta == equipMeta())
            applyEquip(playerId, kind, scene)
        else if (meta == unequipMeta())
            applyUnequip(playerId, scene)
        else if (meta == dropMeta()) {
            // 印が付いていれば印の付いた分をまとめて、無ければカーソルの 1 個だけ捨てる。
            let marks = getMarks(scene);
            if (Set.isEmpty(marks)) applyDrop(playerId, kind, scene)
            else applyBulkDrop(playerId, marks, scene)
        }
        else if (meta == useMeta())
            applyUse(playerId, kind, scene)
        else if (meta == throwMeta())
            applyThrowAction(playerId, scene)
        else scene

    /// 「投げる」: 方向選択フェーズ `ThrowAim` に進む。selectedItem は保持され、
    /// 方向確定時に `Game.throwAimConfirm` → `StaffCast.applyThrow` が読む。
    def applyThrowAction(playerId: Int32, scene: Scene[NodeTag]):
                  Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, GameLogger.GameLogger} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)} は 投げる方向を選び Z で投げる (X で中止)");
        PhaseTransitions.enterThrowAim(scene)

    /// 「そうび」: 武器の場合のみ実行（杖は装備という概念がないので no-op）。
    /// `equipWeapon` で対象武器を weapons の先頭に移動 → `ItemSelect` フェーズに戻る。
    def applyEquip(playerId: Int32, kind: PlayerData.ItemKind,
                     scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, World.Command,
                                      PlayerData.PartyQuery} =
        let equipped = match kind {
            case PlayerData.ItemKind.Weapon(idx)   =>
                // 実際に並びが変わるとき (0 < idx < 本数) だけ巻き戻しドラフトを積む。
                // idx=0 / 範囲外は equipWeapon が no-op なので積まない（誤巻き戻し防止）。
                let n = List.length(weaponsOf(playerId));
                if (idx >= 1 and idx < n)
                    SelectedPlayer.pushDraft(MoveDraft.DraftAction.Equipped(playerId, idx))
                else ();
                PlayerScene.equipWeapon(playerId, idx, scene)
            case PlayerData.ItemKind.Staff(_)      => scene
            case PlayerData.ItemKind.Consumable(_) => scene
            // 指輪は先頭へ移動して装備。並び替えの巻き戻しは武器専用ドラフトのため積まない。
            case PlayerData.ItemKind.Ring(idx)     => PlayerScene.equipRing(playerId, idx, scene)
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, equipped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「はずす」: 装備中の指輪を外す（所持は維持・効果だけ止める）。ターン消費なし。
    /// `ItemSelect` フェーズに戻り、続けて操作できる。
    def applyUnequip(playerId: Int32, scene: Scene[NodeTag]):
                    Scene[NodeTag] \ {TurnPhase.State, GameLogger.GameLogger, World.Command} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)} は 指輪を外した");
        let cleared = PlayerScene.clearSelectedItem(playerId,
            PlayerScene.unequipRing(playerId, scene));
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// `droppedScene` は呼び出し側で `dropXxx` 済みの scene（純粋変換）。
    def dropResolved(playerId: Int32, kind: PlayerData.ItemKind, name: String,
                      ground: ItemData.GroundItemKind, droppedScene: Scene[NodeTag]):
                     Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId, droppedScene)} は ${name} をすてた");
        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(playerId, kind, ground));
        droppedScene

    /// 「すてる」: 武器なら `dropWeapon`、杖なら `dropStaff`。
    /// ターン消費せず ItemSelect に戻る（連続して捨てられる）。
    def applyDrop(playerId: Int32, kind: PlayerData.ItemKind,
                    scene: Scene[NodeTag]):
                   Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                                     SelectedPlayer.State, World.Command, PlayerData.PartyQuery} =
        // 削除前に実体を取得してから Dropped ドラフトを積む（誤巻き戻し防止）。
        // 該当アイテムが無ければ no-op。
        let dropped = match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                Option.getWithDefault(scene,
                    forM (w <- List.nth(idx, weaponsOf(playerId)))
                        yield dropResolved(playerId, kind, w#name,
                                  ItemData.GroundItemKind.WeaponItem(w),
                                  PlayerScene.dropWeapon(playerId, idx, scene)))
            case PlayerData.ItemKind.Staff(idx) =>
                Option.getWithDefault(scene,
                    forM (s <- List.nth(idx, stavesOf(playerId)))
                        yield dropResolved(playerId, kind, s#name,
                                  ItemData.GroundItemKind.StaffItem(s),
                                  PlayerScene.dropStaff(playerId, idx, scene)))
            case PlayerData.ItemKind.Consumable(idx) =>
                Option.getWithDefault(scene,
                    forM (c <- List.nth(idx, consumablesOf(playerId)))
                        yield dropResolved(playerId, kind, c#name,
                                  ItemData.GroundItemKind.ConsumableItem(c),
                                  PlayerScene.dropConsumable(playerId, idx, scene)))
            case PlayerData.ItemKind.Ring(idx) =>
                Option.getWithDefault(scene,
                    forM (r <- List.nth(idx, ringsOf(playerId)))
                        yield dropResolved(playerId, kind, r#name,
                                  ItemData.GroundItemKind.RingItem(r),
                                  PlayerScene.dropRing(playerId, idx, scene)))
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, dropped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 印の付いた複数アイテムをまとめて捨てる。index の大きい順に 1 個ずつ既存の
    /// `applyDrop` へ流すので、ログ・床落ち・巻き戻しドラフトは 1 個ずつ捨てたのと同じになる。
    /// 大きい index から消すことで、まだ処理していない小さい index がずれない
    /// （同じリスト内で前の要素が消えて番号が繰り上がるのを避ける）。捨て終えたら印を消す。
    def applyBulkDrop(playerId: Int32, marks: Set[PlayerData.ItemKind],
                       scene: Scene[NodeTag]):
                      Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                                        SelectedPlayer.State, World.Command, PlayerData.PartyQuery} =
        let dropped = List.foldLeft((acc, kind) -> applyDrop(playerId, kind, acc),
            scene, PlayerData.marksDescendingPerList(marks));
        setMarks(Set#{}, dropped)

    /// 「つかう」: 杖の場合のみ実行（武器の場合は「装備」項目が出るのでここには来ない）。
    /// 杖の発動方向選択フェーズ `StaffAim` に進み、ログに方向キーの操作プロンプトを出す。
    /// selectedItem は保持しておき、`StaffAim` 中の方向入力で
    /// `StaffCast.applyStaffCast` が読む。
    def applyUse(playerId: Int32, kind: PlayerData.ItemKind,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, CursorState.State, GameLogger.GameLogger,
                GameEngine.Audio, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        match kind {
            case PlayerData.ItemKind.Staff(idx) =>
                let name = staffNameOf(playerId, idx, scene);
                GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)} は ${name} の方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim(scene)
            // 消費アイテムはデリバリ（自己 / 投擲 / 自動）で経路が分かれるため別関数へ委譲する。
            case PlayerData.ItemKind.Consumable(idx) =>
                applyConsumableByDelivery(playerId, idx, scene)
            case PlayerData.ItemKind.Weapon(_) => scene
            case PlayerData.ItemKind.Ring(_)   => scene
        }

    /// 消費アイテムを効果から導いたデリバリで分岐する:
    ///   SelfUse     → その場で使用者に効果（方向選択なし）
    ///   Directional → 杖と同じ StaffAim フェーズへ（投げる方向を選ぶ）
    ///   AutoOnDeath → つかうメニューには本来出ない（所持中に自動発動）。来ても no-op。
    /// `applyUse` の `match kind` に match をネストさせないために切り出している。
    def applyConsumableByDelivery(playerId: Int32, idx: Int32, scene: Scene[NodeTag]):
                  Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, EnemyTurn.Queue,
                TurnPhase.State, SelectedPlayer.State, CursorState.State, GameLogger.GameLogger,
                GameEngine.Audio, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        match consumableDeliveryAt(playerId, idx, scene) {
            case Consumable.Delivery.SelfUse =>
                StaffCast.applyConsumableUse(playerId, idx, scene)
            case Consumable.Delivery.Directional =>
                let name = consumableNameOf(playerId, idx, scene);
                GameLogger.playerLog("${PlayerScene.displayName(playerId, scene)} は ${name} を投げる方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim(scene)
            case Consumable.Delivery.AutoOnDeath =>
                scene
        }

    /// 指定プレイヤーの consumables[idx] を取り出す（範囲外 / 未登録なら None）。
    /// PartyQuery（World オーバーレイ）経由。
    def consumableAt(playerId: Int32, idx: Int32):
            Option[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        List.nth(idx, consumablesOf(playerId))

    /// consumables[idx] の効果から導かれるデリバリ。未解決なら SelfUse 扱い（防御）。
    def consumableDeliveryAt(playerId: Int32, idx: Int32, _scene: Scene[NodeTag]):
            Consumable.Delivery \ PlayerData.PartyQuery =
        match consumableAt(playerId, idx) {
            case Some(item) => Consumable.deliveryFor(item#effect)
            case None       => Consumable.Delivery.SelfUse
        }

    /// consumables[idx] の表示名。範囲外なら "くすり" フォールバック。
    def consumableNameOf(playerId: Int32, idx: Int32, _scene: Scene[NodeTag]): String \ PlayerData.PartyQuery =
        match consumableAt(playerId, idx) {
            case Some(item) => item#name
            case None       => "くすり"
        }

    /// 指定プレイヤーの staves[idx] の名前を返す。範囲外なら "つえ" フォールバック。
    def staffNameOf(playerId: Int32, idx: Int32, _scene: Scene[NodeTag]): String \ PlayerData.PartyQuery =
        match List.nth(idx, stavesOf(playerId)) {
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
                GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
                GameEngine.Audio, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
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
