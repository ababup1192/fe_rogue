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
}
