/// リッチテキストラベル（Godot RichTextLabel 準拠の最小実装）
/// see: https://docs.godotengine.org/en/stable/classes/class_richtextlabel.html
///
/// BBCode カラータグ `[color=...]...[/color]` をサポートする。
/// 表示領域 size を持ち、はみ出す行は CPU 側でカリングする（真のクリッピングは未実装）。
/// scrollY を加算して縦方向にスクロールでき、scrollFollowing が true のときは
/// setText 時に自動で末尾までスクロールする（チャットログ用途を想定）。
///
///   RichTextLabel
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew

pub enum RichTextLabel {
    case RichTextLabel({
        text = String,
        fontAtlas = FontAtlas,
        fontSize = Float64,
        size = Vec2.Vec2,
        scrollY = Float64,
        scrollFollowing = Bool,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod RichTextLabel {
    /// テキストとフォントアトラスから RichTextLabel を生成する。
    /// size は表示領域 (w, h)。BBCode 解釈は toDrawables 時に行う。
    pub def make(text: String, fontAtlas: FontAtlas, fontSize: Float64, size: Vec2.Vec2): RichTextLabel =
        RichTextLabel.RichTextLabel({
            text = text,
            fontAtlas = fontAtlas,
            fontSize = fontSize,
            size = size,
            scrollY = 0.0,
            scrollFollowing = false,
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })

    /// テキストを設定する。scrollFollowing が true のとき、末尾まで自動スクロールする。
    pub def setText(text: String, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        let updated = RichTextLabel.RichTextLabel({ text = text | r });
        if (r#scrollFollowing) scrollToBottom(updated)
        else updated

    /// テキストを取得する（BBCode タグ込みの生文字列）
    pub def getText(label: RichTextLabel): String =
        let RichTextLabel.RichTextLabel(r) = label;
        r#text

    /// 表示領域サイズを設定する
    pub def setSize(size: Vec2.Vec2, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ size = size | r })

    /// 表示領域サイズを取得する
    pub def getSize(label: RichTextLabel): Vec2.Vec2 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#size

    /// スクロール位置（縦）を設定する。範囲は 0 〜 max(0, contentHeight - size.y) にクランプ。
    pub def setScrollY(scrollY: Float64, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        let maxScroll = Float64.max(0.0, contentHeight(label) - r#size#y);
        let clamped = Float64.max(0.0, Float64.min(scrollY, maxScroll));
        RichTextLabel.RichTextLabel({ scrollY = clamped | r })

    /// スクロール位置（縦）を取得する
    pub def getScrollY(label: RichTextLabel): Float64 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#scrollY

    /// 自動末尾追従の ON/OFF を設定する。true にすると以降 setText のたびに末尾までスクロール。
    pub def setScrollFollowing(following: Bool, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ scrollFollowing = following | r })

    /// 自動末尾追従の状態を取得する
    pub def getScrollFollowing(label: RichTextLabel): Bool =
        let RichTextLabel.RichTextLabel(r) = label;
        r#scrollFollowing

    /// 末尾までスクロールする（contentHeight - size.y、負なら 0）
    pub def scrollToBottom(label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        let target = Float64.max(0.0, contentHeight(label) - r#size#y);
        RichTextLabel.RichTextLabel({ scrollY = target | r })

    /// 1 行の高さ（フォントサイズに対する scaled line height）
    pub def lineHeight(label: RichTextLabel): Float64 =
        let RichTextLabel.RichTextLabel(r) = label;
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        (atlas#ascent + atlas#descent + atlas#lineGap) * scale

    /// テキスト全体の高さ（タグ除去後の行数 × lineHeight）
    pub def contentHeight(label: RichTextLabel): Float64 =
        let RichTextLabel.RichTextLabel(r) = label;
        let segments = parseBBCode(r#text, r#modulate);
        let lines = splitSegmentsIntoLines(segments);
        let lh = lineHeight(label);
        lh * Int32.toFloat64(Int32.max(1, List.length(lines)))

    /// BBCode テキストを「文字＋色」のフラットなリストに変換する。
    /// 対応タグ: [color=#rrggbb], [color=#rrggbbaa], [color=name], [/color]
    /// 認識できない `[xxx]` 形式はリテラルとして保持する。
    pub def parseBBCode(text: String, defaultColor: Color): List[(Char, Color)] =
        let chars = String.toList(text);
        let result = parseBBCodeLoop(chars, defaultColor :: Nil, Nil);
        List.reverse(result)

    /// BBCode パーサ本体（再帰）。stack は色のスタック、acc は逆順の結果。
    def parseBBCodeLoop(chars: List[Char], stack: List[Color], acc: List[(Char, Color)]): List[(Char, Color)] =
        match chars {
            case Nil => acc
            case '[' :: rest =>
                match takeUntilCloseBracket(rest) {
                    case Some((tagBody, after)) =>
                        match interpretTag(tagBody) {
                            case TagAction.Push(c) =>
                                parseBBCodeLoop(after, c :: stack, acc)
                            case TagAction.Pop =>
                                let newStack = match stack {
                                    case _ :: tail if not List.isEmpty(tail) => tail
                                    case s => s
                                };
                                parseBBCodeLoop(after, newStack, acc)
                            case TagAction.Literal =>
                                // タグとして解釈できない → '[' + tagBody + ']' をリテラル化
                                let cur = currentColor(stack);
                                let lit = '[' :: List.append(String.toList(tagBody), ']' :: Nil);
                                let newAcc = List.foldLeft((a, ch) -> (ch, cur) :: a, acc, lit);
                                parseBBCodeLoop(after, stack, newAcc)
                        }
                    case None =>
                        // 閉じ括弧なし → '[' をリテラル扱いして次へ
                        let cur = currentColor(stack);
                        parseBBCodeLoop(rest, stack, ('[', cur) :: acc)
                }
            case ch :: rest =>
                let cur = currentColor(stack);
                parseBBCodeLoop(rest, stack, (ch, cur) :: acc)
        }

    /// '[' の次から ']' までを取り出す。見つからなければ None。
    /// found = true 以降は、それ以降の char をすべて rest に積む（']' 後に丸ごと残す）。
    def takeUntilCloseBracket(chars: List[Char]): Option[(String, List[Char])] =
        let result = List.foldLeft((acc, ch) -> {
            if (acc#found) {body = acc#body, rest = ch :: acc#rest, found = true}
            else if (ch == ']') {body = acc#body, rest = acc#rest, found = true}
            else {body = ch :: acc#body, rest = acc#rest, found = false}
        }, {body = (Nil: List[Char]), rest = (Nil: List[Char]), found = false}, chars);
        if (result#found)
            Some((charsToString(List.reverse(result#body)), List.reverse(result#rest)))
        else
            None

    /// List[Char] を String に変換するヘルパー
    def charsToString(chars: List[Char]): String =
        List.foldLeft((acc, c) -> acc + Char.toString(c), "", chars)

    /// タグ解釈結果
    enum TagAction {
        case Push(Color)
        case Pop
        case Literal
    }

    /// タグ本体（'[' と ']' の間の文字列）を解釈する
    def interpretTag(tagBody: String): TagAction =
        let trimmed = String.trim(tagBody);
        if (trimmed == "/color") TagAction.Pop
        else if (String.startsWith(prefix = "color=", trimmed)) {
            let value = String.trim(String.drop(6, trimmed));
            match parseColorValue(value) {
                case Some(c) => TagAction.Push(c)
                case None    => TagAction.Literal
            }
        }
        else TagAction.Literal

    /// "#rrggbb" / "#rrggbbaa" / 名前付き色 を Color に変換する。alpha は無視。
    def parseColorValue(value: String): Option[Color] =
        if (String.startsWith(prefix = "#", value)) parseHexColor(String.drop(1, value))
        else parseNamedColor(String.toLowerCase(value))

    /// "rrggbb" または "rrggbbaa" を Color に変換する
    def parseHexColor(hex: String): Option[Color] =
        let len = String.length(hex);
        if (len == 6 or len == 8) {
            let r = parseHexByte(String.slice(start = 0, end = 2, hex));
            let g = parseHexByte(String.slice(start = 2, end = 4, hex));
            let b = parseHexByte(String.slice(start = 4, end = 6, hex));
            match (r, g, b) {
                case (Some(rv), Some(gv), Some(bv)) =>
                    Some({
                        r = Int32.toFloat32(rv) / 255.0f32,
                        g = Int32.toFloat32(gv) / 255.0f32,
                        b = Int32.toFloat32(bv) / 255.0f32
                    })
                case _ => None
            }
        } else None

    /// 2 文字の 16 進数を Int32 (0..255) に変換する
    def parseHexByte(s: String): Option[Int32] =
        if (String.length(s) != 2) None
        else {
            let hi = hexDigit(String.charAt(0, s));
            let lo = hexDigit(String.charAt(1, s));
            match (hi, lo) {
                case (Some(h), Some(l)) => Some(h * 16 + l)
                case _ => None
            }
        }

    /// 1 文字の 16 進数を Int32 (0..15) に変換する
    def hexDigit(ch: Char): Option[Int32] =
        let cp = Char.toBmpCodePoint(ch);
        if (cp >= 48 and cp <= 57) Some(cp - 48)        // '0'..'9'
        else if (cp >= 97 and cp <= 102) Some(cp - 87)  // 'a'..'f'
        else if (cp >= 65 and cp <= 70) Some(cp - 55)   // 'A'..'F'
        else None

    /// 名前付きの色を Color に変換する（Godot Color.named のサブセット）
    def parseNamedColor(name: String): Option[Color] = match name {
        case "white"   => Some({r = 1.0f32, g = 1.0f32, b = 1.0f32})
        case "black"   => Some({r = 0.0f32, g = 0.0f32, b = 0.0f32})
        case "red"     => Some({r = 1.0f32, g = 0.0f32, b = 0.0f32})
        case "green"   => Some({r = 0.0f32, g = 1.0f32, b = 0.0f32})
        case "blue"    => Some({r = 0.0f32, g = 0.0f32, b = 1.0f32})
        case "yellow"  => Some({r = 1.0f32, g = 1.0f32, b = 0.0f32})
        case "cyan"    => Some({r = 0.0f32, g = 1.0f32, b = 1.0f32})
        case "magenta" => Some({r = 1.0f32, g = 0.0f32, b = 1.0f32})
        case "gray"    => Some({r = 0.5f32, g = 0.5f32, b = 0.5f32})
        case "grey"    => Some({r = 0.5f32, g = 0.5f32, b = 0.5f32})
        case "orange"  => Some({r = 1.0f32, g = 0.65f32, b = 0.0f32})
        case _         => None
    }

    /// スタックの現在の色（先頭）を返す。空なら白。
    def currentColor(stack: List[Color]): Color = match stack {
        case c :: _ => c
        case Nil    => {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    }

    /// 改行文字 ('\n') でセグメント列を行ごとに分割する
    pub def splitSegmentsIntoLines(segments: List[(Char, Color)]): List[List[(Char, Color)]] =
        let result = List.foldLeft((acc, pair) -> {
            let (ch, _) = pair;
            if (Char.toBmpCodePoint(ch) == 10)
                {lines = List.reverse(acc#current) :: acc#lines, current = (Nil: List[(Char, Color)])}
            else
                {lines = acc#lines, current = pair :: acc#current}
        }, {lines = (Nil: List[List[(Char, Color)]]), current = (Nil: List[(Char, Color)])}, segments);
        List.reverse(List.reverse(result#current) :: result#lines)

    /// テキストから Drawable のリストを生成する。
    /// 表示領域 (size) からはみ出す行は CPU 側でスキップする。
    /// scrollY ぶん上方向にずらす（正の scrollY で下方向にスクロール）。
    pub def toDrawables(label: RichTextLabel, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let RichTextLabel.RichTextLabel(r) = label;
        let atlas = r#fontAtlas;
        let scale = r#fontSize / atlas#fontSize;
        let lh = lineHeight(label);
        let segments = parseBBCode(r#text, r#modulate);
        let lines = splitSegmentsIntoLines(segments);
        let result = List.foldLeft((acc, lineSegs) -> {
            let lineIdx = acc#lineIdx;
            let lineTopY = Int32.toFloat64(lineIdx) * lh - r#scrollY;
            let lineBottomY = lineTopY + lh;
            // クリップ: 行が表示領域から完全に外れたらスキップ
            if (lineBottomY < 0.0 or lineTopY > r#size#y)
                {drawables = acc#drawables, lineIdx = lineIdx + 1}
            else {
                // 行ごとに各文字の advance を取得
                let advances = List.map(pair -> {
                    let (ch, _) = pair;
                    let cp = TextLayout.charToCodePoint(ch);
                    match Map.get(cp, atlas#glyphs) {
                        case Some(gm) => gm#advance
                        case None => 0.0
                    }
                }, lineSegs);
                let positions = TextLayout.layoutPositions(advances, 0.0, scale, lh);
                let ascentOffset = atlas#ascent * scale;
                let lineGlobalPos = {
                    x = globalPos#x,
                    y = globalPos#y + lineTopY + ascentOffset
                };
                let lineDrawables = List.filterMap(zipped -> {
                    let (pair, penPos) = zipped;
                    let (ch, color) = pair;
                    let cp = TextLayout.charToCodePoint(ch);
                    match Map.get(cp, atlas#glyphs) {
                        case Some(gm) =>
                            let qb = TextLayout.glyphQuadBounds(penPos, gm, scale, lineGlobalPos, 0.0);
                            let w = qb#x1 - qb#x0;
                            let h = qb#y1 - qb#y0;
                            if (w <= 0.0 or h <= 0.0) None
                            else Some({
                                texture = atlas#textureName,
                                position = {x = qb#x0, y = qb#y0},
                                scale = {x = w / atlas#textureSize, y = h / atlas#textureSize},
                                rotation = 0.0,
                                color = color,
                                alpha = 1.0f32,
                                centered = false,
                                uvOffset = {x = gm#s0, y = gm#t0},
                                uvScale = {x = gm#s1 - gm#s0, y = gm#t1 - gm#t0},
                                zIndex = r#zIndex
                            })
                        case None => None
                    }
                }, List.zip(lineSegs, positions));
                {drawables = List.append(acc#drawables, lineDrawables), lineIdx = lineIdx + 1}
            }
        }, {drawables = (Nil: List[GameEngine.Drawable]), lineIdx = 0}, lines);
        result#drawables
}

// -- CanvasItem 実装 --

instance CanvasItem[RichTextLabel] {
    pub def isVisible(label: RichTextLabel): Bool =
        let RichTextLabel.RichTextLabel(r) = label;
        r#visible
    pub def setVisible(visible: Bool, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ visible = visible | r })
    pub def getModulate(label: RichTextLabel): Color =
        let RichTextLabel.RichTextLabel(r) = label;
        r#modulate
    pub def setModulate(color: Color, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ modulate = color | r })
    pub def getZIndex(label: RichTextLabel): Int32 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#zIndex
    pub def setZIndex(zIndex: Int32, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[RichTextLabel] {
    pub def getPosition(label: RichTextLabel): Vec2.Vec2 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#position
    pub def setPosition(position: Vec2.Vec2, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ position = position | r })
    pub def getRotation(label: RichTextLabel): Float64 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#rotation
    pub def setRotation(rotation: Float64, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ rotation = rotation | r })
    pub def getScale(label: RichTextLabel): Vec2.Vec2 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#scale
    pub def setScale(scale: Vec2.Vec2, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ scale = scale | r })
    pub def getSkew(label: RichTextLabel): Float64 =
        let RichTextLabel.RichTextLabel(r) = label;
        r#skew
    pub def setSkew(skew: Float64, label: RichTextLabel): RichTextLabel =
        let RichTextLabel.RichTextLabel(r) = label;
        RichTextLabel.RichTextLabel({ skew = skew | r })
}
