// Mirror（面に映る姿）— テストするのは規約だけ: 面からはみ出した走りの扱い、
// 明るさのしきいで重ね方が変わること、面の外に 1px も出ないこと。
// 映り込みの見た目（濃さ・どこが映るか）はテストしない — 生成した絵の仕事。
mod TestMirror {

    /// 面: (10, 10) から 20×10。
    def glass(): Rect2.Rect2 = { position = { x = 10.0, y = 10.0 }, size = { x = 20.0, y = 10.0 } }

    def style(): Mirror.Style = { alpha = 0.8, lit = 0.5, floor = 0.2, dim = 0.9 }

    /// 走り 1 本（key で色を選べるようにしておく）。
    def span(key: String, x: Float64, y: Float64, w: Float64): PxSprite.Run =
        { x = x, y = y, w = w, h = 1.0, key = key }

    /// 明るさ 0.0 / 0.35 / 1.0 の 3 色（緑を倍に見るので g だけで作れる）。
    def resolver(): String -> Color = key -> match key {
        case "dark" => { r = 0.0f32, g = 0.0f32, b = 0.0f32 }
        case "mid"  => { r = 0.0f32, g = 0.7f32, b = 0.0f32 }
        case _      => { r = 1.0f32, g = 1.0f32, b = 1.0f32 }
    }

    def draw(runs: List[PxSprite.Run]): List[Render.PlacedItem] =
        Mirror.runs({ runs = runs, glass = glass(), style = style(),
                      resolver = resolver(), z = 3 })

    /// 置き場所と幅（レコードは Eq を持たないのでスカラーで比べる）。
    def spanOf(placed: Render.PlacedItem): (Float64, Float64) =
        (placed#at#x, match placed#item {
            case Render.Item.Box(b) => b#size#x
            case _                  => -1.0
        })

    @Test
    def testRunsOutsideTheGlassAreDropped(): Unit \ Assert =
        // 面より上・下の走りは 1 本も返らない（縦は刈らずに丸ごと落とす）。
        let above = span("lit", 12.0, 9.0, 4.0);
        let below = span("lit", 12.0, 21.0, 4.0);
        Assert.assertEq(expected = 0, List.length(draw(above :: below :: Nil)))

    @Test
    def testRunsAreCutAtTheEdgeNotDropped(): Unit \ Assert =
        // 縁をまたいだ走りは面の内側だけが残る。
        // 左（6..12）は面の左端 10 で刈られて 2、右（26..32）は右端 30 で刈られて 4。
        let left = span("lit", 6.0, 12.0, 6.0);
        let right = span("lit", 26.0, 12.0, 6.0);
        Assert.assertEq(expected = ((10.0, 2.0) :: (26.0, 4.0) :: Nil),
            draw(left :: right :: Nil) |> List.map(spanOf))

    @Test
    def testTooDarkIsNotReflected(): Unit \ Assert =
        // floor より暗い色は返らない。しきいの上下を 1 本ずつ。
        Assert.assertEq(expected = (0, 1),
            (List.length(draw(span("dark", 12.0, 12.0, 4.0) :: Nil)),
             List.length(draw(span("mid", 12.0, 12.0, 4.0) :: Nil))))

    @Test
    def testBrightIsAddedAndDarkIsLaidOver(): Unit \ Assert =
        // lit 以上は光として足し（Add）、あいだは向こうを隠す影として重ねる（Normal）。
        let blendOf = placed -> match placed#item {
            case Render.Item.Box(b) => b#blend
            case _                  => DrawCmd.BlendMode.Normal
        };
        Assert.assertEq(expected = (DrawCmd.BlendMode.Add :: Nil, DrawCmd.BlendMode.Normal :: Nil),
            (draw(span("lit", 12.0, 12.0, 4.0) :: Nil) |> List.map(blendOf),
             draw(span("mid", 12.0, 12.0, 4.0) :: Nil) |> List.map(blendOf)))

    @Test
    def testEdgeSliverIsDroppedNotDrawnAsZeroWidth(): Unit \ Assert =
        // 縁にかすっただけ（幅 1px 未満）の走りは、幅 0 の箱を作らずに落とす。
        Assert.assertEq(expected = 0, List.length(draw(span("lit", 29.5, 12.0, 0.4) :: Nil)))
}
