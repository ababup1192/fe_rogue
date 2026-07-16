/// Text — テキストを 1 文字ずつグリフに分けて描画する描画物。
/// 文字描画を一箇所にまとめるので、HUD やメニューのどこでも同じ字体で文字を出せる。
/// 利用例: スコア表示、セリフ、メニューの項目名。
/// 注意: アライメントの Fill は Left/Top と同じ扱い（両端揃えは未対応）。

/// 横方向アライメント
pub enum HorizontalAlignment with Eq, Order, ToString {
    case Left
    case Center
    case Right
    case Fill
}

/// 縦方向アライメント
pub enum VerticalAlignment with Eq, Order, ToString {
    case Top
    case Center
    case Bottom
    case Fill
}

pub enum Text {
    case Text({
        text = String,
        fontAtlas = FontAtlas,
        fontSize = Float64,
        horizontalAlignment = HorizontalAlignment,
        verticalAlignment = VerticalAlignment,
        transform = Transform,
        visual = Visual
    })
}

mod Text {
    /// テキストとフォントアトラスから Text を生成する。
    /// 既定は horizontalAlignment = Left, verticalAlignment = Top。
    pub def make(text: String, fontAtlas: FontAtlas, fontSize: Float64): Text =
        Text.Text({
            text = text,
            fontAtlas = fontAtlas,
            fontSize = fontSize,
            horizontalAlignment = HorizontalAlignment.Left,
            verticalAlignment = VerticalAlignment.Top,
            transform = Transform.identity(),
            visual = Visual.default()
        })

    /// 埋め込んだ Transform 部品を取り出す
    pub def transform(label: Text): Transform =
        let Text.Text(r) = label;
        r#transform

    /// Transform 部品に関数を適用して差し替える
    pub def mapTransform(f: Transform -> Transform \ ef, label: Text): Text \ ef =
        let Text.Text(r) = label;
        Text.Text({transform = f(r#transform) | r})

    /// 埋め込んだ Visual 部品を取り出す
    pub def visual(label: Text): Visual =
        let Text.Text(r) = label;
        r#visual

    /// Visual 部品に関数を適用して差し替える
    pub def mapVisual(f: Visual -> Visual \ ef, label: Text): Text \ ef =
        let Text.Text(r) = label;
        Text.Text({visual = f(r#visual) | r})

    /// テキストを設定する
    pub def setText(text: String, label: Text): Text =
        let Text.Text(r) = label;
        Text.Text({ text = text | r })

    /// 横方向アライメントを設定する
    pub def setHorizontalAlignment(alignment: HorizontalAlignment, label: Text): Text =
        let Text.Text(r) = label;
        Text.Text({ horizontalAlignment = alignment | r })

    /// 縦方向アライメントを設定する
    pub def setVerticalAlignment(alignment: VerticalAlignment, label: Text): Text =
        let Text.Text(r) = label;
        Text.Text({ verticalAlignment = alignment | r })

    /// テキストを描画したときに占める表示サイズを返す。
    /// width  = 行の中で最も幅広い行の advance 合計 (× scale)
    /// height = 行数 × lineHeight (= (ascent + descent + lineGap) × scale)
    /// Layout モジュールが描画物の自然サイズを問い合わせるために使う。
    pub def measure(label: Text): Vec2.Vec2 =
        let Text.Text(r) = label;
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        let lineHeight = (atlas#ascent + atlas#descent + atlas#lineGap) * scale;
        let lines = TextLayout.splitLines(r#text);
        let totalHeight = lineHeight * Int32.toFloat64(Int32.max(1, List.length(lines)));
        let maxLineWidth = List.foldLeft((acc, lineChars) -> {
            let advances = List.map(ch -> {
                let cp = TextLayout.charToCodePoint(ch);
                match Map.get(cp, atlas#glyphs) {
                    case Some(gm) => gm#advance
                    case None     => 0.0
                }
            }, lineChars);
            let width = TextLayout.totalAdvance(advances) * scale;
            Float64.max(acc, width)
        }, 0.0, lines);
        {x = maxLineWidth, y = totalHeight}

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
    pub def toDrawables(label: Text, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let Text.Text(r) = label;
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
                            color = r#visual#color,
                            alpha = 1.0f32,
                            centered = false,
                            uvOffset = {x = gm#s0, y = gm#t0},
                            uvScale = {x = gm#s1 - gm#s0, y = gm#t1 - gm#t0},
                            zIndex = r#visual#zIndex,
                            style = None,
                            clip = None,
                            blend = DrawCmd.Blend.Normal
                        })
                    case None => None
                }
            }, List.zip(lineChars, positions));
            {drawables = List.append(acc#drawables, lineDrawables), lineIdx = lineIdx + 1}
        }, {drawables = (Nil: List[GameEngine.Drawable]), lineIdx = 0}, lines);
        result#drawables

}

// -- Renderable 実装 --

instance GameEngine.Renderable[Text] {
    pub def toDrawables(label: Text, globalPos: Vec2.Vec2):
                         List[GameEngine.Drawable] \ GameEngine.Game =
        // 本体は純粋だが trait 側が Game eff を要求するため checked_ecast で持ち上げる。
        checked_ecast(Text.toDrawables(label, globalPos))
}

