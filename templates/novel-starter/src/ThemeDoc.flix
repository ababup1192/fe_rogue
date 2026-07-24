// ThemeDoc — novel.theme.json（色票）の宣言ドキュメント層と、スプライトの意味色キーを
// 実色に解決する resolver。派生色（ハイライト・窓枠）は基準色から導く（導出できる値は
// Doc に置かない）。fail-open: 読めない・壊れているときは defaults() へ倒す。
// 例外は accentLight — スプライト legend が名指しする色は Studio でも解けるよう
// assets/ui/palette.json の宣言色を優先し、無ければ従来どおり accent から導く（fail-open）。
mod ThemeDoc {
    use Util.Json.Json

    /// 場面の色票と雨の空気。bg = 部屋の闇（床・全体）、wall = 書斎の壁、
    /// window = 雨の窓、accent = 灯り・金（差し色）、ink = 本文・表紙の文字色、
    /// rainCount = 窓の雨すじの本数、rainGlow = 雨すじの明るさ（0〜1。窓色を白に寄せる度合い）。
    /// accentLight は novel.theme.json ではなく assets/ui/palette.json の宣言色
    /// （スプライト legend の意味色キー。宣言が無ければ accent からの導出に倒れる）。
    pub type alias Doc = {
        version = Int32,
        bg = Color,
        wall = Color,
        window = Color,
        accent = Color,
        accentLight = Color,
        ink = Color,
        rainCount = Int32,
        rainGlow = Float64
    }

    pub def path(): String = "assets/novel.theme.json"

    /// accentLight の宣言元（Studio の色解決と同じ色票）。
    pub def palettePath(): String = "assets/ui/palette.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/novel.theme.json と同じ色から出発する）。
    /// accentLight の既定は従来どおり accent からの導出（palette.json が上書きする）。
    pub def defaults(): Doc =
        let accent = rgb(1.0, 0.788235, 0.368627);
        { version = 1,
          bg     = rgb(0.062745, 0.062745, 0.109804),
          wall   = rgb(0.164706, 0.141176, 0.219608),
          window = rgb(0.101961, 0.137255, 0.2),
          accent = accent,
          accentLight = lighten(accent, 0.5),
          ink    = rgb(0.921569, 0.941176, 1.0),
          rainCount = 7,
          rainGlow = 0.22 }

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        let accent = colorOr(d#accent, "accent", root);
        { version = JsonCodec.intOr("version", d#version, root),
          bg     = colorOr(d#bg, "bg", root),
          wall   = colorOr(d#wall, "wall", root),
          window = colorOr(d#window, "window", root),
          accent = accent,
          accentLight = lighten(accent, 0.5),
          ink    = colorOr(d#ink, "ink", root),
          rainCount = JsonCodec.intOr("rainCount", d#rainCount, root),
          rainGlow = JsonCodec.floatOr("rainGlow", d#rainGlow, root) }

    def colorOr(fallbackColor: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallbackColor)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    /// accentLight は palette.json（palettePath）の宣言があれば重ねる。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        let doc = readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults());
        let paletteResult = run { Fs.ReadFile.read(palettePath()) } with Fs.ReadFile.runWithFileRead;
        paletteResult
            |> Result.toOption
            |> Option.map(text -> overlayAccentLight(text, doc))
            |> Option.getWithDefault(doc)

    /// palette.json のテキストの "accentLight" を doc に重ねる。
    /// 読めない・キーが無いときは doc のまま（fail-open = accent からの導出）。
    pub def overlayAccentLight(text: String, doc: Doc): Doc =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get("accentLight", root))
            |> Option.flatMap(json ->
                UiDoc.colorOf(Map.empty(), "accentLight", json) |> Result.toOption)
            |> Option.map(c -> { accentLight = c | doc })
            |> Option.getWithDefault(doc)

    // ── 派生色と resolver ──

    /// 白に寄せる（ハイライト・絵があった跡・窓枠などの派生色）。
    pub def lighten(c: Color, k: Float64): Color =
        Color.lighten(c, k)

    /// スプライトの意味色キー → 実色。未知のキーはマゼンタ（描き忘れが目に見える）。
    pub def resolver(doc: Doc, key: String): Color =
        match key {
            case "accent"      => doc#accent
            case "accentLight" => doc#accentLight
            case _             => { r = 1.0f32, g = 0.0f32, b = 1.0f32 }
        }
}
