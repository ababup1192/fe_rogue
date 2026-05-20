/// プログレスバーノード（Godot ProgressBar + Range 相当の最小実装）
/// see: https://docs.godotengine.org/en/stable/classes/class_progressbar.html
/// see: https://docs.godotengine.org/en/stable/classes/class_range.html
///
/// HP バー・ロード進捗・スタミナゲージなど「現在値 / 最大値」を矩形塗りで見せる
/// UI ノード。Godot では Range（値の管理）+ Control（レイアウト）+ StyleBoxFlat
/// （見た目）の組み合わせだが、本実装は StyleBox 抽象を持たないため Panel と同じく
/// 「背景色 + 塗り色 + 単純な枠線」を直接フィールドに持つ素朴版。
///
/// 描画レイヤ（下から上）:
///   1. 背景（`size` 全体を `backgroundColor` で塗る）
///   2. 塗り（`value` 比率に応じた矩形。`fillMode` で向きが変わる。border の内側に inset）
///   3. tick（`tickInterval > 0` のとき、`tickInterval` ごとに区切り線を入れる。FE 風 HP バー用）
///   4. 枠線 4 辺（`borderWidth > 0` のときのみ。Panel と同形で最外周に乗る）
///
/// 塗りは border の内側に inset されるので、フル値でも border の上に被らず、
/// 「右端の border が fill を 1px 食う」現象が起きない。
///
/// 値のクランプ規則（Godot Range 準拠）:
///   - `setValue` は `minValue..maxValue` の範囲にクランプされる
///   - `maxValue <= minValue` のときはゼロ割を避けて塗り比率 0.0 として描画する
///   - `setBorderWidth` は負値を 0 にクランプ（Panel と同じ）
///   - `setTickWidth` も同様に負値を 0 にクランプ
///
///   ProgressBar
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- size, minValue, maxValue, value, fillMode,
///         backgroundColor, backgroundAlpha,
///         fillColor, fillAlpha,
///         tickInterval, tickColor, tickAlpha, tickWidth,
///         borderColor, borderAlpha, borderWidth

/// 塗りの伸長方向（Godot `FillMode` 準拠）
pub enum FillMode with Eq, Order, ToString {
    case LeftToRight
    case RightToLeft
    case TopToBottom
    case BottomToTop
}

pub enum ProgressBar {
    case ProgressBar({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        size = Vec2.Vec2,
        minValue = Float64,
        maxValue = Float64,
        value = Float64,
        fillMode = FillMode,
        backgroundColor = Color,
        backgroundAlpha = Float32,
        fillColor = Color,
        fillAlpha = Float32,
        // tick: 内部の区切り線。0 なら描画しない。`tickInterval` の単位は `value` と同じ
        // （例えば HP バーで `tickInterval = 5` なら 5 HP ごとに線が入る）。
        tickInterval = Float64,
        tickColor = Color,
        tickAlpha = Float32,
        tickWidth = Int32,
        borderColor = Color,
        borderAlpha = Float32,
        borderWidth = Int32
    })
}

mod ProgressBar {
    /// 背景は黒、枠線なし、minValue=0 / value=0、fillMode=LeftToRight、tick なし
    /// の最小コンストラクタ。呼び出し側は max と塗り色だけを指定すれば後はデフォルトで動く。
    pub def make(size: Vec2.Vec2, max: Float64, fillColor: Color): ProgressBar =
        ProgressBar.ProgressBar({
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            size = size,
            minValue = 0.0,
            maxValue = max,
            value = 0.0,
            fillMode = FillMode.LeftToRight,
            backgroundColor = {r = 0.0f32, g = 0.0f32, b = 0.0f32},
            backgroundAlpha = 1.0f32,
            fillColor = fillColor,
            fillAlpha = 1.0f32,
            tickInterval = 0.0,
            tickColor = {r = 0.0f32, g = 0.0f32, b = 0.0f32},
            tickAlpha = 1.0f32,
            tickWidth = 1,
            borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            borderAlpha = 1.0f32,
            borderWidth = 0
        })

    // ── size ──

    pub def getSize(bar: ProgressBar): Vec2.Vec2 =
        let ProgressBar.ProgressBar(r) = bar;
        r#size

    pub def setSize(size: Vec2.Vec2, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({size = size | r})

    // ── Range 由来の値 ──

    pub def getMinValue(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#minValue

    /// `minValue` を設定する。現在 `value` が新しい min を下回っていれば一緒に引き上げる。
    pub def setMinValue(minValue: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        let newValue = Float64.max(minValue, r#value);
        ProgressBar.ProgressBar({minValue = minValue, value = newValue | r})

    pub def getMaxValue(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#maxValue

    /// `maxValue` を設定する。現在 `value` が新しい max を上回っていれば一緒に切り下げる。
    pub def setMaxValue(maxValue: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        let newValue = Float64.min(maxValue, r#value);
        ProgressBar.ProgressBar({maxValue = maxValue, value = newValue | r})

    pub def getValue(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#value

    /// `value` を `minValue..maxValue` にクランプして設定する（Godot Range と同じ）。
    pub def setValue(value: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        let clamped = Float64.min(r#maxValue, Float64.max(r#minValue, value));
        ProgressBar.ProgressBar({value = clamped | r})

    // ── fillMode ──

    pub def getFillMode(bar: ProgressBar): FillMode =
        let ProgressBar.ProgressBar(r) = bar;
        r#fillMode

    pub def setFillMode(fillMode: FillMode, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({fillMode = fillMode | r})

    // ── background ──

    pub def getBackgroundColor(bar: ProgressBar): Color =
        let ProgressBar.ProgressBar(r) = bar;
        r#backgroundColor

    pub def setBackgroundColor(color: Color, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({backgroundColor = color | r})

    pub def getBackgroundAlpha(bar: ProgressBar): Float32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#backgroundAlpha

    pub def setBackgroundAlpha(alpha: Float32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({backgroundAlpha = alpha | r})

    // ── fill ──

    pub def getFillColor(bar: ProgressBar): Color =
        let ProgressBar.ProgressBar(r) = bar;
        r#fillColor

    pub def setFillColor(color: Color, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({fillColor = color | r})

    pub def getFillAlpha(bar: ProgressBar): Float32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#fillAlpha

    pub def setFillAlpha(alpha: Float32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({fillAlpha = alpha | r})

    // ── tick ──

    pub def getTickInterval(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#tickInterval

    /// `value` 単位の刻み間隔を設定する。0 以下なら tick を描画しない。
    pub def setTickInterval(interval: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({tickInterval = interval | r})

    pub def getTickColor(bar: ProgressBar): Color =
        let ProgressBar.ProgressBar(r) = bar;
        r#tickColor

    pub def setTickColor(color: Color, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({tickColor = color | r})

    pub def getTickAlpha(bar: ProgressBar): Float32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#tickAlpha

    pub def setTickAlpha(alpha: Float32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({tickAlpha = alpha | r})

    pub def getTickWidth(bar: ProgressBar): Int32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#tickWidth

    /// tick 線の太さ（px）。負値は 0 にクランプ（border と同じ規則）。
    pub def setTickWidth(width: Int32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({tickWidth = Int32.max(0, width) | r})

    // ── border ──

    pub def getBorderColor(bar: ProgressBar): Color =
        let ProgressBar.ProgressBar(r) = bar;
        r#borderColor

    pub def setBorderColor(color: Color, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({borderColor = color | r})

    pub def getBorderAlpha(bar: ProgressBar): Float32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#borderAlpha

    pub def setBorderAlpha(alpha: Float32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({borderAlpha = alpha | r})

    /// 枠線の太さ（px）。0 なら枠線描画なし。負値は 0 にクランプ。
    pub def setBorderWidth(width: Int32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({borderWidth = Int32.max(0, width) | r})

    pub def getBorderWidth(bar: ProgressBar): Int32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#borderWidth

    // ── 内部ヘルパ ──

    /// `value` を 0.0..1.0 の比率に正規化する。
    /// `maxValue <= minValue` の防御的ケースは 0.0 を返す（ゼロ割回避）。
    def ratio(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        let span = r#maxValue - r#minValue;
        if (span <= 0.0) 0.0
        else {
            let normalized = (r#value - r#minValue) / span;
            Float64.min(1.0, Float64.max(0.0, normalized))
        }

    /// 塗り矩形の (左上 pos, 描画 size) を fillMode と比率から計算する。
    /// `innerPos` / `innerSize` は border 1px の inset 後の矩形（border が 0 なら size 全体）。
    def fillRectPosSize(fillMode: FillMode, innerPos: Vec2.Vec2,
                         innerSize: Vec2.Vec2, ratio: Float64): (Vec2.Vec2, Vec2.Vec2) =
        let w = innerSize#x;
        let h = innerSize#y;
        match fillMode {
            case FillMode.LeftToRight =>
                ({x = innerPos#x, y = innerPos#y}, {x = w * ratio, y = h})
            case FillMode.RightToLeft =>
                ({x = innerPos#x + w * (1.0 - ratio), y = innerPos#y},
                 {x = w * ratio, y = h})
            case FillMode.TopToBottom =>
                ({x = innerPos#x, y = innerPos#y}, {x = w, y = h * ratio})
            case FillMode.BottomToTop =>
                ({x = innerPos#x, y = innerPos#y + h * (1.0 - ratio)},
                 {x = w, y = h * ratio})
        }

    /// tick 1 本ぶんの Drawable を組み立てる。fillMode が水平系（LtR/RtL）なら
    /// 縦線（`tickWidth` × innerH）、垂直系（TtB/BtB）なら横線（innerW × `tickWidth`）。
    /// `offsetPx` は inner 左上から「value 比率に応じた長さ」分だけずらした位置。
    /// tick 線は境界に乗せるので、`tickWidth/2` を引いて中央寄せする。
    def tickRectPosSize(fillMode: FillMode, innerPos: Vec2.Vec2, innerSize: Vec2.Vec2,
                         offsetPx: Float64, tickWidth: Float64): (Vec2.Vec2, Vec2.Vec2) =
        match fillMode {
            case FillMode.LeftToRight =>
                ({x = innerPos#x + offsetPx - tickWidth / 2.0, y = innerPos#y},
                 {x = tickWidth, y = innerSize#y})
            case FillMode.RightToLeft =>
                ({x = innerPos#x + (innerSize#x - offsetPx) - tickWidth / 2.0, y = innerPos#y},
                 {x = tickWidth, y = innerSize#y})
            case FillMode.TopToBottom =>
                ({x = innerPos#x, y = innerPos#y + offsetPx - tickWidth / 2.0},
                 {x = innerSize#x, y = tickWidth})
            case FillMode.BottomToTop =>
                ({x = innerPos#x, y = innerPos#y + (innerSize#y - offsetPx) - tickWidth / 2.0},
                 {x = innerSize#x, y = tickWidth})
        }

    /// `minValue + interval, +2*interval, ..., < maxValue` の tick 値リストを返す。
    /// `interval <= 0` または `maxValue <= minValue` なら空。
    def tickValues(minV: Float64, maxV: Float64, interval: Float64): List[Float64] =
        if (interval <= 0.0 or maxV <= minV) Nil
        else {
            def loop(acc, v) = {
                if (v >= maxV) List.reverse(acc)
                else loop(v :: acc, v + interval)
            };
            loop(Nil, minV + interval)
        }

    /// 単色矩形 1 枚分の Drawable を組み立てる。texture="" でテクスチャ無し。
    /// Panel.flix の同名ヘルパと同じ構造（互いに参照せず独立に持つ）。
    def makeRectDrawable(pos: Vec2.Vec2, size: Vec2.Vec2, color: Color,
                         alpha: Float32, zIndex: Int32): GameEngine.Drawable =
        {
            texture = "",
            position = pos,
            scale = size,
            rotation = 0.0,
            color = color,
            alpha = alpha,
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = zIndex
        }

    /// 背景 + 塗り + tick + 枠線 4 辺を Drawable リストとして返す。
    /// 枚数: 2 (bg + fill) + N (tick) + 4 (border, if borderWidth>0)。
    /// fill は border の **内側** に inset するので、フル値でも右端の border に被らない。
    /// tick は fill の上に乗り、border の下に潜るレイヤ順。
    pub def toDrawables(bar: ProgressBar, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let ProgressBar.ProgressBar(r) = bar;
        let w = r#size#x;
        let h = r#size#y;
        let bw = Int32.toFloat64(r#borderWidth);
        // border の内側矩形（borderWidth=0 のときは bar 全体と一致）
        let innerPos: Vec2.Vec2 = {x = globalPos#x + bw, y = globalPos#y + bw};
        let innerSize: Vec2.Vec2 = {
            x = Float64.max(0.0, w - 2.0 * bw),
            y = Float64.max(0.0, h - 2.0 * bw)
        };
        let zi = r#zIndex;
        // 1. 背景（全 size 領域、border 含む）
        let bg = makeRectDrawable(globalPos, r#size, r#backgroundColor,
                                  r#backgroundAlpha, zi);
        // 2. 塗り（inner 矩形を起点に value 比率で広げる）
        let (fillPos, fillSize) = fillRectPosSize(r#fillMode, innerPos, innerSize, ratio(bar));
        let fill = makeRectDrawable(fillPos, fillSize, r#fillColor,
                                    r#fillAlpha, zi);
        // 3. tick（tickInterval > 0 のとき、塗りの上に乗せる）
        let span = r#maxValue - r#minValue;
        let isHorizontal = match r#fillMode {
            case FillMode.LeftToRight => true
            case FillMode.RightToLeft => true
            case _                    => false
        };
        let innerLong = if (isHorizontal) innerSize#x else innerSize#y;
        let tickWidthF = Int32.toFloat64(r#tickWidth);
        // tick は **fill 領域の中だけ** に描画する（FE GBA の HP セル感）。
        // empty area には貫通させない（v=value 境界の tick は除く / 厳密 `<` 比較）。
        let ticks =
            if (r#tickInterval <= 0.0 or span <= 0.0 or r#tickWidth <= 0)
                (Nil: List[GameEngine.Drawable])
            else {
                tickValues(r#minValue, r#maxValue, r#tickInterval)
                    |> List.filter(v -> v < r#value)
                    |> List.map(v -> {
                        let offsetPx = (v - r#minValue) / span * innerLong;
                        let (tPos, tSize) = tickRectPosSize(r#fillMode, innerPos, innerSize,
                                                             offsetPx, tickWidthF);
                        makeRectDrawable(tPos, tSize, r#tickColor, r#tickAlpha, zi)
                    })
            };
        // 4. 枠線 4 辺（borderWidth > 0 のときのみ。Panel と同形で最外周に乗る）
        let borders =
            if (r#borderWidth <= 0) (Nil: List[GameEngine.Drawable])
            else {
                let bc = r#borderColor;
                let ba = r#borderAlpha;
                // 上辺: 全幅 × borderWidth
                let top = makeRectDrawable(globalPos, {x = w, y = bw}, bc, ba, zi);
                // 下辺: 全幅 × borderWidth、y は size.y - borderWidth
                let bot = makeRectDrawable(
                    {x = globalPos#x, y = globalPos#y + h - bw},
                    {x = w, y = bw}, bc, ba, zi);
                // 左辺: borderWidth × 全高
                let lft = makeRectDrawable(globalPos, {x = bw, y = h}, bc, ba, zi);
                // 右辺: borderWidth × 全高、x は size.x - borderWidth
                let rgt = makeRectDrawable(
                    {x = globalPos#x + w - bw, y = globalPos#y},
                    {x = bw, y = h}, bc, ba, zi);
                top :: bot :: lft :: rgt :: Nil
            };
        bg :: fill :: List.append(ticks, borders)
}

// ── CanvasItem 実装 ──

instance CanvasItem[ProgressBar] {
    pub def isVisible(bar: ProgressBar): Bool =
        let ProgressBar.ProgressBar(r) = bar;
        r#visible
    pub def setVisible(visible: Bool, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({visible = visible | r})
    pub def getModulate(bar: ProgressBar): Color =
        let ProgressBar.ProgressBar(r) = bar;
        r#modulate
    pub def setModulate(color: Color, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({modulate = color | r})
    pub def getZIndex(bar: ProgressBar): Int32 =
        let ProgressBar.ProgressBar(r) = bar;
        r#zIndex
    pub def setZIndex(zIndex: Int32, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[ProgressBar] {
    pub def getPosition(bar: ProgressBar): Vec2.Vec2 =
        let ProgressBar.ProgressBar(r) = bar;
        r#position
    pub def setPosition(position: Vec2.Vec2, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({position = position | r})
    pub def getRotation(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#rotation
    pub def setRotation(rotation: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({rotation = rotation | r})
    pub def getScale(bar: ProgressBar): Vec2.Vec2 =
        let ProgressBar.ProgressBar(r) = bar;
        r#scale
    pub def setScale(scale: Vec2.Vec2, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({scale = scale | r})
    pub def getSkew(bar: ProgressBar): Float64 =
        let ProgressBar.ProgressBar(r) = bar;
        r#skew
    pub def setSkew(skew: Float64, bar: ProgressBar): ProgressBar =
        let ProgressBar.ProgressBar(r) = bar;
        ProgressBar.ProgressBar({skew = skew | r})
}
