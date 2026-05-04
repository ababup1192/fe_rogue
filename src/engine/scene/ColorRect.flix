/// 色付き矩形ノード（Godot ColorRect 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_colorrect.html
///
/// テクスチャなしで単色の矩形を描画するノード。
/// 背景色やオーバーレイとして使う。
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
        size = Vec2.Vec2
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
            size = size
        })

    /// alpha を設定する
    pub def setAlpha(alpha: Float32, rect: ColorRect): ColorRect =
        let ColorRect.ColorRect(r) = rect;
        ColorRect.ColorRect({ alpha = alpha | r })

    /// Drawable に変換する（texture="" でテクスチャなしを示す）
    pub def toDrawable(rect: ColorRect, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let ColorRect.ColorRect(r) = rect;
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
            zIndex = r#zIndex
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
