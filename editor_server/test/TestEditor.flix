// TestEditor — CORS の Origin 判定を固定する。ヘッダの付け外しそのもの (HTTP) は
// curl での通し確認に任せ、ここでは「どの Origin をエコーするか」の判定だけを見る。

mod TestEditor {

    /// 許可リストにある Origin はそのままエコー (Some)。無い Origin と、
    /// Origin ヘッダ自体が無い curl 等は None = CORS ヘッダを付けない。
    @Test
    def testCorsOriginFor(): Unit \ Assert =
        let allowList = "http://localhost:5173" :: "http://127.0.0.1:5173" :: Nil;
        Assert.assertEq(
            expected = (Some("http://localhost:5173"), (None: Option[String]), (None: Option[String])),
            (Editor.corsOriginFor(Some("http://localhost:5173"), allowList),
             Editor.corsOriginFor(Some("https://evil.example"), allowList),
             Editor.corsOriginFor(None, allowList)))

    /// EDITOR_ALLOW_ORIGINS はカンマ区切り。前後の空白と空要素は捨てる。
    @Test
    def testSplitOrigins(): Unit \ Assert =
        Assert.assertEq(
            expected = "http://localhost:3000" :: "http://myhost:5173" :: Nil,
            Editor.splitOrigins(" http://localhost:3000, http://myhost:5173 ,"))

    // ══ 静的配信 (ビルド済みエディタ画面) ══════════════════

    /// URL パス → 配信ルート相対の写し方: "/" は index.html、通常パスは先頭の "/" を
    /// 外すだけ。上へ出る `..` 入りと、先頭を外しても "/" で始まる "//…" は None で弾く。
    @Test
    def testStaticRelPath(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some("index.html"), Some("assets/app.js"),
                        (None: Option[String]), (None: Option[String])),
            (Editor.staticRelPath("/"),
             Editor.staticRelPath("/assets/app.js"),
             Editor.staticRelPath("/../etc/passwd"),
             Editor.staticRelPath("//etc/passwd")))

    /// Content-Type は拡張子で決める。知らない拡張子は octet-stream に倒す。
    @Test
    def testContentTypeOf(): Unit \ Assert =
        Assert.assertEq(
            expected = "text/html; charset=utf-8" :: "text/javascript; charset=utf-8"
                    :: "text/css; charset=utf-8" :: "image/svg+xml" :: "image/png"
                    :: "font/woff2" :: "application/json; charset=utf-8"
                    :: "application/octet-stream" :: Nil,
            List.map(Editor.contentTypeOf,
                "index.html" :: "assets/app.js" :: "assets/app.css" :: "icon.svg"
                :: "img.png" :: "font.woff2" :: "data.json" :: "file.bin" :: Nil))
}
