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

    /// 色見本の 6 桁 16 進をそのまま書くための近道。読めない綴りはマゼンタ
    /// （書き間違いが画面で目に見える）。
    def hex(code: String): Color =
        Color.hex(code) |> Option.getWithDefault({ r = 1.0f32, g = 0.0f32, b = 1.0f32 })

    /// コード側の既定値（assets/race.theme.json と同じ色から出発する）。
    /// 夜のハイウェイの色。光っているのはレーン標識と車だけで、地面は沈んでいる。
    pub def defaults(): Doc =
        { version = 1,
          grass  = hex("#141a26"),   // 路肩（夜に沈んだ地面）
          road   = hex("#3b4358"),   // 路面（濡れたアスファルト）
          lane   = hex("#ffe066"),   // レーンの標識（ネオンの黄）
          player = hex("#5ee0ff"),   // 自機（水色）
          rivalA = hex("#ff5a7a"),   // ライバル A（赤）
          rivalB = hex("#ffb84d"),   // ライバル B（橙）
          finish = hex("#eceff2"),   // ゴール（白）
          text   = hex("#eceff2") }  // 文字

    /// 遠くへ向かって路面が溶けていく色（夜霧）。基準色から導けるので Doc には置かない。
    pub def haze(doc: Doc): Color =
        Color.cool(Color.darken(doc#road, 0.45), 0.2)

    /// テキストから Doc へ（fail-open）。色の表記（#rrggbb）は UiDoc.colorOf に委ねる。
    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

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
        DocJson.loadOr(fromJson, defaults(), p)
}
