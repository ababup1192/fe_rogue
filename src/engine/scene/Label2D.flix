/// テキスト表示ノード（フォントアトラス付き）
///
/// FontAtlas + TextLayout を使い、テキストをグリフごとに Drawable として描画する。
///
///   Label2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Label2D {
    case Label2D({
        text = String,
        fontAtlas = FontAtlas,
        fontSize = Float64,
        centered = Bool,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod Label2D {
    /// テキストとフォントアトラスから Label2D を生成する
    pub def make(text: String, fontAtlas: FontAtlas, fontSize: Float64): Label2D =
        Label2D.Label2D({
            text = text,
            fontAtlas = fontAtlas,
            fontSize = fontSize,
            centered = false,
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })

    /// テキストを設定する
    pub def setText(text: String, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ text = text | r })

    /// テキストを取得する
    pub def getText(label: Label2D): String =
        let Label2D.Label2D(r) = label;
        r#text

    /// centered フラグを設定する
    pub def setCentered(centered: Bool, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ centered = centered | r })

    /// テキストから Drawable のリストを生成する
    /// 各グリフに対して1つの Drawable を生成する
    /// テキスト中の改行コード(\n)で複数行に分割される
    pub def toDrawables(label: Label2D, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let Label2D.Label2D(r) = label;
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        let lineHeight = (atlas#ascent + atlas#descent + atlas#lineGap) * scale;
        let lines = TextLayout.splitLines(r#text);
        let result = List.foldLeft((acc, lineChars) -> {
            let lineIdx = acc#lineIdx;
            // 各文字の advance を取得
            let advances = List.map(ch -> {
                let cp = TextLayout.charToCodePoint(ch);
                match Map.get(cp, atlas#glyphs) {
                    case Some(gm) => gm#advance
                    case None => 0.0
                }
            }, lineChars);
            // 行ごとにセンタリングオフセットを計算
            let offsetX = if (r#centered)
                TextLayout.centerOffset(TextLayout.totalAdvance(advances), scale)
            else 0.0;
            // レイアウト位置計算
            let positions = TextLayout.layoutPositions(advances, 0.0, scale, lineHeight);
            let yOff = Int32.toFloat64(lineIdx) * lineHeight;
            let ascentOffset = atlas#ascent * scale;
            let lineGlobalPos = {x = globalPos#x, y = globalPos#y + yOff + ascentOffset};
            // グリフごとに Drawable を生成
            let lineDrawables = List.filterMap(pair -> {
                let (ch, penPos) = pair;
                let cp = TextLayout.charToCodePoint(ch);
                match Map.get(cp, atlas#glyphs) {
                    case Some(gm) =>
                        let qb = TextLayout.glyphQuadBounds(penPos, gm, scale, lineGlobalPos, offsetX);
                        let w = qb#x1 - qb#x0;
                        let h = qb#y1 - qb#y0;
                        if (w <= 0.0 or h <= 0.0) None
                        else Some({
                            texture = atlas#textureName,
                            position = {x = qb#x0, y = qb#y0},
                            scale = {x = w / atlas#textureSize, y = h / atlas#textureSize},
                            rotation = 0.0,
                            color = r#modulate,
                            alpha = 1.0f32,
                            centered = false,
                            uvOffset = {x = gm#s0, y = gm#t0},
                            uvScale = {x = gm#s1 - gm#s0, y = gm#t1 - gm#t0},
                            zIndex = r#zIndex
                        })
                    case None => None
                }
            }, List.zip(lineChars, positions));
            {drawables = List.append(acc#drawables, lineDrawables), lineIdx = lineIdx + 1}
        }, {drawables = (Nil: List[GameEngine.Drawable]), lineIdx = 0}, lines);
        result#drawables
}

// -- CanvasItem 実装 --

instance CanvasItem[Label2D] {
    pub def isVisible(label: Label2D): Bool =
        let Label2D.Label2D(r) = label;
        r#visible
    pub def setVisible(visible: Bool, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ visible = visible | r })
    pub def getModulate(label: Label2D): Color =
        let Label2D.Label2D(r) = label;
        r#modulate
    pub def setModulate(color: Color, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ modulate = color | r })
    pub def getZIndex(label: Label2D): Int32 =
        let Label2D.Label2D(r) = label;
        r#zIndex
    pub def setZIndex(zIndex: Int32, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[Label2D] {
    pub def getPosition(label: Label2D): Vec2.Vec2 =
        let Label2D.Label2D(r) = label;
        r#position
    pub def setPosition(position: Vec2.Vec2, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ position = position | r })
    pub def getRotation(label: Label2D): Float64 =
        let Label2D.Label2D(r) = label;
        r#rotation
    pub def setRotation(rotation: Float64, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ rotation = rotation | r })
    pub def getScale(label: Label2D): Vec2.Vec2 =
        let Label2D.Label2D(r) = label;
        r#scale
    pub def setScale(scale: Vec2.Vec2, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ scale = scale | r })
    pub def getSkew(label: Label2D): Float64 =
        let Label2D.Label2D(r) = label;
        r#skew
    pub def setSkew(skew: Float64, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ skew = skew | r })
}
