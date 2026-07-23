// ThemeDoc — rpg.theme.json（色票）の宣言ドキュメント層と、スプライトの意味色キーを
// 実色に解決する resolver。派生色（ハイライト・薬草の葉）は基準色から導く（導出できる値は
// Doc に置かない）。fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json

    /// 画面の色票と幕の暗さ。sky = 夕暮れの空（背景）、path = 道、field = 畑、wall = 石垣、
    /// fog = 霧、paper = ふきだしの紙、ink = 文字と輪郭、accent = 灯り、cloth = 住人の服、
    /// titleVeil / clearVeil = 表紙・クリア画面の幕の暗さ（0〜1）。
    pub type alias Doc = {
        version = Int32,
        sky = Color,
        path = Color,
        field = Color,
        wall = Color,
        fog = Color,
        paper = Color,
        ink = Color,
        accent = Color,
        cloth = Color,
        titleVeil = Float64,
        clearVeil = Float64
    }

    pub def path(): String = "assets/rpg.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/rpg.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          sky    = rgb(0.168627, 0.133333, 0.200000),   // #2b2233
          path   = rgb(0.431373, 0.372549, 0.305882),   // #6e5f4e
          field  = rgb(0.274510, 0.376471, 0.247059),   // #46603f
          wall   = rgb(0.333333, 0.313725, 0.368627),   // #55505e
          fog    = rgb(0.721569, 0.705882, 0.784314),   // #b8b4c8
          paper  = rgb(0.949020, 0.917647, 0.847059),   // #f2ead8
          ink    = rgb(0.149020, 0.133333, 0.180392),   // #26222e
          accent = rgb(1.000000, 0.705882, 0.329412),   // #ffb454
          cloth  = rgb(0.309804, 0.498039, 0.619608),   // #4f7f9e
          titleVeil = 0.45,
          clearVeil = 0.55 }

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          sky    = colorOr(d#sky, "sky", root),
          path   = colorOr(d#path, "path", root),
          field  = colorOr(d#field, "field", root),
          wall   = colorOr(d#wall, "wall", root),
          fog    = colorOr(d#fog, "fog", root),
          paper  = colorOr(d#paper, "paper", root),
          ink    = colorOr(d#ink, "ink", root),
          accent = colorOr(d#accent, "accent", root),
          cloth  = colorOr(d#cloth, "cloth", root),
          titleVeil = JsonCodec.floatOr("titleVeil", d#titleVeil, root),
          clearVeil = JsonCodec.floatOr("clearVeil", d#clearVeil, root) }

    def colorOr(fallbackColor: Color, key: String, obj: Map[String, Json]): Color =
        Map.get(key, obj)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallbackColor)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())

    // ── 派生色と resolver ──

    /// 白に寄せる（ハイライト）。
    pub def lighten(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(k);
        { r = c#r + (1.0f32 - c#r) * t, g = c#g + (1.0f32 - c#g) * t, b = c#b + (1.0f32 - c#b) * t }

    /// 黒に寄せる（影・段の陰）。
    pub def darken(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(1.0 - k);
        { r = c#r * t, g = c#g * t, b = c#b * t }

    /// スプライトの意味色キー → 実色。未知のキーはマゼンタ（描き忘れが目に見える）。
    pub def resolver(doc: Doc, key: String): Color =
        match key {
            case "accent"      => doc#accent
            case "accentLight" => lighten(doc#accent, 0.5)
            case "cloth"       => doc#cloth
            case "clothLight"  => lighten(doc#cloth, 0.5)
            case "ink"         => doc#ink
            case "leaf"        => lighten(doc#field, 0.35)
            case _             => { r = 1.0f32, g = 0.0f32, b = 1.0f32 }
        }
}
