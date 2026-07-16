// Editor — ui.json / hitbox.json エディタの常駐 HTTP サーバ本体。
// ブラウザのエディタ画面 (別オリジン) から fetch で叩くため、全応答に CORS ヘッダを付ける。
// RemoteDebug と違いキュー (Bridge) は使わない: こちらにはゲームループが無く、リクエストの
// 相手 (ファイル) 以外に共有する状態も無いので、ハンドラの中でその場で読んで返せば足りる。
// executor を与えない (null) ので処理は 1 スレッド直列 = 同時リクエストも順番に並ぶ。

mod Editor {
    import java.lang.System
    import java.lang.Thread
    import java.lang.Exception
    import java.net.InetSocketAddress
    import com.sun.net.httpserver.HttpServer
    import com.sun.net.httpserver.HttpHandler
    import com.sun.net.httpserver.HttpExchange
    import java.lang.{String => JavaString}

    use Util.Json.Json
    use Util.Json.Json.{JObject, JString, JNumber, JBool}

    /// /health の version に載せる自分の版 (flix.toml の version と揃える)。
    def version(): String = "0.1.0"

    /// 環境変数 EDITOR_DIR (編集対象のゲームプロジェクト)。未設定・空なら None。
    pub def dirFromEnv(): Option[String] \ IO =
        let value = System.getenv("EDITOR_DIR");
        if (Object.isNull(value) or value == "") None else Some(value)

    /// 環境変数 EDITOR_PORT。未設定・数値でなければ既定の 8787。
    pub def portFromEnv(): Int32 \ IO =
        let value = System.getenv("EDITOR_PORT");
        if (Object.isNull(value)) 8787 else Int32.fromString(value) |> Option.getWithDefault(8787)

    /// 127.0.0.1:port で HTTP サーバを立て、戻らずに待ち続ける。
    pub def serve(dir: String, port: Int32): Unit \ IO =
        let server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        discard server.createContext("/", new HttpHandler {
            def handle(_this: HttpHandler, exchange: HttpExchange): Unit \ IO =
                // 想定外の失敗でもサーバは落とさず、500 の JSON で理由を返して次のリクエストを受け続ける。
                try {
                    dispatch(dir, exchange)
                } catch {
                    case e: Exception => {
                        let message = e.toString();
                        sendJson(500, errorJson("internal error: ${message}"), exchange)
                    }
                }
        });
        server.start();
        println("[editor] serving ${dir} on http://127.0.0.1:${port}");
        waitForever()

    /// main が返ると Flix ランタイムごと終了し得るので、ここで眠り続けてサーバを生かす。
    def waitForever(): Unit \ IO =
        Thread.sleep(60000i64);
        waitForever()

    // ── ルーティング ──────────────────────────────────────

    /// メソッドとパスで各エンドポイントへ振り分ける。
    def dispatch(dir: String, exchange: HttpExchange): Unit \ IO =
        let methodName = exchange.getRequestMethod();
        let uri = exchange.getRequestURI();
        let path = uri.getPath();
        let rawQuery = uri.getQuery();
        let params = queryParams(if (Object.isNull(rawQuery)) "" else rawQuery);
        match (methodName, path) {
            case ("OPTIONS", _)     => sendPreflight(exchange)
            case ("GET", "/health") => handleHealth(dir, exchange)
            case ("GET", "/files")  => handleFiles(dir, exchange)
            case ("GET", "/file")   => handleReadFile(dir, params, exchange)
            case ("PUT", "/file")   => handleWriteFile(dir, readBody(exchange), exchange)
            case ("POST", "/preview/ui") => {
                let (status, json) = PreviewUi.respond(dir, readBody(exchange));
                sendJson(status, json, exchange)
            }
            case ("POST", "/preview/hitbox") => {
                let (status, json) = PreviewHitbox.respond(dir, readBody(exchange));
                sendJson(status, json, exchange)
            }
            case _                  => sendJson(404, errorJson("unknown endpoint: ${methodName} ${path}"), exchange)
        }

    /// GET /health — 対象プロジェクトの題名と設計解像度を返す。エディタ画面の接続確認用。
    /// project.json が読めなくてもサーバは起動継続する (ok: false で理由だけ返す)。
    def handleHealth(dir: String, exchange: HttpExchange): Unit \ IO =
        let loaded = run { ProjectLoader.loadProject(dir) } with Fs.FileRead.runWithIO;
        match loaded {
            case Err(message) => sendJson(200, errorJson(message), exchange)
            case Ok(loadedProject) =>
                let config = loadedProject#config;
                sendJson(200, JObject(Map#{
                    "ok"      => JBool(true),
                    "dir"     => JString(dir),
                    "title"   => JString(config#title),
                    "design"  => JObject(Map#{
                        "w" => JNumber(JsonCodec.intToBd(config#designWidth)),
                        "h" => JNumber(JsonCodec.intToBd(config#designHeight))
                    }),
                    "version" => JString(version())
                }), exchange)
        }

    /// GET /files — 編集対象ファイルの一覧 (ui / hitbox 別) を返す。
    def handleFiles(dir: String, exchange: HttpExchange): Unit \ IO =
        let index = run { FileIndex.listFiles(dir) } with Fs.Glob.runWithIO;
        sendJson(200, JObject(Map#{
            "root"   => JString(dir),
            "ui"     => JsonCodec.encodeList(p -> JString(p), index#ui),
            "hitbox" => JsonCodec.encodeList(p -> JString(p), index#hitbox)
        }), exchange)

    /// GET /file?path=... — dir 相対パスのファイル内容を返す。無い・プロジェクト外は 404。
    def handleReadFile(dir: String, params: Map[String, String], exchange: HttpExchange): Unit \ IO =
        match Map.get("path", params) {
            case None => sendJson(400, errorJson("missing query parameter: path"), exchange)
            case Some(relPath) => match FileIndex.readInside(dir, relPath) {
                case Err(message) => sendJson(404, errorJson(message), exchange)
                case Ok(content)  => sendJson(200, JObject(Map#{
                    "path"    => JString(relPath),
                    "content" => JString(content)
                }), exchange)
            }
        }

    /// PUT /file (body: {path, content}) — dir 相対パスへ書き込む。
    /// プロジェクト外・親ディレクトリ不在は拒否する。
    def handleWriteFile(dir: String, bodyText: String, exchange: HttpExchange): Unit \ IO =
        let fields = JsonCompat.parse(bodyText)
            |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(obj -> forM (
                relPath <- Map.get("path", obj) |> Option.flatMap(JsonCodec.expectString);
                content <- Map.get("content", obj) |> Option.flatMap(JsonCodec.expectString)
            ) yield (relPath, content));
        match fields {
            case None => sendJson(400, errorJson("body must be a JSON object {path, content}"), exchange)
            case Some((relPath, content)) => match FileIndex.writeInside(str = content, dir, relPath) {
                case Err(message) => sendJson(400, errorJson(message), exchange)
                case Ok(_)        => sendJson(200, JObject(Map#{"ok" => JBool(true)}), exchange)
            }
        }

    // ── HTTP の細部 ───────────────────────────────────────

    /// リクエストボディを UTF-8 文字列で読む。
    def readBody(exchange: HttpExchange): String \ IO =
        let requestBody = exchange.getRequestBody();
        new JavaString(requestBody.readAllBytes(), "UTF-8")

    /// "a=1&b=2" を Map にする。URL エンコードは扱わない
    /// (対象ファイルのパスは英数と ./_- だけの想定で、崩れたキーは単に不一致で 404 に落ちる)。
    def queryParams(text: String): Map[String, String] =
        if (text == "") Map.empty()
        else String.splitOn(substr = "&", text)
             |> List.filterMap(pair -> match String.splitOn(substr = "=", pair) {
                 case key :: value :: Nil => Some((key, value))
                 case _                   => None
             })
             |> List.toMap

    /// OPTIONS 全パス — ブラウザの事前確認 (CORS preflight) に 204 で答える。
    def sendPreflight(exchange: HttpExchange): Unit \ IO =
        let headers = exchange.getResponseHeaders();
        headers.set("Access-Control-Allow-Origin", "*");
        headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS");
        headers.set("Access-Control-Allow-Headers", "Content-Type");
        headers.set("Access-Control-Max-Age", "86400");
        exchange.sendResponseHeaders(204, -1i64);
        exchange.close()

    /// JSON 応答を返す。別オリジンのエディタ画面から読めるよう、全応答に CORS ヘッダを付ける。
    def sendJson(status: Int32, json: Json, exchange: HttpExchange): Unit \ IO =
        let headers = exchange.getResponseHeaders();
        headers.set("Access-Control-Allow-Origin", "*");
        headers.set("Content-Type", "application/json; charset=utf-8");
        let bytes = (Util.Json.toPrettyString(2, json) + "\n").getBytes("UTF-8");
        exchange.sendResponseHeaders(status, Int32.toInt64(Array.length(bytes)));
        let out = exchange.getResponseBody();
        out.write(bytes);
        out.close()

    /// 失敗応答の本文 {ok: false, error}。
    def errorJson(message: String): Json =
        JObject(Map#{"ok" => JBool(false), "error" => JString(message)})
}
