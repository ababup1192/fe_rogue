/// 2D スプライトノード（Godot Sprite2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_sprite2d.html
///
/// テクスチャを持つ最小の描画可能ノード。
/// CanvasItem（可視性・描画順）と Node2D（座標変換）を実装する。
///
///   Sprite2D
///     ├─ CanvasItem: visible, zIndex, modulate
///     └─ Node2D: position, rotation, scale, skew
pub enum Sprite2D {
    case Sprite2D({
        position = Vec2.Vec2,  // 位置
        rotation = Float64,     // 回転（ラジアン）
        scale = Vec2.Vec2,     // スケール
        skew = Float64,         // スキュー（ラジアン）
        visible = Bool,         // 表示フラグ
        zIndex = Int32,         // 描画順
        modulate = Color,       // 色変調
        texture = String,       // テクスチャパス
        centered = Bool,        // 中心を原点にするか
        offset = Vec2.Vec2,    // 描画オフセット
        flipH = Bool,           // 水平反転
        flipV = Bool            // 垂直反転
    })
}

mod Sprite2D {
    /// デフォルト値で Sprite2D を生成する
    pub def make(texture: String, position: Vec2.Vec2, scale: Vec2.Vec2): Sprite2D =
        Sprite2D.Sprite2D({
            position = position,
            rotation = 0.0,
            scale = scale,
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            texture = texture,
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false
        })

    /// テクスチャ名を変更する
    pub def setTexture(texture: String, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({texture = texture | r})

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({flipV = v | r})

    /// グローバル座標を受け取り Drawable に変換する
    pub def toDrawableAt(sprite: Sprite2D, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let Sprite2D.Sprite2D(r) = sprite;
        {
            texture = r#texture,
            position = globalPos,
            scale = r#scale,
            rotation = r#rotation,
            color = r#modulate,
            alpha = 1.0f32,
            centered = r#centered,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = r#zIndex
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[Sprite2D] {
    pub def isVisible(sprite: Sprite2D): Bool =
        let Sprite2D.Sprite2D(r) = sprite;
        r#visible
    pub def setVisible(visible: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ visible = visible | r })
    pub def getModulate(sprite: Sprite2D): Color =
        let Sprite2D.Sprite2D(r) = sprite;
        r#modulate
    pub def setModulate(color: Color, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ modulate = color | r })
    pub def getZIndex(sprite: Sprite2D): Int32 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#zIndex
    pub def setZIndex(zIndex: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ zIndex = zIndex | r })
}

// ── Node2D 実装 ──

instance Node2D[Sprite2D] {
    pub def getPosition(sprite: Sprite2D): Vec2.Vec2 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#position
    pub def setPosition(position: Vec2.Vec2, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ position = position | r })
    pub def getRotation(sprite: Sprite2D): Float64 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#rotation
    pub def setRotation(rotation: Float64, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ rotation = rotation | r })
    pub def getScale(sprite: Sprite2D): Vec2.Vec2 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#scale
    pub def setScale(scale: Vec2.Vec2, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ scale = scale | r })
    pub def getSkew(sprite: Sprite2D): Float64 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#skew
    pub def setSkew(skew: Float64, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ skew = skew | r })
}
