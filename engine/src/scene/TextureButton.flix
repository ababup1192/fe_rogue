/// テクスチャボタンノード（Godot TextureButton 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_texturebutton.html
///
/// 状態（normal/pressed/hover/disabled）に応じてテクスチャを切り替えるボタン。
/// 共通インタラクション・座標・可視性は `BaseButton` を内包して実装する。
///
///   TextureButton
///     +-- BaseButton: position, rotation, scale, skew, visible, zIndex, modulate,
///                     size, disabled, visualState, justPressed, centered
///     +-- textureNormal, texturePressed, textureHover, textureDisabled（描画専用）

pub enum TextureButton {
    case TextureButton({
        base = BaseButton,
        textureNormal = String,
        texturePressed = Option[String],
        textureHover = Option[String],
        textureDisabled = Option[String]
    })
}

mod TextureButton {

    /// デフォルト値で TextureButton を生成する（centered=false: Godot Control 準拠）
    /// textureNormal: 通常時テクスチャ（必須）
    /// size: ヒット領域サイズ
    pub def make(textureNormal: String, size: Vec2.Vec2): TextureButton =
        TextureButton.TextureButton({
            base = BaseButton.make(size),
            textureNormal = textureNormal,
            texturePressed = None,
            textureHover = None,
            textureDisabled = None
        })

    /// Pressed 時のテクスチャを設定する（None の場合は textureNormal を使う）
    pub def setTexturePressed(tex: String, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({texturePressed = Some(tex) | r})

    /// Hover 時のテクスチャを設定する
    pub def setTextureHover(tex: String, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({textureHover = Some(tex) | r})

    /// Disabled 時のテクスチャを設定する
    pub def setTextureDisabled(tex: String, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({textureDisabled = Some(tex) | r})

    // ── BaseButton への委譲 ──

    pub def getSize(btn: TextureButton): Vec2.Vec2 =
        let TextureButton.TextureButton(r) = btn;
        BaseButton.getSize(r#base)

    pub def setSize(size: Vec2.Vec2, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = BaseButton.setSize(size, r#base) | r})

    pub def isDisabled(btn: TextureButton): Bool =
        let TextureButton.TextureButton(r) = btn;
        BaseButton.isDisabled(r#base)

    pub def setDisabled(disabled: Bool, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = BaseButton.setDisabled(disabled, r#base) | r})

    pub def getVisualState(btn: TextureButton): ButtonVisualState =
        let TextureButton.TextureButton(r) = btn;
        BaseButton.getVisualState(r#base)

    pub def isJustPressed(btn: TextureButton): Bool =
        let TextureButton.TextureButton(r) = btn;
        BaseButton.isJustPressed(r#base)

    pub def clearJustPressed(btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = BaseButton.clearJustPressed(r#base) | r})

    pub def isCentered(btn: TextureButton): Bool =
        let TextureButton.TextureButton(r) = btn;
        BaseButton.isCentered(r#base)

    pub def setCentered(centered: Bool, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = BaseButton.setCentered(centered, r#base) | r})

    /// マウス状態からインタラクションを更新する
    pub def updateInteraction(mousePos: Vec2.Vec2, mousePressed: Bool,
                              globalPos: Vec2.Vec2, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = BaseButton.updateInteraction(mousePos, mousePressed, globalPos, r#base) | r})

    /// 現在の visualState/disabled に応じたテクスチャ名を返す（フォールバックは textureNormal）
    def currentTexture(btn: TextureButton): String =
        let TextureButton.TextureButton(r) = btn;
        let BaseButton.BaseButton(b) = r#base;
        if (b#disabled) {
            match r#textureDisabled {
                case Some(tex) => tex
                case None => r#textureNormal
            }
        } else match b#visualState {
            case ButtonVisualState.Pressed =>
                match r#texturePressed {
                    case Some(tex) => tex
                    case None => r#textureNormal
                }
            case ButtonVisualState.Hovered =>
                match r#textureHover {
                    case Some(tex) => tex
                    case None => r#textureNormal
                }
            case ButtonVisualState.Normal => r#textureNormal
        }

    /// TextureButton を Drawable に変換する
    /// centered=true: position は中心、false: 左上（Godot Control 準拠）
    pub def toDrawables(btn: TextureButton, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let TextureButton.TextureButton(r) = btn;
        let BaseButton.BaseButton(b) = r#base;
        let drawable: GameEngine.Drawable = {
            texture = currentTexture(btn),
            position = globalPos,
            scale = b#scale,
            rotation = b#rotation,
            color = b#modulate,
            alpha = 1.0f32,
            centered = b#centered,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = b#zIndex
        };
        drawable :: Nil
}

// ── CanvasItem 実装（base へ委譲） ──

instance CanvasItem[TextureButton] {
    pub def isVisible(btn: TextureButton): Bool =
        let TextureButton.TextureButton(r) = btn;
        CanvasItem.isVisible(r#base)
    pub def setVisible(visible: Bool, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = CanvasItem.setVisible(visible, r#base) | r})
    pub def getModulate(btn: TextureButton): Color =
        let TextureButton.TextureButton(r) = btn;
        CanvasItem.getModulate(r#base)
    pub def setModulate(color: Color, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = CanvasItem.setModulate(color, r#base) | r})
    pub def getZIndex(btn: TextureButton): Int32 =
        let TextureButton.TextureButton(r) = btn;
        CanvasItem.getZIndex(r#base)
    pub def setZIndex(zIndex: Int32, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = CanvasItem.setZIndex(zIndex, r#base) | r})
}

// ── Node2D 実装（base へ委譲） ──

instance Node2D[TextureButton] {
    pub def getPosition(btn: TextureButton): Vec2.Vec2 =
        let TextureButton.TextureButton(r) = btn;
        Node2D.getPosition(r#base)
    pub def setPosition(position: Vec2.Vec2, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = Node2D.setPosition(position, r#base) | r})
    pub def getRotation(btn: TextureButton): Float64 =
        let TextureButton.TextureButton(r) = btn;
        Node2D.getRotation(r#base)
    pub def setRotation(rotation: Float64, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = Node2D.setRotation(rotation, r#base) | r})
    pub def getScale(btn: TextureButton): Vec2.Vec2 =
        let TextureButton.TextureButton(r) = btn;
        Node2D.getScale(r#base)
    pub def setScale(scale: Vec2.Vec2, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = Node2D.setScale(scale, r#base) | r})
    pub def getSkew(btn: TextureButton): Float64 =
        let TextureButton.TextureButton(r) = btn;
        Node2D.getSkew(r#base)
    pub def setSkew(skew: Float64, btn: TextureButton): TextureButton =
        let TextureButton.TextureButton(r) = btn;
        TextureButton.TextureButton({base = Node2D.setSkew(skew, r#base) | r})
}
