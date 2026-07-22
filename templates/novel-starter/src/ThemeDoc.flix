// ThemeDoc — novel.theme.json（色票）の宣言ドキュメント層と、スプライトの意味色キーを
// 実色に解決する resolver。派生色（ハイライト・窓枠）は基準色から導く（導出できる値は
// Doc に置かない）。fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json

    /// 場面の色票。bg = 部屋の闇（床・全体）、wall = 書斎の壁、
    /// window = 雨の窓、accent = 灯り・金（差し色）、ink = 本文・表紙の文字色。
    pub type alias Doc = {
        version = Int32,
        bg = Color,
        wall = Color,
        window = Color,
        accent = Color,
        ink = Color
    }

    pub def path(): String = "assets/novel.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/novel.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          bg     = rgb(0.062745, 0.062745, 0.109804),
          wall   = rgb(0.164706, 0.141176, 0.219608),
          window = rgb(0.101961, 0.137255, 0.2),
          accent = rgb(1.0, 0.788235, 0.368627),
          ink    = rgb(0.921569, 0.941176, 1.0) }

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          bg     = colorOr(d#bg, "bg", root),
          wall   = colorOr(d#wall, "wall", root),
          window = colorOr(d#window, "window", root),
          accent = colorOr(d#accent, "accent", root),
          ink    = colorOr(d#ink, "ink", root) }

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

    /// 白に寄せる（ハイライト・絵があった跡・窓枠などの派生色）。
    pub def lighten(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(k);
        { r = c#r + (1.0f32 - c#r) * t, g = c#g + (1.0f32 - c#g) * t, b = c#b + (1.0f32 - c#b) * t }

    /// スプライトの意味色キー → 実色。未知のキーはマゼンタ（描き忘れが目に見える）。
    pub def resolver(doc: Doc, key: String): Color =
        match key {
            case "accent"      => doc#accent
            case "accentLight" => lighten(doc#accent, 0.5)
            case _             => { r = 1.0f32, g = 0.0f32, b = 1.0f32 }
        }
}
