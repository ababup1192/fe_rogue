/// TradeMenuScene — 物交換ウィンドウ (じぶん / あいて の 2 ペイン)
///
/// `TradeTargetSelect` で交換相手を確定すると `TradeInventory` フェーズに入り、
/// 画面に出る 2 つの ItemList。左 (selfMenu) に選択中味方、右 (partnerMenu) に
/// 交換相手の weapons + staves を並べる (両側とも末尾に空スロット "--------")。
/// ↑↓ で選択、Enter/Z で確定。
///
/// 入力フロー (対称版: じぶん側起動 / あいて側起動どちらも同じ流れ):
///   1. 初期状態: focus = Self (左ペイン), pick = None
///   2. どちらかの側でアイテムを Z 選択 → `pick = Some({side, kind})` がセットされ、
///      focus が反対側に切り替わる (次フレームの applyVisibility で受け側が focused)
///   3. 受け側でアイテムを Z 選択 → `PlayerScene.swapItem` で交換実行 →
///      pick クリア、focus は picker のいた側に戻る (連続交換可能)
///   3'. 受け側で空スロット "--------" を Z → 一方向 transfer (picker のアイテムが
///       受け側に移り、picker 側のスロットは空になる)
///   4. picker 側にいる状態で X → pick 解除して focus は picker 側に戻る
///   5. pick=None で X → TradeInventory を抜けて ActionSelect に戻る
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
    /// Z 押下でフォーカスが反対側にトグルされる。先に Z を押した側が `Pick`
    /// となり、相手側でもう 1 回 Z で確定 swap。Self 起動 / Partner 起動どちらも対称。
    pub enum Pane with Eq, ToString {
        case Self
        case Partner
    }

    /// どちらかのペインで「選択中」のスロット。`side` は picker のペイン。
    /// `kind` は picker が選んだスロットの中身: `Some(k)` なら実体アイテム、
    /// `None` なら空スロット (= 「受け取り希望」のマーカー)。
    ///
    /// 反対側でもう 1 回 Z すると `applyTradeSwap` でスワップ実行:
    ///   - 両方 Some  → 双方向 swap (お互いのアイテムを入れ替え)
    ///   - picker Some / 受け側 None → picker → 受け側へ片方向 transfer
    ///   - picker None / 受け側 Some → 受け側 → picker へ片方向 transfer (= 受取)
    ///   - 両方 None  → 両方空なので no-op
    pub type alias Pick = {
        side = Pane,
        kind = Option[PlayerScene.ItemKind]
    }

    /// Panel ノード (`NodeTag.TradePanel(PanelData)`) に紐づくセッション状態。
    ///
    /// フィールドの意味:
    ///   - `partnerId` : 交換相手の player id (TradeTargetSelect で Z 押下時に決まる)。
    ///                    `defaultPanelData` では `-1` (= 未設定) を入れておく。
    ///   - `pick`      : Self / Partner どちらかが先に選んだアイテム (Some)、未選択なら None。
    ///                    Self / Partner どちらの側からも起動できるので side フィールドで区別する。
    ///   - `focus`     : 現在の入力フォーカスのペイン。pick が Some のときは
    ///                    必ず `opposite(pick.side)` (= 受け側) になっている。
    pub type alias PanelData = {
        partnerId = Int32,
        pick      = Option[Pick],
        focus     = Pane
    }

    /// PanelData の初期値 (起動時 / 各 TradeInventory セッション開始前)。
    /// partnerId = -1 は「未設定」を表す番兵値で、`openFor(partnerId)` でセットされる。
    pub def defaultPanelData(): PanelData = {
        partnerId = -1,
        pick      = None,
        focus     = Pane.Self
    }

    /// Pane の反対側を返す。`Self` ↔ `Partner` のトグル。
    /// Pick したあとフォーカスを反対側に飛ばすときと、cancel で picker 側に戻すときに使う。
    pub def opposite(side: Pane): Pane = match side {
        case Pane.Self    => Pane.Partner
        case Pane.Partner => Pane.Self
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

    pub def panelName(): String         = "panel"
    pub def selfMenuName(): String      = "selfMenu"
    pub def partnerMenuName(): String   = "partnerMenu"
    pub def selfClassName(): String     = "selfClass"
    pub def partnerClassName(): String  = "partnerClass"

    pub def rootPath():         NodePath = rootName() :: Nil
    pub def panelPath():        NodePath = rootName() :: panelName() :: Nil
    pub def selfMenuPath():     NodePath = rootName() :: panelName() :: selfMenuName() :: Nil
    pub def partnerMenuPath():  NodePath = rootName() :: panelName() :: partnerMenuName() :: Nil
    pub def selfClassPath():    NodePath = rootName() :: panelName() :: selfClassName() :: Nil
    pub def partnerClassPath(): NodePath = rootName() :: panelName() :: partnerClassName() :: Nil

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

    /// Panel 状態を `f` で更新する (pick の Some/None 切替や focus の入替に使う)。
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
    /// `TradeInventory` のときだけ Panel + 両 ItemList + 兵種 Label を visible にし、
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
            |> Label2D.mapAt(selfClassPath(),    CanvasItem.setVisible(visible))
            |> Label2D.mapAt(partnerClassPath(), CanvasItem.setVisible(visible))

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
        // 閉じている間は両ペインのカーソルを先頭(0)に戻し、次に開いたとき必ず
        // 最初の項目から始まるようにする。表示中はリセットしないので ↑↓ 移動は維持。
        let withItems = if (phase != TurnPhase.Phase.TradeInventory)
                withVisibility
                    |> ItemList.mapAt(selfMenuPath(), ItemList.setSelectedIndex(0))
                    |> ItemList.mapAt(partnerMenuPath(), ItemList.setSelectedIndex(0))
            else refreshBothPanes(withVisibility);
        match Scene.getEngineNode(path, withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// 自分側 (selectedId) と相手側 (panelData#partnerId) のインベントリを
    /// それぞれの ItemList に反映する (毎フレーム呼ばれる)。
    /// 両側とも末尾に空スロット行を表示する: Self / Partner どちらからも起動でき、
    /// どちらにも「あいてのアイテムを空きへ受け取る」一方向 transfer ができるため。
    /// 兵種ラベル (Label2D) も `UnitResource#description` を引いて毎フレーム更新する。
    def refreshBothPanes(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(selfId)   =>
                let panelData = getPanelData(scene);
                let partnerId = panelData#partnerId;
                scene
                    |> ItemList.mapAt(selfMenuPath(), list ->
                        list |> ItemList.setItems(inventoryEntriesWithEmpty(selfId, scene)))
                    |> ItemList.mapAt(partnerMenuPath(), list ->
                        list |> ItemList.setItems(
                            inventoryEntriesWithEmpty(partnerId, scene)))
                    |> Label2D.mapAt(selfClassPath(),
                        Label2D.setText(classNameOf(selfId, scene)))
                    |> Label2D.mapAt(partnerClassPath(),
                        Label2D.setText(classNameOf(partnerId, scene)))
        }

    /// 指定 player id の兵種名 (`UnitResource#description`) を引く。
    /// player が居ない場合は空文字 (`Label2D.setText("")` で何も描かれない)。
    def classNameOf(id: Int32, scene: Scene[NodeTag]): String =
        match PlayerScene.get(id, scene) {
            case Some(d) => d#resource#description
            case None    => ""
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は ItemMenuScene と同じ `"w:<idx>"` 規約。
    /// (Phase 5 で ItemMenuScene と統合予定だが、Phase 4 では局所コピーで進める)
    /// pub: テストから「本体が実際に ItemList に並べている entry」と同じ値を組むのに使う。
    pub def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。metadata は `"s:<idx>"` 規約。
    /// pub: テストから「本体が実際に ItemList に並べている entry」と同じ値を組むのに使う。
    pub def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 消費アイテム 1 個ぶんの ItemEntry。metadata は `"c:<idx>"` 規約。残り使用回数を表示する。
    /// pub: テストから「本体が実際に ItemList に並べている entry」と同じ値を組むのに使う。
    pub def consumableEntry(idx: Int32, item: Consumable.ConsumableResource): ItemEntry = {
        text     = "${item#name} ${item#durability}",
        disabled = false,
        metadata = Some("c:${idx}")
    }

    /// 空スロット (相手側で「ここに自分のアイテムを置ける」位置) を表す ItemEntry。
    /// pub: テストから「本体が実際に ItemList に並べている entry」と同じ値を組むのに使う。
    pub def emptySlotEntry(): ItemEntry = {
        text     = emptySlotEntryText(),
        disabled = false,
        metadata = Some(emptySlotMeta())
    }

    /// 指定 player の weapons + staves + consumables を ItemEntry 列に変換する (自分側用)。
    /// player が居ない場合は空。
    def inventoryEntries(playerId: Int32, scene: Scene[NodeTag]): List[ItemEntry] =
        let weapons     = PlayerScene.getWeapons(playerId, scene);
        let staves      = PlayerScene.getStaves(playerId, scene);
        let consumables = PlayerScene.getConsumables(playerId, scene);
        let weaponEntries     = List.mapWithIndex(idx -> w -> weaponEntry(idx, w), weapons);
        let staffEntries      = List.mapWithIndex(idx -> s -> staffEntry(idx, s),  staves);
        let consumableEntries = List.mapWithIndex(idx -> c -> consumableEntry(idx, c), consumables);
        List.append(weaponEntries, List.append(staffEntries, consumableEntries))

    /// 武器 + 杖を並べた後、末尾に空スロット行を 1 つ追加する。
    /// 「相手のアイテムを空きに受け取る (片方向 transfer)」のスワップが選べるようにする。
    /// Self 側 / Partner 側ともこの形で表示する。
    def inventoryEntriesWithEmpty(playerId: Int32, scene: Scene[NodeTag]):
            List[ItemEntry] =
        List.append(inventoryEntries(playerId, scene), emptySlotEntry() :: Nil)

    // ────────────────────────────────────────────────────────
    // (E) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// エントリの metadata から「対象アイテム種別 / 空スロット」を判定。
    /// "empty" → None (空スロット = 受け側専用)、"w:<idx>" / "s:<idx>" は ItemKind に parse。
    /// Self / Partner 両側の Z 判定で使う (空スロットからは pick できない、ただし受け先にはなれる)。
    def parseEntryKind(entry: ItemEntry): Option[PlayerScene.ItemKind] =
        match entry#metadata {
            case None       => None
            case Some(meta) =>
                if (meta == emptySlotMeta()) None
                else ItemMenuScene.parseItemKind(meta)
        }

    /// picker 側 (`pick`) と受け側 (`receiverKindOpt`) のスロットを 1 回の swap として実行する。
    /// `PlayerScene.swapItem` は `selfKind: ItemKind` (必須) と `partnerKind: Option[ItemKind]`
    /// の非対称 API なので、ここで picker / 受け側のどちらが giver (= 必須側) かを切り替える:
    ///
    ///   - pick.kind = Some → picker が必須 giver、受け側は Option (空 OK)
    ///   - pick.kind = None & 受け側 = Some → 受け側が必須 giver、picker 側は None (空) 受け
    ///   - 両方 None → 何も動かない (no-op、ログも出さない)
    ///
    /// プレイヤー ID は `pick#side` で picker / 反対側に割り当てる。
    def applyTradeSwap(selfPlayerId: Int32, partnerPlayerId: Int32,
                        pick: Pick, receiverKindOpt: Option[PlayerScene.ItemKind],
                        scene: Scene[NodeTag]):
                       Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let (pickerId, receiverId) = match pick#side {
            case Pane.Self    => (selfPlayerId,    partnerPlayerId)
            case Pane.Partner => (partnerPlayerId, selfPlayerId)
        };
        match (pick#kind, receiverKindOpt) {
            case (None, None) =>
                // 両方空スロット同士: 何も交換しない
                scene
            case (Some(pickerKind), receiverOpt) =>
                // picker 実体: picker → 受け側へ swap (受け側が None なら片方向 transfer)
                GameLogger.playerLog("P${selfPlayerId} と P${partnerPlayerId} がアイテム交換");
                recordTradeDraft(pickerId, pickerKind, receiverId, receiverOpt, scene);
                PlayerScene.swapItem({selfId      = pickerId,
                                       selfKind    = pickerKind,
                                       partnerId   = receiverId,
                                       partnerKind = receiverOpt}, scene)
            case (None, Some(receiverKind)) =>
                // picker 空 (= 受取希望) & 受け側実体: 受け側 → picker へ片方向 transfer
                GameLogger.playerLog("P${selfPlayerId} と P${partnerPlayerId} がアイテム交換");
                recordTradeDraft(receiverId, receiverKind, pickerId, None, scene);
                PlayerScene.swapItem({selfId      = receiverId,
                                       selfKind    = receiverKind,
                                       partnerId   = pickerId,
                                       partnerKind = None}, scene)
        }

    /// swap 実行前に、巻き戻し用 `Traded` ドラフトを SelectedPlayer に積む。
    /// swap 前の実体・元 idx を控えるので、キャンセル時に双方の在庫を正確に戻せる。
    /// self 側に実体が無い（swap が no-op になる）場合は積まない。
    def recordTradeDraft(selfId: Int32, selfKind: PlayerScene.ItemKind,
                          partnerId: Int32, partnerKindOpt: Option[PlayerScene.ItemKind],
                          scene: Scene[NodeTag]): Unit \ SelectedPlayer.State =
        match PlayerScene.getInventoryItem(selfId, selfKind, scene) {
            case None           => ()
            case Some(selfItem) =>
                let partnerItemOpt = partnerKindOpt
                    |> Option.flatMap(pk -> PlayerScene.getInventoryItem(partnerId, pk, scene));
                SelectedPlayer.pushDraft(MoveDraft.DraftAction.Traded({
                    selfId      = selfId,      selfKind    = selfKind,
                    selfItem    = selfItem,
                    partnerId   = partnerId,   partnerKind = partnerKindOpt,
                    partnerItem = partnerItemOpt
                }))
        }

    /// Z 押下の中核処理。`currentSide` で押されたペインを示し、現在の `pick` 状態と
    /// エントリ種別 (実体 or 空スロット) から次の状態を決める。
    ///
    /// 状態遷移 (Pick.kind = Option[ItemKind] モデル):
    ///   - pick=None, 任意のエントリ
    ///       → このスロット (実体 or 空) を pick にセット、focus は反対側へ。
    ///         空スロット pick は「受け取り希望」のマーカーになる。
    ///   - pick=Some(同じ側), 任意のエントリ
    ///       → pick を新エントリで上書き (押し直し / 実体 ↔ 空 の切替も可)。
    ///   - pick=Some(反対側), 任意のエントリ
    ///       → `applyTradeSwap` で swap 実行 (両空のときだけ no-op) →
    ///         pick=None, focus = picker のいた側。
    def doConfirm(currentSide: Pane, entry: ItemEntry, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} = {
        let panelData = getPanelData(scene);
        let entryKindOpt = parseEntryKind(entry);
        match panelData#pick {
            case None =>
                // 何も pick されていない → このスロットを pick にする
                checked_ecast(mapPanelData(d ->
                    {pick = Some({side = currentSide, kind = entryKindOpt}),
                     focus = opposite(currentSide) | d}, scene))
            case Some(p) if p#side == currentSide =>
                // 同側で押し直し → pick を新エントリで上書き (空 ↔ 実体の切替もここで吸収)
                checked_ecast(mapPanelData(d ->
                    {pick = Some({side = currentSide, kind = entryKindOpt}) | d}, scene))
            case Some(p) =>
                // 反対側 → swap 実行 (picker = p、受け側 = currentSide)
                match SelectedPlayer.State.get()#id {
                    case None         => scene
                    case Some(selfId) =>
                        applyTradeSwap(selfId, panelData#partnerId, p, entryKindOpt, scene)
                            |> mapPanelData(d ->
                                {pick = None, focus = p#side | d})
                }
        }
    }

    /// X 押下の中核処理。pick=Some なら解除して picker のペインへフォーカスを戻し、
    /// pick=None ならメニューを閉じて ActionSelect (= ActionMenu 再表示) に戻る。
    /// Self / Partner どちらのペインで押しても同じ挙動。
    def doCancel(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        let panelData = getPanelData(scene);
        match panelData#pick {
            case Some(p) =>
                mapPanelData(d -> {pick = None, focus = p#side | d}, scene)
            case None    =>
                PhaseTransitions.enterActionSelectFromTrade(scene)
        }

    /// 自分側 (`TradeSelfMenu`) で Enter/Z を押したとき。`doConfirm(Self, ...)` に委譲。
    pub def onConfirmSelf(entry: ItemEntry, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        doConfirm(Pane.Self, entry, scene)

    /// 相手側 (`TradePartnerMenu`) で Enter/Z を押したとき。`doConfirm(Partner, ...)` に委譲。
    pub def onConfirmPartner(entry: ItemEntry, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        doConfirm(Pane.Partner, entry, scene)

    /// 自分側 (`TradeSelfMenu`) で X/Escape を押したとき。`doCancel` に委譲。
    pub def onCancelSelf(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        doCancel(scene)

    /// 相手側 (`TradePartnerMenu`) で X/Escape を押したとき。`doCancel` に委譲。
    pub def onCancelPartner(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        doCancel(scene)

    /// ←/→ 押下から呼ばれる。指定ペインにフォーカスを動かす。
    /// pick=Some のときも切替可 (picker 側に戻って空スロット押下で pick 解除する等の操作を可能に)。
    /// 次フレームの `applyVisibility` (refreshItems 経由) で対応 ItemList が
    /// focused=true になり、↑↓ がそちらで効くようになる。
    pub def setPaneFocus(target: Pane, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPanelData(d -> {focus = target | d}, scene)

    /// InputHandler の Z 押下から呼ばれる。PanelData#focus を見て、現在
    /// focus のあるペインの ItemList から selected entry を取り、
    /// onConfirmSelf / onConfirmPartner に流す。ActionMenuScene.confirmCurrentSelection
    /// と同じ「focused ペインだけ確定する」パターン。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let path = match getPanelData(scene)#focus {
            case Pane.Self    => selfMenuPath()
            case Pane.Partner => partnerMenuPath()
        };
        match ItemList.getAt(path, scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) => match getPanelData(scene)#focus {
                case Pane.Self    => checked_ecast(onConfirmSelf(entry, scene))
                case Pane.Partner => onConfirmPartner(entry, scene)
            }
        }

    /// InputHandler の X 押下から呼ばれる。PanelData#focus を見て、
    /// onCancelSelf / onCancelPartner に流す (selected entry は不要)。
    pub def cancelCurrent(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        match getPanelData(scene)#focus {
            case Pane.Self    => onCancelSelf(scene)
            case Pane.Partner => checked_ecast(onCancelPartner(scene))
        }
}
