/// 項目リストノード（Godot ItemList 準拠の最小実装）
/// see: https://docs.godotengine.org/en/stable/classes/class_itemlist.html
///
/// 縦並びの項目リストにキー駆動のカーソルを持たせる UI ノード。
/// 「たたかう / じゅもん / どうぐ」のようなコマンドメニューや、Godot の OptionButton
/// 風のドロップダウン項目選択を「マウス前提でない」形で実現する。
///
/// 各 ItemList は `focused` フラグを持ち、`focused = true` のものだけが
/// `handleMenus` パイプライン段でキー入力（↑↓/Enter/Escape）を受ける。
/// サブメニューを実現するときは、親 ItemList の `focused` を false にして
/// 子 ItemList の `focused` を true に切り替える（ゲーム側で制御）。
///
/// 描画は項目テキストを縦に並べ、選択中（かつ focused）の行の左に `cursorGlyph` を表示する。
/// 各項目を `Label2D.toDrawables` 経由でグリフ化することで、フォント描画ロジックを共通化している。
///
///   ItemList
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew

/// 1 項目分のデータ。`text` が表示文字、`disabled = true` の項目は選択不可
/// （カーソル移動時にスキップされ、disabledColor で淡く描画される）。
pub type alias ItemEntry = {
    text     = String,
    disabled = Bool
}

pub enum ItemList {
    case ItemList({
        items           = List[ItemEntry],
        selectedIndex   = Int32,
        focused         = Bool,
        cursorGlyph     = String,
        cursorColor     = Color,
        textColor       = Color,
        disabledColor   = Color,
        itemHeight      = Float64,
        cursorOffsetX   = Float64,
        wrap            = Bool,
        font            = FontAtlas,
        fontSize        = Float64,
        position        = Vec2.Vec2,
        rotation        = Float64,
        scale           = Vec2.Vec2,
        skew            = Float64,
        visible         = Bool,
        zIndex          = Int32,
        modulate        = Color,
        size            = Vec2.Vec2,
        // Enter / Escape の押下フレームで true、MenuEvent.handleMenus がクリアする
        pendingConfirm  = Bool,
        pendingCancel   = Bool,
        // 前フレームのキー状態（押下瞬間検出のため）
        prevUpDown      = Bool,
        prevDownDown    = Bool,
        prevConfirmDown = Bool,
        prevCancelDown  = Bool
    })
}

mod ItemList {
    /// テキスト項目とフォントから最小設定の ItemList を作る。
    /// 既定: selectedIndex=0、focused=false、cursorGlyph="▶"、wrap=true、disabled なし。
    pub def make(items: List[ItemEntry], font: FontAtlas, fontSize: Float64,
                 size: Vec2.Vec2): ItemList =
        ItemList.ItemList({
            items           = items,
            selectedIndex   = 0,
            focused         = false,
            cursorGlyph     = "▶",
            cursorColor     = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            textColor       = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            disabledColor   = {r = 0.5f32, g = 0.5f32, b = 0.5f32},
            itemHeight      = fontSize + 4.0,
            cursorOffsetX   = fontSize,
            wrap            = true,
            font            = font,
            fontSize        = fontSize,
            position        = Vec2.zero(),
            rotation        = 0.0,
            scale           = {x = 1.0, y = 1.0},
            skew            = 0.0,
            visible         = true,
            zIndex          = 0,
            modulate        = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            size            = size,
            pendingConfirm  = false,
            pendingCancel   = false,
            prevUpDown      = false,
            prevDownDown    = false,
            prevConfirmDown = false,
            prevCancelDown  = false
        })

    pub def getItems(list: ItemList): List[ItemEntry] =
        let ItemList.ItemList(r) = list;
        r#items

    pub def setItems(items: List[ItemEntry], list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        let n = List.length(items);
        let clamped = if (n == 0) 0 else Int32.min(r#selectedIndex, n - 1);
        ItemList.ItemList({items = items, selectedIndex = clamped | r})

    pub def getSelectedIndex(list: ItemList): Int32 =
        let ItemList.ItemList(r) = list;
        r#selectedIndex

    /// 選択 index を直接設定する（範囲外は 0..len-1 にクランプ、disabled でもそのまま）。
    /// 通常はキー入力経由で `moveCursor` が呼ばれて自動更新される。
    pub def setSelectedIndex(idx: Int32, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        let n = List.length(r#items);
        let clamped = if (n == 0) 0 else Int32.max(0, Int32.min(idx, n - 1));
        ItemList.ItemList({selectedIndex = clamped | r})

    pub def isFocused(list: ItemList): Bool =
        let ItemList.ItemList(r) = list;
        r#focused

    /// focused フラグを設定する（true でこの ItemList がキー入力を受ける）。
    /// 同一フレームで複数の ItemList を focused=true にすると、handleMenus は全部に
    /// 入力を送ってしまうのでゲーム側で 1 つだけに保つこと。
    ///
    /// false → true への切替時には、直前フレームのキー状態を「全押下中」と仮定して
    /// `prev*Down` を `true` で初期化する。これにより、別フェーズで Enter キーを押した
    /// 余韻でメニューが即確定してしまう問題（フェーズ遷移時の入力連鎖）を防ぐ。
    /// Godot で言う「grab_focus() 直後にキューに残った入力イベントを 1 回消費する」挙動。
    pub def setFocused(focused: Bool, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        if (focused and not r#focused)
            ItemList.ItemList({
                focused         = true,
                prevUpDown      = true,
                prevDownDown    = true,
                prevConfirmDown = true,
                prevCancelDown  = true
                | r
            })
        else
            ItemList.ItemList({focused = focused | r})

    pub def getCursorGlyph(list: ItemList): String =
        let ItemList.ItemList(r) = list;
        r#cursorGlyph

    pub def setCursorGlyph(glyph: String, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({cursorGlyph = glyph | r})

    pub def setCursorColor(color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({cursorColor = color | r})

    pub def setTextColor(color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({textColor = color | r})

    pub def setDisabledColor(color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({disabledColor = color | r})

    pub def setItemHeight(h: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemHeight = h | r})

    pub def setCursorOffsetX(x: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({cursorOffsetX = x | r})

    pub def setWrap(wrap: Bool, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({wrap = wrap | r})

    pub def getSize(list: ItemList): Vec2.Vec2 =
        let ItemList.ItemList(r) = list;
        r#size

    pub def setSize(size: Vec2.Vec2, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({size = size | r})

    /// 選択中の項目を取得する（範囲外なら `None`）。
    pub def getSelected(list: ItemList): Option[ItemEntry] =
        let ItemList.ItemList(r) = list;
        List.nth(r#selectedIndex, r#items)

    /// 指定 index の項目が disabled かどうか
    def isDisabledAt(idx: Int32, items: List[ItemEntry]): Bool =
        match List.nth(idx, items) {
            case Some(entry) => entry#disabled
            case None        => false
        }

    /// `from` から `direction`（+1=次、-1=前）方向に最初の非 disabled 項目を探す。
    /// `wrap = true` なら端で反対側にループする。全項目 disabled なら `from` を返す。
    /// 既に from が非 disabled でも 1 ステップ進めてから探す（呼び元は「次の項目」を期待）。
    pub def findNextEnabled(startIdx: Int32, direction: Int32, wrap: Bool, items: List[ItemEntry]): Int32 = {
        let n = List.length(items);
        if (n == 0) 0
        else findNextEnabledLoop(startIdx, direction, wrap, items, n, 0)
    }

    def findNextEnabledLoop(startIdx: Int32, direction: Int32, wrap: Bool, items: List[ItemEntry], n: Int32, attempts: Int32): Int32 = {
        if (attempts >= n)
            startIdx
        else {
            let candidate = startIdx + direction;
            let normalized =
                if (candidate < 0)
                    if (wrap) n - 1 else 0
                else if (candidate >= n)
                    if (wrap) 0 else n - 1
                else
                    candidate;
            if (not isDisabledAt(normalized, items))
                normalized
            else
                findNextEnabledLoop(normalized, direction, wrap, items, n, attempts + 1)
        }
    }

    /// 1 つ下の項目へカーソル移動。disabled をスキップ。
    pub def moveCursorDown(list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        let next = findNextEnabled(r#selectedIndex, 1, r#wrap, r#items);
        ItemList.ItemList({selectedIndex = next | r})

    /// 1 つ上の項目へカーソル移動。disabled をスキップ。
    pub def moveCursorUp(list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        let next = findNextEnabled(r#selectedIndex, -1, r#wrap, r#items);
        ItemList.ItemList({selectedIndex = next | r})

    pub def isPendingConfirm(list: ItemList): Bool =
        let ItemList.ItemList(r) = list;
        r#pendingConfirm

    pub def isPendingCancel(list: ItemList): Bool =
        let ItemList.ItemList(r) = list;
        r#pendingCancel

    /// pendingConfirm / pendingCancel フラグをクリア。
    /// `MenuEvent.handleMenus` がハンドラ発火後に呼ぶ。
    pub def clearPending(list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({pendingConfirm = false, pendingCancel = false | r})

    /// 現在のキー押下状態を受け取り、前フレームとの差分から押下瞬間を検出して
    /// カーソル移動 + pending フラグの更新を行う。`focused = false` の ItemList は no-op。
    pub def updateInputState(upDown: Bool, downDown: Bool, confirmDown: Bool,
                              cancelDown: Bool, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        if (not r#focused)
            ItemList.ItemList({
                prevUpDown = upDown, prevDownDown = downDown,
                prevConfirmDown = confirmDown, prevCancelDown = cancelDown | r
            })
        else {
            let upPressed = upDown and not r#prevUpDown;
            let downPressed = downDown and not r#prevDownDown;
            let confirmPressed = confirmDown and not r#prevConfirmDown;
            let cancelPressed = cancelDown and not r#prevCancelDown;
            let movedList =
                if (upPressed) moveCursorUp(list)
                else if (downPressed) moveCursorDown(list)
                else list;
            let ItemList.ItemList(m) = movedList;
            ItemList.ItemList({
                prevUpDown      = upDown,
                prevDownDown    = downDown,
                prevConfirmDown = confirmDown,
                prevCancelDown  = cancelDown,
                pendingConfirm  = m#pendingConfirm or confirmPressed,
                pendingCancel   = m#pendingCancel or cancelPressed
                | m
            })
        }

    /// 描画用 Drawable リストを返す。各項目を `Label2D.toDrawables` でグリフ化し、
    /// 選択中（かつ focused）の行の左に cursorGlyph を重ねる。
    pub def toDrawables(list: ItemList, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let ItemList.ItemList(r) = list;
        let textOriginX = globalPos#x + r#cursorOffsetX;
        let result = List.foldLeft((acc, entry) -> {
            let idx = acc#idx;
            let lineY = globalPos#y + Int32.toFloat64(idx) * r#itemHeight;
            let color = if (entry#disabled) r#disabledColor else r#textColor;
            let textLabel = Label2D.make(entry#text, r#font, r#fontSize)
                |> CanvasItem.setModulate(color)
                |> CanvasItem.setZIndex(r#zIndex);
            let textDrawables = Label2D.toDrawables(textLabel, {x = textOriginX, y = lineY});
            let lineDrawables = if (idx == r#selectedIndex and r#focused) {
                let cursorLabel = Label2D.make(r#cursorGlyph, r#font, r#fontSize)
                    |> CanvasItem.setModulate(r#cursorColor)
                    |> CanvasItem.setZIndex(r#zIndex);
                let cursorDrawables = Label2D.toDrawables(cursorLabel, {x = globalPos#x, y = lineY});
                List.append(cursorDrawables, textDrawables)
            } else textDrawables;
            {drawables = List.append(acc#drawables, lineDrawables), idx = idx + 1}
        }, {drawables = (Nil: List[GameEngine.Drawable]), idx = 0}, r#items);
        result#drawables
}

// ── CanvasItem 実装 ──

instance CanvasItem[ItemList] {
    pub def isVisible(list: ItemList): Bool =
        let ItemList.ItemList(r) = list;
        r#visible
    pub def setVisible(visible: Bool, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({visible = visible | r})
    pub def getModulate(list: ItemList): Color =
        let ItemList.ItemList(r) = list;
        r#modulate
    pub def setModulate(color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({modulate = color | r})
    pub def getZIndex(list: ItemList): Int32 =
        let ItemList.ItemList(r) = list;
        r#zIndex
    pub def setZIndex(zIndex: Int32, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[ItemList] {
    pub def getPosition(list: ItemList): Vec2.Vec2 =
        let ItemList.ItemList(r) = list;
        r#position
    pub def setPosition(position: Vec2.Vec2, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({position = position | r})
    pub def getRotation(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#rotation
    pub def setRotation(rotation: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({rotation = rotation | r})
    pub def getScale(list: ItemList): Vec2.Vec2 =
        let ItemList.ItemList(r) = list;
        r#scale
    pub def setScale(scale: Vec2.Vec2, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({scale = scale | r})
    pub def getSkew(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#skew
    pub def setSkew(skew: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({skew = skew | r})
}
