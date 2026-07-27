// BakeService — 焼く仕事を持ったプロセスを常駐させ、頼まれたら呼ぶだけの器。
//
// なぜ要るか: 焼き直しの待ち時間のほとんどは「毎回コンパイルして JVM を起こす」時間で、
// 焼く処理そのものは短い。立ち上げっぱなしにすれば、その待ちが 1 回だけになる。
// エディタは「この値で焼いて」と頼み、焼けた物をその場で受け取れる。
//
// **何を焼くかは知らない**。音でも絵でも、handle が全部決める。
// だからこの器は特定の作り方（合成の方式・Doc の形）に肩入れしない。
//
// 焼くのはゲーム自身のコードなので、**実機と同じ物が出る**。エディタ側に焼く処理の
// 写しを置くと、そちらが古びたときに黙って食い違う。
//
// スレッドの約束: 応答は HTTP のスレッドがそのまま組む（守るべきゲームループが無いため）。
// executor を与えないので処理は 1 本ずつ直列に進む。
mod BakeService {
    import java.lang.System
    import java.lang.Exception
    import java.lang.Thread
    import java.net.InetSocketAddress
    import com.sun.net.httpserver.HttpServer
    import com.sun.net.httpserver.HttpHandler
    import com.sun.net.httpserver.HttpExchange
    import java.util.concurrent.atomic.AtomicLong
    import java.lang.{String => JString}

    /// 1 件ぶんの頼まれごと。params はクエリ（query は Flix の予約語なので使えない）。
    pub type alias Request = {
        method = String,
        path = String,
        params = Map[String, String],
        body = String
    }

    /// 返す物。body はバイト列なので、WAV でも PNG でも JSON でも返せる。
    pub type alias Reply = {
        status = Int32,
        contentType = String,
        body = Array[Int8, Static]
    }

    /// 文字列の応答（JSON・エラー文言）。
    pub def textReply(status: Int32, contentType: String, body: String): Reply \ IO =
        { status = status, contentType = contentType, body = body.getBytes("UTF-8") }

    pub def jsonReply(status: Int32, body: String): Reply \ IO =
        textReply(status, "application/json; charset=utf-8", body)

    /// バイト列の応答（焼けた WAV など）。
    pub def bytesReply(contentType: String, body: Array[Int8, Static]): Reply =
        { status = 200, contentType = contentType, body = body }

    /// 環境変数 BAKE_PORT から待ち受けるポートを読む。未設定・数値でなければ None。
    pub def portFromEnv(): Option[Int32] \ IO =
        let value = System.getenv("BAKE_PORT");
        if (Object.isNull(value)) None else Int32.fromString(value)

    /// 放置されたら自分から終わるまでの秒数。編集していない間にメモリを抱えたままに
    /// しないための約束（次に頼まれたときはエディタが立ち上げ直す）。
    pub def idleSecondsFromEnv(): Int64 =
        600i64

    /// port で待ち受けて、頼まれるたびに handle を呼ぶ。
    /// idleSeconds のあいだ何も頼まれなければ自分から終わる（戻る）。
    pub def serve(port: Int32, idleSeconds: Int64,
                  onRequest: Request -> Reply \ IO): Unit \ IO =
        let lastSeen = new AtomicLong(System.currentTimeMillis());
        let server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        discard server.createContext("/", new HttpHandler {
            def handle(_this: HttpHandler, exchange: HttpExchange): Unit \ IO = {
                discard lastSeen.getAndSet(System.currentTimeMillis());
                let reply = answer(onRequest, exchange);
                let headers = exchange.getResponseHeaders();
                headers.set("Content-Type", reply#contentType);
                exchange.sendResponseHeaders(reply#status,
                    Int32.toInt64(Array.length(reply#body)));
                let out = exchange.getResponseBody();
                out.write(reply#body);
                out.close()
            }
        });
        server.start();
        // 立ち上げに使ったコンパイラの残骸をここで手放す。常駐する以上、
        // 掃除の機会が来ないまま数百 MB を抱え続けてしまう（実測 1.8GB → 38MB）。
        System.gc();
        println("[bake-service] listening on http://127.0.0.1:${port}");
        waitUntilIdle(lastSeen, idleSeconds);
        server.stop(0);
        println("[bake-service] idle for ${idleSeconds}s — 終了します")

    /// 頼まれごとを組んで handle に渡す。handle が落ちても器は落とさない
    /// （1 件の失敗で常駐が死ぬと、次の頼みごとが 10 秒の立ち上げからやり直しになる）。
    def answer(onRequest: Request -> Reply \ IO, exchange: HttpExchange): Reply \ IO =
        try {
            let uri = exchange.getRequestURI();
            let rawQuery = uri.getQuery();
            let params = if (Object.isNull(rawQuery)) Map.empty() else parseParams(rawQuery);
            let bodyText = new JString(exchange.getRequestBody().readAllBytes(), "UTF-8");
            onRequest({ method = exchange.getRequestMethod(), path = uri.getPath(),
                        params = params, body = bodyText })
        } catch {
            case e: Exception =>
                textReply(500, "text/plain; charset=utf-8", "bake failed: ${e.getMessage()}")
        }

    /// "a=1&b=2" → 表。値の中の + は空白へ戻す（フォーム形式の最小限だけ）。
    pub def parseParams(raw: String): Map[String, String] =
        String.split(regex = "&", raw)
            |> List.filterMap(pair -> match String.split(regex = "=", pair) {
                case k :: v :: Nil => Some((k, String.replace(src = "+", dst = " ", v)))
                case k :: Nil      => if (k == "") None else Some((k, ""))
                case _             => None
            })
            |> List.toMap

    /// 最後に頼まれてから idleSeconds 経つまで待つ（5 秒ごとに見る）。
    def waitUntilIdle(lastSeen: AtomicLong, idleSeconds: Int64): Unit \ IO =
        Thread.sleep(5000i64);
        let quiet = (System.currentTimeMillis() - lastSeen.get()) / 1000i64;
        if (quiet >= idleSeconds) ()
        else waitUntilIdle(lastSeen, idleSeconds)
}
