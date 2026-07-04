/// テクスチャなしで単色の矩形を描くノード。
/// 画像を用意せず色とサイズだけで塗れるので、背景や覆いを手軽に置ける。
/// 角丸や 45° の斜線ハッチも指定できる。
/// 利用例: 画面の背景色 / 全画面を覆う半透明のオーバーレイ。
///
///   ColorRect
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum ColorRect {
    case ColorRect({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        alpha = Float32,
        size = Vec2.Vec2,
        // 角丸半径（px、design 解像度）。0 で従来どおりの矩形、>0 で BoxStyle 経由の角丸描画。
        cornerRadius = Float64,
        // 45° 斜線ハッチ（赤マスと同じ仕組み）。stripeWidth<=0 または stripeAlpha<=0 で無効。
        stripeColor = Color,
        stripeAlpha = Float32,
        stripeWidth = Float64,
        stripePeriod = Float64
    })
}

mod ColorRect {
    /// デフォルト値で ColorRect を生成する（alpha は 1.0 = 不透明）
    pub def make(size: Vec2.Vec2, color: Color): ColorRect =
        ColorRect.ColorRect({
            position = {x = 0.0, y = 0.0},
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = color,
            alpha = 1.0f32,
            size = size,
            cornerRadius = 0.0,
            stripeColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            stripeAlpha = 0.0f32,
            stripeWidth = 0.0,
            stripePeriod = 0.0
        })

    /// alpha を設定する
    pub def setAlpha(alpha: Float32, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ alpha = alpha | r })

    /// 角丸半径（px）を設定する。0 で矩形、>0 で角丸（BoxStyle 経由）。
    pub def setCornerRadius(radius: Float64, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ cornerRadius = Float64.max(0.0, radius) | r })

    /// 45° 斜線ハッチを設定する（赤マスの `Panel.setStripe` と同じ）。
    /// width<=0 または alpha<=0 で無効。塗りの上に stripeColor の縞を over 合成する。
    pub def setStripe(color: Color, alpha: Float32, width: Float64, period: Float64,
                      rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ stripeColor = color, stripeAlpha = alpha,
                              stripeWidth = Float64.max(0.0, width),
                              stripePeriod = Float64.max(0.0, period) | r })

    /// 表示サイズ（描画矩形の幅・高さ）を取得する
    pub def getSize(rect: ColorRect): Vec2.Vec2 =
        let ColorRect.ColorRect(r) = rect;
        r#size

    /// 表示サイズを設定する。リサイズ編集の主たる更新先で、`scale` ではなく
    /// この `size` フィールドが描画 (`toDrawable`) の幅・高さに使われる
    pub def setSize(size: Vec2.Vec2, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ size = size | r })

    /// 角丸＋斜線ハッチの BoxStyle（枠なし）。cornerRadius / stripe を反映する。
    def boxStyleOf(r: {cornerRadius = Float64, stripeColor = Color, stripeAlpha = Float32,
                       stripeWidth = Float64, stripePeriod = Float64 | s}): GameEngine.BoxStyle =
        {cornerRadius = r#cornerRadius, borderWidth = 0.0,
         borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32}, borderAlpha = 0.0f32,
         stripeColor = r#stripeColor, stripeAlpha = r#stripeAlpha,
         stripeWidth = r#stripeWidth, stripePeriod = r#stripePeriod}

    /// Drawable に変換する（texture="" でテクスチャなしを示す）
    pub def toDrawable(rect: ColorRect, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let ColorRect.ColorRect(r) = rect;
        let styled = r#cornerRadius > 0.0 or (r#stripeWidth > 0.0 and r#stripeAlpha > 0.0f32);
        {
            texture = "",
            position = globalPos,
            scale = r#size,
            rotation = r#rotation,
            color = r#modulate,
            alpha = r#alpha,
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = r#zIndex,
            style = if (styled) Some(boxStyleOf(r)) else None
        }
}

// -- CanvasItem 実装 --

instance CanvasItem[ColorRect] {
    pub def isVisible(rect: ColorRect): Bool =
        let ColorRect.ColorRect(r) = rect;
        r#visible
    pub def setVisible(visible: Bool, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ visible = visible | r })
    pub def getModulate(rect: ColorRect): Color =
        let ColorRect.ColorRect(r) = rect;
        r#modulate
    pub def setModulate(color: Color, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ modulate = color | r })
    pub def getZIndex(rect: ColorRect): Int32 =
        let ColorRect.ColorRect(r) = rect;
        r#zIndex
    pub def setZIndex(zIndex: Int32, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[ColorRect] {
    pub def getPosition(rect: ColorRect): Vec2.Vec2 =
        let ColorRect.ColorRect(r) = rect;
        r#position
    pub def setPosition(position: Vec2.Vec2, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ position = position | r })
    pub def getRotation(rect: ColorRect): Float64 =
        let ColorRect.ColorRect(r) = rect;
        r#rotation
    pub def setRotation(rotation: Float64, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ rotation = rotation | r })
    pub def getScale(rect: ColorRect): Vec2.Vec2 =
        let ColorRect.ColorRect(r) = rect;
        r#scale
    pub def setScale(scale: Vec2.Vec2, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ scale = scale | r })
    pub def getSkew(rect: ColorRect): Float64 =
        let ColorRect.ColorRect(r) = rect;
        r#skew
    pub def setSkew(skew: Float64, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ skew = skew | r })
}
