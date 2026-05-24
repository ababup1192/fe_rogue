/// TradeMenuScene — 物交換ウィンドウ (じぶん / あいて の 2 ペイン)
///
/// `TradeTargetSelect` で交換相手を確定すると `TradeInventory` フェーズに入り、
/// 画面に出る 2 つの ItemList。左 (selfMenu) に選択中味方、右 (partnerMenu) に
/// 交換相手の weapons + staves を並べる。↑↓ で選択、Enter/Z で確定。
///
/// 入力フロー (Phase 4-D で本実装、4-B 時点では visibility + items 同期のみ):
///   1. 初期状態: focus = Self (左ペイン)
///   2. 自分側でアイテムを Z 選択 → focus が Partner (右ペイン) に切り替わり、
///      `selfPick` に選んだアイテムの kind が保存される
///   3. 相手側でアイテムを Z 選択 → `PlayerScene.swapItem` で交換実行 →
///      focus が Self に戻り `selfPick` クリア
///   4. 自分側選択中に X → 選択解除して focus は Self のまま
///   5. 未選択で X → ActionSelect に戻る (緑マス overlay を片付けて行動継続)
///
/// ノード構造（visible のとき）:
///   TradeMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.TradePanel(PanelData))
///           ├─ selfMenu    (ItemList, NodeTag.TradeSelfMenu)
///           └─ partnerMenu (ItemList, NodeTag.TradePartnerMenu)
mod TradeMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// どちらのペインに入力フォーカスがあるか。
    /// `Self` = 左 (じぶん) / `Partner` = 右 (あいて)。
    /// Z 押下でフォーカスがトグルされる (Self → Partner → swap → Self)。
    pub enum Pane with Eq, ToString {
        case Self
        case Partner
    }

    /// Panel ノード (`NodeTag.TradePanel(PanelData)`) に紐づくセッション状態。
    ///
    /// フィールドの意味:
    ///   - `partnerId` : 交換相手の player id (TradeTargetSelect で Z 押下時に決まる)。
    ///                    `defaultPanelData` では `-1` (= 未設定) を入れておく。
    ///   - `selfPick`  : 自分側で選択中のアイテム (Z 押下で Some、X / 交換完了で None)。
    ///   - `focus`     : 現在の入力フォーカスのペイン。
    pub type alias PanelData = {
        partnerId = Int32,
        selfPick  = Option[PlayerScene.ItemKind],
        focus     = Pane
    }

    /// PanelData の初期値 (起動時 / 各 TradeInventory セッション開始前)。
    /// partnerId = -1 は「未設定」を表す番兵値で、`openFor(partnerId)` でセットされる。
    pub def defaultPanelData(): PanelData = {
        partnerId = -1,
        selfPick  = None,
        focus     = Pane.Self
    }

    /// 空スロットを表す ItemEntry。あいて側に空きがあるときに表示し、Z で
    /// 「自分のアイテムを渡すだけ (自分の枠は空になる)」のスワップを発火する。
    /// metadata = "empty" で `onConfirmPartner` が空スロット選択として認識する。
    pub def emptySlotEntryText(): String = "--------"
    pub def emptySlotMeta(): String      = "empty"

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    def sceneJsonPath(): String = "src/scenes/TradeMenuScene.scene.json"

    def fontName(): String = "ui"

    def rootName(): String = "TradeMenu"

    pub def panelName(): String        = "panel"
    pub def selfMenuName(): String     = "selfMenu"
    pub def partnerMenuName(): String  = "partnerMenu"

    pub def rootPath():        NodePath = rootName() :: Nil
    pub def panelPath():       NodePath = rootName() :: panelName() :: Nil
    pub def selfMenuPath():    NodePath = rootName() :: panelName() :: selfMenuName() :: Nil
    pub def partnerMenuPath(): NodePath = rootName() :: panelName() :: partnerMenuName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                       => Ok(NodeTag.NoTag)
            case Some("NoTag")              => Ok(NodeTag.NoTag)
            case Some("TradePanel")         => Ok(NodeTag.TradePanel(defaultPanelData()))
            case Some("TradeSelfMenu")      => Ok(NodeTag.TradeSelfMenu)
            case Some("TradePartnerMenu")   => Ok(NodeTag.TradePartnerMenu)
            case Some(unknown)              =>
                Err(JsonError(Root, Set#{"TradeMenuScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// scene に TradeMenu ノードツリーを追加する。
    /// `loadSceneWithFont` は ItemList を含むので FontAtlas 必須。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 現在の Panel 状態を取り出す (デバッグ・テスト用 + onConfirm 系の参照)。
    /// ノード未登録なら `defaultPanelData` を返す (防御的フォールバック)。
    pub def getPanelData(scene: Scene[NodeTag]): PanelData =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) => data
            case _                               => defaultPanelData()
        }

    /// Panel 状態を `f` で更新する (selfPick の Some/None 切替や focus の入替に使う)。
    pub def mapPanelData(f: PanelData -> PanelData, scene: Scene[NodeTag]):
            Scene[NodeTag] =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) =>
                Scene.setState(panelPath(), NodeTag.TradePanel(f(data)), scene)
            case _                               => scene
        }

    /// 「物交換ウィンドウが現在 visible か」のヘルパー。
    /// gameLoop の Escape→quit 判定で「メニュー表示中は Escape を quit に流さない」用途。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用 (Push モデル)。
    /// `TradeInventory` のときだけ Panel + 両 ItemList を visible にし、
    /// PanelData#focus 側のペインを focused = true にする (片方ずつ排他的)。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.TradeInventory;
        let focus = if (visible) getPanelData(scene)#focus else Pane.Self;
        let selfFocused    = visible and focus == Pane.Self;
        let partnerFocused = visible and focus == Pane.Partner;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(selfMenuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(selfFocused))
            |> ItemList.mapAt(partnerMenuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(partnerFocused))

    /// Game.flix の `Node[NodeTag] instance` の process redef から TradeMenu の各
    /// ItemList ノードに対して dispatch される。
    /// 責務:
    ///   1. visibility/focus を毎フレーム phase + PanelData#focus で再評価
    ///   2. TradeInventory フェーズなら自分 (selectedId) と相手 (panelData#partnerId)
    ///      のインベントリを items に同期 (相手側には空スロット行も足す)
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = if (phase != TurnPhase.Phase.TradeInventory) withVisibility
                        else refreshBothPanes(withVisibility);
        match Scene.getEngineNode(path, withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// 自分側 (selectedId) と相手側 (panelData#partnerId) のインベントリを
    /// それぞれの ItemList に反映する (毎フレーム呼ばれる)。
    def refreshBothPanes(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(selfId)   =>
                let panelData = getPanelData(scene);
                scene
                    |> ItemList.mapAt(selfMenuPath(), list ->
                        list |> ItemList.setItems(inventoryEntries(selfId, scene)))
                    |> ItemList.mapAt(partnerMenuPath(), list ->
                        list |> ItemList.setItems(
                            inventoryEntriesWithEmpty(panelData#partnerId, scene)))
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は ItemMenuScene と同じ `"w:<idx>"` 規約。
    /// (Phase 5 で ItemMenuScene と統合予定だが、Phase 4 では局所コピーで進める)
    def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。metadata は `"s:<idx>"` 規約。
    def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 空スロット (相手側で「ここに自分のアイテムを置ける」位置) を表す ItemEntry。
    def emptySlotEntry(): ItemEntry = {
        text     = emptySlotEntryText(),
        disabled = false,
        metadata = Some(emptySlotMeta())
    }

    /// 指定 player の weapons + staves を ItemEntry 列に変換する (自分側用)。
    /// player が居ない場合は空。
    def inventoryEntries(playerId: Int32, scene: Scene[NodeTag]): List[ItemEntry] =
        let weapons = PlayerScene.getWeapons(playerId, scene);
        let staves  = PlayerScene.getStaves(playerId, scene);
        let weaponEntries = List.mapWithIndex(idx -> w -> weaponEntry(idx, w), weapons);
        let staffEntries  = List.mapWithIndex(idx -> s -> staffEntry(idx, s),  staves);
        List.append(weaponEntries, staffEntries)

    /// 相手側用: weapons + staves を並べた後、末尾に空スロット行を 1 つ追加する。
    /// 「自分のアイテムを空きに渡すだけ」のスワップが選べるようにする。
    def inventoryEntriesWithEmpty(playerId: Int32, scene: Scene[NodeTag]):
            List[ItemEntry] =
        List.append(inventoryEntries(playerId, scene), emptySlotEntry() :: Nil)

    // ────────────────────────────────────────────────────────
    // (E) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// 自分側 (`TradeSelfMenu`) で Enter/Z を押したとき:
    ///   - 選んだアイテムを PanelData#selfPick に保存
    ///   - focus を Partner に切り替え (次フレームの applyVisibility で右ペインが focused)
    /// metadata が空スロット ("empty") の場合は何もしない (空からは渡せない)。
    pub def onConfirmSelf(entry: ItemEntry, scene: Scene[NodeTag]): Scene[NodeTag] =
        entry#metadata
            |> Option.flatMap(ItemMenuScene.parseItemKind)
            |> Option.map(kind -> mapPanelData(d ->
                {selfPick = Some(kind), focus = Pane.Partner | d}, scene))
            |> Option.getWithDefault(scene)

    /// 相手側 (`TradePartnerMenu`) で Enter/Z を押したとき:
    ///   - selfPick が None なら何もしない (Self 側で先に選ばないと start できない)
    ///   - selfPick が Some なら `PlayerScene.swapItem` でスワップ実行 →
    ///     ログ + PanelData#selfPick=None + focus=Self に戻す (連続交換可能)
    /// 相手側エントリの metadata は:
    ///   - "w:<idx>" / "s:<idx>" → 相手の対応アイテムと交換
    ///   - "empty" → 相手の空スロットへ一方向 transfer (partnerKind = None)
    pub def onConfirmPartner(entry: ItemEntry, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let panelData = getPanelData(scene);
        let partnerKindArg = parsePartnerKind(entry);
        // 自分側未選択 or selectedId が取れないなら no-op
        match (panelData#selfPick, SelectedPlayer.State.get()#id) {
            case (Some(selfPick), Some(selfId)) =>
                applySwap(selfId, selfPick, panelData#partnerId,
                           partnerKindArg, scene)
            case _ => scene
        }

    /// 相手側エントリの metadata から「対象アイテム種別 / 空スロット」を判定。
    /// "empty" → None (空スロット = 一方向 transfer)、それ以外は ItemKind に parse。
    def parsePartnerKind(entry: ItemEntry): Option[PlayerScene.ItemKind] =
        match entry#metadata {
            case None       => None
            case Some(meta) =>
                if (meta == emptySlotMeta()) None
                else ItemMenuScene.parseItemKind(meta)
        }

    /// 実際のスワップ + ログ出力 + PanelData リセット。
    /// 「対象が空スロット (partnerKind=None)」と「対象が実体アイテム」の両ケース統合。
    def applySwap(selfId: Int32, selfKind: PlayerScene.ItemKind,
                   partnerId: Int32, partnerKind: Option[PlayerScene.ItemKind],
                   scene: Scene[NodeTag]):
                   Scene[NodeTag] \ GameLogger.GameLogger =
        GameLogger.playerLog("P${selfId} と P${partnerId} がアイテム交換");
        PlayerScene.swapItem(selfId, selfKind, partnerId, partnerKind, scene)
            |> mapPanelData(d -> {selfPick = None, focus = Pane.Self | d})

    /// 自分側 (`TradeSelfMenu`) で X/Escape を押したとき:
    ///   - selfPick が Some なら選択解除して focus は Self のまま
    ///     (= 「もう一回じぶん側で別アイテムを選び直せる」状態に戻る)
    ///   - selfPick が None なら TradeInventory を抜けて ActionSelect に戻る
    ///     (緑マス overlay も片付ける = `enterActionSelectFromTrade`)
    pub def onCancelSelf(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        let panelData = getPanelData(scene);
        match panelData#selfPick {
            case Some(_) =>
                mapPanelData(d -> {selfPick = None, focus = Pane.Self | d}, scene)
            case None    =>
                PhaseTransitions.enterActionSelectFromTrade(scene)
        }

    /// 相手側 (`TradePartnerMenu`) で X/Escape を押したとき:
    ///   - selfPick を None に戻して focus = Self に巻き戻す (= 自分側選択状態を解除)
    ///   - selfPick が None だった場合 (防御的) も同じ操作で OK
    pub def onCancelPartner(scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPanelData(d -> {selfPick = None, focus = Pane.Self | d}, scene)
}
