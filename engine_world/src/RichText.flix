// RichText — 一部だけ色や太さの違う文章を「スパンの列」として持ち、描画アイテムへ組む。
// 会話文の中で名前だけ色を変える・強調語だけ太くする、が UI の種類を問わずできる。
// 利用例: spans を組み、place に左上位置と最大幅を渡すと折返し済みの Placed 列が返る。
// 文字送り（タイプライター）とは take で繋がる: 先頭 n 文字だけ残して place に渡す。
mod RichText {

    /// 1 スパン。tint = None は呼び側の基本色で描く。bold は同じ字を半ピクセルずらして
    /// 二度描く疑似太字（フォント 1 本で済む）。
    pub type alias Span = { text = String, tint = Option[Color], bold = Bool }

    pub def plain(text: String): Span = { text = text, tint = None, bold = false }

    pub def colored(text: String, tint: Color): Span = { text = text, tint = Some(tint), bold = false }

    pub def strong(text: String): Span = { text = text, tint = None, bold = true }

    /// 見た目を除いた素の文章（文字送りの長さ勘定・テストの pin に使う）。
    pub def plainText(spans: List[Span]): String =
        spans |> List.map(span -> span#text) |> List.foldLeft(String.concat, "")

    /// 全スパンの合計文字数。
    pub def length(spans: List[Span]): Int32 =
        spans |> List.foldLeft((acc, span) -> acc + String.length(span#text), 0)

    /// 先頭 n 文字ぶんだけ残す（タイプライター表示用）。スパンの途中でも切れる。
    pub def take(n: Int32, spans: List[Span]): List[Span] =
        match spans {
            case Nil => Nil
            case span :: rest => {
                let len = String.length(span#text);
                if (n <= 0)
                    Nil
                else if (n >= len)
                    span :: take(n - len, rest)
                else {
                    let cut = String.toList(span#text) |> List.take(n)
                        |> List.map(Char.toString) |> List.foldLeft(String.concat, "");
                    { text = cut | span } :: Nil
                }
            }
        }

    /// place の引数一式。pos = 左上、maxWidth = 折返し幅（pos#x からの幅）、
    /// baseTint = tint 無指定スパンの色、lineGap = 行間（px）。
    pub type alias Placement = {
        atlas = FontAtlas,
        size = Float64,
        baseTint = Color,
        z = Int32,
        pos = Vec2.Vec2,
        maxWidth = Float64,
        lineGap = Float64
    }

    /// スパン列を左上 pos から 1 文字ずつ置いていく。maxWidth を超える字は次の行へ折り返す
    /// （字単位の折返し — 日本語向き。'\n' でも改行する）。太字スパンは半ピクセル右に
    /// ずらしてもう一度描くことで線を太らせる。
    pub def place(p: Placement, spans: List[Span]): List[Render.Placed] =
        let (items, _, _) = spans |> List.foldLeft((acc, span) -> {
            let (done, x, y) = acc;
            let tint = Option.getWithDefault(p#baseTint, span#tint);
            String.toList(span#text) |> List.foldLeft((acc2, ch) -> {
                let (done2, x2, y2) = acc2;
                if (ch == '\n')
                    (done2, 0.0, y2 + p#size + p#lineGap)
                else {
                    let text = Char.toString(ch);
                    let w = TextDraw.width(text, p#atlas, p#size);
                    let (x3, y3) = if (x2 + w > p#maxWidth and x2 > 0.0)
                        (0.0, y2 + p#size + p#lineGap) else (x2, y2);
                    let at = { x = p#pos#x + x3, y = p#pos#y + y3 };
                    let glyph = { at = at, item = Render.textTinted(text, p#atlas, p#size, tint, p#z) };
                    let emboldened = if (span#bold)
                        { at = { x = at#x + 0.5, y = at#y },
                          item = Render.textTinted(text, p#atlas, p#size, tint, p#z) } :: Nil
                    else
                        Nil;
                    (List.append(done2, glyph :: emboldened), x3 + w, y3)
                }
            }, (done, x, y))
        }, (Nil, 0.0, 0.0));
        items
}
