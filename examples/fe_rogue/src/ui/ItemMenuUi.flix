// ItemMenuUi — アイテム選択ウィンドウ（武器 + 消費 + 杖 + 指輪の統合インベントリ・World-entity UI 版）。
//
// UI ツリーは ItemMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「選択中味方の在庫からカテゴリの行を組む / 可視・
// 選択・パネル位置・重量ヘッダ・カテゴリヒントを毎フレーム同期する / 確定・キャンセルのゲーム
// ロジックを適用する」のゲーム側配線を持つ。
//
// ActionMenu「アイテム」確定で `ItemSelect` フェーズに入り、ActionMenu の **右隣に少し重ねて**
// 出る。↑↓ で選び ←→ でカテゴリ切替、Enter/Z で確定すると `ItemActionSelect` フェーズに進み、
// 同じウィンドウの行内容を「つかう / そうび / なげる / すてる」のサブメニューへ差し替える。
//
// 2 フェーズは **同じ root・同じ 3 行スロット** を共有し、内容を切り替える（旧 ItemList が
// 1 ノードを共用していた構造に忠実）。ItemSelect はアイコン付き 2 段組の行、ItemActionSelect は
// テキストのみの行。
//
// ウィンドウ（スクロール）: 旧 ItemList は maxVisibleRows=3 で、持ち物数（個数上限なし・重量制のみ）が
// 3 を超えると縦スクロールした。ここも **3 行の窓** に固定し、選択が窓に入るよう表示 offset を
// クランプする（`windowOffset`＝旧 `ItemList.scrollFirstVisible` と同式）。選択カーソルは在庫全体の
// index を持ち、ハイライトは窓内の相対行 (sel − offset) に置く。
//
// ノード構造（ItemMenu.ui.json / layer=8）:
//   ItemMenu (none, 画面固定 HUD)
//     └─ panel (box, パネル地・ActionMenu 右隣に abs 追従)
//           ├─ header (box) 「重 X.X/Y.Y」（左・積載段階で色替え）＋「◀ カテゴリ ▶」（右）
//           └─ menu (none, 縦並び・gap 0・行ピッチ 12px 固定)
//                 ├─ highlight (box) 選択行の塗り箱（abs 子・行より背面 z・窓内相対行へ毎フレ移動）
//                 └─ row0..row2 (none, 固定高 12px) アイテム 1 個ぶんの行
//                       （iconBg>icon, info>nameRow>name+badge(box カプセル), info>subline）
mod ItemMenuUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/ItemMenu.ui.json")

    /// root（可視トグルの対象）とパネル / リスト所有 entity の名前パス。
    pub def rootPath(): String = "ItemMenu"
    def panelPath(): String = "ItemMenu/panel"
    def menuPath(): String = "ItemMenu/panel/menu"
    def weightPath(): String = "ItemMenu/panel/header/weight"
    def hintPath(): String = "ItemMenu/panel/header/hint"

    /// 表示窓の行数（ui.json の row0..row2 と一致させること）。旧 ItemList の maxVisibleRows=3。
    /// pub: 実 asset の row 宣言数と一致することをテストが pin するため。
    pub def maxSlots(): Int32 = 3
    def rowPath(i: Int32): String = "${menuPath()}/row${i}"
    def iconBgPath(i: Int32): String = "${rowPath(i)}/iconBg"
    /// アイコンチップの無い行（サブメニュー）で icon 列（幅 7）を占位する不可視スペーサ。
    /// 旧 ItemList の `iconSize > 0` 予約（テキストなし行でも icon 列を確保）に対応する。
    def iconSpacerPath(i: Int32): String = "${rowPath(i)}/iconSpacer"
    def iconPath(i: Int32): String = "${rowPath(i)}/iconBg/icon"
    def namePath(i: Int32): String = "${rowPath(i)}/info/nameRow/name"
    def badgePath(i: Int32): String = "${rowPath(i)}/info/nameRow/badge"
    def sublinePath(i: Int32): String = "${rowPath(i)}/info/subline"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各行 height と一致させること（旧 ItemList itemHeight=12）。
    def rowPitch(): Float64 = 12.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること（旧 inset=0.5）。
    def highlightInset(): Float64 = 0.5

    /// パネルの design 空間での固定 y（ui.json の panel abs y と一致）。x は毎フレーム
    /// ActionMenu の右端へ追従させる（`applyPanelPosition`）。
    def panelY(): Float64 = 40.0
    /// コマンドメニュー (ActionMenu) に重ねる px 量（武器メニューと同じ量）。
    def panelOverlapPx(): Float64 = 5.0

    /// 装備中（武器/指輪の先頭）に出すバッジ文字（ui.json の badge テキストと一致）。
    def equippedBadge(): String = "装備"

    // ── 文字色（通常 / disabled=淡色 / 複数選択マーク=黄）──
    // 選択は塗り箱ハイライトで示すため選択行も通常色のまま（旧 ItemList は白文字 + 選択塗り箱）。
    def normalColor(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}
    def disabledColor(): Color = {r = 0.36f32, g = 0.40f32, b = 0.47f32}
    /// 複数選択した行の強調色（黄系）。交換メニューの pick 色と見た目を揃える。
    def markColor(): Color = {r = 1.0f32, g = 0.85f32, b = 0.2f32}

    // ========================================================================
    // カテゴリ（左右で切替。順序 = 武器 → 消費 → 杖 → 指輪）
    // ========================================================================

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

    // ========================================================================
    // metadata（サブメニューの操作識別 / 行の種別+index 識別）
    // ========================================================================

    def equipMeta():   String = "equip"
    def unequipMeta(): String = "unequip"
    def dropMeta():    String = "drop"
    def useMeta():     String = "use"
    def throwMeta():   String = "throw"

    /// metadata の `"w:<idx>"` / `"s:<idx>"` / `"c:<idx>"` / `"r:<idx>"` を `PlayerData.ItemKind` に
    /// パースする。不明形式は `None`。
    pub def parseItemKind(meta: String): Option[PlayerData.ItemKind] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString |> Option.map(PlayerData.ItemKind.Weapon)
        else if (String.startsWith({prefix = "s:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString |> Option.map(PlayerData.ItemKind.Staff)
        else if (String.startsWith({prefix = "c:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString |> Option.map(PlayerData.ItemKind.Consumable)
        else if (String.startsWith({prefix = "r:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString |> Option.map(PlayerData.ItemKind.Ring)
        else None

    // ========================================================================
    // カテゴリ別サブライン（各行の 2 行目）— 純粋。交換メニュー(TradeMenuUi)と共用。
    // ========================================================================

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

    // ========================================================================
    // ウィンドウ（スクロール）: 表示 offset の純関数
    // ========================================================================

    /// 表示窓の先頭 index（旧 `ItemList.scrollFirstVisible` と同式）。
    /// `slots <= 0` または `count <= slots` のときはスクロール不要で 0。それ以外は選択行を窓の
    /// 中央寄りに保ちつつ `[0, count - slots]` にクランプする（末尾で下停止・先頭で 0 停止＝wrap しない）。
    /// pub: 具体値をテストが pin するため（fillWindow / ハイライト位置の基準）。
    pub def windowOffset(sel: Int32, count: Int32, slots: Int32): Int32 =
        if (slots <= 0 or count <= slots) 0
        else {
            let maxFirst = count - slots;
            let centerOff = (slots - 1) / 2;
            Int32.min(maxFirst, Int32.max(0, sel - centerOff))
        }

    // ========================================================================
    // 行データの組み立て（選択中味方の在庫 → 表示行）
    // ========================================================================

    /// ItemSelect の 1 カテゴリ分の表示データ。items は名前/disabled(常に false)/metadata（"w:<idx>" 等）、
    /// sublines/badges は行 index → 文字列（badges は装備先頭だけキーを持つ）、
    /// sprites は items と同順（アイコンの sprite 解決に使う）。
    type alias CategoryView = {
        cat      = Int32,
        player   = PlayerScene.Data,
        items    = List[ItemEntry],
        sublines = Map[Int32, String],
        badges   = Map[Int32, String],
        sprites  = List[SpriteRes.SpriteResource],
        multi    = Bool
    }

    /// 指定カテゴリの所持数。
    def categoryCount(cat: Int32, player: PlayerScene.Data): Int32 =
        if (cat == catWeapon()) List.length(player#weapons)
        else if (cat == catConsumable()) List.length(player#consumables)
        else if (cat == catStaff()) List.length(player#staves)
        else List.length(player#rings)

    /// アイテムが 1 つ以上あるカテゴリだけを表示順で返す（在庫読みは PartyQuery＝World オーバーレイ経由）。
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

    /// `buildRows` へ渡す要素 → 表示データの写像束。
    /// `nameOf`: 本文（1 行目）。`sublineOf`: 2 行目。`spriteOf`: 行頭アイコン。
    /// `equipHead`: true なら先頭行に「装備」バッジを付ける。
    type alias RowBuilders[a] = {
        nameOf    = a -> String,
        sublineOf = a -> String,
        spriteOf  = a -> SpriteRes.SpriteResource,
        equipHead = Bool
    }

    /// 1 カテゴリの行を汎用に組む。metadata は `"${prefix}:${idx}"` 形式で、確定・装備・捨て・
    /// マークの解決に使う。
    def buildRows(prefix: String, xs: List[a], builders: RowBuilders[a]):
            (List[ItemEntry], Map[Int32, String], Map[Int32, String], List[SpriteRes.SpriteResource]) =
        let indexed = List.zipWithIndex(xs);
        let items = List.map(p -> {
            let (idx, x) = p;
            ({text = builders#nameOf(x), disabled = false, metadata = Some("${prefix}:${idx}")}: ItemEntry)
        }, indexed);
        let sublines = List.foldLeft((acc, p) ->
            let (idx, x) = p; Map.insert(idx, builders#sublineOf(x), acc), Map.empty(), indexed);
        let sprites = List.map(builders#spriteOf, xs);
        let badges = if (builders#equipHead and not List.isEmpty(xs))
                Map.insert(0, equippedBadge(), Map.empty())
            else Map.empty();
        (items, sublines, badges, sprites)

    /// 現在カテゴリの (items, sublines, badges, sprites) を組む。サブラインは種別ごとに出し分ける。
    def categoryRows(cat: Int32, player: PlayerScene.Data):
            (List[ItemEntry], Map[Int32, String], Map[Int32, String], List[SpriteRes.SpriteResource]) =
        if (cat == catWeapon())
            buildRows("w", player#weapons,
                {nameOf = w -> w#name, sublineOf = w -> WeaponSelectUi.weaponSubline(w), spriteOf = w -> w#sprite, equipHead = true})
        else if (cat == catConsumable())
            buildRows("c", player#consumables,
                {nameOf = c -> c#name, sublineOf = consumableSubline, spriteOf = c -> c#sprite, equipHead = false})
        else if (cat == catStaff())
            buildRows("s", player#staves,
                {nameOf = s -> s#name, sublineOf = staffSubline, spriteOf = s -> s#sprite, equipHead = false})
        else
            buildRows("r", player#rings,
                {nameOf = r -> r#name, sublineOf = ringStatLine, spriteOf = r -> r#sprite, equipHead = player#ringEquipped})

    /// 選択中味方の「現在カテゴリ」表示データを組む。現在カテゴリが空ならアイテムのある先頭カテゴリへ
    /// クランプする。選択中味方が居ない / 見つからないなら None。
    def resolveCategoryView(): Option[CategoryView]
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield {
            let cats = nonEmptyCategories(playerId);
            let cur0 = ItemMenuState.State.get()#category;
            let cur  = if (List.memberOf(cur0, cats)) cur0
                       else List.head(cats) |> Option.getWithDefault(catWeapon());
            let (items, sublines, badges, sprites) = categoryRows(cur, player);
            {cat = cur, player = player, items = items, sublines = sublines,
             badges = badges, sprites = sprites, multi = List.length(cats) > 1}
        }

    // ── サブメニュー（ItemActionSelect）───────────────────────────────────

    /// 「そうび」「はずす」「つかう」「なげる」「すてる」の項目。
    def equipEntry(): ItemEntry   = {text = "装備", disabled = false, metadata = Some(equipMeta())}
    def unequipEntry(): ItemEntry = {text = "外す", disabled = false, metadata = Some(unequipMeta())}
    def useEntry(): ItemEntry     = {text = "使う", disabled = false, metadata = Some(useMeta())}
    def throwEntry(): ItemEntry   = {text = "投げる", disabled = false, metadata = Some(throwMeta())}
    def dropEntry(): ItemEntry    = {text = "捨てる", disabled = false, metadata = Some(dropMeta())}

    /// 選択中アイテム種別に応じたサブメニュー項目。
    ///   武器           → [そうび, なげる, すてる]
    ///   杖・消費品      → [つかう, なげる, すてる]
    ///   指輪(未装備)    → [そうび, なげる, すてる]
    ///   指輪(装備中)    → [はずす, なげる, すてる]
    ///   未選択          → []
    /// `ringEquipped` は選択中味方の指輪装備フラグ。装備中の指輪（先頭 = index 0）を選んだときだけ「外す」。
    /// `bulkMode`（Shift 複数選択中）が true のときは「捨てる」だけ有効、他は disabled。
    /// `holdOnly`（浮雲など「持つだけ」系）が true のときは装備も使用も投擲もできず「捨てる」だけ。
    /// pub: 文脈分岐（項目の text/disabled/meta）をテストが直接 pin するため。
    pub def actionItemsFor(sel: Option[PlayerData.ItemKind], ringEquipped: Bool,
                           bulkMode: Bool, holdOnly: Bool): List[ItemEntry] =
        // 並び順は「使う/装備 → 投げる → 捨てる」。投げるは全種別で出す（一律投擲可）。
        let base = if (holdOnly) dropEntry() :: Nil else match sel {
            case Some(PlayerData.ItemKind.Weapon(_)) =>
                equipEntry() :: throwEntry() :: dropEntry() :: Nil
            case Some(PlayerData.ItemKind.Staff(_))      =>
                useEntry() :: throwEntry() :: dropEntry() :: Nil
            case Some(PlayerData.ItemKind.Consumable(_)) =>
                useEntry() :: throwEntry() :: dropEntry() :: Nil
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

    /// 選択中アイテムが「持つだけ」系（浮雲など装備も使用もできず捨てるのみ）か。現状は指輪の Levitate のみ。
    def isSelectedPassiveHold(player: PlayerScene.Data): Bool =
        match player#selectedItem {
            case Some(PlayerData.ItemKind.Ring(idx)) =>
                List.nth(idx, player#rings)
                    |> Option.map(Ring.isPassiveHold)
                    |> Option.getWithDefault(false)
            case _ => false
        }

    /// 現在の submenu 項目（ItemActionSelect 中）を組む。選択中味方が居なければ空。
    def submenuItems(): List[ItemEntry]
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery} =
        let bulk = not Set.isEmpty(ItemMenuState.State.get()#marks);
        let itemsOpt = forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield actionItemsFor(player#selectedItem, player#ringEquipped, bulk, isSelectedPassiveHold(player));
        Option.getWithDefault(Nil, itemsOpt)

    // ========================================================================
    // 毎フレーム同期（可視 + 窓流し込み + パネル追従 + 重量/カテゴリヘッダ + 選択ハイライト）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System（旧 refreshItems + applyVisibility の置換）。
    /// ItemSelect ではカテゴリの在庫を、ItemActionSelect ではサブメニューを、同じウィンドウへ流し込む。
    /// それ以外のフェーズでは全行を隠し、カーソルとカテゴリを先頭へ戻す。
    pub def frameStep(_dt: Duration.Duration): Unit
            \ {TurnPhase.State, SelectedPlayer.State, PlayerData.PartyQuery,
               ItemMenuState.State, UiWorldState.State} =
        let phase = TurnPhase.State.get();
        if (phase == TurnPhase.Phase.ItemSelect) syncItemSelect()
        else if (phase == TurnPhase.Phase.ItemActionSelect) syncActionSelect()
        else {
            // 非表示中はカーソルを先頭に戻し、カテゴリを武器へ戻し、全行を隠す（印は保持）。
            // これで次に開いたとき常に先頭カテゴリ・先頭項目から始まる。
            let st = ItemMenuState.State.get();
            ItemMenuState.State.put({category = catWeapon() | st});
            let ui = UiWorldState.State.get();
            UiWorldState.State.put(ui
                |> UiStore.setVisible(rootPath(), false)
                |> hideAllRows
                |> UiStore.putSelection(menuPath(), 0))
        }

    /// ItemSelect: 現在カテゴリの在庫を窓へ流し込む。
    def syncItemSelect(): Unit
            \ {SelectedPlayer.State, PlayerData.PartyQuery, ItemMenuState.State, UiWorldState.State} =
        match resolveCategoryView() {
            case None       =>
                UiWorldState.State.put(UiStore.setVisible(rootPath(), false, UiWorldState.State.get()))
            case Some(view) =>
                // クランプ後の実カテゴリを resource に書き戻す（印はそのまま）。
                let marks = ItemMenuState.State.get()#marks;
                ItemMenuState.State.put({category = view#cat, marks = marks});
                let ui0 = UiWorldState.State.get();
                let count = List.length(view#items);
                // ItemSelect の項目は disabled にならないので単純クランプでよい。
                let sel = clampIndex(count, UiStore.selectionOf(menuPath(), ui0));
                let offset = windowOffset(sel, count, maxSlots());
                UiWorldState.State.put(ui0
                    |> UiStore.setVisible(rootPath(), true)
                    |> applyPanelPosition
                    |> setWeightHeader(view#player)
                    |> setHintLabel(view#cat, view#multi)
                    |> UiStore.setVisible(hintPath(), true)
                    |> fillWindow({items = view#items, sublines = view#sublines, badges = view#badges,
                                  sprites = view#sprites, marks = marks, offset = offset, showChrome = true})
                    |> UiStore.putSelection(menuPath(), sel)
                    |> applyWindowHighlight(sel, offset))
        }

    /// ItemActionSelect: サブメニュー（テキストのみ）を窓へ流し込む。
    def syncActionSelect(): Unit
            \ {SelectedPlayer.State, PlayerData.PartyQuery, ItemMenuState.State, UiWorldState.State} =
        let playerOpt = forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield player;
        match playerOpt {
            case None         =>
                UiWorldState.State.put(UiStore.setVisible(rootPath(), false, UiWorldState.State.get()))
            case Some(player) =>
                let bulk = not Set.isEmpty(ItemMenuState.State.get()#marks);
                let items = actionItemsFor(player#selectedItem, player#ringEquipped, bulk,
                                           isSelectedPassiveHold(player));
                let count = List.length(items);
                let ui0 = UiWorldState.State.get();
                let sel0 = UiStore.selectionOf(menuPath(), ui0);
                // 複数選択中は唯一有効な「捨てる」へカーソルを寄せる。それ以外で disabled 上なら
                // 選択可能行へ寄せる（防御。通常サブメニューは disabled なし）。
                let selResolved =
                    if (bulk) dropRowIndex(items)
                    else if (selectedIsDisabledAt(sel0, items)) firstEnabledIndex(items)
                    else sel0;
                let sel = clampIndex(count, selResolved);
                let offset = windowOffset(sel, count, maxSlots());
                UiWorldState.State.put(ui0
                    |> UiStore.setVisible(rootPath(), true)
                    |> applyPanelPosition
                    |> setWeightHeader(player)
                    |> UiStore.setVisible(hintPath(), false)
                    |> fillWindow({items = items, sublines = Map.empty(), badges = Map.empty(),
                                  sprites = Nil, marks = Set#{}, offset = offset, showChrome = false})
                    |> UiStore.putSelection(menuPath(), sel)
                    |> applyWindowHighlight(sel, offset))
        }

    /// アイテム窓を ActionMenu（コマンドメニュー）の右端基準で配置する。武器メニューと同じ量だけ重ねる。
    def applyPanelPosition(ui: UiStore.UiWorld): UiStore.UiWorld \ UiWorldState.State =
        let newX = ActionMenuUi.panelDesignRight() - panelOverlapPx();
        UiStore.setAbs(panelPath(), {x = newX, y = panelY()}, ui)

    /// ヘッダ左を「重 X.X/Y.Y」の重量ゲージにし、積載段階で色を変える
    /// （通常=ヘッダ色 / 80%+=黄 / 100%+=橙 / 110%+=赤）。
    def setWeightHeader(player: PlayerScene.Data, ui: UiStore.UiWorld): UiStore.UiWorld =
        let load = PlayerScene.loadOf(player);
        ui
            |> UiStore.setText(weightPath(),
                "重 ${Encumbrance.weightText(load#total)}/${Encumbrance.weightText(load#capacity)}")
            |> UiStore.setTextTint(weightPath(), UITheme.encumbranceTierColor(load#tier))

    /// ヘッダ右のヒントを現在カテゴリ名にする。切替先が複数あるときだけ ◀ ▶ を付ける。
    def setHintLabel(cat: Int32, multi: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        let txt = if (multi) "◀ ${categoryLabel(cat)} ▶" else categoryLabel(cat);
        UiStore.setText(hintPath(), txt, ui)

    /// `fillWindow` の引数束。
    /// `items`: 表示窓へ流し込む項目列（在庫全体の順序）。
    /// `sublines`: 行 index → 2 行目文字列（showChrome=false のときは無視）。
    /// `badges`: 行 index → バッジ文字列（装備先頭だけキーを持つ。showChrome=false のときは無視）。
    /// `sprites`: items と同順のアイコン sprite 列（showChrome=false のときは無視）。
    /// `marks`: 複数選択マーク集合（強調色の判定に使う）。
    /// `offset`: 表示窓の先頭 index。
    /// `showChrome`: true ならアイコン/サブライン/装備バッジを出す（ItemSelect）、
    /// false ならテキストのみ（ItemActionSelect）。
    type alias WindowFill = {
        items      = List[ItemEntry],
        sublines   = Map[Int32, String],
        badges     = Map[Int32, String],
        sprites    = List[SpriteRes.SpriteResource],
        marks      = Set[PlayerData.ItemKind],
        offset     = Int32,
        showChrome = Bool
    }

    /// items[offset..offset+slots) を行 0..slots-1 へ流し込む。窓外の行は meta を消して不可視にする。
    /// `showChrome` が true（ItemSelect）ならアイコン/サブライン/装備バッジ/マーク色を出す。
    /// false（ItemActionSelect）ならテキストのみ（アイコン/サブライン/バッジは隠す・マークなし）。
    def fillWindow(fill: WindowFill, ui: UiStore.UiWorld): UiStore.UiWorld =
        List.range(0, maxSlots()) |> List.foldLeft((acc, i) -> {
            let itemIdx = fill#offset + i;
            match List.nth(itemIdx, fill#items) {
                case Some(entry) =>
                    let hasIcon = fill#showChrome and Option.nonEmpty(List.nth(itemIdx, fill#sprites));
                    let base = UiStore.setVisible(iconBgPath(i), hasIcon, acc);
                    let withIcon =
                        match (if (hasIcon) List.nth(itemIdx, fill#sprites) else None) {
                            case Some(spr) => UiStore.setSprite({path = iconPath(i), texture = spr#texture,
                                                  hframes = spr#hframes, vframes = spr#vframes, frame = spr#frame}, base)
                            case None      => base
                        };
                    let hasBadge = fill#showChrome and Option.nonEmpty(Map.get(itemIdx, fill#badges));
                    let subText  = if (fill#showChrome) Option.getWithDefault("", Map.get(itemIdx, fill#sublines)) else "";
                    let hasSubline = not String.isEmpty(subText);
                    withIcon
                        // チップの無い行（サブメニュー）は icon 列を不可視スペーサで占位し名前 x を揃える。
                        |> UiStore.setVisible(iconSpacerPath(i), not hasIcon)
                        |> UiStore.setText(namePath(i), entry#text)
                        |> UiStore.setTextTint(namePath(i), rowTint(entry, fill#marks))
                        |> UiStore.setText(sublinePath(i), subText)
                        |> UiStore.setVisible(badgePath(i), hasBadge)
                        // サブラインの無い行（サブメニュー）はサブラインを畳んで名前 1 行を行内で縦中央に置く。
                        |> UiStore.setVisible(sublinePath(i), hasSubline)
                        |> UiStore.setMeta(rowPath(i), Option.getWithDefault("", entry#metadata))
                        |> UiStore.setVisible(rowPath(i), true)
                case None =>
                    acc
                        |> UiStore.clearMeta(rowPath(i))
                        |> UiStore.setVisible(rowPath(i), false)
            }
        }, ui)

    /// 全行を隠して meta も消す（非表示フェーズ用）。
    def hideAllRows(ui: UiStore.UiWorld): UiStore.UiWorld =
        List.range(0, maxSlots()) |> List.foldLeft((acc, i) ->
            acc |> UiStore.clearMeta(rowPath(i)) |> UiStore.setVisible(rowPath(i), false), ui)

    /// 行の name text tint。disabled=淡色、複数選択マーク付き=黄、それ以外（選択含む）=通常色
    /// （選択は塗り箱ハイライトで示すため文字色は変えない）。マークは entry の metadata（種別+index）で判定する。
    def rowTint(entry: ItemEntry, marks: Set[PlayerData.ItemKind]): Color =
        if (entry#disabled) disabledColor()
        else if (isMarkedAt(entry, marks)) markColor()
        else normalColor()

    /// entry の metadata（種別+index）が複数選択マーク集合に含まれるか。
    def isMarkedAt(entry: ItemEntry, marks: Set[PlayerData.ItemKind]): Bool =
        entry#metadata
            |> Option.flatMap(parseItemKind)
            |> Option.map(k -> Set.memberOf(k, marks))
            |> Option.getWithDefault(false)

    /// 選択行の塗り箱を窓内の相対行（sel − offset）へ動かす。
    def applyWindowHighlight(sel: Int32, offset: Int32, ui: UiStore.UiWorld): UiStore.UiWorld =
        UiMenu.applyHighlight({listPath = menuPath(), highlightPath = highlightPath(),
                               sel = sel - offset, rowPitch = rowPitch(), inset = highlightInset()}, ui)

    /// 選択 index を [0, count) へ収める純関数。項目 0 のときは 0。
    def clampIndex(count: Int32, sel: Int32): Int32 =
        if (count <= 0) 0 else Int32.max(0, Int32.min(count - 1, sel))

    /// items の最初の「選択可能（not disabled）」行 index。全部 disabled なら 0。
    def firstEnabledIndex(items: List[ItemEntry]): Int32 =
        items
            |> List.zipWithIndex
            |> List.findLeft(pair -> {let (_i, entry) = pair; not entry#disabled})
            |> Option.map(pair -> {let (i, _entry) = pair; i})
            |> Option.getWithDefault(0)

    /// 選択 index が disabled 行を指しているか（範囲外は false）。
    def selectedIsDisabledAt(sel: Int32, items: List[ItemEntry]): Bool =
        List.nth(sel, items) |> Option.map(e -> e#disabled) |> Option.getWithDefault(false)

    /// items 内の「捨てる」行 index（複数選択中のカーソル寄せ先）。無ければ 0。
    def dropRowIndex(items: List[ItemEntry]): Int32 =
        List.zipWithIndex(items)
            |> List.findLeft(p -> snd(p)#metadata == Some(dropMeta()))
            |> Option.map(fst)
            |> Option.getWithDefault(0)

    // ========================================================================
    // 選択 / 確定 / キャンセル / カテゴリ / マーク
    // ========================================================================

    /// 選択カーソルを delta（±1）動かす（disabled をスキップ・端で回り込む）。
    /// 現在フェーズ（ItemSelect / ItemActionSelect）に応じた項目列を基準にする。
    pub def moveSelection(delta: Int32): Unit
            \ {TurnPhase.State, UiWorldState.State, SelectedPlayer.State,
               ItemMenuState.State, PlayerData.PartyQuery} =
        let items = currentItems();
        let ui = UiWorldState.State.get();
        let count = List.length(items);
        let disabledAt = i -> List.nth(i, items) |> Option.map(e -> e#disabled) |> Option.getWithDefault(true);
        let next = UiWidget.selectionMoveSkipping(count, delta, UiStore.selectionOf(menuPath(), ui), disabledAt);
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui))

    /// 現在フェーズの項目列（ItemSelect=現在カテゴリの在庫 / ItemActionSelect=サブメニュー）。
    def currentItems(): List[ItemEntry]
            \ {TurnPhase.State, SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery} =
        match TurnPhase.State.get() {
            case TurnPhase.Phase.ItemSelect       =>
                resolveCategoryView() |> Option.map(v -> v#items) |> Option.getWithDefault(Nil)
            case TurnPhase.Phase.ItemActionSelect => submenuItems()
            case _                                => Nil
        }

    /// InputHandler の Z 押下から呼ばれる。現在フェーズに応じて確定を振り分ける。
    /// ItemSelect の Enter → `onItemConfirmed`、ItemActionSelect の Enter → `onActionConfirmed`。
    pub def confirmCurrentSelection(): Unit
            \ {RangeOverlayState.State, EnemyTurn.Queue,
               GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
               ArrowCursorState.State, ItemMenuState.State, GameEngine.Audio, World.Command,
               World.WorldQuery, PlayerData.PartyQuery, UiWorldState.State} =
        let phase = TurnPhase.State.get();
        let sel = UiStore.selectionOf(menuPath(), UiWorldState.State.get());
        match List.nth(sel, currentItems()) {
            case None        => ()
            case Some(entry) =>
                match phase {
                    case TurnPhase.Phase.ItemSelect       => onItemConfirmed(entry)
                    case TurnPhase.Phase.ItemActionSelect =>
                        if (entry#disabled) () else onActionConfirmed(entry)
                    case _                                => ()
                }
        }

    /// ActionMenu「アイテム」確定で呼ばれる。`ItemSelect` フェーズに遷移する。
    /// 常に「アイテムのある先頭カテゴリ」・印なし・カーソル先頭から開く（カーソル 0 は非表示中の
    /// frameStep が戻してある）。
    pub def openFor(playerId: Int32):
            Unit \ {TurnPhase.State, ItemMenuState.State, PlayerData.PartyQuery, RangeOverlayState.State, CursorState.State} =
        PhaseTransitions.enterItemSelect();
        let firstCat = nonEmptyCategories(playerId) |> List.head |> Option.getWithDefault(catWeapon());
        ItemMenuState.State.put({category = firstCat, marks = Set#{}})

    /// ItemSelect 中に Shift が押されたとき、カーソル位置のアイテムの印を付け外しする。
    /// カーソル行の種別+index を取り、マーク集合をトグルして書き戻す。アイテム以外に乗っていれば no-op。
    pub def toggleMarkAtCursor(): Unit
            \ {UiWorldState.State, SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery} =
        let sel = UiStore.selectionOf(menuPath(), UiWorldState.State.get());
        let kindOpt = List.nth(sel, currentSelectItems())
            |> Option.flatMap(entry -> entry#metadata)
            |> Option.flatMap(parseItemKind);
        kindOpt
            |> Option.map(kind -> {
                let st = ItemMenuState.State.get();
                ItemMenuState.State.put({marks = PlayerData.toggleMark(kind, st#marks) | st})
            })
            |> Option.getWithDefault(())

    /// ItemSelect の現在カテゴリ項目列（toggleMark はフェーズ既知なので専用に読む）。
    def currentSelectItems(): List[ItemEntry]
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery} =
        resolveCategoryView() |> Option.map(v -> v#items) |> Option.getWithDefault(Nil)

    /// ←（前カテゴリ）/ →（次カテゴリ）。在庫のあるカテゴリだけを巡回し、カーソルを先頭へ戻す。
    pub def categoryPrev(): Unit
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        cycleCategory(-1)
    pub def categoryNext(): Unit
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        cycleCategory(1)
    def cycleCategory(dir: Int32): Unit
            \ {SelectedPlayer.State, ItemMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        match SelectedPlayer.State.get()#id {
            case None           => ()
            case Some(playerId) =>
                let cats = nonEmptyCategories(playerId);
                let st = ItemMenuState.State.get();
                let next = nextCategoryIn(cats, st#category, dir);
                ItemMenuState.State.put({category = next | st});
                // カテゴリを変えたら選択カーソルを先頭へ戻す（旧 setCategoryIdx の selectedIndex(0)）。
                UiWorldState.State.put(UiStore.putSelection(menuPath(), 0, UiWorldState.State.get()))
        }

    /// ItemSelect で項目を Enter 確定したとき。選択中アイテム種別を Data に書いて
    /// `ItemActionSelect` フェーズに進む（サブメニュー表示へ）。サブメニューは常に先頭から始める。
    pub def onItemConfirmed(entry: ItemEntry): Unit
            \ {TurnPhase.State, SelectedPlayer.State, UiWorldState.State, World.Command} =
        let result = forM (
            kind     <- entry#metadata |> Option.flatMap(parseItemKind);
            playerId <- SelectedPlayer.State.get()#id
        ) yield {
            PlayerScene.setSelectedItem(playerId, kind);
            TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
            UiWorldState.State.put(UiStore.putSelection(menuPath(), 0, UiWorldState.State.get()))
        };
        Option.getWithDefault((), result)

    /// ItemSelect で X / Escape 押下: ActionMenu に戻る（= ActionSelect フェーズ）。
    /// 閉じる時に先頭カテゴリへ戻し、複数選択の印も消し、カーソルを先頭へ戻す。
    pub def onItemCancelled(): Unit
            \ {TurnPhase.State, ItemMenuState.State, UiWorldState.State} =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        ItemMenuState.State.put({category = catWeapon(), marks = Set#{}});
        UiWorldState.State.put(UiStore.putSelection(menuPath(), 0, UiWorldState.State.get()))

    /// ItemActionSelect で X / Escape 押下: ItemSelect に戻る。選択中アイテムをクリアする。
    pub def onActionCancelled(): Unit
            \ {TurnPhase.State, SelectedPlayer.State, World.Command} =
        match SelectedPlayer.State.get()#id {
            case Some(playerId) => PlayerScene.clearSelectedItem(playerId)
            case None           => ()
        };
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect)

    /// ItemActionSelect でサブメニュー項目を Enter 確定したとき。metadata で処理を分配する。
    /// pub: confirm 経路のゲームロジック（equip/drop/use/throw/bulk）をテストが pin するため。
    pub def onActionConfirmed(entry: ItemEntry): Unit
            \ {RangeOverlayState.State, EnemyTurn.Queue,
               GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
               ArrowCursorState.State, ItemMenuState.State, GameEngine.Audio, World.Command,
               World.WorldQuery, PlayerData.PartyQuery} =
        // selectedItem 読みは PartyQuery（World オーバーレイ）経由。
        let result = forM (
            m        <- entry#metadata;
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
            kind     <- player#selectedItem
        ) yield dispatchAction(m, playerId, kind);
        Option.getWithDefault((), result)

    /// サブメニューの metadata 別に処理を分配する。
    def dispatchAction(meta: String, playerId: Int32, kind: PlayerData.ItemKind): Unit
            \ {RangeOverlayState.State, EnemyTurn.Queue,
               GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State, CursorState.State,
               ArrowCursorState.State, ItemMenuState.State, GameEngine.Audio, World.Command,
               World.WorldQuery, PlayerData.PartyQuery} =
        if (meta == equipMeta())
            applyEquip(playerId, kind)
        else if (meta == unequipMeta())
            applyUnequip(playerId)
        else if (meta == dropMeta()) {
            // 印が付いていれば印の付いた分をまとめて、無ければカーソルの 1 個だけ捨てる。
            let marks = ItemMenuState.State.get()#marks;
            if (Set.isEmpty(marks)) applyDrop(playerId, kind)
            else applyBulkDrop(playerId, marks)
        }
        else if (meta == useMeta())
            applyUse(playerId, kind)
        else if (meta == throwMeta())
            applyThrowAction(playerId)
        else ()

    /// 「投げる」: 方向選択フェーズ `ThrowAim` に進む。selectedItem は保持され、方向確定時に読む。
    def applyThrowAction(playerId: Int32): Unit
            \ {TurnPhase.State, SelectedPlayer.State, ArrowCursorState.State, GameLogger.GameLogger,
               CursorState.State, World.WorldQuery} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は 投げる方向を選び Z で投げる (X で中止)");
        PhaseTransitions.enterThrowAim()

    /// 「そうび」: 武器/指輪を先頭へ移動して装備し、`ItemSelect` フェーズに戻る（ターン消費なし）。
    /// 杖・消費アイテムは装備概念がないので no-op。
    def applyEquip(playerId: Int32, kind: PlayerData.ItemKind): Unit
            \ {TurnPhase.State, SelectedPlayer.State, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        match kind {
            case PlayerData.ItemKind.Weapon(idx)   =>
                // 実際に並びが変わるとき (0 < idx < 本数) だけ巻き戻しドラフトを積む。
                let n = List.length(weaponsOf(playerId));
                if (idx >= 1 and idx < n)
                    SelectedPlayer.pushDraft(MoveDraft.DraftAction.Equipped(playerId, idx))
                else ();
                PlayerScene.equipWeapon(playerId, idx)
            case PlayerData.ItemKind.Staff(_)      => ()
            case PlayerData.ItemKind.Consumable(_) => ()
            case PlayerData.ItemKind.Ring(idx)     => PlayerScene.equipRing(playerId, idx)
        };
        PlayerScene.clearSelectedItem(playerId);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect)

    /// 「はずす」: 装備中の指輪を外す（所持は維持・効果だけ止める）。ターン消費なし。`ItemSelect` に戻る。
    def applyUnequip(playerId: Int32): Unit
            \ {TurnPhase.State, GameLogger.GameLogger, World.Command, World.WorldQuery} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は 指輪を外した");
        PlayerScene.unequipRing(playerId);
        PlayerScene.clearSelectedItem(playerId);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect)

    /// 対応する削除処理（`dropXxx`）は呼び出し側で実行済み。ここはログと巻き戻しドラフトの記録のみ行う。
    def dropResolved(playerId: Int32, kind: PlayerData.ItemKind, name: String,
                     ground: ItemData.GroundItemKind): Unit
            \ {GameLogger.GameLogger, SelectedPlayer.State, World.WorldQuery} =
        GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${name} をすてた");
        SelectedPlayer.pushDraft(MoveDraft.DraftAction.Dropped(playerId, kind, ground))

    /// 「すてる」: 種別に応じて削除し、ターン消費せず ItemSelect に戻る（連続して捨てられる）。
    def applyDrop(playerId: Int32, kind: PlayerData.ItemKind): Unit
            \ {GameLogger.GameLogger, TurnPhase.State,
               SelectedPlayer.State, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        match kind {
            case PlayerData.ItemKind.Weapon(idx) =>
                Option.getWithDefault((),
                    forM (w <- List.nth(idx, weaponsOf(playerId)))
                        yield {
                            PlayerScene.dropWeapon(playerId, idx);
                            dropResolved(playerId, kind, w#name, ItemData.GroundItemKind.WeaponItem(w))
                        })
            case PlayerData.ItemKind.Staff(idx) =>
                Option.getWithDefault((),
                    forM (s <- List.nth(idx, stavesOf(playerId)))
                        yield {
                            PlayerScene.dropStaff(playerId, idx);
                            dropResolved(playerId, kind, s#name, ItemData.GroundItemKind.StaffItem(s))
                        })
            case PlayerData.ItemKind.Consumable(idx) =>
                Option.getWithDefault((),
                    forM (c <- List.nth(idx, consumablesOf(playerId)))
                        yield {
                            PlayerScene.dropConsumable(playerId, idx);
                            dropResolved(playerId, kind, c#name, ItemData.GroundItemKind.ConsumableItem(c))
                        })
            case PlayerData.ItemKind.Ring(idx) =>
                Option.getWithDefault((),
                    forM (r <- List.nth(idx, ringsOf(playerId)))
                        yield {
                            PlayerScene.dropRing(playerId, idx);
                            dropResolved(playerId, kind, r#name, ItemData.GroundItemKind.RingItem(r))
                        })
        };
        PlayerScene.clearSelectedItem(playerId);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect)

    /// 印の付いた複数アイテムをまとめて捨てる。index の大きい順に 1 個ずつ `applyDrop` へ流す
    /// （大きい index から消すことで、まだ処理していない小さい index がずれない）。捨て終えたら印を消す。
    def applyBulkDrop(playerId: Int32, marks: Set[PlayerData.ItemKind]): Unit
            \ {GameLogger.GameLogger, TurnPhase.State,
               SelectedPlayer.State, ItemMenuState.State, World.Command, World.WorldQuery, PlayerData.PartyQuery} =
        List.forEach(kind -> applyDrop(playerId, kind), PlayerData.marksDescendingPerList(marks));
        let st = ItemMenuState.State.get();
        ItemMenuState.State.put({marks = Set#{} | st})

    /// 「つかう」: 杖なら発動方向選択 `StaffAim` へ、消費アイテムはデリバリで分岐。武器/指輪は no-op。
    def applyUse(playerId: Int32, kind: PlayerData.ItemKind): Unit
            \ {RangeOverlayState.State, EnemyTurn.Queue,
               TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
               GameLogger.GameLogger, GameEngine.Audio, World.Command, World.WorldQuery,
               PlayerData.PartyQuery} =
        match kind {
            case PlayerData.ItemKind.Staff(idx) =>
                let name = staffNameOf(playerId, idx);
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${name} の方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim()
            case PlayerData.ItemKind.Consumable(idx) =>
                applyConsumableByDelivery(playerId, idx)
            case PlayerData.ItemKind.Weapon(_) => ()
            case PlayerData.ItemKind.Ring(_)   => ()
        }

    /// 消費アイテムを効果から導いたデリバリで分岐する（自己使用 / 方向投擲 / 自動発動）。
    def applyConsumableByDelivery(playerId: Int32, idx: Int32): Unit
            \ {RangeOverlayState.State, EnemyTurn.Queue,
               TurnPhase.State, SelectedPlayer.State, CursorState.State, ArrowCursorState.State,
               GameLogger.GameLogger, GameEngine.Audio, World.Command, World.WorldQuery,
               PlayerData.PartyQuery} =
        match consumableDeliveryAt(playerId, idx) {
            case Consumable.Delivery.SelfUse =>
                StaffCast.applyConsumableUse(playerId, idx)
            case Consumable.Delivery.Directional =>
                let name = consumableNameOf(playerId, idx);
                GameLogger.playerLog("${PlayerScene.displayName(playerId)} は ${name} を投げる方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim()
            case Consumable.Delivery.AutoOnDeath =>
                ()
        }

    // ── 在庫読みの薄ラッパ（PartyQuery＝World オーバーレイ経由）──

    def weaponsOf(id: Int32): List[UnitCatalog.WeaponResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#weapons) |> Option.getWithDefault(Nil)
    def stavesOf(id: Int32): List[Staff.StaffResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#staves) |> Option.getWithDefault(Nil)
    def consumablesOf(id: Int32): List[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#consumables) |> Option.getWithDefault(Nil)
    def ringsOf(id: Int32): List[Ring.RingResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#rings) |> Option.getWithDefault(Nil)

    /// 指定プレイヤーの consumables[idx]（範囲外 / 未登録なら None）。
    def consumableAt(playerId: Int32, idx: Int32):
            Option[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        List.nth(idx, consumablesOf(playerId))

    /// consumables[idx] の効果から導かれるデリバリ。未解決なら SelfUse 扱い（防御）。
    def consumableDeliveryAt(playerId: Int32, idx: Int32): Consumable.Delivery \ PlayerData.PartyQuery =
        match consumableAt(playerId, idx) {
            case Some(item) => Consumable.deliveryFor(item#effect)
            case None       => Consumable.Delivery.SelfUse
        }

    /// consumables[idx] の表示名。範囲外なら "くすり" フォールバック。
    def consumableNameOf(playerId: Int32, idx: Int32): String \ PlayerData.PartyQuery =
        match consumableAt(playerId, idx) {
            case Some(item) => item#name
            case None       => "くすり"
        }

    /// 指定プレイヤーの staves[idx] の名前。範囲外なら "杖" フォールバック。
    def staffNameOf(playerId: Int32, idx: Int32): String \ PlayerData.PartyQuery =
        match List.nth(idx, stavesOf(playerId)) {
            case Some(staff) => staff#name
            case None        => "杖"
        }

    // ========================================================================
    // 攻撃中の武器 index 解決（BattlePanelUi と共用する seam）
    // ========================================================================

    /// カーソル上の敵に届く「選択すべき武器」の index（weapons 内）。`BattlePanelUi` が予報と
    /// 攻撃開始で読む。現在カーソル上の敵との距離に届く先頭武器を返す。カーソルが敵に乗っていない /
    /// 届く武器が無いなら None。
    pub def activeAttackWeaponIndex(): Option[Int32]
            \ {SelectedPlayer.State, CursorState.State, PlayerData.PartyQuery, World.WorldQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId);
            d        <- cursorTargetDistance(playerId);
            idx      <- PlayerScene.firstWeaponIdxReaching(player, d)
        ) yield idx

    /// カーソルが乗っている敵と選択中味方とのマンハッタン距離。敵が居なければ None。
    def cursorTargetDistance(playerId: Int32):
            Option[Int32] \ {World.WorldQuery, CursorState.State} =
        forM (
            player <- PlayerScene.get(playerId);
            eid    <- EnemyScene.findIdAt(CursorScene.getGridPos());
            enemy  <- EnemyScene.get(eid)
        ) yield Weapon.manhattan(player#gridPos, enemy#gridPos)
}
