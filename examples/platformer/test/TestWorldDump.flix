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

    // 画面 1 枚ぶんの矩形（0..480×0..360・カメラ引き後の design）: Track F のレベルは地面が
    // y=416 なので、この空の領域に掛かるのは左の境界壁 198（x=0 に接する・全高）だけ。
    // スポーン（56,392）のプレイヤーは矩形の外。
    @Test
    def testFullRectSeesEverything(): Unit \ Assert =
        let text = dumpOf(fullRect());
        Assert.assertEq(expected = (true, true),
            (String.contains({substr = "\"platformsInRect\":[198]"}, text),
             String.contains({substr = "\"playerInRect\":false"}, text)))

    // セクション 2 の一方通行の棚（行22・列47-50・id 305）だけを囲う小さな矩形なら、
    // その 1 枚だけが載りプレイヤーは外。
    @Test
    def testSmallRectFiltersPlatforms(): Unit \ Assert =
        let rect = { position = { x = 760.0, y = 354.0 }, size = { x = 20.0, y = 8.0 } };
        let text = dumpOf(rect);
        Assert.assertEq(expected = (true, true),
            (String.contains({substr = "\"platformsInRect\":[305]"}, text),
             String.contains({substr = "\"playerInRect\":false"}, text)))
}
