// ThemeDoc — 夜道、車、文字の役割ごとの色をまとめる Doc。
// 明暗の派生色は View が基準色から導き、同じ意味の色を増やさない。
mod ThemeDoc {
    use Util.Json.Json

    /// 夜間レースの色票。
    pub type alias Doc = {
        version = Int32,
        night = Color,
        ground = Color,
        road = Color,
        roadShade = Color,
        shoulder = Color,
        lane = Color,
        player = Color,
        rivalA = Color,
        rivalB = Color,
        danger = Color,
        text = Color,
        muted = Color
    }

    pub def path(): String = "assets/apex.theme.json"

    def rgb(red: Float64, green: Float64, blue: Float64): Color =
        { r = Float64.truncateToFloat32(red),
          g = Float64.truncateToFloat32(green),
          b = Float64.truncateToFloat32(blue) }

    /// JSON が無い時にも役割を見分けられる既定色。
    pub def defaults(): Doc =
        { version = 1,
          night = rgb(0.019608, 0.062745, 0.113725),
          ground = rgb(0.035294, 0.101961, 0.152941),
          road = rgb(0.094118, 0.145098, 0.211765),
          roadShade = rgb(0.066667, 0.105882, 0.160784),
          shoulder = rgb(0.145098, 0.850980, 1.0),
          lane = rgb(1.0, 0.819608, 0.4),
          player = rgb(1.0, 0.239216, 0.552941),
          rivalA = rgb(0.262745, 0.909804, 0.741176),
          rivalB = rgb(1.0, 0.623529, 0.262745),
          danger = rgb(1.0, 0.364706, 0.450980),
          text = rgb(0.952941, 0.968627, 1.0),
          muted = rgb(0.509804, 0.572549, 0.666667) }

    /// JSON から Doc を読む。壊れた色はその欄だけ既定色へ戻す。
    pub def fromJson(text: String): Option[Doc] =
        DocValue.root(text)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let defaults = defaults();
        { version = JsonCodec.intOr("version", defaults#version, root),
          night = colorOr(defaults#night, "night", root),
          ground = colorOr(defaults#ground, "ground", root),
          road = colorOr(defaults#road, "road", root),
          roadShade = colorOr(defaults#roadShade, "roadShade", root),
          shoulder = colorOr(defaults#shoulder, "shoulder", root),
          lane = colorOr(defaults#lane, "lane", root),
          player = colorOr(defaults#player, "player", root),
          rivalA = colorOr(defaults#rivalA, "rivalA", root),
          rivalB = colorOr(defaults#rivalB, "rivalB", root),
          danger = colorOr(defaults#danger, "danger", root),
          text = colorOr(defaults#text, "text", root),
          muted = colorOr(defaults#muted, "muted", root) }

    def colorOr(fallback: Color, key: String, root: Map[String, Json]): Color =
        Map.get(key, root)
            |> Option.flatMap(json -> UiDoc.colorOf(Map.empty(), key, json) |> Result.toOption)
            |> Option.getWithDefault(fallback)

    /// 色を白へ寄せる。車の窓や光のような、基準色から導ける部分に使う。
    pub def lighten(color: Color, amount: Float64): Color =
        Color.lighten(color, amount)

    /// 色を黒へ寄せる。車の影やパネルのような、基準色から導ける部分に使う。
    pub def darken(color: Color, amount: Float64): Color =
        Color.darken(color, amount)

    /// ファイルを読み、失敗した時は既定値で続ける。
    pub def load(filePath: String): Doc \ Fs.FileRead =
        DocValue.load(filePath, defaults(), fromJson)
}
