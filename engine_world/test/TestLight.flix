// Light の単体テスト: singleLightItems（穴あき暗幕1+周囲黒帯4+ハロ1の6枚）と
// multiLightItems（全面暗幕+ハロN枚の近似）の出力を、Render.draw に通した
// Drawable（record なので match 不要で読める）で個数・blend種別・zIndex・tint を pin する。
mod TestLight {

    def orange(): Color = { r = 1.0f32, g = 0.6f32, b = 0.2f32 }

    def sampleLight(): Light.Light =
        { at = { x = 100.0, y = 80.0 }, radius = 40.0, color = orange(), halo = 0.6 }

    /// テスト用 holeFrac。engine_world は engine_tools（RadialGlow の所属先）に依存できない
    /// ため直接参照できず、値を複製する。RadialGlow.defaultHoleFrac() と揃えておかないと
    /// 実際に焼くテクスチャと maskScale の前提がずれる — 変えたときは両方揃えて直すこと。
    def holeFrac(): Float64 = 0.5

    def sampleDarkness(): Float64 = 0.95

    def singleCfg(): Light.SingleLightConfig =
        { light = sampleLight(), viewport = { x = 320.0, y = 240.0 },
          maskSprite = "glow_mask", maskSourceSize = 512.0, maskHoleFrac = holeFrac(),
          haloSprite = "glow_halo", haloSourceSize = 256.0, darkness = sampleDarkness(), z = 10 }

    // singleLightItems は 7 枚（暗幕1 → 周囲黒帯4 → ハロ1、の 6 枚のはずが実装順は
    // 暗幕 :: 黒帯4 :: ハロ = 6 枚）。
    @Test
    def testSingleLightItemsHasMaskSurroundThenHalo(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        Assert.assertEq(expected = 6, List.length(drawables))

    // 暗幕は Multiply・zIndex=cfg#z・texture=maskSprite・光の位置が中心（centered sprite）・
    // alpha=darkness。
    @Test
    def testSingleLightMaskIsMultiplyAtCfgZ(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        let mask = List.head(drawables);
        Assert.assertEq(
            expected = Some((DrawCmd.BlendMode.Multiply, 10, "glow_mask", 100.0, 80.0, 0.95f32)),
            mask |> Option.map(d -> (d#blend, d#zIndex, d#texture, d#position#x, d#position#y, d#alpha)))

    // ハロは末尾・Add・zIndex=cfg#z+1・texture=haloSprite・tint=light#color・alpha=light#halo。
    // Color はレコードで Eq/ToString を持たないため r/g/b を個別に比較する。
    @Test
    def testSingleLightHaloIsAddWithLightTint(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        let halo = List.last(drawables);
        Assert.assertEq(
            expected = Some((DrawCmd.BlendMode.Add, 11, "glow_halo", 1.0f32, 0.6f32, 0.2f32, 0.6f32)),
            halo |> Option.map(d -> (d#blend, d#zIndex, d#texture, d#color#r, d#color#g, d#color#b, d#alpha)))

    // 暗幕のスケールは「穴の実寸半径=radius」から逆算した倍率のみ（coverage 下限は廃止）。
    // radius=40, holeFrac=0.5, maskSourceSize=512 → 40/(0.5*512/2) = 0.3125。
    // radius が小さくても、この倍率で穴半径がちゃんと radius になる（下の pin テストで確認）。
    @Test
    def testSingleLightMaskScalesFromRadiusOnly(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        let mask = List.head(drawables);
        Assert.assertEq(expected = Some(0.3125), mask |> Option.map(d -> d#scale#x))

    // radius を大きくしても（200）同じ式で線形に伸びる（200/(0.5*512/2) = 1.5625）。
    // coverage 下限が無いので、viewport の大小に関わらず穴半径=radius が常に守られる。
    @Test
    def testSingleLightMaskScalesLinearlyWithRadius(): Unit \ Assert =
        let bigLight = { radius = 200.0 | sampleLight() };
        let cfg = { light = bigLight | singleCfg() };
        let (drawables, _) = Render.draw(Light.singleLightItems(cfg));
        let mask = List.head(drawables);
        Assert.assertEq(expected = Some(1.5625), mask |> Option.map(d -> d#scale#x))

    // 穴の実寸半径 = maskSourceSize × scale × holeFrac / 2 が、どの radius でも radius 自身に
    // 一致する（設計の核心の pin）。
    @Test
    def testSingleLightHoleRadiusMatchesLightRadius(): Unit \ Assert =
        let radii = 10.0 :: 40.0 :: 200.0 :: Nil;
        let holeRadiusOf = r -> {
            let cfg = { light = { radius = r | sampleLight() } | singleCfg() };
            let (drawables, _) = Render.draw(Light.singleLightItems(cfg));
            let scale = List.head(drawables) |> Option.map(d -> d#scale#x) |> Option.getWithDefault(0.0);
            scale * cfg#maskSourceSize * holeFrac() / 2.0
        };
        Assert.assertEq(expected = radii, List.map(holeRadiusOf, radii))

    // 周囲の黒帯4枚（暗幕の次〜ハロの前）は Multiply・cfg#z・alpha=darkness で、
    // mask 正方形と同じ z 帯に隙間なく敷かれる。
    @Test
    def testSingleLightSurroundBoxesAreMultiplyAtCfgZWithDarkness(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        let surround = drawables |> List.drop(1) |> List.take(4);
        let props = surround |> List.map(d -> (d#blend, d#zIndex, d#alpha));
        Assert.assertEq(
            expected = (DrawCmd.BlendMode.Multiply, 10, 0.95f32) :: (DrawCmd.BlendMode.Multiply, 10, 0.95f32)
                :: (DrawCmd.BlendMode.Multiply, 10, 0.95f32) :: (DrawCmd.BlendMode.Multiply, 10, 0.95f32) :: Nil,
            props)

    // ハロのスケールは「光の直径 / haloSourceSize」= 80/256 = 0.3125。
    @Test
    def testSingleLightHaloScalesToLightDiameter(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.singleLightItems(singleCfg()));
        let halo = List.last(drawables);
        Assert.assertEq(expected = Some(0.3125), halo |> Option.map(d -> d#scale#x))

    // ── multiLightItems ──

    def twoLights(): List[Light.Light] =
        sampleLight() :: { at = { x = 200.0, y = 150.0 }, radius = 20.0, color = orange(), halo = 0.4 } :: Nil

    def multiCfg(): Light.MultiLightConfig =
        { lights = twoLights(), darkness = 0.8, viewport = { x = 320.0, y = 240.0 },
          haloSprite = "glow_halo", haloSourceSize = 256.0, z = 5 }

    // 全面暗幕1枚 + 光の数ぶんのハロ（2 光源なら 3 枚）。
    @Test
    def testMultiLightItemsCountsCoverPlusHaloes(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.multiLightItems(multiCfg()));
        Assert.assertEq(expected = 3, List.length(drawables))

    // 全面暗幕は Multiply・zIndex=cfg#z・alpha=darkness・画面全体を覆う矩形（左上が原点）。
    @Test
    def testMultiLightCoverIsMultiplyFullScreen(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.multiLightItems(multiCfg()));
        let cover = List.head(drawables);
        Assert.assertEq(
            expected = Some((DrawCmd.BlendMode.Multiply, 5, 0.8f32, 0.0, 0.0, 320.0, 240.0)),
            cover |> Option.map(d -> (d#blend, d#zIndex, d#alpha, d#position#x, d#position#y, d#scale#x, d#scale#y)))

    // ハロは全て zIndex=cfg#z+1（重なり順に依らず Add で足し合わさるため同じ高さでよい）。
    @Test
    def testMultiLightHaloesShareSameZIndex(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.multiLightItems(multiCfg()));
        let haloZs = List.drop(1, drawables) |> List.map(d -> d#zIndex);
        Assert.assertEq(expected = 6 :: 6 :: Nil, haloZs)

    // 2 つ目のハロは 2 つ目の光の色・強さ・位置を反映する。
    @Test
    def testMultiLightSecondHaloUsesSecondLight(): Unit \ Assert =
        let (drawables, _) = Render.draw(Light.multiLightItems(multiCfg()));
        let second = List.drop(2, drawables) |> List.head;
        Assert.assertEq(
            expected = Some((DrawCmd.BlendMode.Add, 200.0, 150.0, 0.4f32)),
            second |> Option.map(d -> (d#blend, d#position#x, d#position#y, d#alpha)))
}
