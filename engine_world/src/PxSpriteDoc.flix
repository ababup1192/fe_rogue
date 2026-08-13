// PxSpriteDoc — *.sprite.json(文字格子のドット絵)の宣言ドキュメント層。
// 絵は「文字の格子」で書く: legend が文字→意味色キー(実色でなくテーマで解決する名前)を
// 与え、sprites が 名前 →{frames: 名前付きコマ(rows = 文字列の配列), anchor} を並べる。
// legend はファイルに 1 個でコマ間共有。legend に無い文字は透明(fail-open)。
// 実色への解決は描く側(PxSprite.draw の resolver)が行う — Doc は色の名前しか知らない。
//
// 外形は Doc 規約どおり: version / note 歓迎 / 全フィールド fail-open
// (欠け・書き損じは既定へ落とす — 壊れたファイルでも empty() で必ず動く)。
mod PxSpriteDoc {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray, JString}

    /// スプライト 1 体: anchor(格子内の基準セル — draw の置き場所がこのセルに来る)と、
    /// 名前付きコマ(rows 形式: 上の行から順の文字列の配列)。
    pub type alias Sprite = {
        anchor = Vec2.Vec2,
        frames = Map[String, List[String]]
    }

    /// sprite.json 全体。legend は 1 文字 → 意味色キー。
    pub type alias Doc = {
        version = Int32,
        note = Option[String],
        legend = Map[Char, String],
        sprites = Map[String, Sprite]
    }

    /// 何も描かない空の Doc。「まだ読めていない」の置き場 — draw は常に空を返す。
    pub def empty(): Doc =
        { version = 1, note = None, legend = Map.empty(), sprites = Map.empty() }

    /// テキストから Doc へ(fail-open)。JSON でない・形が違うフィールドは既定へ落とす。
    pub def fromJson(text: String): Option[Doc] =
        DocJson.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    /// パース済みの Json 値から Doc へ(エディタの doc/path 経路用 — fromJson と同じ fail-open)。
    /// オブジェクトでなければ None(呼び手が empty へ倒す)。
    pub def fromJsonValue(json: Json): Option[Doc] =
        JsonCodec.expectObject(json) |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = empty();
        { version = JsonCodec.intOr("version", d#version, root),
          note = Map.get("note", root) |> Option.flatMap(JsonCodec.expectString),
          legend = legendOf(root),
          sprites = spritesOf(root) }

    /// legend: {"h": "hair", ...}。キーが 1 文字でない・値が文字列でない項は黙って捨てる。
    def legendOf(root: Map[String, Json]): Map[Char, String] =
        Map.get("legend", root)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(m -> m
                |> Map.toList
                |> List.filterMap(entry -> {
                    let (k, v) = entry;
                    match (String.toList(k), JsonCodec.expectString(v)) {
                        case (ch :: Nil, Some(key)) => Some((ch, key))
                        case _                      => None
                    }
                })
                |> List.toMap)
            |> Option.getWithDefault(Map.empty())

    def spritesOf(root: Map[String, Json]): Map[String, Sprite] =
        Map.get("sprites", root)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(m -> m
                |> Map.toList
                |> List.filter(entry -> { let (name, _) = entry;
                    not String.startsWith(prefix = "//", name) })
                |> List.filterMap(entry -> {
                    let (name, json) = entry;
                    spriteOf(json) |> Option.map(sp -> (name, sp))
                })
                |> List.toMap)
            |> Option.getWithDefault(Map.empty())

    /// スプライト 1 体。anchor 省略時は {0,0}(格子の左上)。frames の中で
    /// 文字列でない行が混ざったコマは、そのコマだけ捨てる(fail-open)。
    def spriteOf(json: Json): Option[Sprite] =
        JsonCodec.expectObject(json) |> Option.map(obj ->
            { anchor = Map.get("anchor", obj)
                  |> Option.flatMap(JsonCodec.decodeVec2)
                  |> Option.getWithDefault({ x = 0.0, y = 0.0 }),
              frames = framesOf(obj) })

    def framesOf(obj: Map[String, Json]): Map[String, List[String]] =
        Map.get("frames", obj)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(m -> m
                |> Map.toList
                |> List.filter(entry -> { let (name, _) = entry;
                    not String.startsWith(prefix = "//", name) })
                |> List.filterMap(entry -> {
                    let (name, json) = entry;
                    JsonCodec.decodeList(JsonCodec.expectString, json)
                        |> Option.map(rows -> (name, rows))
                })
                |> List.toMap)
            |> Option.getWithDefault(Map.empty())

    /// コマの格子の大きさ（列数・行数）。列数は一番長い行の文字数。
    /// そのスプライト・そのコマが無ければ None。
    /// 絵の大きさは「絵が決める」— 呼び側が数えると、絵を描き替えたとき静かに食い違う。
    pub def gridSizeOf(doc: Doc, sprite: String, frame: String): Option[{ cols = Int32, rows = Int32 }] =
        Map.get(sprite, doc#sprites)
            |> Option.flatMap(sp -> Map.get(frame, sp#frames))
            |> Option.map(Grid.dimsOfRows)

    /// path の Doc を読む。読めない・壊れているときは empty(fail-open)。
    /// empty に倒れると絵が「消える」だけで落ちないぶん原因が見えにくいので、
    /// 読み口を DocJson.loadOr に委譲し、倒れた事実は標準エラーへ 1 行出る。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, empty(), p)
}
