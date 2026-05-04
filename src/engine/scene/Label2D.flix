/// テキスト表示ノード（Godot Label2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_label.html
///
/// FontAtlas + TextLayout を使い、テキストをグリフごとに Drawable として描画する。
/// 横方向・縦方向のアライメントを Godot HorizontalAlignment / VerticalAlignment と同じ
/// enum で指定する。Fill は本実装では Left/Top と同じ扱い（justify は未対応）。
///
///   Label2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew

/// 横方向アライメント（Godot HorizontalAlignment 準拠）
pub enum HorizontalAlignment with Eq, Order, ToString {
    case Left
    case Center
    case Right
    case Fill
}

/// 縦方向アライメント（Godot VerticalAlignment 準拠）
pub enum VerticalAlignment with Eq, Order, ToString {
    case Top
    case Center
    case Bottom
    case Fill
}

pub enum Label2D {
    case Label2D({
        text = String,
        fontAtlas = FontAtlas,
        fontSize = Float64,
        horizontalAlignment = HorizontalAlignment,
        verticalAlignment = VerticalAlignment,
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
    /// テキストとフォントアトラスから Label2D を生成する。
    /// Godot のデフォルトは horizontalAlignment = Left, verticalAlignment = Top
    pub def make(text: String, fontAtlas: FontAtlas, fontSize: Float64): Label2D =
        Label2D.Label2D({
            text = text,
            fontAtlas = fontAtlas,
            fontSize = fontSize,
            horizontalAlignment = HorizontalAlignment.Left,
            verticalAlignment = VerticalAlignment.Top,
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

    /// 横方向アライメントを設定する
    pub def setHorizontalAlignment(alignment: HorizontalAlignment, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ horizontalAlignment = alignment | r })

    /// 横方向アライメントを取得する
    pub def getHorizontalAlignment(label: Label2D): HorizontalAlignment =
        let Label2D.Label2D(r) = label;
        r#horizontalAlignment

    /// 縦方向アライメントを設定する
    pub def setVerticalAlignment(alignment: VerticalAlignment, label: Label2D): Label2D =
        let Label2D.Label2D(r) = label;
        Label2D.Label2D({ verticalAlignment = alignment | r })

    /// 縦方向アライメントを取得する
    pub def getVerticalAlignment(label: Label2D): VerticalAlignment =
        let Label2D.Label2D(r) = label;
        r#verticalAlignment

    /// 行内テキスト幅 (lineWidth) と horizontalAlignment から、グリフ列に適用する
    /// 横方向オフセットを返す。Fill は本実装では Left と同じ扱い（justify は未対応）。
    pub def horizontalOffsetFor(alignment: HorizontalAlignment, lineWidth: Float64): Float64 =
        match alignment {
            case HorizontalAlignment.Left   => 0.0
            case HorizontalAlignment.Center => -lineWidth / 2.0
            case HorizontalAlignment.Right  => -lineWidth
            case HorizontalAlignment.Fill   => 0.0
        }

    /// 全行の合計高さ (totalHeight) と verticalAlignment から、テキストブロック全体に
    /// 適用する縦方向オフセットを返す。Fill は本実装では Top と同じ扱い。
    pub def verticalOffsetFor(alignment: VerticalAlignment, totalHeight: Float64): Float64 =
        match alignment {
            case VerticalAlignment.Top    => 0.0
            case VerticalAlignment.Center => -totalHeight / 2.0
            case VerticalAlignment.Bottom => -totalHeight
            case VerticalAlignment.Fill   => 0.0
        }

    /// テキストから Drawable のリストを生成する。
    /// 各グリフに対して 1 つの Drawable を生成する。テキスト中の改行 (\n) で複数行に分割される。
    /// horizontalAlignment は行ごとに、verticalAlignment はテキストブロック全体に適用される。
    pub def toDrawables(label: Label2D, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let Label2D.Label2D(r) = label;
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        let lineHeight = (atlas#ascent + atlas#descent + atlas#lineGap) * scale;
        let lines = TextLayout.splitLines(r#text);
        let totalHeight = lineHeight * Int32.toFloat64(Int32.max(1, List.length(lines)));
        let blockYOffset = verticalOffsetFor(r#verticalAlignment, totalHeight);
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
            // 行幅と horizontalAlignment から横オフセット計算
            let lineWidth = TextLayout.totalAdvance(advances) * scale;
            let offsetX = horizontalOffsetFor(r#horizontalAlignment, lineWidth);
            // レイアウト位置計算
            let positions = TextLayout.layoutPositions(advances, 0.0, scale, lineHeight);
            let yOff = Int32.toFloat64(lineIdx) * lineHeight + blockYOffset;
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
