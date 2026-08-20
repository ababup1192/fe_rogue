// DrawCmd の構築（make / fromParts）と部分更新（with* 6 本）のテスト。
// Drawable は 20 個の位置引数へ平置きされていて、隣り合う Float64 の取り違えは
// コンパイルが通ってしまう — 全 14 欄が互いに異なる値の spec を 1 個作り、
// 「全欄がそのまま運ばれる」「with* は名指しの欄だけ変わる」を具体値で pin する。
mod TestDrawCmd {

    def baseColor(): Color = { r = 0.1, g = 0.2, b = 0.3 }

    def baseSpec(): DrawCmd.DrawableSpec =
        { texture = "tex",
          position = { x = 1.0, y = 2.0 },
          scale = { x = 3.0, y = 4.0 },
          rotation = 5.0,
          color = baseColor(),
          alpha = 0.5,
          centered = true,
          uvOffset = { x = 6.0, y = 7.0 },
          uvScale = { x = 8.0, y = 9.0 },
          zIndex = 10,
          style = Some({ cornerRadius = 11.0 | DrawCmd.defaultStyle(baseColor()) }),
          clip = Some({ position = { x = 12.0, y = 13.0 }, size = { x = 14.0, y = 15.0 } }),
          blend = DrawCmd.BlendMode.Add,
          mask = (({ x = 16.0, y = 17.0 }: Vec2.Vec2) :: Nil) :: Nil }

    def base(): DrawCmd.Drawable = DrawCmd.make(baseSpec())

    /// 全 14 欄をスカラーへ展開した組（レコードは Eq を持てないため）。
    /// style は cornerRadius を目印に、clip は 4 値、mask は頂点の (x, y) 列で見る。
    def flat(d: DrawCmd.Drawable): ((String, Float64, Float64, Float64, Float64),
                                    (Float64, Float64, Float64, Float64, Float64),
                                    (Bool, Float64, Float64, Float64, Float64, Int32),
                                    (Option[Float64],
                                     Option[(Float64, Float64, Float64, Float64)],
                                     DrawCmd.BlendMode,
                                     List[List[(Float64, Float64)]])) =
        let spec = DrawCmd.toSpec(d);
        ((spec#texture, spec#position#x, spec#position#y, spec#scale#x, spec#scale#y),
         (spec#rotation, spec#color#r, spec#color#g, spec#color#b, spec#alpha),
         (spec#centered, spec#uvOffset#x, spec#uvOffset#y, spec#uvScale#x, spec#uvScale#y, spec#zIndex),
         (spec#style |> Option.map(st -> st#cornerRadius),
          spec#clip |> Option.map(r -> (r#position#x, r#position#y, r#size#x, r#size#y)),
          spec#blend,
          spec#mask |> List.map(poly -> poly |> List.map(v -> (v#x, v#y)))))

    def baseFlat(): ((String, Float64, Float64, Float64, Float64),
                     (Float64, Float64, Float64, Float64, Float64),
                     (Bool, Float64, Float64, Float64, Float64, Int32),
                     (Option[Float64],
                      Option[(Float64, Float64, Float64, Float64)],
                      DrawCmd.BlendMode,
                      List[List[(Float64, Float64)]])) =
        (("tex", 1.0, 2.0, 3.0, 4.0),
         (5.0, 0.1, 0.2, 0.3, 0.5),
         (true, 6.0, 7.0, 8.0, 9.0, 10),
         (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
          ((16.0, 17.0) :: Nil) :: Nil))

    // make(spec) は全 14 欄をそのまま運ぶ（toSpec との往復で欄がずれない）。
    @Test
    def testMakeCarriesAllFields(): Unit \ Assert =
        Assert.assertEq(expected = baseFlat(), flat(base()))

    // fromParts(全引数) は make(spec) と全欄一致する（2 つの構築の入口が同じ並びを書く）。
    @Test
    def testFromPartsMatchesMake(): Unit \ Assert =
        let d = DrawCmd.fromParts(
            "tex", { x = 1.0, y = 2.0 }, { x = 3.0, y = 4.0 },
            5.0, baseColor(), 0.5, true,
            { x = 6.0, y = 7.0 }, { x = 8.0, y = 9.0 }, 10,
            Some({ cornerRadius = 11.0 | DrawCmd.defaultStyle(baseColor()) }),
            Some({ position = { x = 12.0, y = 13.0 }, size = { x = 14.0, y = 15.0 } }),
            DrawCmd.BlendMode.Add,
            (({ x = 16.0, y = 17.0 }: Vec2.Vec2) :: Nil) :: Nil);
        Assert.assertEq(expected = baseFlat(), flat(d))

    // withClip は clip だけ変わり、他の 13 欄は不変。
    @Test
    def testWithClipChangesOnlyClip(): Unit \ Assert =
        let d = DrawCmd.withClip(
            Some({ position = { x = 20.0, y = 21.0 }, size = { x = 22.0, y = 23.0 } }), base());
        Assert.assertEq(
            expected = (("tex", 1.0, 2.0, 3.0, 4.0),
                        (5.0, 0.1, 0.2, 0.3, 0.5),
                        (true, 6.0, 7.0, 8.0, 9.0, 10),
                        (Some(11.0), Some((20.0, 21.0, 22.0, 23.0)), DrawCmd.BlendMode.Add,
                         ((16.0, 17.0) :: Nil) :: Nil)),
            flat(d))

    // withTintAndZIndex は color と zIndex だけ変わり、他の 12 欄は不変。
    @Test
    def testWithTintAndZIndexChangesOnlyColorAndZ(): Unit \ Assert =
        let d = DrawCmd.withTintAndZIndex({ r = 0.6, g = 0.7, b = 0.8 }, 30, base());
        Assert.assertEq(
            expected = (("tex", 1.0, 2.0, 3.0, 4.0),
                        (5.0, 0.6, 0.7, 0.8, 0.5),
                        (true, 6.0, 7.0, 8.0, 9.0, 30),
                        (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
                         ((16.0, 17.0) :: Nil) :: Nil)),
            flat(d))

    // withScale は scale だけ変わり、他の 13 欄は不変。
    @Test
    def testWithScaleChangesOnlyScale(): Unit \ Assert =
        let d = DrawCmd.withScale({ x = 24.0, y = 25.0 }, base());
        Assert.assertEq(
            expected = (("tex", 1.0, 2.0, 24.0, 25.0),
                        (5.0, 0.1, 0.2, 0.3, 0.5),
                        (true, 6.0, 7.0, 8.0, 9.0, 10),
                        (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
                         ((16.0, 17.0) :: Nil) :: Nil)),
            flat(d))

    // withScaleAndMask は scale と mask だけ変わり、他の 12 欄は不変。
    @Test
    def testWithScaleAndMaskChangesOnlyScaleAndMask(): Unit \ Assert =
        let d = DrawCmd.withScaleAndMask({ x = 24.0, y = 25.0 },
            (({ x = 26.0, y = 27.0 }: Vec2.Vec2) :: Nil) :: Nil, base());
        Assert.assertEq(
            expected = (("tex", 1.0, 2.0, 24.0, 25.0),
                        (5.0, 0.1, 0.2, 0.3, 0.5),
                        (true, 6.0, 7.0, 8.0, 9.0, 10),
                        (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
                         ((26.0, 27.0) :: Nil) :: Nil)),
            flat(d))

    // withPositionAndRotation は position と rotation だけ変わり、他の 12 欄は不変。
    @Test
    def testWithPositionAndRotationChangesOnlyPositionAndRotation(): Unit \ Assert =
        let d = DrawCmd.withPositionAndRotation({ x = 28.0, y = 29.0 }, 31.0, base());
        Assert.assertEq(
            expected = (("tex", 28.0, 29.0, 3.0, 4.0),
                        (31.0, 0.1, 0.2, 0.3, 0.5),
                        (true, 6.0, 7.0, 8.0, 9.0, 10),
                        (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
                         ((16.0, 17.0) :: Nil) :: Nil)),
            flat(d))

    // withUv は uvOffset と uvScale だけ変わり、他の 12 欄は不変。
    @Test
    def testWithUvChangesOnlyUv(): Unit \ Assert =
        let d = DrawCmd.withUv({ x = 32.0, y = 33.0 }, { x = 34.0, y = 35.0 }, base());
        Assert.assertEq(
            expected = (("tex", 1.0, 2.0, 3.0, 4.0),
                        (5.0, 0.1, 0.2, 0.3, 0.5),
                        (true, 32.0, 33.0, 34.0, 35.0, 10),
                        (Some(11.0), Some((12.0, 13.0, 14.0, 15.0)), DrawCmd.BlendMode.Add,
                         ((16.0, 17.0) :: Nil) :: Nil)),
            flat(d))
}
