/// TradeMenuScene — 物交換ウィンドウ (N ペイン: 最大 3 人)
///
/// 通常ターンの「こうかん」(隣接 2 人) と、集合後ローグモードの「交換」(集合した
/// 生存メンバー全員) を **同じ Scene / 同じ TradeInventory フェーズ**で扱う。
/// 2 人交換は「ペイン数 = 2」、集合交換は「ペイン数 = 2..3」の特殊ケースにすぎない。
///
/// 各ペインに 1 人ぶんの weapons + staves + consumables を縦に並べる。持ち物が
/// 上限未満のペインは末尾に空スロット "--------" を出す (上限ちょうどなら出さない)。
/// これで満杯メンバーへの片方向流入は自然にブロックされ、1 対 1 入替 (満杯側も 1 つ
/// 手放す) は引き続き可能になる。
///
/// 入力フロー:
///   1. ←→ で focus ペインを移動 (0..paneCount-1 にクランプ)。
///   2. focus ペインのスロットを Z 選択 → `pick = Some({paneIndex, kind})`。
///   3. 別ペインに移動してスロットを Z → `PlayerScene.swapItem` で交換実行 →
///      pick クリア、focus は place したペインに留まる (連続交換可能)。
///      空スロット "--------" への place は片方向 transfer。
///   4. pick=Some で X → pick 解除 (focus 据置)。
///   5. pick=None で X → `origin` に応じてメニューを閉じる
///      (FromTurn → ActionSelect / FromRogue → RogueMove)。
///
/// ノード構造（visible のとき）:
///   TradeMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.TradePanel(PanelData))
///           ├─ class0..2 (Label2D, 兵種名)
///           └─ menu0..2  (ItemList, NodeTag.TradeMenu(i))
mod TradeMenuScene {

    use JsonCompat.PathTag.Root

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// どちらかのペインで「選択中」のスロット。`paneIndex` は picker のペイン (0 起点)。
    /// `kind` は picker が選んだスロットの中身: `Some(k)` なら実体アイテム、
    /// `None` なら空スロット (= 「受け取り希望」のマーカー)。
    pub type alias Pick = {
        paneIndex = Int32,
        kind      = Option[PlayerData.ItemKind]
    }

    /// 交換セッションの出口。cancel でメニューを閉じたときの戻り先フェーズを決める。
    ///   - `FromTurn`  : 通常ターンの隣接 2 人交換 (X で ActionSelect へ戻す。巻き戻しドラフトを積む)
    ///   - `FromRogue` : 集合後の交換 (X で RogueMove へ戻す。ローグは undo 無しなのでドラフト無し)
    pub enum Origin with Eq, ToString {
        case FromTurn
        case FromRogue
    }

    /// Panel ノード (`NodeTag.TradePanel(PanelData)`) に紐づくセッション状態。
    ///   - `members` : 各ペインに対応する player id (左→右の表示順)。length = ペイン数 (2..3)。
    ///   - `focus`   : 現在の入力フォーカスのペイン index (0 起点)。
    ///   - `pick`    : 先に選んだスロット (無ければ None)。
    ///   - `origin`  : セッションの出口 (cancel の戻り先)。
    pub type alias PanelData = {
        members = List[Int32],
        focus   = Int32,
        pick    = Option[Pick],
        origin  = Origin
    }

    /// PanelData の初期値。`enterTradeInventory` / `enterGatherTrade` が members/origin をセットする。
    pub def defaultPanelData(): PanelData = {
        members = Nil,
        focus   = 0,
        pick    = None,
        origin  = Origin.FromTurn
    }

    /// 確定 (Z) 押下の結果。状態更新だけか、別ペインとの swap か、同ペイン内の並び替えか。
    /// (中身に record alias を含むので Eq は導出しない。match で分解して使う。)
    pub enum ConfirmOutcome {
        case JustUpdate(PanelData)
        case DoSwap(PanelData, SwapPlan)
        case DoReorder(PanelData, ReorderPlan)
    }

    /// 1 回の swap で動かすアイテムの計画。player id は `members` から解決済み。
    ///   - picker = 先に選んだ側 / receiver = 後から選んだ (place した) 側。
    ///   - kind が `None` の側は空スロット (= 受け取り専用)。
    pub type alias SwapPlan = {
        pickerId     = Int32,
        pickerKind   = Option[PlayerData.ItemKind],
        receiverId   = Int32,
        receiverKind = Option[PlayerData.ItemKind]
    }

    /// 同じペイン (同じ player) 内でアイテムの並び順を入れ替える計画。
    /// kindA (先に pick) と kindB (後から選択) の表示位置を入れ替える。
    pub type alias ReorderPlan = {
        playerId = Int32,
        kindA    = PlayerData.ItemKind,
        kindB    = PlayerData.ItemKind
    }

    /// 空スロットを表す ItemEntry のテキスト / metadata。
    pub def emptySlotEntryText(): String = "--------"
    pub def emptySlotMeta(): String      = "empty"

    // ────────────────────────────────────────────────────────
    // (B) 定数 / パス
    // ────────────────────────────────────────────────────────

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/TradeMenuScene.scene.json")

    def fontName(): String = "ui"

    def rootName(): String = "TradeMenu"

    /// scene.json で宣言しているペインの最大数。
    pub def maxPanes(): Int32 = 3

    pub def panelName(): String         = "panel"
    pub def menuName(i: Int32): String  = "menu${i}"
    pub def className(i: Int32): String = "class${i}"

    pub def rootPath():  NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(i: Int32):  NodePath = rootName() :: panelName() :: menuName(i) :: Nil
    pub def classPath(i: Int32): NodePath = rootName() :: panelName() :: className(i) :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("TradePanel")    => Ok(NodeTag.TradePanel(defaultPanelData()))
            case Some("TradeMenu0")    => Ok(NodeTag.TradeMenu(0))
            case Some("TradeMenu1")    => Ok(NodeTag.TradeMenu(1))
            case Some("TradeMenu2")    => Ok(NodeTag.TradeMenu(2))
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"TradeMenuScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築 / 状態アクセス
    // ────────────────────────────────────────────────────────

    /// scene に TradeMenu ノードツリーを追加する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 現在の Panel 状態を取り出す。ノード未登録なら `defaultPanelData`。
    pub def getPanelData(scene: Scene[NodeTag]): PanelData =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) => data
            case _                               => defaultPanelData()
        }

    /// Panel 状態を `f` で更新する。
    pub def mapPanelData(f: PanelData -> PanelData, scene: Scene[NodeTag]):
            Scene[NodeTag] =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) =>
                Scene.setState(panelPath(), NodeTag.TradePanel(f(data)), scene)
            case _                               => scene
        }

    /// Panel 状態を丸ごと差し替える。
    def setPanelData(data: PanelData, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPanelData(_ -> data, scene)

    /// 「物交換ウィンドウが現在 visible か」のヘルパー (gameLoop の Escape→quit 判定用)。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    // ────────────────────────────────────────────────────────
    // (D) 純粋ロジック (effect 無し・テスト対象)
    // ────────────────────────────────────────────────────────

    /// 現在のペイン数 (= members の長さ)。
    pub def paneCount(data: PanelData): Int32 = List.length(data#members)

    /// ペイン index に対応する player id。範囲外なら None。
    pub def playerIdAt(i: Int32, data: PanelData): Option[Int32] = List.nth(i, data#members)

    /// focus を delta(±1) だけ動かして `0..(paneCount-1)` にクランプする。
    pub def moveFocus(delta: Int32, data: PanelData): PanelData =
        let count = paneCount(data);
        if (count <= 0) data
        else {
            let raw = data#focus + delta;
            let clamped = Int32.max(0, Int32.min(count - 1, raw));
            {focus = clamped | data}
        }

    /// Z 押下の純粋な状態遷移。`paneIndex` で押されたペイン、`entryKind` でそのスロットの
    /// 中身 (実体 or 空) を示す。
    ///   - pick=None                       → このスロットを pick (focus 据置)
    ///   - pick=Some, 同ペイン同スロット    → pick 解除
    ///   - pick=Some, 同ペイン別スロット(両実体) → 並び替え (reorder)
    ///   - pick=Some, 同ペイン (空スロット絡み)  → pick を新スロットで上書き
    ///   - pick=Some, 別ペイン              → swap 実行 (pick クリア、focus は place ペインに)
    pub def decideConfirm(paneIndex: Int32, entryKind: Option[PlayerData.ItemKind],
                          data: PanelData): ConfirmOutcome =
        match data#pick {
            case None =>
                ConfirmOutcome.JustUpdate(
                    {pick = Some({paneIndex = paneIndex, kind = entryKind}) | data})
            case Some(p) if p#paneIndex == paneIndex =>
                match (p#kind, entryKind) {
                    case (Some(ka), Some(kb)) =>
                        if (ka == kb)
                            // 同じスロットをもう一度 → pick 解除
                            ConfirmOutcome.JustUpdate({pick = None | data})
                        else
                            // 同ペインの別の実体アイテム → 並び替え
                            match playerIdAt(paneIndex, data) {
                                case Some(pid) =>
                                    ConfirmOutcome.DoReorder({pick = None | data},
                                        {playerId = pid, kindA = ka, kindB = kb})
                                case None =>
                                    ConfirmOutcome.JustUpdate({pick = None | data})
                            }
                    case _ =>
                        // 空スロットが絡む → pick を新スロットで上書き
                        ConfirmOutcome.JustUpdate(
                            {pick = Some({paneIndex = paneIndex, kind = entryKind}) | data})
                }
            case Some(p) =>
                match (playerIdAt(p#paneIndex, data), playerIdAt(paneIndex, data)) {
                    case (Some(pickerId), Some(receiverId)) =>
                        let plan = {pickerId     = pickerId,   pickerKind   = p#kind,
                                    receiverId   = receiverId, receiverKind = entryKind};
                        ConfirmOutcome.DoSwap({pick = None, focus = paneIndex | data}, plan)
                    case _ =>
                        // members が解決できない (防御的) → pick だけ解除する
                        ConfirmOutcome.JustUpdate({pick = None | data})
                }
        }

    /// ペイン数に応じた各ペインの位置とサイズ (panel 相対)。panel は 166x84。
    /// 2 ペインは幅広 (x=2/86, w=80)、3 ペインは 3 分割 (x=2/57/112, w=53)。
    def paneLayout(count: Int32, i: Int32): {pos = Vec2.Vec2, size = Vec2.Vec2} =
        let y = 10.0;
        let h = 70.0;
        if (count <= 2)
            match i {
                case 0 => {pos = {x = 2.0,  y = y}, size = {x = 80.0, y = h}}
                case _ => {pos = {x = 86.0, y = y}, size = {x = 80.0, y = h}}
            }
        else
            match i {
                case 0 => {pos = {x = 2.0,   y = y}, size = {x = 53.0, y = h}}
                case 1 => {pos = {x = 57.0,  y = y}, size = {x = 53.0, y = h}}
                case _ => {pos = {x = 112.0, y = y}, size = {x = 53.0, y = h}}
            }

    /// 兵種ラベルの位置 (ペインの左上、y=2)。
    def classPos(count: Int32, i: Int32): Vec2.Vec2 =
        let layout = paneLayout(count, i);
        {x = layout#pos#x, y = 2.0}

    // ────────────────────────────────────────────────────────
    // (E) 表示更新 (毎フレーム)
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用 (Push モデル)。
    /// `TradeInventory` のとき paneCount 個のペイン (+兵種ラベル) を visible にし、
    /// `paneLayout` で位置・サイズを設定する。focus ペインだけ focused = true。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let open = phase == TurnPhase.Phase.TradeInventory;
        let data = getPanelData(scene);
        let count = paneCount(data);
        let focus = data#focus;
        let withPanel = Panel.mapAt(panelPath(), CanvasItem.setVisible(open), scene);
        List.foldLeft((acc, i) -> {
            let paneVisible = open and i < count;
            let paneFocused = paneVisible and i == focus;
            let layout = paneLayout(count, i);
            acc
                |> ItemList.mapAt(menuPath(i), list ->
                    list
                        |> CanvasItem.setVisible(paneVisible)
                        |> ItemList.setFocused(paneFocused)
                        |> Node2D.setPosition(layout#pos)
                        |> ItemList.setSize(layout#size))
                |> Label2D.mapAt(classPath(i), label ->
                    label
                        |> CanvasItem.setVisible(paneVisible)
                        |> Node2D.setPosition(classPos(count, i)))
        }, withPanel, List.range(0, maxPanes()))

    /// Game.flix の process redef から各 TradeMenu ItemList に dispatch される。
    ///   1. visibility/focus/layout を毎フレーム再評価
    ///   2. TradeInventory なら各ペインに対応 player のインベントリを同期 (満杯でなければ空スロット行を足す)
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {TurnPhase.State, PlayerData.PartyQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        // 閉じている間は全ペインのカーソルを先頭(0)に戻し、次に開いたとき必ず最初から。
        let withItems = if (phase != TurnPhase.Phase.TradeInventory)
                resetAllCursors(withVisibility)
            else refreshPanes(withVisibility);
        match Scene.getEngineNode(path, withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// 全ペインの選択カーソルを先頭(0)に戻す。
    def resetAllCursors(scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, i) ->
            ItemList.mapAt(menuPath(i), ItemList.setSelectedIndex(0), acc),
            scene, List.range(0, maxPanes()))

    /// 各ペインに対応 player のインベントリ (満杯でなければ末尾に空スロット) と兵種名を反映し、
    /// pick 中のアイテムは強調色 (黄) で描く。
    def refreshPanes(scene: Scene[NodeTag]): Scene[NodeTag] \ PlayerData.PartyQuery =
        let data = getPanelData(scene);
        let count = paneCount(data);
        List.foldLeft((acc, i) ->
            match playerIdAt(i, data) {
                case None      => acc
                case Some(pid) =>
                    let cls = classNameOf(pid, acc);
                    let items = paneEntries(pid, acc);
                    let highlightIdx = pickHighlightIndex(i, pid, data, acc);
                    acc
                        |> ItemList.mapAt(menuPath(i), list ->
                            list |> ItemList.setItems(items) |> applyHighlight(highlightIdx))
                        |> Label2D.mapAt(classPath(i), Label2D.setText(cls))
            },
            scene, List.range(0, count))

    /// このペインで pick 中のアイテムの表示行 index (色強調する行)。pick が別ペイン /
    /// 空スロット pick / 未 pick なら None。
    def pickHighlightIndex(paneIndex: Int32, playerId: Int32, data: PanelData,
                            scene: Scene[NodeTag]): Option[Int32] \ PlayerData.PartyQuery =
        match data#pick {
            case Some(p) if p#paneIndex == paneIndex =>
                p#kind |> Option.map(k -> displayIndexOf(k, playerId, scene))
            case _ => None
        }

    /// pick 中アイテムの行を強調色にする (それ以外は色をクリアして既定色に戻す)。
    def applyHighlight(idxOpt: Option[Int32], list: ItemList): ItemList =
        let cleared = ItemList.clearItemColors(list);
        match idxOpt {
            case Some(idx) => ItemList.setItemColor(idx, pickColor(), cleared)
            case None      => cleared
        }

    /// pick 中アイテムの強調色 (黄)。
    def pickColor(): Color = {r = 1.0f32, g = 0.85f32, b = 0.2f32}

    /// ItemKind を、ペイン表示 (weapons ++ staves ++ consumables) 上の行 index に変換する。
    def displayIndexOf(kind: PlayerData.ItemKind, playerId: Int32,
                        _scene: Scene[NodeTag]): Int32 \ PlayerData.PartyQuery =
        let nw = List.length(weaponsOf(playerId));
        let ns = List.length(stavesOf(playerId));
        match kind {
            case PlayerData.ItemKind.Weapon(i)     => i
            case PlayerData.ItemKind.Staff(i)      => nw + i
            case PlayerData.ItemKind.Consumable(i) => nw + ns + i
        }

    /// 指定 player id の兵種名 (`UnitResource#description`)。居なければ空文字。
    def classNameOf(id: Int32, _scene: Scene[NodeTag]): String \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(id) {
            case Some(d) => d#resource#description
            case None    => ""
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は ItemMenuScene と同じ `"w:<idx>"` 規約。
    pub def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。metadata は `"s:<idx>"` 規約。
    pub def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 消費アイテム 1 個ぶんの ItemEntry。metadata は `"c:<idx>"` 規約。
    pub def consumableEntry(idx: Int32, item: Consumable.ConsumableResource): ItemEntry = {
        text     = "${item#name} ${item#durability}",
        disabled = false,
        metadata = Some("c:${idx}")
    }

    /// 空スロット (「ここに自分のアイテムを置ける」位置) を表す ItemEntry。
    pub def emptySlotEntry(): ItemEntry = {
        text     = emptySlotEntryText(),
        disabled = false,
        metadata = Some(emptySlotMeta())
    }

    /// 指定 player の weapons + staves + consumables を ItemEntry 列に変換する。
    // 非driver の在庫 read を effect 経由（PartyQuery）に寄せる薄ラッパ（op 非増殖）。
    // render/refresh 経路でのみ使う。mutator 経路の recordTradeDraft 内 read は scene-arg 据え置き。
    def weaponsOf(id: Int32): List[UnitCatalog.WeaponResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#weapons) |> Option.getWithDefault(Nil)

    def stavesOf(id: Int32): List[Staff.StaffResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#staves) |> Option.getWithDefault(Nil)

    def consumablesOf(id: Int32): List[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#consumables) |> Option.getWithDefault(Nil)

    def inventoryEntries(playerId: Int32, _scene: Scene[NodeTag]):
            List[ItemEntry] \ PlayerData.PartyQuery =
        let weapons     = weaponsOf(playerId);
        let staves      = stavesOf(playerId);
        let consumables = consumablesOf(playerId);
        let weaponEntries     = List.mapWithIndex(idx -> w -> weaponEntry(idx, w), weapons);
        let staffEntries      = List.mapWithIndex(idx -> s -> staffEntry(idx, s),  staves);
        let consumableEntries = List.mapWithIndex(idx -> c -> consumableEntry(idx, c), consumables);
        List.append(weaponEntries, List.append(staffEntries, consumableEntries))

    /// 1 ペインに並べる ItemEntry 列。インベントリ + (上限未満のときだけ) 末尾の空スロット行。
    /// 上限ちょうど (満杯) なら空スロットを出さない = 片方向流入をブロックする。
    /// pub: テストが「満杯ペインに空スロットが出ない」ことを確認するのに使う。
    pub def paneEntries(playerId: Int32, scene: Scene[NodeTag]):
            List[ItemEntry] \ PlayerData.PartyQuery =
        let base = inventoryEntries(playerId, scene);
        if (isFull(playerId, scene)) base
        else List.append(base, emptySlotEntry() :: Nil)

    /// 指定 player の持ち物が上限に達しているか。居なければ false。
    def isFull(playerId: Int32, _scene: Scene[NodeTag]): Bool \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(playerId) {
            case Some(d) => PlayerScene.isInventoryFull(d)
            case None    => false
        }

    // ────────────────────────────────────────────────────────
    // (F) swap の適用
    // ────────────────────────────────────────────────────────

    /// エントリの metadata から「対象アイテム種別 / 空スロット」を判定。
    /// "empty" → None (空スロット)、"w:<idx>" / "s:<idx>" / "c:<idx>" は ItemKind に parse。
    def parseEntryKind(entry: ItemEntry): Option[PlayerData.ItemKind] =
        match entry#metadata {
            case None       => None
            case Some(meta) =>
                if (meta == emptySlotMeta()) None
                else ItemMenuScene.parseItemKind(meta)
        }

    /// `SwapPlan` を実行する。picker/receiver のどちらが giver (= 必須側) かを kind で切り替える:
    ///   - pickerKind = Some → picker → receiver (receiver が None なら片方向 transfer)
    ///   - pickerKind = None & receiverKind = Some → receiver → picker (受取)
    ///   - 両方 None → no-op
    /// 巻き戻しドラフトは `origin == FromTurn` のときだけ積む (ローグは undo 無し)。
    def applyTradeSwap(plan: SwapPlan, origin: Origin, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        match (plan#pickerKind, plan#receiverKind) {
            case (None, None) =>
                scene
            case (Some(pickerKind), receiverOpt) =>
                GameLogger.playerLog("P${plan#pickerId} と P${plan#receiverId} がアイテム交換");
                recordIfTurn(origin, plan#pickerId, pickerKind, plan#receiverId, receiverOpt, scene);
                PlayerScene.swapItem({selfId      = plan#pickerId,   selfKind    = pickerKind,
                                       partnerId   = plan#receiverId, partnerKind = receiverOpt}, scene)
            case (None, Some(receiverKind)) =>
                GameLogger.playerLog("P${plan#pickerId} と P${plan#receiverId} がアイテム交換");
                recordIfTurn(origin, plan#receiverId, receiverKind, plan#pickerId, None, scene);
                PlayerScene.swapItem({selfId      = plan#receiverId, selfKind    = receiverKind,
                                       partnerId   = plan#pickerId,   partnerKind = None}, scene)
        }

    /// `origin == FromTurn` のときだけ巻き戻しドラフトを積む。
    def recordIfTurn(origin: Origin, selfId: Int32, selfKind: PlayerData.ItemKind,
                      partnerId: Int32, partnerKindOpt: Option[PlayerData.ItemKind],
                      scene: Scene[NodeTag]): Unit \ SelectedPlayer.State =
        match origin {
            case Origin.FromTurn  =>
                recordTradeDraft(selfId, selfKind, partnerId, partnerKindOpt, scene)
            case Origin.FromRogue => ()
        }

    /// swap 実行前に、巻き戻し用 `Traded` ドラフトを SelectedPlayer に積む。
    /// self 側に実体が無い (swap が no-op になる) 場合は積まない。
    def recordTradeDraft(selfId: Int32, selfKind: PlayerData.ItemKind,
                          partnerId: Int32, partnerKindOpt: Option[PlayerData.ItemKind],
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

    // ────────────────────────────────────────────────────────
    // (G) 入力ハンドラ (InputHandler / MenuHandler から呼ばれる)
    // ────────────────────────────────────────────────────────

    /// 指定ペインの指定 entry に対する Z 確定処理。`decideConfirm` の結果を scene に適用する。
    /// `confirmCurrentSelection` から focus ペインの selected entry を渡して使うほか、
    /// テストが ItemList の中身に依存せず確定操作を直接駆動するのにも使う。
    pub def confirmAt(paneIndex: Int32, entry: ItemEntry, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let data = getPanelData(scene);
        let entryKind = parseEntryKind(entry);
        match decideConfirm(paneIndex, entryKind, data) {
            case ConfirmOutcome.JustUpdate(d2)      =>
                checked_ecast(setPanelData(d2, scene))
            case ConfirmOutcome.DoSwap(d2, plan)    =>
                applyTradeSwap(plan, data#origin, scene)
                    |> setPanelData(d2)
            case ConfirmOutcome.DoReorder(d2, plan) =>
                checked_ecast(
                    PlayerScene.reorderItem(plan#playerId, plan#kindA, plan#kindB, scene)
                        |> setPanelData(d2))
        }

    /// Z 押下: focus ペインの selected entry を取り、`confirmAt` に流す。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, SelectedPlayer.State} =
        let data = getPanelData(scene);
        let i = data#focus;
        match ItemList.getAt(menuPath(i), scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) => confirmAt(i, entry, scene)
        }

    /// X 押下: pick=Some なら pick 解除 (focus 据置)、pick=None なら origin に応じて閉じる。
    pub def cancelCurrent(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        let data = getPanelData(scene);
        match data#pick {
            case Some(_) =>
                checked_ecast(mapPanelData(d -> {pick = None | d}, scene))
            case None    =>
                match data#origin {
                    case Origin.FromTurn  =>
                        PhaseTransitions.enterActionSelectFromTrade(scene)
                    case Origin.FromRogue =>
                        PhaseTransitions.enterRogueMove(scene)
                            |> mapPanelData(_ -> defaultPanelData())
                }
        }

    /// ←/→ 押下: focus ペインを delta(±1) 動かす。
    pub def setPaneFocusDelta(delta: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPanelData(d -> moveFocus(delta, d), scene)
}
