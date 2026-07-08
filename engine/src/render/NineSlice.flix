/// NineSlice — 矩形に背景色と枠線を描く UI ノード。
/// テーマ機構を持たず「背景色 + 枠線色 + 枠線太さ」を直接フィールドに持つ素朴版なので、軽く使える。
/// 利用例: メニューやダイアログの下敷き、HUD パネルの背景。
///
/// `toDrawables` は最大 5 枚の Rect 由来 Drawable を返す:
///   1. 背景（borderWidth ぶん内側に小さく描く形ではなく、size 全体を背景塗りつぶし）
///   2-5. 上/下/左/右 の枠線（borderWidth > 0 のときのみ）
///
/// 子ノードのレイアウトは持たない（必要なら親 Control + Layout.Anchor で配置する）。
///
///   NineSlice
///     +-- visual: visible, zIndex, modulate
///     +-- transform: position, rotation, scale, skew
///     +-- size, backgroundColor, backgroundAlpha, borderColor, borderAlpha, borderWidth
pub enum NineSlice {
    case NineSlice({
        transform = Transform,
        visual = Visual,
        size = Vec2.Vec2,
        backgroundColor = Color,
        backgroundAlpha = Float32,
        borderColor = Color,
        borderAlpha = Float32,
        // 枠線の太さ（design px）。設計解像度を拡大表示するため小数（例 0.5）も許す。
        borderWidth = Float64,
        // 角丸半径 (px)。0 で従来の直角 (5 矩形描画)。>0 で角丸スタイル描画 (1 Drawable)。
        cornerRadius = Float64,
        // 塗り領域に重ねる 45° 斜線ハッチ (CSS repeating-linear-gradient 相当)。
        // stripeWidth <= 0 または stripeAlpha <= 0 でハッチ無効。stripePeriod は縞の周期 px。
        stripeColor = Color,
        stripeAlpha = Float32,
        stripeWidth = Float64,
        stripePeriod = Float64
    })
}

mod NineSlice {
    /// 背景色のみ、枠線なしの最小コンストラクタ。
    pub def make(size: Vec2.Vec2, backgroundColor: Color): NineSlice =
        NineSlice.NineSlice({
            transform = { position = {x = 0.0, y = 0.0}, rotation = 0.0, scale = {x = 1.0, y = 1.0}, skew = 0.0 },
            visual = Visual.default(),
            size = size,
            backgroundColor = backgroundColor,
            backgroundAlpha = 1.0f32,
            borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            borderAlpha = 1.0f32,
            borderWidth = 0.0,
            cornerRadius = 0.0,
            stripeColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            stripeAlpha = 0.0f32,
            stripeWidth = 0.0,
            stripePeriod = 0.0
        })

    /// 埋め込んだ Transform 部品を取り出す
    pub def transform(panel: NineSlice): Transform =
        let NineSlice.NineSlice(r) = panel;
        r#transform

    /// Transform 部品に関数を適用して差し替える
    pub def mapTransform(f: Transform -> Transform \ ef, panel: NineSlice): NineSlice \ ef =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({transform = f(r#transform) | r})

    /// 埋め込んだ Visual 部品を取り出す
    pub def visual(panel: NineSlice): Visual =
        let NineSlice.NineSlice(r) = panel;
        r#visual

    /// Visual 部品に関数を適用して差し替える
    pub def mapVisual(f: Visual -> Visual \ ef, panel: NineSlice): NineSlice \ ef =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({visual = f(r#visual) | r})

    pub def getSize(panel: NineSlice): Vec2.Vec2 =
        let NineSlice.NineSlice(r) = panel;
        r#size

    pub def setSize(size: Vec2.Vec2, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({size = size | r})

    pub def setBackgroundColor(color: Color, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({backgroundColor = color | r})

    pub def getBackgroundColor(panel: NineSlice): Color =
        let NineSlice.NineSlice(r) = panel;
        r#backgroundColor

    pub def setBackgroundAlpha(alpha: Float32, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({backgroundAlpha = alpha | r})

    pub def getBackgroundAlpha(panel: NineSlice): Float32 =
        let NineSlice.NineSlice(r) = panel;
        r#backgroundAlpha

    pub def setBorderColor(color: Color, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({borderColor = color | r})

    pub def getBorderColor(panel: NineSlice): Color =
        let NineSlice.NineSlice(r) = panel;
        r#borderColor

    pub def setBorderAlpha(alpha: Float32, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({borderAlpha = alpha | r})

    pub def getBorderAlpha(panel: NineSlice): Float32 =
        let NineSlice.NineSlice(r) = panel;
        r#borderAlpha

    /// 枠線の太さ（design px）。0 なら枠線描画なし。小数（例 0.5）も指定できる。
    pub def setBorderWidth(width: Float64, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({borderWidth = Float64.max(0.0, width) | r})

    /// 角丸半径 (px) を設定する。0 で直角。
    pub def setCornerRadius(radius: Float64, panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({cornerRadius = Float64.max(0.0, radius) | r})

    /// 角丸半径 (px) を取得する。
    pub def getCornerRadius(panel: NineSlice): Float64 =
        let NineSlice.NineSlice(r) = panel;
        r#cornerRadius

    /// 塗り領域に重ねる 45° 斜線ハッチを設定する。
    /// `color`/`alpha` は縞の色と不透明度、`width` は縞 1 本の幅 px、`period` は縞の周期 px。
    /// width<=0 または alpha<=0 でハッチ無効（従来の塗りのみ）。
    pub def setStripe(color: Color, alpha: Float32, width: Float64, period: Float64,
                      panel: NineSlice): NineSlice =
        let NineSlice.NineSlice(r) = panel;
        NineSlice.NineSlice({stripeColor = color, stripeAlpha = alpha,
                     stripeWidth = Float64.max(0.0, width),
                     stripePeriod = Float64.max(0.0, period) | r})

    /// 斜線ハッチが有効か（width>0 かつ alpha>0）。
    pub def hasStripe(panel: NineSlice): Bool =
        let NineSlice.NineSlice(r) = panel;
        r#stripeWidth > 0.0 and r#stripeAlpha > 0.0f32

    pub def getBorderWidth(panel: NineSlice): Float64 =
        let NineSlice.NineSlice(r) = panel;
        r#borderWidth

    /// 単色矩形 1 枚分の Drawable を組み立てる。texture="" でテクスチャ無し。
    /// `pos` は左上、`size` は描画矩形。
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
            zIndex = zIndex,
            style = None
        }

    /// 背景 + 枠線 4 辺を Drawable リストとして返す。
    /// cornerRadius > 0 のときは「塗り＋枠＋角丸＋AA」を 1 フラグメントで描く styled Drawable 1 枚を返す
    /// （半透明でも枠/塗りが排他描画され二重合成しない）。cornerRadius = 0 のときは従来の最大 5 矩形。
    pub def toDrawables(panel: NineSlice, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let NineSlice.NineSlice(r) = panel;
        let w = r#size#x;
        let h = r#size#y;
        // 背景 Drawable は全分岐で共有（角丸/ハッチ時は style を載せ替えるだけ＝重複リテラルを持たない）。
        let bg = makeRectDrawable(globalPos, r#size, r#backgroundColor, r#backgroundAlpha, r#visual#zIndex);
        // 角丸 or 斜線ハッチがあれば styled パス（1 枚で塗り＋枠＋角丸＋ハッチ＋AA を排他描画）。
        let styled = r#cornerRadius > 0.0 or (r#stripeWidth > 0.0 and r#stripeAlpha > 0.0f32);
        if (styled)
            ({style = Some({cornerRadius = r#cornerRadius,
                            borderWidth = r#borderWidth,
                            borderColor = r#borderColor,
                            borderAlpha = r#borderAlpha,
                            stripeColor = r#stripeColor,
                            stripeAlpha = r#stripeAlpha,
                            stripeWidth = r#stripeWidth,
                            stripePeriod = r#stripePeriod}) | bg}: GameEngine.Drawable) :: Nil
        else if (r#borderWidth <= 0.0)
            bg :: Nil
        else {
            let bw = r#borderWidth;
            let bc = r#borderColor;
            let ba = r#borderAlpha;
            let zi = r#visual#zIndex;
            // 上辺 / 下辺 / 左辺 / 右辺（背景の上に同 z で重ねる）。
            let top = makeRectDrawable(globalPos, {x = w, y = bw}, bc, ba, zi);
            let bot = makeRectDrawable(
                {x = globalPos#x, y = globalPos#y + h - bw},
                {x = w, y = bw}, bc, ba, zi);
            let lft = makeRectDrawable(globalPos, {x = bw, y = h}, bc, ba, zi);
            let rgt = makeRectDrawable(
                {x = globalPos#x + w - bw, y = globalPos#y},
                {x = bw, y = h}, bc, ba, zi);
            bg :: top :: bot :: lft :: rgt :: Nil
        }

}
