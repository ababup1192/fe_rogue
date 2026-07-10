// RemoteDebug — 起動中のゲームを外部プロセス（AI エージェント等）が HTTP で操作・観測する口。
// curl 一発で「キー入力の台本を N フレーム実行して、結果の状態を受け取る」が完結する。
// デバッグ専用: App の debug が有効かつ環境変数 DEBUG_HTTP_PORT があるときだけ立ち上がる。
//
// スレッドの約束: HTTP のスレッドは World に一切触れない。リクエストの生文字列をキューへ
// 積んで応答文字列を待つだけで、パース・実行・応答の組み立てはすべてゲームループ側
// （App）が行う。ゲームが応答しなければ 10 秒で 503 を返す。

mod RemoteDebug {
    import java.lang.System
    import java.net.InetSocketAddress
    import com.sun.net.httpserver.HttpServer
    import com.sun.net.httpserver.HttpHandler
    import com.sun.net.httpserver.HttpExchange
    import java.util.concurrent.{LinkedBlockingQueue => JQueue}
    import java.util.concurrent.TimeUnit
    import java.lang.{String => JString}

    // ── HTTP スレッドとゲームループを繋ぐ橋 ──

    /// HTTP サーバ本体と、リクエスト / レスポンスを受け渡す 2 本のキュー。
    pub type alias Bridge = {
        server = HttpServer,           // 稼働中のサーバ（終了時に stop する）
        requests = JQueue[String],     // HTTP → ゲームループ（"METHOD /path?query\n台本" の生文字列）
        responses = JQueue[String]     // ゲームループ → HTTP（text/plain の応答本文）
    }

    /// 環境変数 DEBUG_HTTP_PORT からポート番号を読む。未設定・数値でなければ None。
    pub def portFromEnv(): Option[Int32] \ IO =
        let value = System.getenv("DEBUG_HTTP_PORT");
        if (Object.isNull(value)) None else Int32.fromString(value)

    /// 127.0.0.1 の port で HTTP サーバを立てて Bridge を返す。
    /// ハンドラはリクエストを 1 つの文字列に畳んでキューへ積み、応答を最大 10 秒待つ。
    /// executor を与えない（null）ので処理は 1 スレッド直列 = 同時リクエストも順番に並ぶ。
    pub def start(port: Int32): Bridge \ IO =
        let requests: JQueue[String] = new JQueue();
        let responses: JQueue[String] = new JQueue();
        let server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        discard server.createContext("/", new HttpHandler {
            def handle(_this: HttpHandler, exchange: HttpExchange): Unit \ IO = {
                let uri = exchange.getRequestURI();
                let rawQuery = uri.getQuery();
                let queryPart = if (Object.isNull(rawQuery)) "" else "?" + rawQuery;
                let requestBody = exchange.getRequestBody();
                let bodyText = new JString(requestBody.readAllBytes(), "UTF-8");
                let methodName = exchange.getRequestMethod();
                let path = uri.getPath();
                discard requests.offer("${methodName} ${path}${queryPart}\n${bodyText}");
                let answer = responses.poll(10i64, TimeUnit.SECONDS);
                let timedOut = Object.isNull(answer);
                let text = if (timedOut) "error: game loop did not answer within 10s\n" else answer;
                let headers = exchange.getResponseHeaders();
                headers.set("Content-Type", "text/plain; charset=utf-8");
                let bytes = text.getBytes("UTF-8");
                exchange.sendResponseHeaders(if (timedOut) 503 else 200, Int32.toInt64(Array.length(bytes)));
                let out = exchange.getResponseBody();
                out.write(bytes);
                out.close()
            }
        });
        server.start();
        println("[remote-debug] listening on http://127.0.0.1:${port} (GET /help)");
        { server = server, requests = requests, responses = responses }

    /// ゲームループが毎フレーム呼ぶ非ブロッキングの受信。届いていなければ None。
    pub def pollRequest(bridge: Bridge): Option[String] \ IO =
        let queue = bridge#requests;
        let raw = queue.poll();
        if (Object.isNull(raw)) None else Some(raw)

    /// 応答本文を HTTP スレッドへ返す（pollRequest で受けた 1 件に必ず 1 回対で呼ぶ）。
    pub def respond(text: String, bridge: Bridge): Unit \ IO =
        let queue = bridge#responses;
        discard queue.offer(text)

    /// サーバを止める（ゲーム終了時）。待機中のリクエストは切断される。
    pub def shutdown(bridge: Bridge): Unit \ IO =
        let server = bridge#server;
        server.stop(0)

    // ── リクエストのパース（ここから下は純関数）──

    /// パース済みリクエスト。1 行目が "METHOD /path?query"、2 行目以降がボディ（台本 DSL）。
    pub type alias Request = {
        method = String,             // "GET" / "POST"
        path = String,               // "/step" など
        params = Map[String, String], // クエリパラメータ（view=status 等）。query は Flix 予約語
        body = String                // ボディ（/step の台本）
    }

    /// Bridge から受けた生文字列をリクエストへ分解する。
    pub def parseRequest(raw: String): Request =
        let (headLine, bodyLines) = match String.lines(raw) {
            case first :: rest => (first, rest)
            case Nil           => ("", Nil)
        };
        let (methodName, url) = match String.words(headLine) {
            case m :: u :: _ => (m, u)
            case _           => ("", "")
        };
        let (path, queryText) = match String.splitOn({substr = "?"}, url) {
            case p :: q :: _ => (p, q)
            case p :: Nil    => (p, "")
            case Nil         => ("", "")
        };
        { method = methodName, path = path, params = parseQuery(queryText),
          body = bodyLines |> String.intercalate("\n") }

    /// "a=1&b=2" を Map へ。値に = を含む形や URL エンコードは扱わない（このプロトコルでは不要）。
    def parseQuery(text: String): Map[String, String] =
        if (text == "") Map.empty()
        else String.splitOn({substr = "&"}, text)
             |> List.filterMap(pair -> match String.splitOn({substr = "="}, pair) {
                 case key :: value :: Nil => Some((key, value))
                 case _                   => None
             })
             |> List.toMap

    // ── /step・/state のパラメータ ──

    /// 観測の詳細度。応答のトークン量を必要最小限に抑えるための選択肢。
    pub enum View with Eq, ToString {
        case Status,  // 1 行サマリ（App.withStatusLine）
        case Summary, // 数行サマリ（当面 Status と同じ。ゲームの statusLine が複数行なら差が出る）
        case Full,    // ゲーム定義の worldDump（App.withWorldDump）
        case Scene,   // 描画物の一覧（配線不要のフォールバック観測）
        case Silent   // 本文なし（イベントとヘッダだけ欲しいとき）
    }

    /// /step を台本の途中で止める条件。「意味のある瞬間」で止まることで往復を減らす。
    pub enum Until with Eq, ToString {
        case Always,               // 止めない（台本を最後まで実行）
        case SfxAny,               // 何か音が鳴ったら止まる
        case SfxNamed(Set[String]), // 指定した名前の音が鳴ったら止まる
        case Quiet(Int32)          // N フレーム連続で無音になったら止まる（演出待ちに）
    }

    /// /step・/state のクエリを解釈した実行パラメータ。
    pub type alias StepParams = {
        view = View,                 // 応答に載せる観測の詳細度
        rect = Option[Rect2.Rect2],  // full / scene の関心矩形（デザイン座標。None = 全画面）
        stopWhen = Until,            // 早期停止の条件
        maxFrames = Int32,           // 1 リクエストで実行するフレーム数の上限
        traceEvery = Option[Int32],  // K フレームごとに statusLine を応答へ 1 行足す
        dtSeconds = Float64          // 合成フレーム 1 コマの経過秒（既定 1/60。診断用に変更可）
    }

    /// クエリ Map を StepParams へ。不正な値は理由つきの Err（応答にそのまま載せる）。
    pub def parseParams(queryMap: Map[String, String]): Result[String, StepParams] =
        forM (
            view <- parseView(Map.getWithDefault("view", "status", queryMap));
            rect <- parseRect(Map.get("rect", queryMap));
            stopWhen <- parseUntil(Map.get("until", queryMap));
            maxFrames <- parseMax(Map.get("max", queryMap));
            traceEvery <- parseTrace(Map.get("trace", queryMap));
            dtSeconds <- parseDt(Map.get("dt", queryMap))
        ) yield { view = view, rect = rect, stopWhen = stopWhen,
                  maxFrames = maxFrames, traceEvery = traceEvery, dtSeconds = dtSeconds }

    def parseView(name: String): Result[String, View] =
        match String.toLowerCase(name) {
            case "status"  => Ok(View.Status)
            case "summary" => Ok(View.Summary)
            case "full"    => Ok(View.Full)
            case "scene"   => Ok(View.Scene)
            case "none"    => Ok(View.Silent)
            case other     => Err("error: unknown view '${other}' (status|summary|full|scene|none)")
        }

    def parseRect(text: Option[String]): Result[String, Option[Rect2.Rect2]] =
        match text {
            case None => Ok(None)
            case Some(spec) =>
                match String.splitOn({substr = ","}, spec) |> List.filterMap(Float64.fromString) {
                    case x :: y :: w :: h :: Nil =>
                        Ok(Some({ position = { x = x, y = y }, size = { x = w, y = h } }))
                    case _ => Err("error: rect must be 'x,y,w,h' (got '${spec}')")
                }
        }

    def parseUntil(text: Option[String]): Result[String, Until] =
        match text |> Option.map(String.splitOn({substr = ":"})) {
            case None                          => Ok(Until.Always)
            case Some("sfx" :: "any" :: Nil)   => Ok(Until.SfxAny)
            case Some("sfx" :: names :: Nil)   =>
                Ok(Until.SfxNamed(String.splitOn({substr = ","}, names) |> List.toSet))
            case Some("quiet" :: count :: Nil) =>
                match Int32.fromString(count) {
                    case Some(n) if n > 0 => Ok(Until.Quiet(n))
                    case _                => Err("error: until=quiet:N needs a positive N (got '${count}')")
                }
            case Some(_) => Err("error: until must be 'sfx:any' / 'sfx:name1,name2' / 'quiet:N'")
        }

    def parseMax(text: Option[String]): Result[String, Int32] =
        match text {
            case None => Ok(1200)
            case Some(spec) => match Int32.fromString(spec) {
                case Some(n) if n >= 1 and n <= frameCap() => Ok(n)
                case _ => Err("error: max must be 1..${frameCap()} (got '${spec}')")
            }
        }

    def parseTrace(text: Option[String]): Result[String, Option[Int32]] =
        match text |> Option.map(String.splitOn({substr = ":"})) {
            case None => Ok(None)
            case Some("status" :: every :: Nil) => match Int32.fromString(every) {
                case Some(k) if k > 0 => Ok(Some(k))
                case _                => Err("error: trace=status:K needs a positive K")
            }
            case Some(_) => Err("error: trace must be 'status:K'")
        }

    def parseDt(text: Option[String]): Result[String, Float64] =
        match text {
            case None => Ok(1.0 / 60.0)
            case Some(spec) => match Float64.fromString(spec) {
                case Some(ms) if ms >= 0.1 and ms <= 100.0 => Ok(ms / 1000.0)
                case _ => Err("error: dt is milliseconds in 0.1..100 (got '${spec}')")
            }
        }

    /// 1 リクエストで実行できる合成フレーム数の天井（60fps で 1 分ぶん）。
    pub def frameCap(): Int32 = 3600

    /// until 条件の 1 フレームぶんの判定。このフレームで鳴った音名と「無音が何フレーム
    /// 続いているか」から、(停止理由, 新しい無音連続数) を返す。停止理由 "" = 続行。
    pub def stopCheck(stopWhen: Until, soundsThisFrame: List[String], quietRun: Int32): (String, Int32) =
        match stopWhen {
            case Until.Always => ("", 0)
            case Until.SfxAny =>
                (if (List.isEmpty(soundsThisFrame)) "" else "until:sfx", 0)
            case Until.SfxNamed(names) =>
                (if (List.exists(name -> Set.memberOf(name, names), soundsThisFrame)) "until:sfx" else "", 0)
            case Until.Quiet(need) =>
                let quietNow = if (List.isEmpty(soundsThisFrame)) quietRun + 1 else 0;
                (if (quietNow >= need) "until:quiet" else "", quietNow)
        }

    // ── 台本 DSL のパース ──

    /// 台本 1 コマ = そのフレームで押しているキーの集合。リストの並びがフレームの並び。
    pub type alias Script = List[Set[GameEngine.Key]]

    /// 台本 DSL を 1 フレーム 1 コマのキー集合列へ展開する。# 以降はコメント。
    ///   idle N          … 何も押さないフレームを N 個
    ///   press K         … K を 1 フレーム押して 1 フレーム離す（1 押下 = 1 発火）
    ///   hold K N        … K を N フレーム押しっぱなし
    ///   hold K1,K2 N    … 同時押しで N フレーム
    pub def parseScript(body: String): Result[String, Script] =
        String.lines(body)
        |> List.map(line -> stripComment(line) |> String.trim)
        |> List.filter(line -> line != "")
        |> parseScriptLines

    def parseScriptLines(lines: List[String]): Result[String, Script] =
        match lines {
            case Nil => Ok(Nil)
            case line :: rest =>
                forM (frames <- parseScriptLine(line); tail <- parseScriptLines(rest))
                    yield List.append(frames, tail)
        }

    def parseScriptLine(line: String): Result[String, Script] =
        match String.words(line) {
            case "idle" :: count :: Nil =>
                forM (n <- parseCount(count)) yield List.repeat(n, Set.empty())
            case "press" :: keys :: Nil =>
                forM (keySet <- parseKeys(keys)) yield keySet :: Set.empty() :: Nil
            case "hold" :: keys :: count :: Nil =>
                forM (keySet <- parseKeys(keys); n <- parseCount(count))
                    yield List.repeat(n, keySet)
            case _ => Err("error: cannot parse script line '${line}' (idle N / press K / hold K N)")
        }

    def parseCount(text: String): Result[String, Int32] =
        match Int32.fromString(text) {
            case Some(n) if n >= 1 and n <= frameCap() => Ok(n)
            case _ => Err("error: frame count must be 1..${frameCap()} (got '${text}')")
        }

    def parseKeys(text: String): Result[String, Set[GameEngine.Key]] =
        String.splitOn({substr = ","}, text)
        |> List.foldLeft((acc, name) -> forM (
               keySet <- acc;
               key <- keyOf(name) |> Option.toOk("error: unknown key '${name}' (${keyNames()})")
           ) yield Set.insert(key, keySet), Ok(Set.empty()))

    /// "z" や "Enter" のようなキー名を Key へ（大文字小文字は区別しない）。
    pub def keyOf(name: String): Option[GameEngine.Key] =
        GameEngine.allKeys()
        |> List.find(key -> String.toLowerCase("${key}") == String.toLowerCase(name))

    /// 台本で使える全キー名（help と unknown key エラーに載せる）。
    pub def keyNames(): String =
        GameEngine.allKeys() |> List.map(key -> "${key}") |> String.intercalate(",")

    def stripComment(line: String): String =
        match String.indexOfLeft({substr = "#"}, line) {
            case Some(i) => String.takeLeft(i, line)
            case None    => line
        }

    // ── 応答の整形 ──

    /// /step 応答の 1 行目。何フレーム進んで何故止まったかを 1 行で伝える。
    pub def stepHeader(info: { stepped = Int32, total = Int32, frame = Int64,
                               stoppedBy = String, quit = Bool }): String =
        "ok stepped=${info#stepped} frame=${info#frame} mode=halted"
        + " stopped=${info#stoppedBy} consumed=${info#stepped}/${info#total}"
        + (if (info#quit) " quit=true" else "")
        + "\n"

    /// 実行中に鳴った音のブロック。「f=フレーム番号 sfx=音名」の行を時系列で並べる。
    /// 音はフレーム間に何が起きたか（衝突・ミス・フェーズ遷移）を伝える主要な観測チャンネル。
    pub def eventsBlock(sounds: List[(Int64, String)]): String =
        if (List.isEmpty(sounds)) ""
        else "[events]\n" + (sounds
             |> List.map(pair -> { let (frameNo, name) = pair; "f=${frameNo} sfx=${name}" })
             |> String.intercalate("\n")) + "\n"

    /// trace=status:K で集めた status 行のブロック。
    pub def traceBlock(lines: List[String]): String =
        if (List.isEmpty(lines)) ""
        else "[trace]\n" + String.intercalate("\n", lines) + "\n"

    /// scene ビューの本文。矩形に重なる描画物を z 順に 1 行ずつ（多すぎる場合は打ち切る）。
    /// worldDump が未配線のゲームでも、何がどこに描かれているかはこれで観測できる。
    pub def sceneBlock(rect: Rect2.Rect2, hitList: List[Annotate.Hit]): String =
        let sorted = hitList |> List.sortBy(hit -> hit#zIndex);
        let total = List.length(sorted);
        let capped = List.take(sceneLimit(), sorted);
        let header = "[scene] rect=(${fmt1(rect#position#x)},${fmt1(rect#position#y)},"
                   + "${fmt1(rect#size#x)},${fmt1(rect#size#y)}) items=${total}";
        let lines = capped |> List.map(sceneLine);
        let extra = if (total > sceneLimit()) ("(+${total - sceneLimit()} more)" :: Nil) else Nil;
        (header :: List.append(lines, extra)) |> String.intercalate("\n")

    /// scene 1 行に載せる描画物の上限（トークン量の安全弁）。
    def sceneLimit(): Int32 = 80

    def sceneLine(hit: Annotate.Hit): String =
        let label = if (hit#name == "") hit#kind else "${hit#kind} ${hit#name}";
        "${label} pos=(${fmt1(hit#position#x)},${fmt1(hit#position#y)})"
        + " size=(${fmt1(hit#aabb#size#x)},${fmt1(hit#aabb#size#y)}) z=${hit#zIndex}"

    /// 小数第 1 位までに丸めた表示（座標の長い小数でトークンを浪費しないため）。
    pub def fmt1(value: Float64): String =
        "${Float64.round(value * 10.0) / 10.0}"

    /// view=full の本文の安全弁。矩形無指定の worldDump は数万文字になり得る
    /// （fe_rogue 全画面で実測 80KB）ので、超過分を打ち切って rect= の指定を促す。
    pub def capBody(text: String): String =
        let limit = 8192;
        if (String.length(text) <= limit) text
        else String.takeLeft(limit, text)
             + "\n...(truncated ${String.length(text) - limit} chars; pass rect=x,y,w,h to narrow)"

    /// GET /help の本文。プロトコルの自己記述（セッション冒頭に 1 回読む想定）。
    pub def helpText(): String =
        "remote debug protocol (all responses are text/plain)\n"
        + "\n"
        + "GET  /help                    this text\n"
        + "GET  /state?view=&rect=       observe without advancing\n"
        + "POST /halt                    pause the game (lockstep mode)\n"
        + "POST /resume                  resume realtime play\n"
        + "POST /step?view=&rect=&until=&max=&trace=&dt=\n"
        + "     body = input script; runs it frame by frame, then answers.\n"
        + "     auto-halts first if the game is running.\n"
        + "\n"
        + "script DSL (one command per line, # comments):\n"
        + "  idle N        wait N frames\n"
        + "  press K       tap key K (1 frame down + 1 frame up)\n"
        + "  hold K N      hold key K for N frames\n"
        + "  hold K1,K2 N  hold keys together for N frames\n"
        + "keys: " + keyNames() + "\n"
        + "\n"
        + "query params:\n"
        + "  view=status|summary|full|scene|none   response detail (default status)\n"
        + "  rect=x,y,w,h   design-space rect for full/scene (default whole screen)\n"
        + "  until=sfx:any | sfx:name1,name2 | quiet:N   stop early on sound events\n"
        + "  max=N          frame cap for this request (default 1200, max ${frameCap()})\n"
        + "  trace=status:K append a status line every K frames\n"
        + "  dt=MS          per-frame delta time in ms (default 16.67; diagnostics only)\n"
        + "\n"
        + "response: header line, then [events] (sounds with frame numbers),\n"
        + "[trace] if requested, and the view block ([status]/[full]/[scene]).\n"
}
