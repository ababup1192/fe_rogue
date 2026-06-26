// 共有 lib Render の単体テスト — RenderItem → Drawable 射影。
// Drawable/Vec2/Color レコード丸ごとの assertEq は ToString 不在で不可なので、スカラフィールドのみ assert。

mod TestRender {

    def red(): Color = {r = 1.0f32, g = 0.0f32, b = 0.0f32}

    def testFontAtlas(): FontAtlas = {
        textureName = "font_test", fontSize = 32.0, textureSize = 512.0,
        ascent = 0.0, descent = 0.0, lineGap = 0.0, glyphs = Map.empty()
    }

    def firstOf(ds: List[GameEngine.Drawable]): GameEngine.Drawable =
        List.head(ds) |> Option.getWithDefault(
            { texture = "?", position = {x = 0.0, y = 0.0}, scale = {x = 0.0, y = 0.0},
              rotation = 0.0, color = red(), alpha = 0.0f32, centered = false,
              uvOffset = {x = 0.0, y = 0.0}, uvScale = {x = 0.0, y = 0.0}, zIndex = 0, style = None })

    /// sprite: texture/zIndex/centered と flip→scale 符号。
    @Test
    def testSprite(): Unit \ Assert =
        let d = firstOf(Render.toDrawables(Render.sprite("hero", 5i32, true, false), {x = 1.0, y = 2.0}));
        Assert.assertEq(expected = true,
            d#texture == "hero" and d#zIndex == 5i32 and d#centered == true and
            d#scale#x == -1.0 and d#scale#y == 1.0)   // flipH=true→x負、flipV=false→y正

    /// solidBox: texture=""・centered=false・size=scale・zIndex・style=Some。
    @Test
    def testBox(): Unit \ Assert =
        let d = firstOf(Render.toDrawables(Render.solidBox({x = 40.0, y = 30.0}, red(), 100i32), {x = 5.0, y = 6.0}));
        Assert.assertEq(expected = true,
            d#texture == "" and d#centered == false and d#zIndex == 100i32 and
            d#scale#x == 40.0 and d#scale#y == 30.0 and Option.nonEmpty(d#style))

    /// draw: 複数アイテム（sprite + box）を順に Drawable 化＝個数 2。
    @Test
    def testDrawCollectsItems(): Unit \ Assert =
        let items = ({x = 0.0, y = 0.0}, Render.sprite("a", 0i32, false, false)) ::
                    ({x = 10.0, y = 10.0}, Render.solidBox({x = 5.0, y = 5.0}, red(), 2i32)) :: Nil;
        Assert.assertEq(expected = 2, List.length(Render.draw(items)))

    /// ボタン = Box+Text の2アイテム。先頭は box（texture=""）。text は空グリフ atlas で 0 個でも box は出る。
    @Test
    def testButtonBoxFirst(): Unit \ Assert =
        let items = ({x = 0.0, y = 0.0}, Render.solidBox({x = 80.0, y = 36.0}, red(), 100i32)) ::
                    ({x = 12.0, y = 4.0}, Render.text("Start", testFontAtlas(), 24.0, 100i32)) :: Nil;
        let ds = Render.draw(items);
        Assert.assertEq(expected = true, List.length(ds) >= 1 and firstOf(ds)#texture == "")
}
