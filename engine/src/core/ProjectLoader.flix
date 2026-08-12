// ProjectLoader — project.json を読み込んで engine 起動用の設定 + scene ファイル列挙を提供する。
//
// project.json は engine / examples が共通で読む唯一の真実 (single source of truth)。
// engine（契約層）に置くことで、バックエンド（render_gl）やゲームのどこからも import できる。
//
// スキーマ (engine の `GameEngine.EngineConfig` と完全一致):
//
//   {
//     "title": String,
//     "designWidth": Int, "designHeight": Int,
//     "windowWidth": Int, "windowHeight": Int,
//     "clearColor": {"r": Float, "g": Float, "b": Float},
//     "maxDeltaTime": Float,
//     "textures": [{"name": String, "path": String, "hasAlpha": Bool}, ...],
//     "fonts":    [{"name": String, "path": String, "fontSize": Float}, ...],
//     "sounds":   [{"name": String, "path": String, "looping": Bool}, ...],
//     "mainScene": String   // project root からの相対パス (engine では現状未使用)
//   }
//
// 画像・フォント・サウンドのパスは project root からの相対で記述する。
// IDE は (Java 起動時の) CWD と無関係に動かしたいため、rootDir + relative の絶対パス
// 文字列に書き換えてから返す。examples は CWD = project root で動くので rootDir = "." を
// 渡す慣習。

mod ProjectLoader {
    use Util.Json.Json.{JObject, JArray, JString, JNumber, JBool}

    /// project.json から組み立てた、engine 起動に渡すための設定。
    /// shape は engine の `GameEngine.EngineConfig` と完全一致させてあり、
    /// Flix の structural record により `LwjglLayer.withLwjgl` 等にそのまま渡せる。
    /// project.json に任意キー `windowScale`(>0) があれば、windowWidth/windowHeight より
    /// 優先して window = design × scale をロード時に解決する（buildProject 参照）。
    pub type alias ProjectConfig = {
        rootDir         = String,
        glyphs          = String,
        designWidth     = Int32,
        designHeight    = Int32,
        windowWidth     = Int32,
        windowHeight    = Int32,
        title           = String,
        textureManifest = List[{name = String, path = String, hasAlpha = Bool}],
        fontManifest    = List[{name = String, path = String, fontSize = Float64}],
        soundManifest   = List[{name = String, path = String, looping = Bool}],
        clearColor      = Color,
        maxDeltaTime    = Float64
    }

    /// 読み込み結果。シーンは別途 `findSceneFiles` で列挙する。
    pub type alias Project = {
        rootDir = String,
        config  = ProjectConfig
    }

    /// project.json を読んで Project を組み立てる。
    /// 読み込み/JSON パース失敗時は Err(message) を返す (呼び出し側が dialog 表示・終了などを決める)。
    /// JSON 中の型不一致など内部構造のエラーは依然 bug! でクラッシュする
    /// (= 不正な project.json は開発者が直すべきもの)。
    pub def loadProject(rootDir: String): Result[String, Project] \ {Fs.FileRead} =
        let projectJsonPath = joinPath(rootDir, "project.json");
        let readResult = run { Fs.ReadFile.read(projectJsonPath) }
            with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => Err("Failed to read ${projectJsonPath}: ${e}")
            case Ok(content) =>
                match (Util.Json.parse(String.trim(content)) |> Result.toOption) {
                    case None    => Err("JSON parse failed: ${projectJsonPath}")
                    case Some(j) => Ok(buildProject(rootDir, j))
                }
        }

    def buildProject(rootDir: String, json: Util.Json.Json): Project =
        let root = matchObject(json, "root");
        let title       = getString(root, "title");
        let designW     = getInt(root, "designWidth");
        let designH     = getInt(root, "designHeight");
        // glyphs（任意）: 起動時にどの字を生成するか。
        //   "auto"（既定）… 起動時は生成せず、出た字から順に生成する。起動が一番速い
        //   "used"         … ソースとアセットに書いてある字を先に生成する。最初の画面で引っかからない
        //   "all"          … フォントが持つ字を全部。日本語だと数十秒かかる
        // どれでも、足りない字は出そうとしたときに追加生成される（消えることはない）。
        let glyphs = match Map.get("glyphs", root) {
            case Some(JString(g)) => g
            case _                => "auto"
        };
        // windowScale（任意）: あれば window = design × scale をロード時に解決し、
        // windowWidth/windowHeight より優先する。アスペクト比を design に合わせたまま
        // ウィンドウだけ拡大したいとき用（見た目そのままで画面を大きくする）。
        let scaleOpt = match Map.get("windowScale", root) {
            case Some(JNumber(n)) => Some(n.doubleValue())
            case _                => None
        };
        let (windowW, windowH) = match scaleOpt {
            case Some(s) if s > 0.0 =>
                (Float64.tryToInt32(Float64.round(Int32.toFloat64(designW) * s)) |> Option.getWithDefault(designW),
                 Float64.tryToInt32(Float64.round(Int32.toFloat64(designH) * s)) |> Option.getWithDefault(designH))
            case _ => (getInt(root, "windowWidth"), getInt(root, "windowHeight"))
        };
        let clearColor  = readColor(getField(root, "clearColor"));
        let maxDelta    = getFloat(root, "maxDeltaTime");
        let textures    = readTextures(rootDir, getField(root, "textures"));
        let fonts       = readFonts(rootDir, getField(root, "fonts"));
        let sounds      = readSounds(rootDir, getField(root, "sounds"));
        let config: ProjectConfig = {
            rootDir         = rootDir,
            glyphs          = glyphs,
            designWidth     = designW,
            designHeight    = designH,
            windowWidth     = windowW,
            windowHeight    = windowH,
            title           = title,
            textureManifest = textures,
            fontManifest    = fonts,
            soundManifest   = sounds,
            clearColor      = clearColor,
            maxDeltaTime    = maxDelta
        };
        { rootDir = rootDir, config = config }

    // ========================================================================

    /// プロジェクトディレクトリを再帰的に走査して *.scene.json を列挙する。
    /// 返るパスは rootDir からの相対形 ("src/scenes/MenuScene.scene.json" 等)。
    /// IDE 側はこれを scene リストに表示し、クリックで loadScene に渡す。
    pub def findSceneFiles(rootDir: String): List[String] \ Fs.Glob =
        Fs.Glob.glob(rootDir, "**/*.scene.json")
            |> Result.getWithDefault(Nil)
            |> List.map(absPath ->
                // glob は絶対パス or rootDir 相対で返すので、rootDir プレフィックスを剥がす
                if (String.startsWith({prefix = rootDir + "/"}, absPath))
                    absPath.substring(String.length(rootDir) + 1)
                else if (String.startsWith({prefix = rootDir}, absPath))
                    absPath.substring(String.length(rootDir))
                else
                    absPath
            )

    // ========================================================================
    // JSON 抽出ヘルパー
    // ========================================================================

    def matchObject(elem: Util.Json.Json, ctx: String): Map[String, Util.Json.Json] =
        match elem {
            case JObject(m) => m
            case _             => bug!("ProjectLoader: ${ctx} is not a JSON object")
        }

    def getField(map: Map[String, Util.Json.Json], key: String): Util.Json.Json =
        match Map.get(key, map) {
            case Some(v) => v
            case None    => bug!("ProjectLoader: missing key '${key}' in project.json")
        }

    def getString(map: Map[String, Util.Json.Json], key: String): String =
        match getField(map, key) {
            case JString(s) => s
            case _             => bug!("ProjectLoader: '${key}' is not a string")
        }

    def getInt(map: Map[String, Util.Json.Json], key: String): Int32 =
        match getField(map, key) {
            case JNumber(n) => n.intValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getFloat(map: Map[String, Util.Json.Json], key: String): Float64 =
        match getField(map, key) {
            case JNumber(n) => n.doubleValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getFloat32(map: Map[String, Util.Json.Json], key: String): Float32 =
        match getField(map, key) {
            case JNumber(n) => n.floatValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getBool(map: Map[String, Util.Json.Json], key: String): Bool =
        match getField(map, key) {
            case JBool(b) => b
            case _           => bug!("ProjectLoader: '${key}' is not a boolean")
        }

    def readColor(elem: Util.Json.Json): Color =
        let m = matchObject(elem, "clearColor");
        { r = getFloat32(m, "r"), g = getFloat32(m, "g"), b = getFloat32(m, "b") }

    def readTextures(rootDir: String, elem: Util.Json.Json):
                       List[{name = String, path = String, hasAlpha = Bool}] =
        match elem {
            case JArray(v) =>
                Vector.toList(v) |> List.map(item ->
                    let m = matchObject(item, "texture entry");
                    {
                        name     = getString(m, "name"),
                        path     = joinPath(rootDir, getString(m, "path")),
                        hasAlpha = getBool(m, "hasAlpha")
                    }
                )
            case _ => bug!("ProjectLoader: 'textures' is not an array")
        }

    def readFonts(rootDir: String, elem: Util.Json.Json):
                    List[{name = String, path = String, fontSize = Float64}] =
        match elem {
            case JArray(v) =>
                Vector.toList(v) |> List.map(item ->
                    let m = matchObject(item, "font entry");
                    {
                        name     = getString(m, "name"),
                        path     = joinPath(rootDir, getString(m, "path")),
                        fontSize = getFloat(m, "fontSize")
                    }
                )
            case _ => bug!("ProjectLoader: 'fonts' is not an array")
        }

    def readSounds(rootDir: String, elem: Util.Json.Json):
                     List[{name = String, path = String, looping = Bool}] =
        match elem {
            case JArray(v) =>
                Vector.toList(v) |> List.map(item ->
                    let m = matchObject(item, "sound entry");
                    {
                        name    = getString(m, "name"),
                        path    = joinPath(rootDir, getString(m, "path")),
                        looping = getBool(m, "looping")
                    }
                )
            case _ => bug!("ProjectLoader: 'sounds' is not an array")
        }

    /// パスを単純連結する (rootDir + "/" + relative)。
    /// 末尾スラッシュの重複は除去する。絶対パス化は OS の File.toAbsolutePath などに
    /// 委ねず、CWD ベースのパスで loadTexture/loadScene が動く前提。
    def joinPath(dir: String, rel: String): String =
        if (String.endsWith({suffix = "/"}, dir))
            "${dir}${rel}"
        else
            "${dir}/${rel}"
}
