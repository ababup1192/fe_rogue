/// ボタンノード（Godot Button 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_button.html
///
/// 背景矩形 + テキスト + マウス操作を持つ UI ボタン。
/// 共通インタラクション・座標・可視性は `BaseButton` を内包して実装する。
///
///   Button
///     +-- BaseButton: position, rotation, scale, skew, visible, zIndex, modulate,
///                     size, disabled, visualState, justPressed, centered
///     +-- text, fontAtlas, fontSize（描画専用）

pub enum Button {
    case Button({
        base = BaseButton,
        text = String,
        fontAtlas = FontAtlas,
        fontSize = Float64
    })
}

mod Button {
    /// デフォルト値で Button を生成する（centered=false: Godot Control 準拠）
    pub def make(text: String, fontAtlas: FontAtlas, fontSize: Float64, size: Vec2.Vec2): Button =
        Button.Button({
            base = BaseButton.make(size),
            text = text,
            fontAtlas = fontAtlas,
            fontSize = fontSize
        })

    /// テキストを取得する
    pub def getText(btn: Button): String =
        let Button.Button(r) = btn;
        r#text

    /// テキストを設定する
    pub def setText(text: String, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ text = text | r })

    // ── BaseButton への委譲 ──

    /// サイズを取得する
    pub def getSize(btn: Button): Vec2.Vec2 =
        let Button.Button(r) = btn;
        BaseButton.getSize(r#base)

    /// サイズを設定する
    pub def setSize(size: Vec2.Vec2, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = BaseButton.setSize(size, r#base) | r })

    /// disabled を取得する
    pub def isDisabled(btn: Button): Bool =
        let Button.Button(r) = btn;
        BaseButton.isDisabled(r#base)

    /// disabled を設定する
    pub def setDisabled(disabled: Bool, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = BaseButton.setDisabled(disabled, r#base) | r })

    /// visualState を取得する
    pub def getVisualState(btn: Button): ButtonVisualState =
        let Button.Button(r) = btn;
        BaseButton.getVisualState(r#base)

    /// justPressed を取得する
    pub def isJustPressed(btn: Button): Bool =
        let Button.Button(r) = btn;
        BaseButton.isJustPressed(r#base)

    /// justPressed フラグをクリアする
    pub def clearJustPressed(btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = BaseButton.clearJustPressed(r#base) | r })

    /// マウス状態からボタンのインタラクションを更新する
    pub def updateInteraction(mousePos: Vec2.Vec2, mousePressed: Bool,
                              globalPos: Vec2.Vec2, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = BaseButton.updateInteraction(mousePos, mousePressed, globalPos, r#base) | r })

    // ── 描画 ──

    /// ビジュアル状態に応じた背景色を返す（Godot 4 デフォルトテーマ準拠）
    def bgColor(state: ButtonVisualState): Color = match state {
        case ButtonVisualState.Normal  => {r = 0.1f32, g = 0.1f32, b = 0.1f32}
        case ButtonVisualState.Hovered => {r = 0.225f32, g = 0.225f32, b = 0.225f32}
        case ButtonVisualState.Pressed => {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    }

    /// ビジュアル状態に応じた背景アルファを返す（Godot 4 デフォルトテーマ準拠）
    def bgAlpha(_state: ButtonVisualState): Float32 = 0.6f32

    /// ビジュアル状態に応じたフォント色を返す（Godot 4 デフォルトテーマ準拠）
    def fontColor(state: ButtonVisualState): Color = match state {
        case ButtonVisualState.Normal  => {r = 0.875f32, g = 0.875f32, b = 0.875f32}
        case ButtonVisualState.Hovered => {r = 0.95f32, g = 0.95f32, b = 0.95f32}
        case ButtonVisualState.Pressed => {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    }

    /// Button を Drawable のリストに変換する（背景矩形 + テキスト）
    pub def toDrawables(btn: Button, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let Button.Button(r) = btn;
        let BaseButton.BaseButton(b) = r#base;
        // 背景矩形
        let bgDrawable: GameEngine.Drawable = {
            texture = "",
            position = globalPos,
            scale = b#size,
            rotation = b#rotation,
            color = bgColor(b#visualState),
            alpha = bgAlpha(b#visualState),
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = b#zIndex
        };
        // テキスト（ボタン中央配置）
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        let chars = String.toList(r#text);
        let advances = List.map(ch -> {
            let cp = TextLayout.charToCodePoint(ch);
            match Map.get(cp, atlas#glyphs) {
                case Some(gm) => gm#advance
                case None => 0.0
            }
        }, chars);
        let textWidth = TextLayout.totalAdvance(advances) * scale;
        // グリフの視覚的 Y 範囲を計算（yOff が負の場合を考慮）
        let yBounds = List.foldLeft((acc, ch) -> {
            let cp = TextLayout.charToCodePoint(ch);
            match Map.get(cp, atlas#glyphs) {
                case Some(gm) =>
                    let top = gm#yOff;
                    let bottom = gm#yOff + gm#glyphH;
                    { minY = Float64.min(acc#minY, top), maxY = Float64.max(acc#maxY, bottom) }
                case None => acc
            }
        }, { minY = 0.0, maxY = 0.0 }, chars);
        let visualHeight = (yBounds#maxY - yBounds#minY) * scale;
        // テキスト開始位置（視覚的バウンディングボックスをボタン中央にセンタリング）
        let textX = globalPos#x + (b#size#x - textWidth) / 2.0;
        let textY = globalPos#y + (b#size#y - visualHeight) / 2.0 - yBounds#minY * scale;
        let textBasePos: Vec2.Vec2 = {x = textX, y = textY};
        let positions = TextLayout.layoutPositions(advances, 0.0, scale, r#fontSize * TextLayout.lineHeightMultiplier());
        let textDrawables = List.filterMap(pair -> {
            let (ch, penPos) = pair;
            let cp = TextLayout.charToCodePoint(ch);
            match Map.get(cp, atlas#glyphs) {
                case Some(gm) =>
                    let qb = TextLayout.glyphQuadBounds(penPos, gm, scale, textBasePos, 0.0);
                    let w = qb#x1 - qb#x0;
                    let h = qb#y1 - qb#y0;
                    if (w <= 0.0 or h <= 0.0) None
                    else Some({
                        texture = atlas#textureName,
                        position = {x = qb#x0, y = qb#y0},
                        scale = {x = w / atlas#textureSize, y = h / atlas#textureSize},
                        rotation = 0.0,
                        color = fontColor(b#visualState),
                        alpha = 1.0f32,
                        centered = false,
                        uvOffset = {x = gm#s0, y = gm#t0},
                        uvScale = {x = gm#s1 - gm#s0, y = gm#t1 - gm#t0},
                        zIndex = b#zIndex + 1
                    })
                case None => None
            }
        }, List.zip(chars, positions));
        bgDrawable :: textDrawables
}

// -- CanvasItem 実装（base へ委譲） --

instance CanvasItem[Button] {
    pub def isVisible(btn: Button): Bool =
        let Button.Button(r) = btn;
        CanvasItem.isVisible(r#base)
    pub def setVisible(visible: Bool, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = CanvasItem.setVisible(visible, r#base) | r })
    pub def getModulate(btn: Button): Color =
        let Button.Button(r) = btn;
        CanvasItem.getModulate(r#base)
    pub def setModulate(color: Color, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = CanvasItem.setModulate(color, r#base) | r })
    pub def getZIndex(btn: Button): Int32 =
        let Button.Button(r) = btn;
        CanvasItem.getZIndex(r#base)
    pub def setZIndex(zIndex: Int32, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = CanvasItem.setZIndex(zIndex, r#base) | r })
}

// -- Node2D 実装（base へ委譲） --

instance Node2D[Button] {
    pub def getPosition(btn: Button): Vec2.Vec2 =
        let Button.Button(r) = btn;
        Node2D.getPosition(r#base)
    pub def setPosition(position: Vec2.Vec2, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = Node2D.setPosition(position, r#base) | r })
    pub def getRotation(btn: Button): Float64 =
        let Button.Button(r) = btn;
        Node2D.getRotation(r#base)
    pub def setRotation(rotation: Float64, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = Node2D.setRotation(rotation, r#base) | r })
    pub def getScale(btn: Button): Vec2.Vec2 =
        let Button.Button(r) = btn;
        Node2D.getScale(r#base)
    pub def setScale(scale: Vec2.Vec2, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = Node2D.setScale(scale, r#base) | r })
    pub def getSkew(btn: Button): Float64 =
        let Button.Button(r) = btn;
        Node2D.getSkew(r#base)
    pub def setSkew(skew: Float64, btn: Button): Button =
        let Button.Button(r) = btn;
        Button.Button({ base = Node2D.setSkew(skew, r#base) | r })
}
