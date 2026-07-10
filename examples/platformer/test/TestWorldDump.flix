// TestWorldDump — world.json の本文が組めて、調べたいものが載っていることを pin する。
// （実際のチケット化・HTTP 応答は App/RemoteDebug の仕事。ここは純粋な本文だけを見る）

mod TestWorldDump {

    /// 本文から空白と改行を落とす（pretty-print の整形に依存せず中身だけを比べる）。
    def dumpOf(rect: Rect2.Rect2): String =
        WorldDump.dump(rect, Field.initialWorld())
        |> String.replace(src = " ", dst = "")
        |> String.replace(src = "\n", dst = "")

    def fullRect(): Rect2.Rect2 =
        { position = Vec2.zero(), size = { x = Field.designW(), y = Field.designH() } }

    // 運動学・パラメータ・地形・出来事ログの各セクションが載る。
    @Test
    def testDumpHasSections(): Unit \ Assert =
        let text = dumpOf(fullRect());
        Assert.assertEq(expected = (true, true, true, true, true),
            (String.contains({substr = "\"player\""}, text),
             String.contains({substr = "\"params\""}, text),
             String.contains({substr = "\"platforms\""}, text),
             String.contains({substr = "\"eventLog\""}, text),
             String.contains({substr = "\"coyoteLeft\""}, text)))

    // 画面全体の矩形なら地形 6 枚（地面+浮き床3+壁2）が全部 rect に掛かり、プレイヤーも中に居る。
    @Test
    def testFullRectSeesEverything(): Unit \ Assert =
        let text = dumpOf(fullRect());
        Assert.assertEq(expected = (true, true),
            (String.contains({substr = "\"platformsInRect\":[100,101,102,103,110,111]"}, text),
             String.contains({substr = "\"playerInRect\":true"}, text)))

    // 右上の小さな矩形（浮き床 2 だけの場所）なら、その 1 枚だけが載りプレイヤーは外。
    @Test
    def testSmallRectFiltersPlatforms(): Unit \ Assert =
        let rect = { position = { x = 190.0, y = 110.0 }, size = { x = 30.0, y = 15.0 } };
        let text = dumpOf(rect);
        Assert.assertEq(expected = (true, true),
            (String.contains({substr = "\"platformsInRect\":[102]"}, text),
             String.contains({substr = "\"playerInRect\":false"}, text)))
}
