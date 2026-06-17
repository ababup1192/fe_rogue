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
/// `metadata` は表示テキストとは別にゲーム側が項目に紐付ける文字列識別子（Godot の
/// ItemList.set_item_metadata 準拠）。 例: 「ホイミ」 表示の項目に `Some("hoimi")` を
/// 持たせ、 確定時に MenuHandler 側で spell_id として取り出す。
pub type alias ItemEntry = {
    text     = String,
    disabled = Bool,
    metadata = Option[String]
}

/// 行ごとのアイコン情報。`text` の左に sprite sheet の指定 frame を描画するときに使う。
/// Godot ItemList の `set_item_icon(idx, texture)` + sub-rect 相当。
/// 任意の行に部分的にアイコンを置きたいので、`itemIcons` は index→ItemIcon の Map で持つ。
pub type alias ItemIcon = {
    texture = String,
    hframes = Int32,
    vframes = Int32,
    frame   = Int32
}

/// 選択行の角丸ハイライト設定（関連設定を1レコードに集約）。`fillColor = None` で無効（既定）。
/// 描画は `Drawable.style`（BoxStyle）を行背景に敷く＝Panel と同じ角丸＋枠の仕組みを再利用する。
/// `inset` は行矩形を全方向に縮めて「浮いた角丸枠」にするための余白（px）。
pub type alias SelectedHighlight = {
    fillColor    = Option[Color],
    fillAlpha    = Float32,
    borderColor  = Color,
    borderAlpha  = Float32,
    borderWidth  = Float64,
    cornerRadius = Float64,
    inset        = Float64
}

/// ItemList の各項目ラベルの横配置。Left=従来の左固定、Center=列内中央寄せ。
/// Godot Label の HorizontalAlignment（Left/Center）に対応する2値。
pub enum ItemAlignment with Eq {
    case Left
    case Center
}

pub enum ItemList {
    case ItemList({
        items           = List[ItemEntry],
        // 行 index → アイコン。指定行のみアイコン表示する。
        // iconSize > 0 のときに限り toDrawables が描画する。
        itemIcons       = Map[Int32, ItemIcon],
        // 行 index → 右寄せサブラベル（主テキストの右端に淡色で出す副説明。例「敵を選ぶ」）。
        // 指定行のみ描画。Godot ItemList には無い拡張。
        itemSubtexts    = Map[Int32, String],
        // アイコン表示サイズ（px、正方形）。0 ならアイコン領域を確保しない（既存挙動）。
        iconSize        = Float64,
        // アイコンとテキストの間隔（px）。iconSize > 0 のときのみ有効。
        iconTextGap     = Float64,
        selectedIndex   = Int32,
        focused         = Bool,
        cursorGlyph     = String,
        cursorColor     = Color,
        textColor       = Color,
        disabledColor   = Color,
        // 行 index → 文字色の個別上書き。指定行は textColor/disabledColor の代わりにこの色で描く。
        // Godot の ItemList.set_item_custom_fg_color 相当（pick 中アイテムの強調などに使う）。
        itemColors      = Map[Int32, Color],
        // 右寄せサブラベルの文字色（itemSubtexts 用）。
        subtextColor    = Color,
        // 右寄せサブラベルのフォントサイズ。既定は本文 fontSize と同じ（後方互換）。
        subtextFontSize = Float64,
        // 選択行の角丸ハイライト（`fillColor=None` で無効＝従来どおり cursorGlyph 表示のみ）。
        selectedHighlight = SelectedHighlight,
        // 全行に敷くチップ背景（`fillColor=None` で無効＝既定）。selectedHighlight の下に描く。
        rowHighlight    = SelectedHighlight,
        // 各項目ラベルの横配置（Left=左固定／Center=列内中央寄せ）。既定 Left。
        itemAlignment   = ItemAlignment,
        itemHeight      = Float64,
        cursorOffsetX   = Float64,
        wrap            = Bool,
        // 列数（Godot の ItemList.max_columns 相当）。1 で従来どおりの単一縦リスト。
        // 2 以上のとき toDrawables は「縦詰め（左列に上から、あふれたら次の列）」で並べる。
        // カーソル移動は列に関係なく selectedIndex を上下する 1 次元のまま（描画位置だけ列対応）。
        maxColumns      = Int32,
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
            itemIcons       = (Map.empty(): Map[Int32, ItemIcon]),
            itemSubtexts    = (Map.empty(): Map[Int32, String]),
            iconSize        = 0.0,
            iconTextGap     = 2.0,
            selectedIndex   = 0,
            focused         = false,
            cursorGlyph     = "▶",
            cursorColor     = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            textColor       = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            disabledColor   = {r = 0.5f32, g = 0.5f32, b = 0.5f32},
            itemColors      = (Map.empty(): Map[Int32, Color]),
            subtextColor    = {r = 0.5f32, g = 0.5f32, b = 0.5f32},
            subtextFontSize = fontSize,
            selectedHighlight = ({fillColor = None, fillAlpha = 1.0f32,
                                   borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
                                   borderAlpha = 1.0f32, borderWidth = 0.0,
                                   cornerRadius = 0.0, inset = 0.0}: SelectedHighlight),
            rowHighlight    = ({fillColor = None, fillAlpha = 1.0f32,
                                 borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
                                 borderAlpha = 1.0f32, borderWidth = 0.0,
                                 cornerRadius = 0.0, inset = 0.0}: SelectedHighlight),
            itemAlignment   = ItemAlignment.Left,
            itemHeight      = fontSize + 4.0,
            cursorOffsetX   = fontSize,
            wrap            = true,
            maxColumns      = 1,
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

    // ── アイコン ──

    pub def getItemIcons(list: ItemList): Map[Int32, ItemIcon] =
        let ItemList.ItemList(r) = list;
        r#itemIcons

    /// 全行ぶんのアイコンマップを差し替える。`setItems` と同じくらいの頻度で呼ぶ想定。
    pub def setItemIcons(icons: Map[Int32, ItemIcon], list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemIcons = icons | r})

    // ── 個別文字色（Godot の set_item_custom_fg_color 相当）──

    pub def getItemColors(list: ItemList): Map[Int32, Color] =
        let ItemList.ItemList(r) = list;
        r#itemColors

    /// 行 index → 文字色の上書きマップを丸ごと差し替える。
    pub def setItemColors(colors: Map[Int32, Color], list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemColors = colors | r})

    /// 指定行の文字色を上書きする（既存のマップに 1 件追加）。
    pub def setItemColor(idx: Int32, color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemColors = Map.insert(idx, color, r#itemColors) | r})

    /// 個別文字色をすべて消す（textColor/disabledColor の既定描画に戻す）。
    pub def clearItemColors(list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemColors = (Map.empty(): Map[Int32, Color]) | r})

    /// 単一行のアイコンを設定/上書きする。
    pub def setIconAt(idx: Int32, icon: ItemIcon, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemIcons = Map.insert(idx, icon, r#itemIcons) | r})

    pub def getIconSize(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#iconSize

    /// アイコン表示サイズを設定する。0 で「アイコン領域なし」（既存挙動）。
    /// 0 より大なら各行 `iconSize × iconSize` のアイコンを描画用に左に確保し、テキストが右にずれる。
    pub def setIconSize(size: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({iconSize = Float64.max(0.0, size) | r})

    pub def getIconTextGap(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#iconTextGap

    pub def setIconTextGap(gap: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({iconTextGap = gap | r})

    // ── items ──

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

    // ── 右寄せサブラベル ──

    /// 行 index → 右寄せサブラベル文字列のマップを丸ごと差し替える（`setItems` と同頻度で呼ぶ想定）。
    pub def setItemSubtexts(subtexts: Map[Int32, String], list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemSubtexts = subtexts | r})

    pub def setSubtextColor(color: Color, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({subtextColor = color | r})

    // ── 選択行の角丸ハイライト（BoxStyle 再利用）──

    /// 選択行ハイライト設定を丸ごと設定する。`fillColor = Some(..)` で有効化、`None`（既定）で無効。
    pub def setSelectedHighlight(highlight: SelectedHighlight, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({selectedHighlight = highlight | r})

    pub def getSelectedHighlight(list: ItemList): SelectedHighlight =
        let ItemList.ItemList(r) = list;
        r#selectedHighlight

    /// 全行に敷くチップ背景を設定する。`fillColor = Some(..)` で有効化、`None`（既定）で無効。
    /// selectedHighlight の下に描かれるので「全行チップ＋選択行はより明るい枠」を2層で表現できる。
    pub def setRowHighlight(highlight: SelectedHighlight, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({rowHighlight = highlight | r})

    pub def getRowHighlight(list: ItemList): SelectedHighlight =
        let ItemList.ItemList(r) = list;
        r#rowHighlight

    /// 各項目ラベルの横配置を設定する（Left=左固定／Center=列内中央寄せ）。
    pub def setItemAlignment(alignment: ItemAlignment, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemAlignment = alignment | r})

    pub def getItemAlignment(list: ItemList): ItemAlignment =
        let ItemList.ItemList(r) = list;
        r#itemAlignment

    /// 右寄せサブラベルのフォントサイズを設定する（既定は本文 fontSize と同じ）。
    pub def setSubtextFontSize(size: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({subtextFontSize = size | r})

    pub def getSubtextFontSize(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#subtextFontSize

    /// フォントアトラス（テキスト幅の実測などに使う）。
    pub def getFont(list: ItemList): FontAtlas =
        let ItemList.ItemList(r) = list;
        r#font

    pub def getFontSize(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#fontSize

    pub def getCursorOffsetX(list: ItemList): Float64 =
        let ItemList.ItemList(r) = list;
        r#cursorOffsetX

    pub def setItemHeight(h: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({itemHeight = h | r})

    pub def setCursorOffsetX(x: Float64, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({cursorOffsetX = x | r})

    pub def setWrap(wrap: Bool, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({wrap = wrap | r})

    pub def getMaxColumns(list: ItemList): Int32 =
        let ItemList.ItemList(r) = list;
        r#maxColumns

    /// 列数を設定する（最小 1）。2 以上で toDrawables が縦詰め複数列描画になる。
    pub def setMaxColumns(n: Int32, list: ItemList): ItemList =
        let ItemList.ItemList(r) = list;
        ItemList.ItemList({maxColumns = Int32.max(1, n) | r})

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

    /// アイコン 1 つ分の Drawable を組み立てる（sprite sheet の指定 frame を iconSize に
    /// スケールして描画）。`spriteToDrawable` の texture info 取得が `GameEngine.Game` を要求する。
    def renderIcon(icon: ItemIcon, pos: Vec2.Vec2, iconSize: Float64, zIndex: Int32):
            GameEngine.Drawable \ GameEngine.Game =
        let texInfo = match GameEngine.Game.getTextureInfo(icon#texture) {
            case Some(info) => info
            case None       => bug!("ItemList icon: texture '${icon#texture}' not registered")
        };
        let cellW = texInfo#width  / Int32.toFloat64(icon#hframes);
        let cellH = texInfo#height / Int32.toFloat64(icon#vframes);
        let scaleX = if (cellW <= 0.0) 0.0 else iconSize / cellW;
        let scaleY = if (cellH <= 0.0) 0.0 else iconSize / cellH;
        let sprite = Sprite2D.make(icon#texture, Vec2.zero(), {x = scaleX, y = scaleY})
            |> Sprite2D.setHframes(icon#hframes)
            |> Sprite2D.setVframes(icon#vframes)
            |> Sprite2D.setFrame(icon#frame)
            |> Sprite2D.setCentered(false)
            |> CanvasItem.setZIndex(zIndex);
        EngineNode.spriteToDrawable(sprite, pos)

    /// 選択行ハイライトの styled Drawable を作る。`rowPos`/`rowSize` は行矩形（左上＋サイズ）、
    /// `inset` で全方向に縮めて「浮いた角丸枠」にする。塗り＋枠＋角丸は `Drawable.style`(BoxStyle) に委ねる。
    def highlightDrawable(h: SelectedHighlight, fill: Color, rowPos: Vec2.Vec2,
                           rowSize: Vec2.Vec2, zIndex: Int32): GameEngine.Drawable =
        let hi = h#inset;
        ({texture = "", position = {x = rowPos#x + hi, y = rowPos#y + hi},
          scale = {x = rowSize#x - 2.0 * hi, y = rowSize#y - 2.0 * hi},
          rotation = 0.0, color = fill, alpha = h#fillAlpha, centered = false,
          uvOffset = {x = 0.0, y = 0.0}, uvScale = {x = 1.0, y = 1.0}, zIndex = zIndex,
          style = Some({cornerRadius = h#cornerRadius, borderWidth = h#borderWidth,
                        borderColor = h#borderColor, borderAlpha = h#borderAlpha,
                        stripeColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
                        stripeAlpha = 0.0f32, stripeWidth = 0.0, stripePeriod = 0.0})}: GameEngine.Drawable)

    /// 描画用 Drawable リストを返す。各項目を `Label2D.toDrawables` でグリフ化し、
    /// 選択中（かつ focused）の行の左に cursorGlyph を重ねる。
    /// `iconSize > 0` のときは各行のテキストの左にアイコン領域を確保する
    /// （`itemIcons` Map に登録のある行のみアイコンが描かれる）。
    pub def toDrawables(list: ItemList, globalPos: Vec2.Vec2):
            List[GameEngine.Drawable] \ GameEngine.Game =
        let ItemList.ItemList(r) = list;
        let hasIconArea = r#iconSize > 0.0;
        // 列レイアウト（縦詰め）: 列数 cols、1 列あたり rowsPerCol 行。
        // idx → col = idx / rowsPerCol、row = idx % rowsPerCol。col=0 が左列。
        // rowsPerCol は「列の高さ size.y に収まる行数」とすることで、**左列を一番下まで埋めてから
        // 次の列へ**送る（= 列が満ちるまで空スロットも左列の最後に出る）。均等割り(ceil)にすると
        // 3 項目が左2/右1 に分かれてしまうため高さ基準にする。
        // cols=1 は全項目を 1 列に積む従来挙動（高さ超過は従来どおり下にあふれる）。
        let cols = Int32.max(1, r#maxColumns);
        let count = List.length(r#items);
        let rowsPerCol =
            if (cols <= 1) Int32.max(1, count)
            else Int32.max(1,
                Float64.tryToInt32(Float64.floor(r#size#y / r#itemHeight))
                    |> Option.getWithDefault(1));
        let colWidth = r#size#x / Int32.toFloat64(cols);
        // 行内縦中央寄せ: テキスト行高・アイコンを itemHeight の中央に置く（Godot ItemList 準拠）。
        // itemHeight ちょうどに本文 1 行が収まるときは vCenter≈0（従来の上端揃えとほぼ同じ）。
        let mainScale = r#fontSize / r#font#fontSize;
        let mainLineHeight = (r#font#ascent + r#font#descent + r#font#lineGap) * mainScale;
        let vCenter = (r#itemHeight - mainLineHeight) / 2.0;
        let iconVCenter = (r#itemHeight - r#iconSize) / 2.0;
        // サブラベルのベースラインを本文に揃える縦補正の係数。
        let ascentRatio = r#font#ascent / r#font#fontSize;
        let result = List.foldLeft((acc, entry) -> {
            let idx = acc#idx;
            let col = idx / rowsPerCol;
            let row = Int32.remainder(idx, rowsPerCol);
            let colX = globalPos#x + Int32.toFloat64(col) * colWidth;
            let lineY = globalPos#y + Int32.toFloat64(row) * r#itemHeight;
            let textY = lineY + vCenter;
            let iconY = lineY + iconVCenter;
            let iconStartX = colX + r#cursorOffsetX;
            let textOriginX =
                if (hasIconArea) iconStartX + r#iconSize + r#iconTextGap
                else colX + r#cursorOffsetX;
            let color = match Map.get(idx, r#itemColors) {
                case Some(c) => c
                case None    => if (entry#disabled) r#disabledColor else r#textColor
            };
            // テキスト（itemAlignment=Center なら列幅中央に寄せる）
            let (textX, textAlign) = match r#itemAlignment {
                case ItemAlignment.Center =>
                    (colX + colWidth / 2.0, HorizontalAlignment.Center)
                case ItemAlignment.Left   =>
                    (textOriginX, HorizontalAlignment.Left)
            };
            let textLabel = Label2D.make(entry#text, r#font, r#fontSize)
                |> CanvasItem.setModulate(color)
                |> CanvasItem.setZIndex(r#zIndex)
                |> Label2D.setHorizontalAlignment(textAlign);
            let textDrawables = Label2D.toDrawables(textLabel, {x = textX, y = textY});
            // アイコン（その行に登録があり、iconSize > 0 のとき）
            let iconDrawables: List[GameEngine.Drawable] =
                if (hasIconArea) match Map.get(idx, r#itemIcons) {
                    case Some(icon) =>
                        renderIcon(icon, {x = iconStartX, y = iconY}, r#iconSize, r#zIndex) :: Nil
                    case None       => Nil
                }
                else Nil;
            // カーソル glyph（選択中かつ focused のとき）。列対応で colX 基準に出す。
            // cursorGlyph="" なら Label2D がグリフ0で何も描かない（角丸ハイライトで選択を示すケース）。
            let baseLine = if (idx == r#selectedIndex and r#focused) {
                let cursorLabel = Label2D.make(r#cursorGlyph, r#font, r#fontSize)
                    |> CanvasItem.setModulate(r#cursorColor)
                    |> CanvasItem.setZIndex(r#zIndex);
                let cursorDrawables = Label2D.toDrawables(cursorLabel, {x = colX, y = textY});
                List.append(cursorDrawables, List.append(iconDrawables, textDrawables))
            } else
                List.append(iconDrawables, textDrawables);
            // 全行チップ（最背面に敷く）。rowHighlight#fillColor=None で無効（既定＝従来）。
            let rowHighlightDrawables: List[GameEngine.Drawable] =
                match r#rowHighlight#fillColor {
                    case Some(fill) =>
                        highlightDrawable(r#rowHighlight, fill, {x = colX, y = lineY},
                                          {x = colWidth, y = r#itemHeight}, r#zIndex) :: Nil
                    case None => Nil
                };
            // 選択行の角丸ハイライト（rowHighlight の上・本文の下に敷く）。fillColor=None で無効（従来）。
            let highlightDrawables: List[GameEngine.Drawable] =
                if (idx == r#selectedIndex and r#focused)
                    match r#selectedHighlight#fillColor {
                        case Some(fill) =>
                            highlightDrawable(r#selectedHighlight, fill, {x = colX, y = lineY},
                                              {x = colWidth, y = r#itemHeight}, r#zIndex) :: Nil
                        case None => Nil
                    }
                else Nil;
            // 右寄せサブラベル（最後に emit ＝本文の上）。登録行のみ。右端＝列右端から測った幅ぶん戻す。
            let subtextDrawables: List[GameEngine.Drawable] =
                match Map.get(idx, r#itemSubtexts) {
                    case Some(sub) =>
                        let subLabel = Label2D.make(sub, r#font, r#subtextFontSize)
                            |> CanvasItem.setModulate(r#subtextColor)
                            |> CanvasItem.setZIndex(r#zIndex);
                        let subW = Label2D.measure(subLabel)#x;
                        let subX = colX + colWidth - subW - r#iconTextGap;
                        // 本文の縦中央位置(textY)に、小フォントのベースラインを合わせる。
                        // subtextFontSize == fontSize なら本文と同じ y（後方互換）。
                        let subY = textY + ascentRatio * (r#fontSize - r#subtextFontSize);
                        Label2D.toDrawables(subLabel, {x = subX, y = subY})
                    case None => Nil
                };
            let lineDrawables =
                List.append(rowHighlightDrawables,
                    List.append(highlightDrawables,
                        List.append(baseLine, subtextDrawables)));
            {drawables = List.append(acc#drawables, lineDrawables), idx = idx + 1}
        }, {drawables = (Nil: List[GameEngine.Drawable]), idx = 0}, r#items);
        result#drawables

    /// path 位置に ItemList が居れば取り出す（Godot の `GetNode<ItemList>(path)` 相当）。
    /// 別ノードや欠落なら `None`。
    pub def getAt(path: NodePath, scene: Scene[s]): Option[ItemList] =
        match Scene.getEngineNode(path, scene) {
            case Some(EngineNode.ItemListWithState(list, _)) => Some(list)
            case _                                            => None
        }

    /// path 位置の ItemList に f を適用。state タグは保持される。
    /// path に ItemList が居なければ no-op。
    pub def mapAt(path: NodePath, f: ItemList -> ItemList,
                   scene: Scene[s]): Scene[s] =
        Scene.mapEngineNode(path, node -> match node {
            case EngineNode.ItemListWithState(list, tag) =>
                EngineNode.ItemListWithState(f(list), tag)
            case other => other
        }, scene)
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
