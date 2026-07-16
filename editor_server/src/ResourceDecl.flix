// ResourceDecl — project.json の "editor" セクション (ゲーム側の名乗り) を読む純粋層。
// ゲームは「このファイルをこういう画面で編集したい」をここで宣言し、
// サーバは宣言に従って一覧・スキーマ・プラグインを引く。
// ここはファイルにも HTTP にも触らない: JSON 値 → 宣言の変換と、
// パターン照合・パス規約の計算だけを持つ。

mod ResourceDecl {
    use Util.Json.Json
    use Util.Json.Json.{JObject, JArray}

    /// 編集対象リソース 1 種類ぶんの宣言。
    /// schemaPath の省略時既定は「pattern の .json を .schema.json に置換」だが、
    /// glob を含む pattern では既定を作れないので None のまま
    /// (解決は一致ファイルごとに sibling 規約)。
    pub type alias Decl = {
        id = String,                    // 宣言を指すための短い名前 (例: "level")
        pattern = String,               // 対象ファイルの照合パターン。'*' は「/ を含まない任意の文字列」
        title = Option[String],         // エディタ画面に出す表示名。無ければ画面側が id で代用する
        schemaPath = Option[String],    // 入力フォームの形を決めるスキーマファイル
        plugin = Option[String],        // 専用の編集画面プラグイン名。無ければ汎用フォームで編集する
        builtin = Bool                  // true = サーバ組み込み (ui / hitbox)。project.json 由来は false
    }

    /// 一覧・集計ボード 1 枚ぶんの宣言。
    pub type alias DashboardDecl = {
        id = String,             // 宣言を指すための短い名前 (例: "monsterBoard")
        title = Option[String],  // エディタ画面に出す表示名。無ければ画面側が id で代用する
        plugin = String,         // 描画を受け持つ画面側プラグイン名 (汎用フォームで代用できないので必須)
        uses = List[String]      // このボードが読むリソース宣言の id の列
    }

    /// project.json 全体から editor 宣言を読む。"editor" 不在は Ok(空) —
    /// 名乗っていないゲームも従来どおり (ui / hitbox 組み込みだけで) 編集できる。
    /// resources / dashboards の形違い (id 欠落等) は、どの項目かを含む
    /// 平易な日本語 1 行の Err で返す。
    pub def fromProjectJson(json: Json): Result[String, {resources = List[Decl], dashboards = List[DashboardDecl]}] =
        match editorSection(json) {
            case None => Ok({resources = Nil, dashboards = Nil})
            case Some(editorJson) =>
                forM (
                    editorObj  <- asObjectAt("editor", editorJson);
                    resources  <- declListAt("resources", declAt, editorObj);
                    dashboards <- declListAt("dashboards", dashboardAt, editorObj)
                ) yield {resources = resources, dashboards = dashboards}
        }

    /// pattern に一致するファイルを allJsonPaths から選ぶ (純粋)。
    /// '*' は「/ を含まない任意の文字列」として解釈し、'*' 無しはそのまま比較する。
    pub def matchFiles(pattern: String, allJsonPaths: List[String]): List[String] =
        List.filter(path -> globMatch(String.toList(pattern), String.toList(path)), allJsonPaths)

    /// データファイルパス → 隣に置くスキーマのパス (foo.json → foo.schema.json)。
    pub def siblingSchemaPath(dataPath: String): String =
        if (String.endsWith(suffix = ".json", dataPath))
            String.dropRight(String.length(".json"), dataPath) + ".schema.json"
        else
            dataPath + ".schema.json"

    /// サーバ組み込みの編集対象 (ui = *.ui.json / hitbox = hitbox.json) を宣言と同じ形で返す。
    // WhyNot: schemaPath は exact な "hitbox.json" でも sibling 既定を入れない —
    // 組み込みは専用のプレビュー画面が受け持ち、スキーマ駆動フォームを使わないため。
    pub def builtinDecls(): List[Decl] =
           { id = "ui",     pattern = "*.ui.json",  title = Some("UI"),
             schemaPath = None, plugin = None, builtin = true }
        :: { id = "hitbox", pattern = "hitbox.json", title = Some("ヒットボックス"),
             schemaPath = None, plugin = None, builtin = true }
        :: Nil

    // ── "editor" セクションの分解 ─────────────────────────

    /// project.json のてっぺんから "editor" の値を取り出す。
    /// てっぺんがオブジェクトでない・"editor" キーが無い、はどちらも None (= 宣言なし)。
    def editorSection(json: Json): Option[Json] =
        JsonCodec.expectObject(json) |> Option.flatMap(topObj -> Map.get("editor", topObj))

    /// location (例: "editor.resources[0]") の値がオブジェクトであることを確かめて中身を返す。
    def asObjectAt(location: String, json: Json): Result[String, Map[String, Json]] =
        JsonCodec.expectObject(json)
            |> Option.toOk("${location} はオブジェクト ({ }) で書いてください")

    /// key の配列を、要素ごとの読み取り itemAt (位置番号付き) でリストにする。
    /// キー自体が無いのは Ok(空) — resources だけ・dashboards だけの宣言を許す。
    def declListAt(key: String, itemAt: (Int32, Json) -> Result[String, a],
                   editorObj: Map[String, Json]): Result[String, List[a]] =
        match Map.get(key, editorObj) {
            case None => Ok(Nil)
            case Some(JArray(items)) =>
                Vector.toList(items)
                    |> List.zipWithIndex
                    |> Result.traverse(entry -> {
                        let (index, itemJson) = entry;
                        itemAt(index, itemJson)
                    })
            case Some(_) => Err("editor.${key} は配列 ([ ]) で書いてください")
        }

    /// resources の要素 1 件を Decl に読む。id と pattern は必須。
    /// schema 省略時は exact な pattern に限り sibling 規約で既定を埋める。
    def declAt(index: Int32, json: Json): Result[String, Decl] =
        let location = "editor.resources[${index}]";
        forM (
            declObj <- asObjectAt(location, json);
            id      <- requiredString(location, "id", declObj);
            pattern <- requiredString(location, "pattern", declObj)
        ) yield {
            id         = id,
            pattern    = pattern,
            title      = optionalString("title", declObj),
            schemaPath = schemaPathOf(pattern, optionalString("schema", declObj)),
            plugin     = optionalString("plugin", declObj),
            builtin    = false
        }

    /// dashboards の要素 1 件を DashboardDecl に読む。id と plugin は必須。
    def dashboardAt(index: Int32, json: Json): Result[String, DashboardDecl] =
        let location = "editor.dashboards[${index}]";
        forM (
            boardObj <- asObjectAt(location, json);
            id       <- requiredString(location, "id", boardObj);
            plugin   <- requiredString(location, "plugin", boardObj);
            uses     <- usesAt(location, boardObj)
        ) yield {id = id, title = optionalString("title", boardObj), plugin = plugin, uses = uses}

    /// 宣言された schema をそのまま使う。省略時は pattern から sibling 規約で決めるが、
    /// glob を含む pattern は既定を作れないので None (一致ファイルごとに解決する)。
    def schemaPathOf(pattern: String, declared: Option[String]): Option[String] =
        match declared {
            case Some(path) => Some(path)
            case None       =>
                if (String.contains(substr = "*", pattern)) None
                else Some(siblingSchemaPath(pattern))
        }

    /// uses (このボードが読むリソース id の列)。キーが無ければ空 = 何も読まないボード。
    def usesAt(location: String, boardObj: Map[String, Json]): Result[String, List[String]] =
        match Map.get("uses", boardObj) {
            case None           => Ok(Nil)
            case Some(usesJson) =>
                JsonCodec.decodeList(JsonCodec.expectString, usesJson)
                    |> Option.toOk("${location} の uses は文字列の配列で書いてください")
        }

    /// location の必須文字列フィールド。無い・文字列でないときは位置入りの一文で断る。
    def requiredString(location: String, key: String, declObj: Map[String, Json]): Result[String, String] =
        Map.get(key, declObj)
            |> Option.flatMap(JsonCodec.expectString)
            |> Option.toOk("${location} に ${key} (文字列) がありません")

    /// 任意の文字列フィールド。
    // WhyNot: 文字列以外が書かれていても Err にせず None に倒す — title / plugin / schema は
    // 飾りの類で、無くても組み込み既定で編集は続けられる。必須の id / pattern だけ厳しくする。
    def optionalString(key: String, declObj: Map[String, Json]): Option[String] =
        Map.get(key, declObj) |> Option.flatMap(JsonCodec.expectString)

    // ── glob 照合 ─────────────────────────────────────────

    /// パターンとパスを 1 文字ずつ照合する。'*' は globStar へ委ねる。
    def globMatch(pattern: List[Char], path: List[Char]): Bool =
        match (pattern, path) {
            case (Nil, Nil)                     => true
            case ('*' :: patternRest, _)        => globStar(patternRest, path)
            case (pc :: patternRest, sc :: pathRest) => pc == sc and globMatch(patternRest, pathRest)
            case _                              => false
        }

    /// '*' に 0 文字以上を食べさせる。'/' は食べない —
    /// "assets/*.json" が別ディレクトリの奥まで拾わないようにするため。
    def globStar(patternRest: List[Char], path: List[Char]): Bool =
        globMatch(patternRest, path) or (match path {
            case Nil            => false
            case c :: pathRest  => c != '/' and globStar(patternRest, pathRest)
        })
}
