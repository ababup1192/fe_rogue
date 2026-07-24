// ThemeDoc — race.theme.json（色票）の宣言ドキュメント層。
// 草（道の外）・路面・レーン線・自機・ライバル 2 台・ゴールライン・文字の色を持つ。
// 派生色（明るめ・暗め）は基準色から導ける範囲はコードで導く（導出できる値は Doc に置かない）。
// fail-open: 読めない・壊れているときは defaults() へ倒す。
mod ThemeDoc {
    use Util.Json.Json

    /// 画面の色票。grass = 道の外（草）、road = 路面、lane = レーンの破線、
    /// player = 自機の車、rivalA / rivalB = ライバル 2 台、finish = ゴールの旗、text = 文字。
    pub type alias Doc = {
        version = Int32,
        grass = Color,
        road = Color,
        lane = Color,
        player = Color,
        rivalA = Color,
        rivalB = Color,
        finish = Color,
        text = Color
    }

    pub def path(): String = "assets/race.theme.json"

    def rgb(r: Float64, g: Float64, b: Float64): Color =
        { r = Float64.truncateToFloat32(r),
          g = Float64.truncateToFloat32(g),
          b = Float64.truncateToFloat32(b) }

    /// コード側の既定値（assets/race.theme.json と同じ色から出発する）。
    pub def defaults(): Doc =
        { version = 1,
          grass  = rgb(0.180392, 0.360784, 0.196078),   // #2e5c32 道の外の草
          road   = rgb(0.223529, 0.231373, 0.258824),   // #393b42 路面（アスファルト）
          lane   = rgb(0.909804, 0.878431, 0.529412),   // #e8e087 レーンの破線（淡い黄）
          player = rgb(0.376471, 0.784314, 0.929412),    // #60c8ed 自機（水色）
          rivalA = rgb(0.909804, 0.352941, 0.407843),    // #e85a68 ライバル A（赤）
          rivalB = rgb(0.980392, 0.756863, 0.286275),    // #fac149 ライバル B（黄）
          finish = rgb(0.925490, 0.937255, 0.949020),    // #eceff2 ゴール（白）
          text   = rgb(0.925490, 0.937255, 0.949020) }   // #eceff2 文字

    /// 白に寄せる（ハイライト）。車の照りなどに使う。
    pub def lighten(c: Color, k: Float64): Color =
        Color.lighten(c, k)

    /// 黒に寄せる（影）。
    pub def darken(c: Color, k: Float64): Color =
        Color.darken(c, k)

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          grass  = colorOr(d#grass, "grass", root),
          road   = colorOr(d#road, "road", root),
          lane   = colorOr(d#lane, "lane", root),
          player = colorOr(d#player, "player", root),
          rivalA = colorOr(d#rivalA, "rivalA", root),
          rivalB = colorOr(d#rivalB, "rivalB", root),
          finish = colorOr(d#finish, "finish", root),
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
