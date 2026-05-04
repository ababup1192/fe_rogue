/// 2D マーカーノード（Godot Marker2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_marker2d.html
///
/// 位置だけを保持するシンプルなノード。
/// スポーン地点・ターゲット位置などの参照点として使う。
///
///   Marker2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Marker2D {
    case Marker2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod Marker2D {
    /// デフォルト値で Marker2D を生成する
    /// visible=true は Godot 準拠。Marker2D 自身は描画されないが、子ノードの可視性伝播
    /// （`drawContextWalk` の AND）で false にすると子も描画されないため
    pub def make(position: Vec2.Vec2): Marker2D =
        Marker2D.Marker2D({
            position = position,
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })
}

// -- CanvasItem 実装 --

instance CanvasItem[Marker2D] {
    pub def isVisible(marker: Marker2D): Bool =
        let Marker2D.Marker2D(r) = marker;
        r#visible
    pub def setVisible(visible: Bool, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ visible = visible | r })
    pub def getModulate(marker: Marker2D): Color =
        let Marker2D.Marker2D(r) = marker;
        r#modulate
    pub def setModulate(color: Color, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ modulate = color | r })
    pub def getZIndex(marker: Marker2D): Int32 =
        let Marker2D.Marker2D(r) = marker;
        r#zIndex
    pub def setZIndex(zIndex: Int32, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[Marker2D] {
    pub def getPosition(marker: Marker2D): Vec2.Vec2 =
        let Marker2D.Marker2D(r) = marker;
        r#position
    pub def setPosition(position: Vec2.Vec2, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ position = position | r })
    pub def getRotation(marker: Marker2D): Float64 =
        let Marker2D.Marker2D(r) = marker;
        r#rotation
    pub def setRotation(rotation: Float64, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ rotation = rotation | r })
    pub def getScale(marker: Marker2D): Vec2.Vec2 =
        let Marker2D.Marker2D(r) = marker;
        r#scale
    pub def setScale(scale: Vec2.Vec2, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ scale = scale | r })
    pub def getSkew(marker: Marker2D): Float64 =
        let Marker2D.Marker2D(r) = marker;
        r#skew
    pub def setSkew(skew: Float64, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ skew = skew | r })
}
