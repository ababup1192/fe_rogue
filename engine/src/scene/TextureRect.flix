/// UI 用テクスチャ表示ノード（Godot TextureRect 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_texturerect.html
///
/// Control 系の画像表示ノード。HBoxContainer / VBoxContainer などの子として
/// 直接配置でき、`size` を持つので Layout の measureNode で測定可能。
///
/// Sprite2D との違い:
///   - position は **左上座標** (Sprite2D の centered=true と異なる、Godot Control 準拠)
///   - `size` フィールドを明示的に持つ → Layout が natural size を取れる
///   - region/hframes/vframes/frame は持たない (UI 静止画用なのでフルテクスチャ前提)
///
/// 描画範囲は `(position, size)` の矩形。texture はフルサイズで矩形内に表示する
/// (テクスチャ解像度と size が異なる場合は引き伸ばし/縮小)。
///
///   TextureRect
///     ├─ CanvasItem: visible, zIndex, modulate, alpha
///     └─ Node2D: position, rotation, scale, skew
pub enum TextureRect {
    case TextureRect({
        position = Vec2.Vec2,    // 左上座標
        size     = Vec2.Vec2,    // 表示矩形サイズ
        rotation = Float64,
        scale    = Vec2.Vec2,
        skew     = Float64,
        visible  = Bool,
        zIndex   = Int32,
        modulate = Color,
        alpha    = Float32,
        texture  = String,
        flipH    = Bool,
        flipV    = Bool
    })
}

mod TextureRect {
    /// 最小デフォルト値で TextureRect を生成する
    pub def make(texture: String, position: Vec2.Vec2, size: Vec2.Vec2): TextureRect =
        TextureRect.TextureRect({
            position = position,
            size     = size,
            rotation = 0.0,
            scale    = {x = 1.0, y = 1.0},
            skew     = 0.0,
            visible  = true,
            zIndex   = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            alpha    = 1.0f32,
            texture  = texture,
            flipH    = false,
            flipV    = false
        })

    /// テクスチャ名を変更する
    pub def setTexture(texture: String, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({texture = texture | r})

    /// テクスチャ名を取得する
    pub def getTexture(rect: TextureRect): String =
        let TextureRect.TextureRect(r) = rect;
        r#texture

    /// サイズを変更する
    pub def setSize(size: Vec2.Vec2, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({size = size | r})

    /// サイズを取得する (Layout の measureNode から呼ばれる)
    pub def getSize(rect: TextureRect): Vec2.Vec2 =
        let TextureRect.TextureRect(r) = rect;
        r#size

    /// 不透明度を設定する (0.0 = 完全透明、1.0 = 不透明)
    pub def setAlpha(alpha: Float32, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({alpha = alpha | r})

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({flipV = v | r})

    /// TextureRect を Drawable に変換する。
    /// position は左上、size は表示矩形。texture はフル UV (0..1) で矩形内に展開。
    /// レンダラは drawable#scale を size として読むため、size を scale 形式に変換する。
    pub def toDrawable(rect: TextureRect, globalPos: Vec2.Vec2):
                       GameEngine.Drawable \ GameEngine.Game =
        let TextureRect.TextureRect(r) = rect;
        let texInfo = match GameEngine.Game.getTextureInfo(r#texture) {
            case Some(info) => info
            case None       => bug!("TextureRect.toDrawable: texture '${r#texture}' not registered")
        };
        // texture サイズに対する表示サイズの比 = drawable の scale 相当
        let drawScale: Vec2.Vec2 = {
            x = r#size#x / texInfo#width,
            y = r#size#y / texInfo#height
        };
        {
            texture  = r#texture,
            position = globalPos,
            scale    = drawScale,
            rotation = r#rotation,
            color    = r#modulate,
            alpha    = r#alpha,
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale  = {x = 1.0, y = 1.0},
            zIndex   = r#zIndex
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[TextureRect] {
    pub def isVisible(rect: TextureRect): Bool =
        let TextureRect.TextureRect(r) = rect;
        r#visible
    pub def setVisible(visible: Bool, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ visible = visible | r })
    pub def getModulate(rect: TextureRect): Color =
        let TextureRect.TextureRect(r) = rect;
        r#modulate
    pub def setModulate(color: Color, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ modulate = color | r })
    pub def getZIndex(rect: TextureRect): Int32 =
        let TextureRect.TextureRect(r) = rect;
        r#zIndex
    pub def setZIndex(zIndex: Int32, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ zIndex = zIndex | r })
}

// ── Node2D 実装 ──

instance Node2D[TextureRect] {
    pub def getPosition(rect: TextureRect): Vec2.Vec2 =
        let TextureRect.TextureRect(r) = rect;
        r#position
    pub def setPosition(position: Vec2.Vec2, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ position = position | r })
    pub def getRotation(rect: TextureRect): Float64 =
        let TextureRect.TextureRect(r) = rect;
        r#rotation
    pub def setRotation(rotation: Float64, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ rotation = rotation | r })
    pub def getScale(rect: TextureRect): Vec2.Vec2 =
        let TextureRect.TextureRect(r) = rect;
        r#scale
    pub def setScale(scale: Vec2.Vec2, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ scale = scale | r })
    pub def getSkew(rect: TextureRect): Float64 =
        let TextureRect.TextureRect(r) = rect;
        r#skew
    pub def setSkew(skew: Float64, rect: TextureRect): TextureRect =
        let TextureRect.TextureRect(r) = rect;
        TextureRect.TextureRect({ skew = skew | r })
}
