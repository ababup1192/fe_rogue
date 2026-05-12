/// 不可視UIコンテナノード（Godot Control 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_control.html
///
/// 描画なしで size を持つ UI コンテナ。Button の基盤。
///
///   Control
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Control {
    case Control({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        size = Vec2.Vec2
    })
}

mod Control {
    /// デフォルト値で Control を生成する
    pub def make(size: Vec2.Vec2): Control =
        Control.Control({
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            size = size
        })

    /// サイズを取得する
    pub def getSize(ctrl: Control): Vec2.Vec2 =
        let Control.Control(r) = ctrl;
        r#size

    /// サイズを設定する
    pub def setSize(size: Vec2.Vec2, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ size = size | r })
}

// -- CanvasItem 実装 --

instance CanvasItem[Control] {
    pub def isVisible(ctrl: Control): Bool =
        let Control.Control(r) = ctrl;
        r#visible
    pub def setVisible(visible: Bool, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ visible = visible | r })
    pub def getModulate(ctrl: Control): Color =
        let Control.Control(r) = ctrl;
        r#modulate
    pub def setModulate(color: Color, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ modulate = color | r })
    pub def getZIndex(ctrl: Control): Int32 =
        let Control.Control(r) = ctrl;
        r#zIndex
    pub def setZIndex(zIndex: Int32, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[Control] {
    pub def getPosition(ctrl: Control): Vec2.Vec2 =
        let Control.Control(r) = ctrl;
        r#position
    pub def setPosition(position: Vec2.Vec2, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ position = position | r })
    pub def getRotation(ctrl: Control): Float64 =
        let Control.Control(r) = ctrl;
        r#rotation
    pub def setRotation(rotation: Float64, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ rotation = rotation | r })
    pub def getScale(ctrl: Control): Vec2.Vec2 =
        let Control.Control(r) = ctrl;
        r#scale
    pub def setScale(scale: Vec2.Vec2, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ scale = scale | r })
    pub def getSkew(ctrl: Control): Float64 =
        let Control.Control(r) = ctrl;
        r#skew
    pub def setSkew(skew: Float64, ctrl: Control): Control =
        let Control.Control(r) = ctrl;
        Control.Control({ skew = skew | r })
}
