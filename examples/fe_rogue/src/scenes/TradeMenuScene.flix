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
///
/// layer=2 は HUD (layer=1) より手前に重ねてウィンドウが常に最前面に来るようにする。
/// Panel を TradeMenu の直下に置くことで Panel 全体の表示/非表示を TradeMenu の
/// CanvasItem 操作 1 回で制御でき、子 ItemList/Label2D も連動して隠れる。
mod TradeMenuScene {

    use JsonCompat.PathTag.Root

    /// どちらかのペインで「選択中」のスロット。`paneIndex` は picker のペイン (0 起点)。
    /// `paneIndex` を保持するのは、次の Z 押下が同じペインか別ペインかで
    /// 「並び替え / 上書き」と「swap」を区別するため。
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

    /// PanelData の初期値。members=Nil / origin=FromTurn のゼロ状態。
    /// セッション開始時に呼び手が members と origin を上書きして使う。
    pub def defaultPanelData(): PanelData = {
        members = Nil,
        focus   = 0,
        pick    = None,
        origin  = Origin.FromTurn
    }

    /// 確定 (Z) 押下の結果。状態更新だけか、別ペインとの swap か、同ペイン内の並び替えか。
    /// (中身に record alias を含む。Flix では record alias に Eq インスタンスを自動導出できない
    ///  制約があるため、Eq は導出せず match で分解して使う。)
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

    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 現在の Panel 状態を取り出す。ノード未登録なら `defaultPanelData`。
    pub def getPanelData(scene: Scene[NodeTag]): PanelData =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) => data
            case _                               => defaultPanelData()
        }

    /// Panel 状態を `f` で更新する。ノードが未登録の場合は scene をそのまま返す (副作用なし)。
    pub def mapPanelData(f: PanelData -> PanelData, scene: Scene[NodeTag]):
            Scene[NodeTag] =
        match Scene.getState(panelPath(), scene) {
            case Some(NodeTag.TradePanel(data)) =>
                Scene.setState(panelPath(), NodeTag.TradePanel(f(data)), scene)
            case _                               => scene
        }

    def setPanelData(data: PanelData, scene: Scene[NodeTag]): Scene[NodeTag] =
        mapPanelData(_ -> data, scene)

    /// 「物交換ウィンドウが現在 visible か」のヘルパー。呼び手が visible 判定を行うために使う。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    pub def paneCount(data: PanelData): Int32 = List.length(data#members)

    /// ペイン index に対応する player id。範囲外なら None。
    pub def playerIdAt(i: Int32, data: PanelData): Option[Int32] = List.nth(i, data#members)

    /// focus を delta(±1) だけ動かす。両端で押すと反対側ペインへラップする
    /// (左端で← → 右端、右端で→ → 左端)。垂直方向 (ItemList 内) は wrap=true で対応済みなので
    /// 水平 (ペイン間) もラップして一貫させる。`Int32.modulo` は除数符号 (正) に従うため
    /// `modulo(-1, n) = n-1`、`modulo(n, n) = 0` となり負の raw も正側へ畳まれる。
    pub def moveFocus(delta: Int32, data: PanelData): PanelData =
        let count = paneCount(data);
        if (count <= 0) data
        else {
            let wrapped = Int32.modulo(data#focus + delta, count);
            {focus = wrapped | data}
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
                            // 同ペインの別の実体アイテム → 並び替え（player が引ければ DoReorder、引けねば JustUpdate）
                            playerIdAt(paneIndex, data)
                                |> Option.map(pid -> ConfirmOutcome.DoReorder({pick = None | data},
                                       {playerId = pid, kindA = ka, kindB = kb}))
                                |> Option.getWithDefault(ConfirmOutcome.JustUpdate({pick = None | data}))
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

    // panel は最大 166x84。各ペインの幅は「重み」比で配分する。ロード(持ち物2倍=2列表示)は
    // 重み 2.0 で他ペインの倍幅を取り、他ペインはその右へ押し出される（= 全体が少し右寄り）。
    // ただしロードのアイテムが 2 列目に達していないときは重み 1.0 (1 列) に落とし、
    // ウィンドウ幅もそのぶん縮める (panelWidthFor 参照)。
    def panelFullWidth(): Float64  = 166.0  // 2 列フル表示時の最大幅 (scene.json と一致)
    def panelHeight(): Float64     = 84.0   // ウィンドウ高さは固定 (scene.json と一致)
    def paneLeftMargin(): Float64  = 4.0   // 左にわずかな余白（右寄せ感）
    def paneRightMargin(): Float64 = 2.0
    def paneGap(): Float64         = 2.0
    def paneTop(): Float64         = 10.0
    def paneHeight(): Float64      = 70.0

    // 重み 1 ぶんの「快適幅」。基準は「2 人交換でロード 2 列 = 合計重み 3 のときちょうど 166」。
    // ウィンドウ幅は max=166 を上限に、合計重み × この単位幅で自然に縮める。
    def comfortUnitWidth(): Float64 =
        (panelFullWidth() - paneLeftMargin() - paneRightMargin()) / 3.0

    // 1 列に収まる行数 = floor(paneHeight / itemHeight)。itemHeight は scene.json の ItemList と
    // 一致させる (engine に getItemHeight が無いためここでローカル定数として同期)。
    def slotHeight(): Float64 = 6.0  // = TradeMenuScene.scene.json の ItemList itemHeight
    def maxRowsPerColumn(): Int32 =
        Float64.tryToInt32(Float64.floor(paneHeight() / slotHeight())) |> Option.getWithDefault(1)

    /// 表示エントリ数が 1 列に収まらず 2 列目に達するか (= ロードに 2 列描画が要るか) の純粋判定。
    pub def needsSecondColumn(entryCount: Int32): Bool = entryCount > maxRowsPerColumn()

    /// ペインの重み。ロードは 2 列が必要なときだけ 2.0、それ以外 (非ロード / 1 列で足りるロード) は 1.0。
    def paneWeight(isLord: Bool, lordNeeds2Cols: Bool): Float64 =
        if (isLord and lordNeeds2Cols) 2.0 else 1.0

    /// members から各ペインの重みリストを作る。
    pub def paneWeights(members: List[Int32], lordNeeds2Cols: Bool): List[Float64] =
        let lid = PlayerScene.lordId();
        members |> List.map(m -> paneWeight(m == lid, lordNeeds2Cols))

    def sumF(xs: List[Float64]): Float64 = List.foldLeft((a, x) -> a + x, 0.0, xs)

    /// ウィンドウ幅。合計重み × 快適幅 (+ マージン) を 166 で頭打ち。
    /// 2 人・ロード1列(重み2) → 112.7 / 2 人・ロード2列(重み3) → 166 / 3 人 → 166 頭打ち。
    pub def panelWidthFor(members: List[Int32], lordNeeds2Cols: Bool): Float64 =
        let total   = sumF(paneWeights(members, lordNeeds2Cols));
        let natural = paneLeftMargin() + paneRightMargin() + total * comfortUnitWidth();
        Float64.min(panelFullWidth(), natural)

    /// ペイン i の位置とサイズ (panel 相対)。重み比で左から詰め、2 列ロードは倍幅。
    def paneLayoutFor(members: List[Int32], lordNeeds2Cols: Bool, i: Int32):
            {pos = Vec2.Vec2, size = Vec2.Vec2} =
        let weights = paneWeights(members, lordNeeds2Cols);
        let total   = sumF(weights);
        let avail   = panelWidthFor(members, lordNeeds2Cols) - paneLeftMargin() - paneRightMargin();
        let unitW   = if (total <= 0.0) avail else avail / total;
        let before  = sumF(List.take(i, weights));
        let w       = (List.nth(i, weights) |> Option.getWithDefault(1.0)) * unitW;
        {pos  = {x = paneLeftMargin() + before * unitW, y = paneTop()},
         size = {x = w - paneGap(), y = paneHeight()}}

    /// 兵種ラベルの位置 (ペインの左上、y=2)。
    def classPosFor(members: List[Int32], lordNeeds2Cols: Bool, i: Int32): Vec2.Vec2 =
        let layout = paneLayoutFor(members, lordNeeds2Cols, i);
        {x = layout#pos#x, y = 2.0}

    /// フェーズ遷移時の visibility 適用 (Push モデル)。
    /// `TradeInventory` のとき paneCount 個のペイン (+兵種ラベル) を visible にし、
    /// `paneLayout` で位置・サイズを設定する。focus ペインだけ focused = true。
    pub def applyVisibility(phase: TurnPhase.Phase, lordNeeds2Cols: Bool,
                             scene: Scene[NodeTag]): Scene[NodeTag] =
        let open = phase == TurnPhase.Phase.TradeInventory;
        let data = getPanelData(scene);
        let count = paneCount(data);
        let focus = data#focus;
        // 可視時はウィンドウ幅も内容に合わせて縮める (pos は左上固定なので右端が左へ寄る)。
        let withPanel = Panel.mapAt(panelPath(), p ->
            let visP = CanvasItem.setVisible(open, p);
            if (open) Panel.setSize({x = panelWidthFor(data#members, lordNeeds2Cols),
                                     y = panelHeight()}, visP)
            else visP,
            scene);
        List.foldLeft((acc, i) -> {
            let paneVisible = open and i < count;
            let paneFocused = paneVisible and i == focus;
            let layout = paneLayoutFor(data#members, lordNeeds2Cols, i);
            // ロード(持ち物2倍)が 2 列目に達したときだけ 2 列描画にして縦の突き抜けを防ぐ。
            let columns =
                if (playerIdAt(i, data) == Some(PlayerScene.lordId()) and lordNeeds2Cols) 2 else 1;
            acc
                |> ItemList.mapAt(menuPath(i), list ->
                    list
                        |> CanvasItem.setVisible(paneVisible)
                        |> ItemList.setFocused(paneFocused)
                        |> ItemList.setMaxColumns(columns)
                        |> Node2D.setPosition(layout#pos)
                        |> ItemList.setSize(layout#size))
                |> Label2D.mapAt(classPath(i), label ->
                    label
                        |> CanvasItem.setVisible(paneVisible)
                        |> Node2D.setPosition(classPosFor(data#members, lordNeeds2Cols, i)))
        }, withPanel, List.range(0, maxPanes()))

    /// 毎フレーム呼ばれる ItemList の process コールバック。
    ///   1. visibility/focus/layout を毎フレーム再評価
    ///   2. TradeInventory なら各ペインに対応 player のインベントリを同期 (満杯でなければ空スロット行を足す)
    /// 毎フレーム再評価するのは、フェーズ変化や swap によるインベントリ変化を
    /// イベント駆動でなく一貫した Pull モデルで反映するため。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                          path: NodePath,
                          scene: Scene[NodeTag]):
                         (EngineNode[NodeTag], Scene[NodeTag])
                         \ {TurnPhase.State, PlayerData.PartyQuery} =
        let phase = TurnPhase.State.get();
        let needs2 = lordNeeds2Columns(getPanelData(scene), scene);
        let withVisibility = applyVisibility(phase, needs2, scene);
        // 閉じている間は全ペインのカーソルを先頭(0)に戻し、次に開いたとき必ず最初から。
        let withItems = if (phase != TurnPhase.Phase.TradeInventory)
                resetAllCursors(withVisibility)
            else refreshPanes(withVisibility);
        match Scene.getEngineNode(path, withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    def resetAllCursors(scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, i) ->
            ItemList.mapAt(menuPath(i), ItemList.setSelectedIndex(0), acc),
            scene, List.range(0, maxPanes()))

    /// ロードが参加していて、その表示エントリ数 (在庫 + 空スロット) が 1 列に収まらない
    /// (= 2 列目に達する) か。これが false のときはウィンドウ幅・ロードの列数を縮める。
    def lordNeeds2Columns(data: PanelData, scene: Scene[NodeTag]): Bool \ PlayerData.PartyQuery =
        let lid = PlayerScene.lordId();
        if (List.exists(m -> m == lid, data#members))
            needsSecondColumn(List.length(paneEntries(lid, scene)))
        else false

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

    /// pick 中アイテムの行を強調色にする。ItemList に部分更新 API が無いため、一度
    /// `clearItemColors` で全行リセットしてから対象行だけ再塗りする。
    def applyHighlight(idxOpt: Option[Int32], list: ItemList): ItemList =
        let cleared = ItemList.clearItemColors(list);
        match idxOpt {
            case Some(idx) => ItemList.setItemColor(idx, pickColor(), cleared)
            case None      => cleared
        }

    /// UI 強調色を 1 か所に集約し、テーマ変更時の散逸を防ぐ。
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

    // 非 driver からの在庫 read は PartyQuery effect 経由に統一する。
    // 呼び出し回数を増やさないよう、render/refresh 経路だけで使う薄ラッパ。
    // mutator 経路 (recordTradeDraft) 内の read は scene-arg を直接渡すので経路が異なる。
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
    /// 表示とブロックロジックをここに同居させることで、空スロット有無の判断が分散しない。
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
    /// UI は direction-free (どちらのペインからでも place できる) なので、
    /// 実際の「誰が渡すか」は実行時に kind の有無で動的に決定する。
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
