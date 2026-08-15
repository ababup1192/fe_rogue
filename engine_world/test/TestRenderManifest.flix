// RenderManifest（焼いた 1 枚の目録）— 未宣言が id で出ること・申告であることの断りが必ず
// 載ること・下地の色がトップレベルに出ること・写し方によって変わるのは world の長さと
// FirstPerson の 3 欄だけであること。
mod TestRenderManifest {

    def design(): Vec2.Vec2 = { x = 320.0, y = 200.0 }

    def side(): ViewProjection.ViewProjection =
        ViewProjection.side({ design = design(), center = Vec2.zero(), zoom = 100.0 })

    def quarter(): ViewProjection.ViewProjection =
        ViewProjection.quarter({ design = design(), tile = { x = 32.0, y = 16.0 },
                                 rise = 16.0, origin = { x = 160.0, y = 40.0 } })

    def firstPerson(): ViewProjection.ViewProjection =
        ViewProjection.firstPerson({ design = design(),
            camera = ViewProjection.makeCamera({ x = 0.5, y = 0.5 }, Dir4.Dir4.Down),
            persp = { center = { x = 160.0, y = 100.0 }, fx = 192.0, fy = 192.0 },
            near = 0.05 })

    def ink(): Color = { r = 0.0, g = 0.0, b = 1.0 }

    def rock(): RenderManifest.Claim =
        { id = "rock@0", kind = "rock", material = "stone", role = RenderManifest.Role.Prop,
          layer = "mid", zIndex = 44, at = ViewProjection.worldPosAt(3.0, 1.0, 7.5),
          src = "quarry.scene.json#place[7]",
          aabb = { position = { x = 100.0, y = 80.0 }, size = { x = 32.0, y = 24.0 } },
          colors = { r = 0.5, g = 0.5, b = 0.5 } :: Nil,
          intent = "grounded" :: Nil | RenderManifest.blank() }

    /// 何も主張していない物（intent が空）。
    def mystery(): RenderManifest.Claim =
        { id = "blob@0", kind = "blob" | RenderManifest.blank() }

    def render(vp: ViewProjection.ViewProjection, claims: List[RenderManifest.Claim]): String =
        RenderManifest.build({ shot = "probe", projection = vp, background = ink() },
            claims, Map.empty(), Nil)

    @Test
    def testUndeclaredIsNamedNotJustCounted(): Unit \ Assert =
        // intent を書かなかった行は検査が動かない代わりに id で見える（黙らせない・
        // 数だけ出して読む人にどの行かを数えさせない）。
        Assert.assertEq(expected = "blob@0" :: "blob@1" :: Nil,
            RenderManifest.undeclaredIds(
                mystery() :: rock() :: { id = "blob@1" | mystery() } :: Nil))

    @Test
    def testUndeclaredIdsReachTheJson(): Unit \ Assert =
        Assert.assertEq(expected = true,
            String.contains(substr = "\"blob@0\"",
                render(quarter(), rock() :: mystery() :: Nil)))

    @Test
    def testDeclaredNoteIsAlwaysPresent(): Unit \ Assert =
        // aabb / colors が計測でないことの断りは、呼び側が unmeasured を空で渡しても必ず載る。
        Assert.assertEq(expected = true,
            String.contains(substr = "aabb/colors", render(quarter(), rock() :: Nil)))

    @Test
    def testCallerUnmeasuredIsKept(): Unit \ Assert =
        // 呼び側が「測れなかった」を足しても消えない。
        let json = RenderManifest.build(
            { shot = "probe", projection = quarter(), background = ink() }, rock() :: Nil,
            Map.empty(), { check = "sunk", why = "奥へ退く地面では列ごとの表面が 1 つに決まらない" } :: Nil);
        Assert.assertEq(expected = (true, true),
            (String.contains(substr = "sunk", json), String.contains(substr = "aabb/colors", json)))

    @Test
    def testSrcSurvivesSoTheFixIsMechanical(): Unit \ Assert =
        // src が載るから「place[7].x を n へ」と言える。目録の直しの効き目はここで決まる。
        Assert.assertEq(expected = true,
            String.contains(substr = "quarry.scene.json#place[7]", render(quarter(), rock() :: Nil)))

    @Test
    def testBackgroundIsTopLevelNotAPaletteEntry(): Unit \ Assert =
        // 「主役が背景に溶けた」を測るのに要る色。パレットは材質名 → 色の表なので、
        // 下地をそこへ差し込むと存在しない材質が 1 つ増える。
        Assert.assertEq(expected = true,
            String.contains(substr = "\"background\": \"#0000ff\"", render(quarter(), Nil)))

    @Test
    def testHeightSurvivesWhereTheViewUsesIt(): Unit \ Assert =
        // 高さを使う Quarter と FirstPerson では world が [x, y, h] の 3 つ。
        // 高さの軸を持たない Side だけ h（7.5）が落ちる。
        Assert.assertEq(expected = (true, true, false),
            (String.contains(substr = "7.5", render(quarter(), rock() :: Nil)),
             String.contains(substr = "7.5", render(firstPerson(), rock() :: Nil)),
             String.contains(substr = "7.5", render(side(), rock() :: Nil))))

    @Test
    def testFirstPersonAddsTheInverseSubstitutes(): Unit \ Assert =
        // 逆変換が無い写し方では yaw / distance / visible が代わりに生える。
        let json = render(firstPerson(), rock() :: Nil);
        Assert.assertEq(expected = (true, true, true),
            (String.contains(substr = "\"yaw\"", json),
             String.contains(substr = "\"distance\"", json),
             String.contains(substr = "\"visible\"", json)))

    @Test
    def testQuarterHasNoCameraFields(): Unit \ Assert =
        // 逆変換のある写し方には代替の 3 欄を出さない（要らない物を全視点に生やさない）。
        Assert.assertEq(expected = false,
            String.contains(substr = "\"distance\"", render(quarter(), rock() :: Nil)))

    @Test
    def testRoleIsWrittenFromTheClosedVocabulary(): Unit \ Assert =
        // role は 4 つで閉じているので enum。"backdrop" を "background" と打ち間違えられない。
        Assert.assertEq(expected = true,
            String.contains(substr = "\"role\": \"backdrop\"",
                render(quarter(), { role = RenderManifest.Role.Backdrop | rock() } :: Nil)))

    @Test
    def testPaletteIsWrittenAsHex(): Unit \ Assert =
        // 色の表記は Color.toHex に一本化する（同じ色が別の文字列にならない）。
        let json = RenderManifest.build(
            { shot = "probe", projection = quarter(), background = ink() }, Nil,
            Map#{ "stone" => ({ r = 0.0, g = 0.5, b = 1.0 }: Color) }, Nil);
        Assert.assertEq(expected = true, String.contains(substr = "\"stone\": \"#0080ff\"", json))
}
