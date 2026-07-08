// TradeMenuUi — 物交換ウィンドウ（最大 4 ペイン・World-entity UI 版）。
//
// UI ツリーは TradeMenu.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「各ペインに 1 人ぶんの在庫行を組む / 可視・選択・
// フォーカス・パネル位置を毎フレーム同期する / pick→渡す・まとめ渡し・キャンセルのゲーム
// ロジックを適用する」のゲーム側配線を持つ。
//
// 通常ターンの「こうかん」（隣接 2 人）と、集合（行軍）の「交換」（主人公＋隣接味方最大 3 人
// ＝計 4 人）を **同じ TradeInventory フェーズ**で扱う。2 人交換は「ペイン数 = 2」、集合交換は
// 「ペイン数 = 2..4」の特殊ケースにすぎない。
//
// 各ペインに 1 人ぶんの weapons + staves + consumables + rings を縦に並べる。持ち物が上限未満の
// ペインは末尾に空スロット行を出す（上限ちょうどなら出さない）。これで満杯メンバーへの片方向
// 流入は自然にブロックされ、1 対 1 入替（満杯側も 1 つ手放す）は引き続き可能になる。
//
// 入力フロー:
//   1. ←→ で focus ペインを移動（両端でラップ）。
//   2. focus ペインのスロットを Z 選択 → `pick = Some({paneIndex, kind})`。
//   3. 別ペインに移動してスロットを Z → `PlayerScene.swapItem` で交換実行 → pick クリア、
//      focus は place したペインに留まる（連続交換可能）。空スロットへの place は片方向 transfer。
//   4. pick=Some で X → pick 解除（focus 据置）。
//   5. pick=None で X → origin に応じてメニューを閉じる（FromTurn / FromGather → ActionSelect）。
//   6. Shift で focus ペインのアイテムに印を付け、別ペインで Z → 印の付いた分をまとめて渡す。
//
// ウィンドウ（スクロール）: 各ペインは `maxSlots()` 行の窓に固定し、在庫数が窓を超えると
// `windowOffset`（選択が窓に入るよう表示 offset をクランプする純関数）で縦スクロールする。
// 選択カーソルは在庫全体の index を持ち、ハイライトは窓内の相対行 (sel − offset) に置く。
// ペインごとに **selection は名前パスキーで独立**（"TradeMenu/panel/panesRow/pane0/menu" 等）で、
// ↑↓ は focus ペインの selection だけを動かす。
//
// ノード構造（TradeMenu.ui.json / layer=2）:
//   TradeMenu (none, 画面固定 HUD)
//     └─ panel (box, dir column, 可視時に幅=ペイン数から中央寄せ)
//           ├─ header (box) 「持物の交換」
//           ├─ panesRow (row) pane0..pane3（数を超えるペインは display:none で場所を取らない）
//           │      └─ pane_i (column) class（兵種名 重/最大）＋ menu（highlight + row0..row5）
//           └─ hint (text) 操作ヒント
mod TradeMenuUi {

    // ========================================================================
    // セッション状態の型（実体は `TradeMenuState.State` resource）
    // ========================================================================

    /// どちらかのペインで「選択中」のスロット。`paneIndex` は picker のペイン（0 起点）。
    /// `paneIndex` を保持するのは、次の Z 押下が同じペインか別ペインかで
    /// 「並び替え / 上書き」と「swap」を区別するため。
    /// `kind` は picker が選んだスロットの中身: `Some(k)` なら実体アイテム、
    /// `None` なら空スロット（=「受け取り希望」のマーカー）。
    pub type alias Pick = {
        paneIndex = Int32,
        kind      = Option[PlayerData.ItemKind]
    }

    /// 交換セッションの出口。cancel でメニューを閉じたときの戻り先フェーズを決める。
    ///   - `FromTurn`  : 通常ターンの隣接 2 人交換（X で ActionSelect へ戻す。巻き戻しドラフトを積む）
    ///   - `FromGather`: 集合（行軍）の隣接メニューからの交換（X で集合の隣接メニュー=ActionSelect
    ///                   へ戻す。undo 無し）
    pub enum Origin with Eq, ToString {
        case FromTurn
        case FromGather
    }

    /// 交換セッションの状態。
    ///   - `members`  : 各ペインに対応する player id（左→右の表示順）。length = ペイン数（2..4）。
    ///   - `focus`    : 現在の入力フォーカスのペイン index（0 起点）。
    ///   - `pick`     : 先に選んだスロット（無ければ None）。
    ///   - `origin`   : セッションの出口（cancel の戻り先）。
    ///   - `marks`    : Shift で複数選択した「まとめ渡し」対象アイテムの印。
    ///   - `markPane` : 印が属するペイン index（= 渡す側）。印は 1 人ぶんだけ持つので、別ペインに
    ///                  付け替えたら前の印は捨てる。印なしなら None。
    pub type alias PanelData = {
        members  = List[Int32],
        focus    = Int32,
        pick     = Option[Pick],
        origin   = Origin,
        marks    = Set[PlayerData.ItemKind],
        markPane = Option[Int32]
    }

    /// PanelData の初期値。members=Nil / origin=FromTurn / 印なしのゼロ状態。
    /// セッション開始時に呼び手が members と origin を上書きして使う。
    pub def defaultPanelData(): PanelData = {
        members  = Nil,
        focus    = 0,
        pick     = None,
        origin   = Origin.FromTurn,
        marks    = Set#{},
        markPane = None
    }

    /// 確定（Z）押下の結果。状態更新だけか、別ペインとの swap か、同ペイン内の並び替えか。
    /// （中身に record alias を含む。Flix では record alias に Eq インスタンスを自動導出できない
    ///  制約があるため、Eq は導出せず match で分解して使う。）
    pub enum ConfirmOutcome {
        case JustUpdate(PanelData)
        case DoSwap(PanelData, SwapPlan)
        case DoReorder(PanelData, ReorderPlan)
    }

    /// 1 回の swap で動かすアイテムの計画。player id は `members` から解決済み。
    ///   - picker = 先に選んだ側 / receiver = 後から選んだ（place した）側。
    ///   - kind が `None` の側は空スロット（= 受け取り専用）。
    pub type alias SwapPlan = {
        pickerId     = Int32,
        pickerKind   = Option[PlayerData.ItemKind],
        receiverId   = Int32,
        receiverKind = Option[PlayerData.ItemKind]
    }

    /// 同じペイン（同じ player）内でアイテムの並び順を入れ替える計画。
    /// kindA（先に pick）と kindB（後から選択）の表示位置を入れ替える。
    pub type alias ReorderPlan = {
        playerId = Int32,
        kindA    = PlayerData.ItemKind,
        kindB    = PlayerData.ItemKind
    }

    // ========================================================================
    // spec 置き場 / 名前パス / 表示定数
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/TradeMenu.ui.json")

    /// root（可視トグルの対象）と主要ノードの名前パス。
    pub def rootPath(): String = "TradeMenu"
    def panelPath(): String = "TradeMenu/panel"
    def panesRowPath(): String = "TradeMenu/panel/panesRow"
    def panePath(i: Int32): String = "${panesRowPath()}/pane${i}"
    def classPath(i: Int32): String = "${panePath(i)}/class"
    def menuPath(i: Int32): String = "${panePath(i)}/menu"
    def highlightPath(i: Int32): String = "${menuPath(i)}/highlight"
    def rowPath(i: Int32, r: Int32): String = "${menuPath(i)}/row${r}"
    def iconBgPath(i: Int32, r: Int32): String = "${rowPath(i, r)}/iconBg"
    def iconPath(i: Int32, r: Int32): String = "${rowPath(i, r)}/iconBg/icon"
    /// 空スロット行でアイコンチップの代わりに icon 列（幅 7）を占位する不可視スペーサ。
    /// これでアイコンの無い空スロットでも名前がアイテム行と同じ x へ揃う。
    def iconSpacerPath(i: Int32, r: Int32): String = "${rowPath(i, r)}/iconSpacer"
    def namePath(i: Int32, r: Int32): String = "${rowPath(i, r)}/info/name"
    def sublinePath(i: Int32, r: Int32): String = "${rowPath(i, r)}/info/subline"

    /// 交換ペインの最大数。通常ターンの隣接 2 人交換は 2、集合（行軍）の交換は主人公＋隣接味方
    /// 最大 3 人 = 計 4 まで。物理ノード（pane0..3）もこの数だけ用意する。
    pub def maxPanes(): Int32 = 4

    /// 1 ペインの表示窓の行数（ui.json の row0..row5 と一致させること）。
    /// pub: 実 asset の row 宣言数と一致することをテストが pin するため。
    pub def maxSlots(): Int32 = 6

    /// 行ピッチ（px）。ui.json の各行 height と一致させること（アイコン付き 2 段組）。
    def rowPitch(): Float64 = 12.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること。
    def highlightInset(): Float64 = 0.5

    /// 設計解像度の横幅（project.json の designWidth）。ウィンドウの中央寄せ計算に使う。
    def designWidth(): Float64 = 240.0
    /// ウィンドウ上端（design 空間）。カードに被らない範囲で縦中央よりやや上に置く。
    def panelTop(): Float64 = 18.0
    /// 1 ペインの固定幅（ui.json の tradePane width と一致）。
    def paneWidth(): Float64 = 48.0
    /// ペイン間の間隔（ui.json の panesRow gap と一致）。
    def paneGap(): Float64 = 2.0
    /// panel の内側余白（ui.json の panel pad と一致）。左右で 2 回効く。
    def panelPad(): Float64 = 2.0

    // ── 文字色（通常 / pick・印の強調＝黄）──
    def normalColor(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}
    /// pick 中 / まとめ渡し印のアイテムの強調色（黄系）。
    def markColor(): Color = {r = 1.0f32, g = 0.85f32, b = 0.2f32}

    // 選択ハイライト箱の配色（青枠）は TradeMenu.ui.json の highlight ノードで固定宣言する。
    // ハイライトは focus ペインだけに出す（非 focus ペインは箱を隠す）ので、ここで塗り分けはしない。

    /// 空スロットを表す ItemEntry のテキスト / metadata。
    pub def emptySlotEntryText(): String = "空きスロット"
    pub def emptySlotMeta(): String      = "empty"

    // ========================================================================
    // セッション状態の読み書き（resource 越し）
    // ========================================================================

    /// 現在の状態を取り出す。resource の初期値は `defaultPanelData`。
    pub def getPanelData(): PanelData \ TradeMenuState.State =
        TradeMenuState.State.get()

    /// 状態を `f` で更新する。
    pub def mapPanelData(f: PanelData -> PanelData): Unit \ TradeMenuState.State =
        TradeMenuState.State.put(f(TradeMenuState.State.get()))

    def setPanelData(data: PanelData): Unit \ TradeMenuState.State =
        mapPanelData(_ -> data)

    pub def paneCount(data: PanelData): Int32 = List.length(data#members)

    /// ペイン index に対応する player id。範囲外なら None。
    pub def playerIdAt(i: Int32, data: PanelData): Option[Int32] = List.nth(i, data#members)

    /// focus を delta(±1) だけ動かす。両端で押すと反対側ペインへラップする
    /// （左端で← → 右端、右端で→ → 左端）。`Int32.modulo` は除数符号（正）に従うため
    /// 負の raw も正側へ畳まれる。
    pub def moveFocus(delta: Int32, data: PanelData): PanelData =
        let count = paneCount(data);
        if (count <= 0) data
        else {
            let wrapped = Int32.modulo(data#focus + delta, count);
            {focus = wrapped | data}
        }

    /// Z 押下の純粋な状態遷移。`paneIndex` で押されたペイン、`entryKind` でそのスロットの
    /// 中身（実体 or 空）を示す。
    ///   - pick=None                       → このスロットを pick（focus 据置）
    ///   - pick=Some, 同ペイン同スロット    → pick 解除
    ///   - pick=Some, 同ペイン別スロット(両実体) → 並び替え（reorder）
    ///   - pick=Some, 同ペイン（空スロット絡み）  → pick を新スロットで上書き
    ///   - pick=Some, 別ペイン              → swap 実行（pick クリア、focus は place ペインに）
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
                            // 同ペインの別の実体アイテム → 並び替え（player が引ければ DoReorder）
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
                        // members が解決できない（防御的）→ pick だけ解除する
                        ConfirmOutcome.JustUpdate({pick = None | data})
                }
        }

    // ========================================================================
    // 行データ（各ペインの ItemEntry 列）— 純粋（読みは PartyQuery＝World オーバーレイ経由）
    // ========================================================================

    /// 武器 1 本ぶんの ItemEntry。本文は名前のみ（耐久・性能はサブラインへ）。
    /// metadata は ItemMenuUi と同じ `"w:<idx>"` 規約。
    pub def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = weapon#name,
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。本文は名前のみ。metadata は `"s:<idx>"` 規約。
    pub def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = staff#name,
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 消費アイテム 1 個ぶんの ItemEntry。本文は名前のみ。metadata は `"c:<idx>"` 規約。
    pub def consumableEntry(idx: Int32, item: Consumable.ConsumableResource): ItemEntry = {
        text     = item#name,
        disabled = false,
        metadata = Some("c:${idx}")
    }

    /// 指輪 1 個ぶんの ItemEntry。metadata は `"r:<idx>"` 規約。装備マークは付けない
    /// （武器同様、交換ウィンドウでは装備表示を省く方針に揃える）。
    pub def ringEntry(idx: Int32, ring: Ring.RingResource): ItemEntry = {
        text     = "${ring#name}",
        disabled = false,
        metadata = Some("r:${idx}")
    }

    /// 空スロット（「ここに自分のアイテムを置ける」位置）を表す ItemEntry。
    pub def emptySlotEntry(): ItemEntry = {
        text     = emptySlotEntryText(),
        disabled = false,
        metadata = Some(emptySlotMeta())
    }

    // 非 driver からの在庫 read は PartyQuery effect 経由に統一する。
    def weaponsOf(id: Int32): List[UnitCatalog.WeaponResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#weapons) |> Option.getWithDefault(Nil)
    def stavesOf(id: Int32): List[Staff.StaffResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#staves) |> Option.getWithDefault(Nil)
    def consumablesOf(id: Int32): List[Consumable.ConsumableResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#consumables) |> Option.getWithDefault(Nil)
    def ringsOf(id: Int32): List[Ring.RingResource] \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(id) |> Option.map(d -> d#rings) |> Option.getWithDefault(Nil)

    /// 在庫を武器→杖→消費→指輪の順に ItemEntry 列へ並べる（表示行 index と同順）。
    def inventoryEntries(playerId: Int32): List[ItemEntry] \ PlayerData.PartyQuery =
        let weaponEntries     = List.mapWithIndex(idx -> w -> weaponEntry(idx, w), weaponsOf(playerId));
        let staffEntries      = List.mapWithIndex(idx -> s -> staffEntry(idx, s),  stavesOf(playerId));
        let consumableEntries = List.mapWithIndex(idx -> c -> consumableEntry(idx, c), consumablesOf(playerId));
        let ringEntries       = List.mapWithIndex(idx -> r -> ringEntry(idx, r), ringsOf(playerId));
        List.append(weaponEntries,
            List.append(staffEntries, List.append(consumableEntries, ringEntries)))

    /// 1 ペインに並べる ItemEntry 列。インベントリ +（上限未満のときだけ）末尾の空スロット行。
    /// 上限ちょうど（満杯）なら空スロットを出さない = 片方向流入をブロックする。
    /// pub: テストが「満杯ペインに空スロットが出ない」ことを確認するのに使う。
    pub def paneEntries(playerId: Int32):
            List[ItemEntry] \ PlayerData.PartyQuery =
        let base = inventoryEntries(playerId);
        if (isFull(playerId)) base
        else List.append(base, emptySlotEntry() :: Nil)

    /// 指定 player の持ち物が上限に達しているか。居なければ false。
    def isFull(playerId: Int32): Bool \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(playerId) {
            case Some(d) => PlayerScene.isInventoryFull(d)
            case None    => false
        }

    /// エントリの metadata から「対象アイテム種別 / 空スロット」を判定。
    /// "empty" → None（空スロット）、"w:<idx>" / "s:<idx>" / "c:<idx>" / "r:<idx>" は ItemKind に parse。
    def parseEntryKind(entry: ItemEntry): Option[PlayerData.ItemKind] =
        match entry#metadata {
            case None       => None
            case Some(meta) =>
                if (meta == emptySlotMeta()) None
                else ItemMenuUi.parseItemKind(meta)
        }

    // ========================================================================
    // 毎フレーム同期（可視 + 中央寄せ + 各ペインの窓流し込み + フォーカス表現）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。TradeInventory の間だけ root を可視化し、
    /// paneCount 個のペインへ対応 player の在庫を窓へ流し込み、focus ペインだけ選択ハイライト箱を
    /// 出す（非 focus ペインは箱を隠す）。それ以外のフェーズでは全て隠し、各ペインのカーソルを先頭へ戻す。
    pub def frameStep(_dt: Duration.Duration): Unit
            \ {TurnPhase.State, TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        if (TurnPhase.State.get() != TurnPhase.Phase.TradeInventory) {
            // 非表示中は全ペインのカーソルを先頭に戻し、全ペインを隠す
            //（次に開いたとき常に最初のペイン・先頭項目から始まる）。
            let ui0 = UiWorldState.State.get();
            let hidden = List.range(0, maxPanes()) |> List.foldLeft((acc, i) ->
                acc |> UiStore.putSelection(menuPath(i), 0) |> UiStore.setVisible(panePath(i), false), ui0);
            UiWorldState.State.put(UiStore.setVisible(rootPath(), false, hidden))
        } else {
            let data = getPanelData();
            let count = paneCount(data);
            let width = panelOuterWidth(count);
            let ui0 = UiWorldState.State.get()
                |> UiStore.setVisible(rootPath(), true)
                |> UiStore.setAbs(panelPath(), {x = (designWidth() - width) / 2.0, y = panelTop()});
            let synced = List.range(0, maxPanes()) |> List.foldLeft((acc, i) ->
                syncPane(i, data, count, acc), ui0);
            UiWorldState.State.put(synced)
        }

    /// 可視ペイン数から panel の外形幅を求める（中央寄せ用）。ui.json の auto 幅と一致する式:
    /// pad×2 ＋ 幅×ペイン数 ＋ gap×(ペイン数−1)。隠しペインは display:none で場所を取らないため一致する。
    def panelOuterWidth(count: Int32): Float64 =
        if (count <= 0) 2.0 * panelPad()
        else 2.0 * panelPad()
             + Int32.toFloat64(count) * paneWidth()
             + Int32.toFloat64(count - 1) * paneGap()

    /// ペイン i を同期する。i >= count は隠す。それ以外は在庫を窓へ流し込み、見出し・ハイライトを更新する。
    def syncPane(i: Int32, data: PanelData, count: Int32,
                 ui: UiStore.UiWorld): UiStore.UiWorld \ PlayerData.PartyQuery =
        if (i >= count) UiStore.setVisible(panePath(i), false, ui)
        else match playerIdAt(i, data) {
            case None      => UiStore.setVisible(panePath(i), false, ui)
            case Some(pid) =>
                let entries = paneEntries(pid);
                let (sublines, sprites) = paneDecor(pid);
                let (header, headerColor) = paneHeader(pid);
                let total = List.length(entries);
                let sel = clampIndex(total, UiStore.selectionOf(menuPath(i), ui));
                let offset = windowOffsetLocal(sel, total);
                let focused = i == data#focus;
                let withRows = ui
                    |> UiStore.setVisible(panePath(i), true)
                    |> UiStore.setText(classPath(i), header)
                    |> UiStore.setTextTint(classPath(i), headerColor)
                    |> fillPaneRows({i = i, data = data, entries = entries, sublines = sublines,
                                     sprites = sprites, offset = offset})
                    |> UiStore.putSelection(menuPath(i), sel);
                // 選択ハイライト箱は focus ペインだけに出す（旧 ItemList の focused ハイライト準拠）。
                // 非 focus ペインは箱を隠し、空スロット行に減光箱が乗って「枠が動く」ように見えるのを防ぐ。
                if (focused)
                    UiMenu.applyHighlight({listPath = menuPath(i), highlightPath = highlightPath(i),
                                          sel = sel - offset, rowPitch = rowPitch(), inset = highlightInset()}, withRows)
                else
                    UiStore.setVisible(highlightPath(i), false, withRows)
        }

    /// `fillPaneRows` の引数束。
    /// `i`: ペイン index。`data`: セッション状態（pick / 印の強調色判定に使う）。
    /// `entries`: ペインの在庫全体（窓オフセット適用前）。`sublines`/`sprites`: 表示行 index →
    /// 2 行目文字列 / アイコン sprite。`offset`: 表示窓の先頭 index。
    type alias PaneRowsInput = {
        i        = Int32,
        data     = PanelData,
        entries  = List[ItemEntry],
        sublines = Map[Int32, String],
        sprites  = Map[Int32, SpriteRes.SpriteResource],
        offset   = Int32
    }

    /// entries[offset..offset+slots) を行 0..slots-1 へ流し込む。窓外の行は meta を消して不可視にする。
    /// 実体アイテムはアイコンチップ + 名前 + サブライン。空スロットはチップの代わりに不可視スペーサで
    /// icon 列（幅 7）を占位し、サブラインを畳んで名前 1 行を行内で縦中央に置く（旧 ItemList 準拠：
    /// アイコン列を予約したまま名前をアイテム行と同じ x へ揃え、縦中央に描く）。
    /// pick / 印の付いた行は名前を強調色（黄）で描く。
    def fillPaneRows(input: PaneRowsInput, ui: UiStore.UiWorld): UiStore.UiWorld =
        // 在庫が窓（maxSlots）を超えるのは windowOffset のスクロールで正常なので上限チェックはしない。
        List.range(0, maxSlots()) |> List.foldLeft((acc, r) -> {
            let idx = input#offset + r;
            match List.nth(idx, input#entries) {
                case Some(entry) =>
                    let hasIcon = Option.nonEmpty(Map.get(idx, input#sprites));
                    let hasSubline = Option.nonEmpty(Map.get(idx, input#sublines));
                    let withIcon = match Map.get(idx, input#sprites) {
                        case Some(spr) => UiStore.setSprite({path = iconPath(input#i, r), texture = spr#texture,
                                              hframes = spr#hframes, vframes = spr#vframes, frame = spr#frame}, acc)
                        case None      => acc
                    };
                    withIcon
                        |> UiStore.setVisible(iconBgPath(input#i, r), hasIcon)
                        // チップの無い行（空スロット）は icon 列を不可視スペーサで占位して名前 x を揃える。
                        |> UiStore.setVisible(iconSpacerPath(input#i, r), not hasIcon)
                        |> UiStore.setText(namePath(input#i, r), entry#text)
                        |> UiStore.setTextTint(namePath(input#i, r), rowTintFor(entry, input#i, input#data))
                        |> UiStore.setText(sublinePath(input#i, r), Option.getWithDefault("", Map.get(idx, input#sublines)))
                        // サブラインの無い行（空スロット）はサブラインを畳んで名前 1 行を縦中央に置く。
                        |> UiStore.setVisible(sublinePath(input#i, r), hasSubline)
                        |> UiStore.setMeta(rowPath(input#i, r), Option.getWithDefault("", entry#metadata))
                        |> UiStore.setVisible(rowPath(input#i, r), true)
                case None =>
                    acc
                        |> UiStore.clearMeta(rowPath(input#i, r))
                        |> UiStore.setVisible(rowPath(input#i, r), false)
            }
        }, ui)

    /// 行の name text tint。pick 中の行・まとめ渡し印の行は強調色（黄）、それ以外（選択含む）は通常色
    /// （選択は塗り箱ハイライトで示すため文字色は変えない）。
    def rowTintFor(entry: ItemEntry, paneIndex: Int32, data: PanelData): Color =
        let k = parseEntryKind(entry);
        let isPick = match data#pick {
            case Some(p) => p#paneIndex == paneIndex and Option.nonEmpty(k) and p#kind == k
            case None    => false
        };
        let isMark = data#markPane == Some(paneIndex)
            and (k |> Option.map(kk -> Set.memberOf(kk, data#marks)) |> Option.getWithDefault(false));
        if (isPick or isMark) markColor() else normalColor()

    /// 各ペインの各行（武器→杖→消費→指輪の順）に対応する「2 行目サブライン」と「行頭スプライト」を、
    /// 表示行 index をキーにした Map で返す。末尾の空スロット行はどちらの Map にも入れない。
    /// サブライン文字列は武器/アイテムメニューと同じ pub ヘルパーを再利用して表記を揃える。
    def paneDecor(playerId: Int32): (Map[Int32, String], Map[Int32, SpriteRes.SpriteResource])
            \ PlayerData.PartyQuery =
        let wD = List.map(w -> (WeaponSelectUi.weaponSubline(w), w#sprite), weaponsOf(playerId));
        let sD = List.map(s -> (ItemMenuUi.staffSubline(s),      s#sprite), stavesOf(playerId));
        let cD = List.map(c -> (ItemMenuUi.consumableSubline(c), c#sprite), consumablesOf(playerId));
        let rD = List.map(r -> (ItemMenuUi.ringStatLine(r),      r#sprite), ringsOf(playerId));
        let indexed = List.zipWithIndex(
            List.append(wD, List.append(sD, List.append(cD, rD))));
        let sublines = List.foldLeft((acc, pair) ->
            let (idx, tuple) = pair; let (sub, _) = tuple; Map.insert(idx, sub, acc),
            (Map.empty(): Map[Int32, String]), indexed);
        let sprites = List.foldLeft((acc, pair) ->
            let (idx, tuple) = pair; let (_, spr) = tuple; Map.insert(idx, spr, acc),
            (Map.empty(): Map[Int32, SpriteRes.SpriteResource]), indexed);
        (sublines, sprites)

    /// 見出し「兵種名 重量/最大」と積載段階の色。名前は兵種名（`resource#description`）、重量は
    /// 現在総重量と最大積載量。居なければ空文字＋ヘッダ色。配色は ItemMenu の重量ゲージと共通。
    def paneHeader(playerId: Int32): (String, Color) \ PlayerData.PartyQuery =
        match PlayerData.PartyQuery.get(playerId) {
            case Some(d) =>
                let load = PlayerScene.loadOf(d);
                ("${d#resource#description} ${Encumbrance.weightText(load#total)}/${Encumbrance.weightText(load#capacity)}",
                 UITheme.encumbranceTierColor(load#tier))
            case None    => ("", UITheme.headerText())
        }

    /// 表示窓の先頭 index。窓（maxSlots）を選択が超えないよう `ItemMenuUi.windowOffset` を再利用する。
    def windowOffsetLocal(sel: Int32, count: Int32): Int32 =
        ItemMenuUi.windowOffset(sel, count, maxSlots())

    /// 選択 index を [0, count) へ収める純関数。項目 0 のときは 0。
    def clampIndex(count: Int32, sel: Int32): Int32 =
        if (count <= 0) 0 else Int32.max(0, Int32.min(count - 1, sel))

    // ========================================================================
    // 選択 / フォーカス（↑↓ は focus ペインのみ・←→ でペイン切替）
    // ========================================================================

    /// ↑↓ 押下: focus ペインの選択カーソルを delta（±1）動かす（端で停止＝wrap しない）。
    pub def moveSelection(delta: Int32): Unit
            \ {TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        let data = getPanelData();
        let i = data#focus;
        match playerIdAt(i, data) {
            case None      => ()
            case Some(pid) =>
                let count = List.length(paneEntries(pid));
                let ui = UiWorldState.State.get();
                let next = clampIndex(count, UiStore.selectionOf(menuPath(i), ui) + delta);
                UiWorldState.State.put(UiStore.putSelection(menuPath(i), next, ui))
        }

    /// ←/→ 押下: focus ペインを delta(±1) 動かす（両端でラップ）。
    pub def setPaneFocusDelta(delta: Int32): Unit \ TradeMenuState.State =
        mapPanelData(d -> moveFocus(delta, d))

    // ========================================================================
    // 確定 / キャンセル / 印（Z / X / Shift）
    // ========================================================================

    /// focus ペインの選択カーソル位置の ItemEntry。ペインが解決できなければ None。
    def focusedEntry(paneIndex: Int32, data: PanelData):
            Option[ItemEntry] \ {PlayerData.PartyQuery, UiWorldState.State} =
        match playerIdAt(paneIndex, data) {
            case None      => None
            case Some(pid) =>
                let sel = UiStore.selectionOf(menuPath(paneIndex), UiWorldState.State.get());
                List.nth(sel, paneEntries(pid))
        }

    /// Z 押下: focus ペインの選択 entry を取り、`confirmAt` に流す。
    pub def confirmCurrentSelection():
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery,
                    TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        let data = getPanelData();
        let i = data#focus;
        match focusedEntry(i, data) {
            case None        => ()
            case Some(entry) => confirmAt(i, entry)
        }

    /// 指定ペインの指定 entry に対する Z 確定処理。`decideConfirm` の結果を状態に適用する。
    /// `confirmCurrentSelection` から focus ペインの selected entry を渡して使うほか、
    /// テストが選択状態に依存せず確定操作を直接駆動するのにも使う。
    pub def confirmAt(paneIndex: Int32, entry: ItemEntry):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery, TradeMenuState.State} =
        let data = getPanelData();
        // 印が付いていて、その付け元と違うペインで Z を押したら「まとめ渡し」。
        // それ以外（印なし / 同じペインで Z）は従来どおり 1 個ずつの pick / swap / 並び替え。
        if (isBulkConfirm(paneIndex, data))
            confirmBulkTransfer(paneIndex, data)
        else {
            let entryKind = parseEntryKind(entry);
            match decideConfirm(paneIndex, entryKind, data) {
                case ConfirmOutcome.JustUpdate(d2)      =>
                    checked_ecast(setPanelData(d2))
                case ConfirmOutcome.DoSwap(d2, plan)    =>
                    applyTradeSwap(plan, data#origin);
                    setPanelData(d2)
                case ConfirmOutcome.DoReorder(d2, plan) =>
                    checked_ecast({
                        PlayerScene.reorderItem(plan#playerId, plan#kindA, plan#kindB);
                        setPanelData(d2)
                    })
            }
        }

    /// X 押下の優先順位: pick=Some なら pick 解除（focus 据置）→ 印があれば印を解除 →
    /// どちらも無ければ origin に応じてウィンドウを閉じる。複数選択を 1 段で全部消さず、
    /// 「まず選択を取り消す」段階を踏めるようにしている。
    pub def cancelCurrent(): Unit \ {TurnPhase.State, TradeMenuState.State, RangeOverlayState.State} =
        let data = getPanelData();
        if (not Option.isEmpty(data#pick))
            checked_ecast(mapPanelData(d -> {pick = None | d}))
        else if (not Set.isEmpty(data#marks))
            checked_ecast(mapPanelData(d -> {marks = Set#{}, markPane = None | d}))
        else closeTrade(data#origin)

    /// pick も印も無いときの X: origin に応じて交換ウィンドウを閉じる（どちらも ActionSelect へ）。
    def closeTrade(origin: Origin): Unit \ {TurnPhase.State, TradeMenuState.State, RangeOverlayState.State} =
        match origin {
            case Origin.FromTurn   => PhaseTransitions.enterActionSelectFromTrade()
            case Origin.FromGather => PhaseTransitions.enterActionSelectFromTrade()
        }

    /// Shift 押下: focus ペインのカーソル位置にある自分のアイテムの印を付け外しする。
    /// 空スロットには印を付けない（種別が引けず None になる）。
    pub def toggleTradeMarkAtCursor(): Unit
            \ {TradeMenuState.State, PlayerData.PartyQuery, UiWorldState.State} =
        let data = getPanelData();
        let i = data#focus;
        let kindOpt = focusedEntry(i, data) |> Option.flatMap(parseEntryKind);
        match kindOpt {
            case Some(kind) => setPanelData(toggledMarks(i, kind, data))
            case None       => ()
        }

    /// 印を付け外しした後の PanelData を返す純粋関数。focus ペインが今の印元（`markPane`）と
    /// 違うときは前の印を捨てて focus を新しい印元にする（印は 1 ペインぶんだけ持つ）。
    /// 結果が空集合になったら印元も None に戻す。
    pub def toggledMarks(paneIndex: Int32, kind: PlayerData.ItemKind, data: PanelData): PanelData =
        let baseMarks = if (data#markPane == Some(paneIndex)) data#marks else Set#{};
        let newMarks = PlayerData.toggleMark(kind, baseMarks);
        if (Set.isEmpty(newMarks)) {marks = newMarks, markPane = None | data}
        else {marks = newMarks, markPane = Some(paneIndex) | data}

    /// 印が付いていて、その付け元（`markPane`）と違うペインで Z を押したか（= まとめ渡し条件）。
    def isBulkConfirm(paneIndex: Int32, data: PanelData): Bool =
        match data#markPane {
            case Some(giverPane) => not Set.isEmpty(data#marks) and giverPane != paneIndex
            case None            => false
        }

    // ========================================================================
    // swap / 片方向 transfer / まとめ渡しの適用
    // ========================================================================

    /// `SwapPlan` を実行する。picker/receiver のどちらが giver（= 必須側）かを kind で切り替える:
    ///   - pickerKind = Some → picker → receiver（receiver が None なら片方向 transfer）
    ///   - pickerKind = None & receiverKind = Some → receiver → picker（受取）
    ///   - 両方 None → no-op
    /// 巻き戻しドラフトは `origin == FromTurn` のときだけ積む（ローグは undo 無し）。
    def applyTradeSwap(plan: SwapPlan, origin: Origin):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery} =
        match (plan#pickerKind, plan#receiverKind) {
            case (None, None) =>
                ()
            case (Some(pickerKind), receiverOpt) =>
                GameLogger.playerLog("${PlayerScene.displayName(plan#pickerId)} と ${PlayerScene.displayName(plan#receiverId)} がアイテム交換");
                recordIfTurn(origin, {selfId = plan#pickerId, selfKind = pickerKind,
                                      partnerId = plan#receiverId, partnerKindOpt = receiverOpt});
                PlayerScene.swapItem({selfId      = plan#pickerId,   selfKind    = pickerKind,
                                       partnerId   = plan#receiverId, partnerKind = receiverOpt})
            case (None, Some(receiverKind)) =>
                GameLogger.playerLog("${PlayerScene.displayName(plan#pickerId)} と ${PlayerScene.displayName(plan#receiverId)} がアイテム交換");
                recordIfTurn(origin, {selfId = plan#receiverId, selfKind = receiverKind,
                                      partnerId = plan#pickerId, partnerKindOpt = None});
                PlayerScene.swapItem({selfId      = plan#receiverId, selfKind    = receiverKind,
                                       partnerId   = plan#pickerId,   partnerKind = None})
        }

    /// 巻き戻しドラフト用の trade 当事者データ。self が起点（実際に持ち物が動く側）、
    /// partner が相手側（partnerKindOpt=None なら相手は何も渡さない片方向）。
    type alias TradeParties = {
        selfId         = Int32,
        selfKind       = PlayerData.ItemKind,
        partnerId      = Int32,
        partnerKindOpt = Option[PlayerData.ItemKind]
    }

    /// `origin == FromTurn` のときだけ巻き戻しドラフトを積む。
    def recordIfTurn(origin: Origin, parties: TradeParties): Unit \ {SelectedPlayer.State, World.WorldQuery} =
        match origin {
            case Origin.FromTurn   =>
                recordTradeDraft(parties)
            case Origin.FromGather => ()
        }

    /// swap 実行前に、巻き戻し用 `Traded` ドラフトを SelectedPlayer に積む。
    /// self 側に実体が無い（swap が no-op になる）場合は積まない。
    def recordTradeDraft(parties: TradeParties): Unit \ {SelectedPlayer.State, World.WorldQuery} =
        match PlayerScene.getInventoryItem(parties#selfId, parties#selfKind) {
            case None           => ()
            case Some(selfItem) =>
                let partnerItemOpt = parties#partnerKindOpt
                    |> Option.flatMap(pk -> PlayerScene.getInventoryItem(parties#partnerId, pk));
                SelectedPlayer.pushDraft(MoveDraft.DraftAction.Traded({
                    selfId      = parties#selfId,      selfKind    = parties#selfKind,
                    selfItem    = selfItem,
                    partnerId   = parties#partnerId,   partnerKind = parties#partnerKindOpt,
                    partnerItem = partnerItemOpt
                }))
        }

    /// 印の付いた自分の複数アイテムを、別ペイン（`receiverPane` = 受け取り側）の空き枠ぶんだけ
    /// まとめて渡す。index の大きい順に 1 個ずつ既存の片方向 transfer に流すので、ログと巻き戻し
    /// ドラフトは 1 個ずつ渡したのと同じになる。渡し終えたら focus を受け取り側に残し印を消す。
    def confirmBulkTransfer(receiverPane: Int32, data: PanelData):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery, TradeMenuState.State} =
        let giverIdOpt    = data#markPane |> Option.flatMap(giverPane -> playerIdAt(giverPane, data));
        let receiverIdOpt = playerIdAt(receiverPane, data);
        let ordered       = PlayerData.marksDescendingPerList(data#marks);
        transferEach({giverIdOpt = giverIdOpt, receiverIdOpt = receiverIdOpt,
                      origin = data#origin, kinds = ordered});
        setPanelData({pick = None, marks = Set#{}, markPane = None, focus = receiverPane | data})

    /// `transferEach` の引数束。giver/receiver は共に片方向渡しの当事者 player id（Option は
    /// ペイン解決の失敗を表す）。`kinds` は渡す順（`PlayerData.marksDescendingPerList` の並び）。
    type alias TransferBatch = {
        giverIdOpt    = Option[Int32],
        receiverIdOpt = Option[Int32],
        origin        = Origin,
        kinds         = List[PlayerData.ItemKind]
    }

    /// giver / receiver が両方そろうときだけ、印の付いたアイテムを順に渡す。どちらか欠けたら no-op。
    def transferEach(batch: TransferBatch):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery} =
        match (batch#giverIdOpt, batch#receiverIdOpt) {
            case (Some(giverId), Some(receiverId)) =>
                List.forEach(kind ->
                    transferOne({giverId = giverId, receiverId = receiverId, origin = batch#origin, kind = kind}),
                    batch#kinds)
            case _ => ()
        }

    /// `transferOne` の引数束。giver=渡す側、receiver=受け取る側。
    type alias TransferOne = {
        giverId    = Int32,
        receiverId = Int32,
        origin     = Origin,
        kind       = PlayerData.ItemKind
    }

    /// 1 個を giver → receiver に片方向で渡す。受け取ると重量過多になるなら何もしない（部分転送の停止）。
    /// 容量は World から最新値を読む（連続して渡す途中で総重量が変わるため snapshot に頼らない）。
    def transferOne(t: TransferOne):
            Unit \ {GameLogger.GameLogger, SelectedPlayer.State, World.Command, World.WorldQuery} =
        if (receiverCanAccept(t#giverId, t#receiverId, t#kind))
            applyTradeSwap({pickerId = t#giverId, pickerKind = Some(t#kind),
                            receiverId = t#receiverId, receiverKind = None}, t#origin)
        else ()

    /// 受け取り側がこの 1 個を受け取っても重量過多(110%+ ＝ 移動不可)にならないか。
    /// 拾得ゲート（`PlayerScene.wouldOverloadByPicking`）と同じ基準で、まとめ渡しが受け手を
    /// 移動不可まで積み込むのを防ぐ（アイテム単位で判定し、超える 1 個目の手前で止める）。
    /// まとめ渡しの fold 内で 1 個渡すごとに最新の積載を見る read-during-mutation。在庫は
    /// World 権威で、Cmd emit は worldRef へ即時適用される（read-after-write）ため、WorldQuery の
    /// dataFromWorld 直読みが常に fold 中の最新在庫を返す（frame-top snapshot の PartyQuery とは別物）。
    def receiverCanAccept(giverId: Int32, receiverId: Int32,
                           kind: PlayerData.ItemKind): Bool \ World.WorldQuery =
        let w = World.WorldQuery.get();
        match (World.dataFromWorld(giverId, w), World.dataFromWorld(receiverId, w)) {
            case (Some(giver), Some(receiver)) =>
                match PlayerScene.heldItemWeight(giver, kind) {
                    case Some(weight) =>
                        not Encumbrance.wouldExceedImmobile(PlayerScene.loadOf(receiver), weight)
                    case None => false
                }
            case _ => false
        }
}
