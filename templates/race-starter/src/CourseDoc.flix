// CourseDoc — race.course.json（コースの形）の宣言ドキュメント層。
// コースは「文字格子（rows）」1 枚で表す。1 行 = コースを縦に薄く切った 1 段で、
// 上の行ほどコースの「先（遠く）」、下の行ほど「手前」。行の各文字がそのマスの地面:
//   '#'（と '=' など '.'/' ' 以外）= 路面（走れる）、'.'・空白 = 草（道の外・減速）。
// rpg のマップ rows と同じ発想 — 格子を書き換えれば別のコースになる。'#' の並びを
// 左右にずらせばカーブになり、幅を変えれば道が広く/狭くなる。
//
// コースは下から上へ無限に流れる（周回）。前進した距離を格子の行に写して、
// いま自機の足元がどの行かを決める（World.roadRowAt）。曲がる・はみ出す・周回するの
// 規則はコード（World）側 — ここは「地面の地図」だけ。
// fail-open — 読めない・壊れているときは defaults() へ倒し、ゲームは必ず起動する。
mod CourseDoc {
    use Util.Json.Json

    /// コースの地図。rows = 上（先）から下（手前）へ 1 段ずつの文字格子。
    /// 各文字は「そのマスが路面か草か」。列数（一番長い行の長さ）を画面幅いっぱいに割り付ける。
    pub type alias Doc = {
        version = Int32,
        rows = List[String]
    }

    pub def path(): String = "assets/race.course.json"

    /// 「路面（走れる）マス」を表す文字か（'.'・空白は草に倒す — fail-open）。
    /// ここだけが「格子の文字 → 路面かどうか」を決める唯一の入口。
    pub def isRoad(ch: Char): Bool =
        not (ch == '.' or ch == ' ')

    /// コード側の既定値。ゆるやかに左右へ振れる 1 本道（読んで学べる最小のコース）。
    /// '#' の帯が右へ寄り・左へ戻る = カーブ。手前（下）ほど道幅は素直に一定。
    pub def defaults(): Doc =
        { version = 1,
          rows =
              "...#####...."
           :: "....#####..."
           :: ".....#####.."
           :: "......#####."
           :: ".....#####.."
           :: "....#####..."
           :: "...#####...."
           :: "..#####....."
           :: ".#####......"
           :: "..#####....."
           :: "...#####...."
           :: "....#####..."
           :: Nil }

    /// 行数（コースを縦に切った段の数）。前進距離を行に写すときの割り算の分母。
    pub def rowCount(doc: Doc): Int32 =
        List.length(doc#rows)

    /// 列数（一番長い行の長さ）。画面幅を割り付けるマスの数。
    pub def colCount(doc: Doc): Int32 =
        doc#rows |> List.map(String.length) |> List.foldLeft(Int32.max, 1)

    /// n 行目（0 始まり・範囲外は先頭へ巻き戻す = 周回）の文字格子。
    /// コースは無限ループなので、行番号は rowCount で割った余りで読む。
    pub def rowAt(n: Int32, doc: Doc): String =
        let count = rowCount(doc);
        if (count <= 0) ""
        else {
            let wrapped = Int32.modulo(Int32.modulo(n, count) + count, count);
            List.nth(wrapped, doc#rows) |> Option.getWithDefault("")
        }

    /// 列 c（0 始まり）が路面か。範囲外の列は草に倒す（fail-open）。
    pub def isRoadCell(row: String, c: Int32): Bool =
        String.toList(row) |> List.nth(c) |> Option.map(isRoad) |> Option.getWithDefault(false)

    /// テキストから Doc へ（fail-open）。JSON でない・形が違うフィールドは既定へ倒す。
    pub def fromJson(text: String): Option[Doc] =
        JsonCompat.parse(String.trim(text))
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = defaults();
        { version = JsonCodec.intOr("version", d#version, root),
          rows = rowsOr(d#rows, "rows", root) }

    /// 「文字列の配列」を読む。形が違う・要素に文字列でないものが混じるときは既定へ倒す。
    def rowsOr(fallback: List[String], key: String, obj: Map[String, Json]): List[String] =
        Map.get(key, obj)
            |> Option.flatMap(JsonCodec.decodeList(JsonCodec.expectString))
            |> Option.getWithDefault(fallback)

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        let readResult = run { Fs.ReadFile.read(p) } with Fs.ReadFile.runWithFileRead;
        readResult
            |> Result.toOption
            |> Option.flatMap(fromJson)
            |> Option.getWithDefault(defaults())
}
