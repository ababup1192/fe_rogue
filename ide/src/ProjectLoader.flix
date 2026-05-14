// ProjectLoader — project.json を読み込んで GameEngine.EngineConfig を組み立てる。
//
// project.json は IDE が読む manifest で、ゲーム側 (examples/*/src/Main.flix) は
// 関知しない。スキーマはゲームの Main.flix のハードコード config と同等:
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
//     "mainScene": String   // project root からの相対パス
//   }
//
// 画像・フォント・サウンドのパスは project root からの相対で記述する。
// IDE は (Java 起動時の) CWD と無関係に動かしたいため、ProjectLoader 内で
// `rootDir + relative` の絶対パス文字列に書き換えてから EngineConfig に詰める。

mod ProjectLoader {
    use Json.JsonElement.{JsonObject, JsonArray, JsonString, JsonNumber, JsonBool}

    /// 読み込み結果。`mainScenePath` は絶対パス (rootDir + manifest の "mainScene")。
    pub type alias Project = {
        rootDir       = String,
        config        = GameEngine.EngineConfig,
        mainScenePath = String
    }

    /// project.json を読んで Project を組み立てる。失敗時は bug! でクラッシュ。
    /// `rootDir` は project.json があるディレクトリの相対 or 絶対パス。
    pub def loadProject(rootDir: String): Project \ {Fs.FileRead} =
        let projectJsonPath = joinPath(rootDir, "project.json");
        let readResult = run { Fs.ReadFile.read(projectJsonPath) }
            with Fs.ReadFile.runWithFileRead;
        let content = match readResult {
            case Ok(s)  => s
            case Err(e) => bug!("ProjectLoader: failed to read ${projectJsonPath}: ${e}")
        };
        let json = match Json.Parse.parse(String.trim(content)) {
            case Some(j) => j
            case None    => bug!("ProjectLoader: JSON parse failed for ${projectJsonPath}")
        };
        let root = matchObject(json, "root");
        let title       = getString(root, "title");
        let designW     = getInt(root, "designWidth");
        let designH     = getInt(root, "designHeight");
        let windowW     = getInt(root, "windowWidth");
        let windowH     = getInt(root, "windowHeight");
        let clearColor  = readColor(getField(root, "clearColor"));
        let maxDelta    = getFloat(root, "maxDeltaTime");
        let textures    = readTextures(rootDir, getField(root, "textures"));
        let fonts       = readFonts(rootDir, getField(root, "fonts"));
        let sounds      = readSounds(rootDir, getField(root, "sounds"));
        let mainScene   = getString(root, "mainScene");
        let config: GameEngine.EngineConfig = {
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
        {
            rootDir       = rootDir,
            config        = config,
            mainScenePath = joinPath(rootDir, mainScene)
        }

    // ========================================================================
    // JSON 抽出ヘルパー
    // ========================================================================

    def matchObject(elem: Json.JsonElement, ctx: String): Map[String, Json.JsonElement] =
        match elem {
            case JsonObject(m) => m
            case _             => bug!("ProjectLoader: ${ctx} is not a JSON object")
        }

    def getField(map: Map[String, Json.JsonElement], key: String): Json.JsonElement =
        match Map.get(key, map) {
            case Some(v) => v
            case None    => bug!("ProjectLoader: missing key '${key}' in project.json")
        }

    def getString(map: Map[String, Json.JsonElement], key: String): String =
        match getField(map, key) {
            case JsonString(s) => s
            case _             => bug!("ProjectLoader: '${key}' is not a string")
        }

    def getInt(map: Map[String, Json.JsonElement], key: String): Int32 =
        match getField(map, key) {
            case JsonNumber(n) => n.intValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getFloat(map: Map[String, Json.JsonElement], key: String): Float64 =
        match getField(map, key) {
            case JsonNumber(n) => n.doubleValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getFloat32(map: Map[String, Json.JsonElement], key: String): Float32 =
        match getField(map, key) {
            case JsonNumber(n) => n.floatValue()
            case _             => bug!("ProjectLoader: '${key}' is not a number")
        }

    def getBool(map: Map[String, Json.JsonElement], key: String): Bool =
        match getField(map, key) {
            case JsonBool(b) => b
            case _           => bug!("ProjectLoader: '${key}' is not a boolean")
        }

    def readColor(elem: Json.JsonElement): Color =
        let m = matchObject(elem, "clearColor");
        { r = getFloat32(m, "r"), g = getFloat32(m, "g"), b = getFloat32(m, "b") }

    def readTextures(rootDir: String, elem: Json.JsonElement): List[GameEngine.TextureEntry] =
        match elem {
            case JsonArray(v) =>
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

    def readFonts(rootDir: String, elem: Json.JsonElement): List[GameEngine.FontEntry] =
        match elem {
            case JsonArray(v) =>
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

    def readSounds(rootDir: String, elem: Json.JsonElement): List[GameEngine.AudioEntry] =
        match elem {
            case JsonArray(v) =>
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
