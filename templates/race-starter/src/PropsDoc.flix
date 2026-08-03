// PropsDoc — race.props.json（コースに置く物の置き場）の宣言ドキュメント層。
// 1 行 = コースの 1 段、1 文字 = 道幅を 9 等分したレーン 1 本。文字はそのマスに立つ物:
//   '.' 何も無い / 'I' アイテム / 'X' コーン / 'G' 土管ゲート（その列が隙間）/ 'P' 振り子バー
//
// 列は「画面の位置」ではなく「道の中のレーン」。左端の列が道の左端で、右端の列が道の右端。
// だからカーブで道が細くなれば、置き物も当たりも一緒に細くなる。
//
// 形（race.course.json）と置き場（このファイル）で Doc を分けてある。1 Doc = 1 関心
// （docs/doc-conventions.md）の見本 — コースの曲がりを直す作業と、物を並べ替える作業は
// 別の作業で、同時に読み直したい物でもない。行数はコースの段数（区間の len の合計）と
// 揃える。足りない行はその段に何も無い、余った行は捨てる（fail-open）。
mod PropsDoc {
    use Util.Json.Json

    /// マスに立つ物の種類。
    pub enum Kind with Eq, ToString {
        case Item     // アイテム箱
        case Cone     // コーン（点の障害物）
        case Gate     // 土管ゲート（2 本の土管の間の隙間を通す）
        case Bar      // 振り子バー（道を左右に往復する横棒）
    }

    /// 置き物 1 つ。lane は 0（道の左端）から lanes()-1（道の右端）まで。
    pub type alias Cell = { lane = Int32, kind = Kind }

    /// 置き場の表。rows = スタートの段から 1 段ずつ。
    pub type alias Doc = { version = Int32, rows = List[String] }

    pub def path(): String = "assets/race.props.json"

    /// 道幅を割るレーンの数（= 1 行の文字数）。奇数にしてあるので真ん中の列（4）が道の中心。
    pub def lanes(): Int32 = 9

    /// 既定コース（CourseDoc.defaults）の段数。既定の置き場もこの数だけ行を持つ。
    def defaultRows(): Int32 = 66

    /// 何か置いてある段だけの表（段番号, その段の 1 行）。残りの段は空の行で埋める —
    /// 66 行すべてを並べると、どこに何があるかが読み取れない表になる。
    /// ねらいは race.props.json の note に書いてある。
    def marks(): List[(Int32, String)] =
           (8,  "......G..")   // 左 U 字の手前: 隙間は右（コーナーの外側）
        :: (9,  "..X......")
        :: (19, "....I....")
        :: (21, "......X..")
        :: (25, "......X..")
        :: (27, "....I....")
        :: (30, "....I....")
        :: (32, "....P....")   // 長い直線の振り子（ブレーキで待つかニトロで抜けるか）
        :: (39, "......X..")
        :: (41, "..G......")   // 右ヘアピンの手前: 隙間は左
        :: (47, "....P....")
        :: (49, "..X......")
        :: (53, "....I....")
        :: (57, "....P....")
        :: Nil

    /// 何も置かれていない 1 行。
    def emptyRow(): String = "........."

    /// コード側の既定値（assets/race.props.json と同じ置き場から出発する）。
    pub def defaults(): Doc =
        let table = List.toMap(marks());
        { version = 1,
          rows = List.range(0, defaultRows())
              |> List.map(n -> Map.getWithDefault(n, emptyRow(), table)) }

    /// 段 m（コース 1 周の中の段。周回の巻き戻しは呼ぶ側の仕事）に置かれた物。
    /// 行が足りない段は何も無い（fail-open — 置き場が短くてもゲームは走れる）。
    pub def cellsAt(m: Int32, doc: Doc): List[Cell] =
        if (m < 0) Nil
        else List.drop(m, doc#rows) |> List.head
            |> Option.map(cellsOfRow) |> Option.getWithDefault(Nil)

    /// 1 行を左から読んで、立っている物だけを拾う。レーン数より右の文字は捨てる。
    def cellsOfRow(row: String): List[Cell] =
        String.toList(row) |> List.zipWithIndex |> List.filterMap(entry -> {
            let (i, ch) = entry;
            if (i >= lanes()) None
            else kindOf(ch) |> Option.map(k -> ({ lane = i, kind = k }: Cell))
        })

    /// 文字 → 種類。知らない文字は「何も無い」（fail-open）。
    def kindOf(ch: Char): Option[Kind] =
        match ch {
            case 'I' => Some(Kind.Item)
            case 'X' => Some(Kind.Cone)
            case 'G' => Some(Kind.Gate)
            case 'P' => Some(Kind.Bar)
            case _   => None
        }

    /// レーン lane の中心が道の中心から何 px ずれた所か（half = その段の道の半幅）。
    pub def laneOff(lane: Int32, half: Float64): Float64 =
        half * (2.0 * (Int32.toFloat64(lane) + 0.5) / Int32.toFloat64(lanes()) - 1.0)

    /// レーン lane の左の境（lane = lanes() を渡すと道の右端）。
    /// 帯で当たりを取る物（ゲートの土管）はここから辺を引く。
    pub def laneEdge(lane: Int32, half: Float64): Float64 =
        half * (2.0 * Int32.toFloat64(lane) / Int32.toFloat64(lanes()) - 1.0)

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          rows = rowsOr(d#rows, root) }

    /// rows（置き場の表）を読む。配列でない・空のときは既定の置き場へ倒す。
    def rowsOr(fallback: List[String], root: Map[String, Json]): List[String] =
        Map.get("rows", root)
            |> Option.flatMap(JsonCodec.decodeList(JsonCodec.expectString))
            |> Option.filter(rows -> not List.isEmpty(rows))
            |> Option.getWithDefault(fallback)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
