// CourseDoc — 閉じた空中コースの形を文字格子で宣言する Doc。
// 1 行が短い道路区間で、# が通常路面、= が加速帯。補間や規則は Course が担う。
mod CourseDoc {
    use Util.Json.Json

    /// rows は進行方向へ並ぶ道路の断面。末尾の次は先頭へ戻る。
    pub type alias Doc = {
        version = Int32,
        rows = List[String]
    }

    pub def path(): String = "assets/apex.course.json"

    /// JSONを直せない時にも走行確認ができる、短い予備コース。
    /// 完成コースはStudioで編集するassets/apex.course.jsonを正本にする。
    pub def defaults(): Doc =
        { version = 1,
          rows =
              ".....##############....."
           :: ".....==============....."
           :: ".......##############..."
           :: "..........############.."
           :: ".......#############...."
           :: "....##############......"
           :: "......==============...."
           :: ".....##############....."
           :: Nil }

    /// JSON から Doc を読む。2 行未満や空行を含む rows は既定コースへ戻す。
    pub def fromJson(text: String): Option[Doc] =
        DocValue.root(text)
            |> Option.map(fromRoot)

    def fromRoot(root: Map[String, Json]): Doc =
        let defaults = defaults();
        let decodedRows = Map.get("rows", root)
            |> Option.flatMap(JsonCodec.decodeList(JsonCodec.expectString))
            |> Option.getWithDefault(defaults#rows);
        { version = JsonCodec.intOr("version", defaults#version, root),
          rows = if (validRows(decodedRows)) decodedRows else defaults#rows }

    def validRows(rows: List[String]): Bool =
        List.length(rows) >= 2 and List.forAll(row -> String.length(row) >= 3, rows)

    /// ファイルを読み、失敗した時は既定値で続ける。
    pub def load(filePath: String): Doc \ Fs.FileRead =
        DocValue.load(filePath, defaults(), fromJson)
}
