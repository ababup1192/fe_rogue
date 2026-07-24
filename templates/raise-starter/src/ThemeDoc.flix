// ThemeDoc — raise.theme.json（色票）の宣言ドキュメント層。
// 背景・パネル・カーソル・文字・3 本のパラメータ棒・きらめきの色を持つ。派生色（明るめ・暗め）は
// 基準色から導ける範囲はコードで導く（導出できる値は Doc に置かない）。
// fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json

    /// 画面の色票。bg = 背景、panel = 枠の中、cursor = 選択カーソル、text = 文字、
    /// bar1/bar2/bar3 = 3 パラメータの棒、spark = 伸びた合図のきらめき。
    pub type alias Doc = {
        version = Int32,
        bg = Color,
        panel = Color,
        cursor = Color,
        text = Color,
        bar1 = Color,
        bar2 = Color,
        bar3 = Color,
        spark = Color
    }

    pub def path(): String = "assets/raise.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/raise.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          bg     = rgb(0.098039, 0.101961, 0.137255),   // #191823 背景
          panel  = rgb(0.149020, 0.137255, 0.211765),   // #262336 パネル
          cursor = rgb(0.960784, 0.768627, 0.317647),   // #f5c451 選択カーソル
          text   = rgb(0.901961, 0.886275, 0.941176),   // #e6e2f0 文字
          bar1   = rgb(0.435294, 0.827451, 0.929412),    // #6fd3ed たいりょく
          bar2   = rgb(0.941176, 0.478431, 0.549020),    // #f07a8c きあい
          bar3   = rgb(0.560784, 0.878431, 0.560784),    // #8fe08f わざ
          spark  = rgb(1.000000, 0.909804, 0.603922) }   // #ffe89a きらめき

    /// n 番目（0 始まり）のパラメータ棒の色。範囲外は文字色へ倒す（fail-open）。
    /// stats は 3 つを想定するので bar1..bar3 を順に返す。
    pub def barColor(n: Int32, d: Doc): Color =
        match n {
            case 0 => d#bar1
            case 1 => d#bar2
            case 2 => d#bar3
            case _ => d#text
        }

    /// 白に寄せる（ハイライト）。
    pub def lighten(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(k);
        { r = c#r + (1.0f32 - c#r) * t, g = c#g + (1.0f32 - c#g) * t, b = c#b + (1.0f32 - c#b) * t }

    /// 黒に寄せる（影）。
    pub def darken(c: Color, k: Float64): Color =
        let t = Float64.truncateToFloat32(1.0 - k);
        { r = c#r * t, g = c#g * t, b = c#b * t }

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          bg     = colorOr(d#bg, "bg", root),
          panel  = colorOr(d#panel, "panel", root),
          cursor = colorOr(d#cursor, "cursor", root),
          text   = colorOr(d#text, "text", root),
          bar1   = colorOr(d#bar1, "bar1", root),
          bar2   = colorOr(d#bar2, "bar2", root),
          bar3   = colorOr(d#bar3, "bar3", root),
          spark  = colorOr(d#spark, "spark", root) }

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
}
