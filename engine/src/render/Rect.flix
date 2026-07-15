/// テクスチャなしで単色の矩形を描く描画物。
/// 画像を用意せず色とサイズだけで塗れるので、背景や覆いを手軽に置ける。
/// 枠線・角丸・45° の斜線ハッチも指定でき、枠付きパネルもこれ 1 つで描ける。
/// 利用例: 画面の背景色 / 全画面を覆う半透明のオーバーレイ / メニューの枠付き下敷き。
pub enum Rect {
    case Rect({
        transform = Transform,
        visual = Visual,
        alpha = Float32,
        size = Vec2.Vec2,
        // 角丸半径（px、design 解像度）。0 で直角、>0 で BoxStyle 経由の角丸描画。
        cornerRadius = Float64,
        // 枠線（design px）。borderWidth<=0 または borderAlpha<=0 で枠なし。
        borderColor = Color,
        borderAlpha = Float32,
        borderWidth = Float64,
        // 45° 斜線ハッチ。stripeWidth<=0 または stripeAlpha<=0 で無効。
        stripeColor = Color,
        stripeAlpha = Float32,
        stripeWidth = Float64,
        stripePeriod = Float64
    })
}

mod Rect {
    /// デフォルト値で Rect を生成する（alpha は 1.0 = 不透明）
    pub def make(size: Vec2.Vec2, color: Color): Rect =
        Rect.Rect({
            transform = { position = {x = 0.0, y = 0.0}, rotation = 0.0, scale = {x = 1.0, y = 1.0}, skew = 0.0 },
            visual = Visual.setColor(color, Visual.default()),
            alpha = 1.0f32,
            size = size,
            cornerRadius = 0.0,
            borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            borderAlpha = 0.0f32,
            borderWidth = 0.0,
            stripeColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            stripeAlpha = 0.0f32,
            stripeWidth = 0.0,
            stripePeriod = 0.0
        })

    /// 埋め込んだ Transform 部品を取り出す
    pub def transform(rect: Rect): Transform =
        let Rect.Rect(r) = rect;
        r#transform

    /// Transform 部品に関数を適用して差し替える
    pub def mapTransform(f: Transform -> Transform \ ef, rect: Rect): Rect \ ef =
        let Rect.Rect(r) = rect;
        Rect.Rect({transform = f(r#transform) | r})

    /// 埋め込んだ Visual 部品を取り出す
    pub def visual(rect: Rect): Visual =
        let Rect.Rect(r) = rect;
        r#visual

    /// Visual 部品に関数を適用して差し替える
    pub def mapVisual(f: Visual -> Visual \ ef, rect: Rect): Rect \ ef =
        let Rect.Rect(r) = rect;
        Rect.Rect({visual = f(r#visual) | r})

    /// alpha を設定する
    pub def setAlpha(alpha: Float32, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ alpha = alpha | r })

    /// 角丸半径（px）を設定する。0 で矩形、>0 で角丸（BoxStyle 経由）。
    pub def setCornerRadius(radius: Float64, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ cornerRadius = Float64.max(0.0, radius) | r })

    /// 枠線の色を設定する。
    pub def setBorderColor(color: Color, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ borderColor = color | r })

    /// 枠線の不透明度を設定する（0 で枠なし）。
    pub def setBorderAlpha(alpha: Float32, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ borderAlpha = alpha | r })

    /// 枠線の太さ（design px）を設定する。0 以下で枠なし。小数も可。
    pub def setBorderWidth(width: Float64, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ borderWidth = Float64.max(0.0, width) | r })

    /// 枠線の太さ（design px）を取得する。
    pub def getBorderWidth(rect: Rect): Float64 =
        let Rect.Rect(r) = rect;
        r#borderWidth

    /// 45° 斜線ハッチを設定する。width<=0 または alpha<=0 で無効。
    /// 塗りの上に stripeColor の縞を over 合成する。
    pub def setStripe(color: Color, alpha: Float32, width: Float64, period: Float64,
                      rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ stripeColor = color, stripeAlpha = alpha,
                              stripeWidth = Float64.max(0.0, width),
                              stripePeriod = Float64.max(0.0, period) | r })

    /// 表示サイズ（描画矩形の幅・高さ）を取得する
    pub def getSize(rect: Rect): Vec2.Vec2 =
        let Rect.Rect(r) = rect;
        r#size

    /// 表示サイズを設定する。リサイズ編集の主たる更新先で、`scale` ではなく
    /// この `size` フィールドが描画 (`toDrawable`) の幅・高さに使われる
    pub def setSize(size: Vec2.Vec2, rect: Rect): Rect =
        let Rect.Rect(r) = rect;
        Rect.Rect({ size = size | r })

    /// 枠線＋角丸＋斜線ハッチをまとめた BoxStyle を作る。
    def boxStyleOf(r: {cornerRadius = Float64, borderColor = Color, borderAlpha = Float32,
                       borderWidth = Float64, stripeColor = Color, stripeAlpha = Float32,
                       stripeWidth = Float64, stripePeriod = Float64 | s}): GameEngine.BoxStyle =
        // Rect が持たない縞の向き・市松は defaultStyle の既定値のまま。
        {cornerRadius = r#cornerRadius, borderWidth = r#borderWidth,
         borderColor = r#borderColor, borderAlpha = r#borderAlpha,
         stripeColor = r#stripeColor, stripeAlpha = r#stripeAlpha,
         stripeWidth = r#stripeWidth, stripePeriod = r#stripePeriod
         | DrawCmd.defaultStyle(r#borderColor)}

    /// Drawable に変換する（texture="" でテクスチャなしを示す）
    pub def toDrawable(rect: Rect, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let Rect.Rect(r) = rect;
        let styled = r#cornerRadius > 0.0 or (r#stripeWidth > 0.0 and r#stripeAlpha > 0.0f32)
            or (r#borderWidth > 0.0 and r#borderAlpha > 0.0f32);
        {
            texture = "",
            position = globalPos,
            scale = r#size,
            rotation = r#transform#rotation,
            color = r#visual#color,
            alpha = r#alpha,
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = r#visual#zIndex,
            style = if (styled) Some(boxStyleOf(r)) else None
        }
}
