/// ベースボタンノード（Godot BaseButton 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_basebutton.html
///
/// ボタン全般に共通する状態とインタラクションを担う abstract 相当の内部型。
/// `Button`（テキスト + 背景矩形）と `TextureButton`（スプライト）が
/// この `BaseButton` を内包して compose する。
///
/// Godot 同様、`BaseButton` 自身はシーングラフのノードとして直接配置されない。
/// `Button` / `TextureButton` を経由してのみ Scene に存在する。
///
///   BaseButton
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- size, disabled, visualState, justPressed, centered

/// ボタンのビジュアル状態（旧 Button.flix から移動）
pub enum ButtonVisualState with Eq, ToString {
    case Normal
    case Hovered
    case Pressed
}

pub enum BaseButton {
    case BaseButton({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        size = Vec2.Vec2,
        disabled = Bool,
        visualState = ButtonVisualState,
        justPressed = Bool,
        centered = Bool                  // true: position は中心、false: 左上（Godot Control デフォルト）
    })
}

mod BaseButton {

    /// デフォルト値で BaseButton を生成する（centered=false: Godot Control 準拠）
    pub def make(size: Vec2.Vec2): BaseButton =
        BaseButton.BaseButton({
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            size = size,
            disabled = false,
            visualState = ButtonVisualState.Normal,
            justPressed = false,
            centered = false
        })

    pub def getSize(base: BaseButton): Vec2.Vec2 =
        let BaseButton.BaseButton(r) = base;
        r#size

    pub def setSize(size: Vec2.Vec2, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({size = size | r})

    pub def isDisabled(base: BaseButton): Bool =
        let BaseButton.BaseButton(r) = base;
        r#disabled

    pub def setDisabled(disabled: Bool, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({disabled = disabled | r})

    pub def getVisualState(base: BaseButton): ButtonVisualState =
        let BaseButton.BaseButton(r) = base;
        r#visualState

    pub def isJustPressed(base: BaseButton): Bool =
        let BaseButton.BaseButton(r) = base;
        r#justPressed

    pub def clearJustPressed(base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({justPressed = false | r})

    pub def isCentered(base: BaseButton): Bool =
        let BaseButton.BaseButton(r) = base;
        r#centered

    pub def setCentered(centered: Bool, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({centered = centered | r})

    /// マウス状態からボタンのインタラクションを更新する
    /// 状態遷移:
    ///   外: Normal, justPressed=false
    ///   内+押下中: Pressed, justPressed=false
    ///   内+押下→離脱: Hovered, justPressed=true（クリック確定）
    ///   内+非押下: Hovered, justPressed=false
    pub def updateInteraction(mousePos: Vec2.Vec2, mousePressed: Bool,
                              globalPos: Vec2.Vec2, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        if (r#disabled) base
        else {
            let inBounds = if (r#centered) {
                let halfX = r#size#x / 2.0;
                let halfY = r#size#y / 2.0;
                mousePos#x >= globalPos#x - halfX and mousePos#x <= globalPos#x + halfX and
                mousePos#y >= globalPos#y - halfY and mousePos#y <= globalPos#y + halfY
            } else {
                mousePos#x >= globalPos#x and mousePos#x <= globalPos#x + r#size#x and
                mousePos#y >= globalPos#y and mousePos#y <= globalPos#y + r#size#y
            };
            if (not inBounds)
                BaseButton.BaseButton({visualState = ButtonVisualState.Normal, justPressed = false | r})
            else if (mousePressed)
                BaseButton.BaseButton({visualState = ButtonVisualState.Pressed, justPressed = false | r})
            else if (r#visualState == ButtonVisualState.Pressed)
                BaseButton.BaseButton({visualState = ButtonVisualState.Hovered, justPressed = true | r})
            else
                BaseButton.BaseButton({visualState = ButtonVisualState.Hovered, justPressed = false | r})
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[BaseButton] {
    pub def isVisible(base: BaseButton): Bool =
        let BaseButton.BaseButton(r) = base;
        r#visible
    pub def setVisible(visible: Bool, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({visible = visible | r})
    pub def getModulate(base: BaseButton): Color =
        let BaseButton.BaseButton(r) = base;
        r#modulate
    pub def setModulate(color: Color, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({modulate = color | r})
    pub def getZIndex(base: BaseButton): Int32 =
        let BaseButton.BaseButton(r) = base;
        r#zIndex
    pub def setZIndex(zIndex: Int32, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[BaseButton] {
    pub def getPosition(base: BaseButton): Vec2.Vec2 =
        let BaseButton.BaseButton(r) = base;
        r#position
    pub def setPosition(position: Vec2.Vec2, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({position = position | r})
    pub def getRotation(base: BaseButton): Float64 =
        let BaseButton.BaseButton(r) = base;
        r#rotation
    pub def setRotation(rotation: Float64, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({rotation = rotation | r})
    pub def getScale(base: BaseButton): Vec2.Vec2 =
        let BaseButton.BaseButton(r) = base;
        r#scale
    pub def setScale(scale: Vec2.Vec2, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({scale = scale | r})
    pub def getSkew(base: BaseButton): Float64 =
        let BaseButton.BaseButton(r) = base;
        r#skew
    pub def setSkew(skew: Float64, base: BaseButton): BaseButton =
        let BaseButton.BaseButton(r) = base;
        BaseButton.BaseButton({skew = skew | r})
}
