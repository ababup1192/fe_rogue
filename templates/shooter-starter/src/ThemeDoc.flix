// ThemeDoc — shooter.theme.json（色票）の宣言ドキュメント層。
// 宇宙（背景）・星・自機・弾・敵・爆発・文字の色を持つ。派生色（明るめ・暗め）は
// 基準色から導ける範囲はコードで導く（導出できる値は Doc に置かない）。
// fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json

    /// 画面の色票。space = 宇宙の背景、star = 星（流れる点）、
    /// player = 自機、bullet = 弾、enemy = 敵、boom = 撃破の閃光、text = 文字。
    pub type alias Doc = {
        version = Int32,
        space = Color,
        star = Color,
        player = Color,
        bullet = Color,
        enemy = Color,
        boom = Color,
        text = Color
    }

    pub def path(): String = "assets/shooter.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/shooter.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          space  = rgb(0.043137, 0.050980, 0.086275),   // #0b0d16 宇宙の暗い紺
          star   = rgb(0.301961, 0.352941, 0.470588),   // #4d5a78 遠い星
          player = rgb(0.376471, 0.827451, 0.929412),    // #60d3ed 自機（水色）
          bullet = rgb(0.980392, 0.909804, 0.474510),    // #fae879 弾（淡い黄）
          enemy  = rgb(0.909804, 0.352941, 0.407843),    // #e85a68 敵（赤）
          boom   = rgb(1.000000, 0.878431, 0.560784),    // #ffe08f 撃破の閃光（暖色）
          text   = rgb(0.827451, 0.858824, 0.917647) }   // #d3dbea 文字

    /// 白に寄せる（ハイライト）。自機の照りなどに使う。
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
          space  = colorOr(d#space, "space", root),
          star   = colorOr(d#star, "star", root),
          player = colorOr(d#player, "player", root),
          bullet = colorOr(d#bullet, "bullet", root),
          enemy  = colorOr(d#enemy, "enemy", root),
          boom   = colorOr(d#boom, "boom", root),
          text   = colorOr(d#text, "text", root) }

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
