// PxSpriteAtlas / PxSprite.drawQuad のテスト。テストするのはルールだけ:
// 「棚詰めの座標規約(左→右・折り返し・1px 隙間・溢れ=None)」「region の目次」
// 「画素 = legend×resolver(未定義文字は透明)」「drawQuad の置き場所規約(anchor/flipX)が
// box 列(runs)と同じ画素範囲を被覆する」。絵そのもの(色の見た目)はテストしない。

mod TestPxSpriteAtlas {

    def doc(): PxSpriteDoc.Doc =
        PxSpriteDoc.fromJson(String.unlines(
            "{" ::
            "  \"legend\": { \"a\": \"body\", \"b\": \"hair\" }," ::
            "  \"sprites\": {" ::
            "    \"guy\": {" ::
            "      \"anchor\": { \"x\": 1.0, \"y\": 2.0 }," ::
            "      \"frames\": {" ::
            "        \"f0\": [ \".aa.\", \"aaaa\", \"b.b.\" ]," ::
            "        \"f1\": [ \"ab\" ]" ::
            "      }" ::
            "    }" ::
            "  }" ::
            "}" :: Nil))
            |> Option.getWithDefault(PxSpriteDoc.empty())

    def red(): Color = { r = 1.0, g = 0.0, b = 0.0 }
    def blue(): Color = { r = 0.0, g = 0.0, b = 1.0 }

    def resolver(key: String): Color =
        if (key == "body") red() else blue()

    // ── shelfPack ──

    /// 左→右に 1px 隙間で詰め、行に収まらなければ「行の最大高 + 1」下へ折り返す。
    @Test
    def testShelfPackPlacesLeftToRightAndWraps(): Unit \ Assert =
        let items = ("a", (4, 3)) :: ("b", (3, 2)) :: ("c", (4, 2)) :: Nil;
        // side=10: a=(0,0), b=(5,0), c は 5+3+1+4=13 > 10 で折り返し → (0, 3+1=4)。
        Assert.assertEq(expected = Some(Map#{"a" => (0, 0), "b" => (5, 0), "c" => (0, 4)}),
            PxSpriteAtlas.shelfPack(10, items))

    /// 縦に溢れたら None(呼び手が辺長を広げる)。
    @Test
    def testShelfPackOverflowIsNone(): Unit \ Assert =
        Assert.assertEq(expected = None,
            PxSpriteAtlas.shelfPack(4, ("a", (4, 3)) :: ("b", (4, 3)) :: Nil))

    /// 辺長の候補の最大(2048)より広い 1 コマだけを持つ Doc。
    def oversizedDoc(): PxSpriteDoc.Doc =
        { version = 1, note = None,
          legend = Map#{'a' => "body"},
          sprites = Map#{"wide" =>
              { anchor = { x = 0.0, y = 0.0 },
                frames = Map#{"f0" => String.repeat(3000, "a") :: Nil} }} }

    // ── bake ──

    /// どの辺長にも詰められない Doc は bakeChecked が Err(既定値を使うかは呼び側が決める)。
    @Test
    def testBakeCheckedFailsWhenFrameExceedsLargestSide(): Unit \ Assert =
        Assert.assertEq(expected = true,
            PxSpriteAtlas.bakeChecked(oversizedDoc(), resolver) |> Result.isErr)

    /// 全コマが詰められる Doc では bakeChecked が Ok で、bake と同じ辺長になる。
    @Test
    def testBakeCheckedIsOkForFittingDoc(): Unit \ Assert =
        Assert.assertEq(expected = Ok(16),
            PxSpriteAtlas.bakeChecked(doc(), resolver) |> Result.map(baked -> baked#side))

    /// regions は全コマを持ち、寸法は格子どおり(f0 = 4×3, f1 = 2×1)。
    @Test
    def testBakeRegionsFollowGridSize(): Unit \ Assert =
        let baked = PxSpriteAtlas.bake(doc(), resolver);
        let dims = key -> Map.get(key, baked#regions)
            |> Option.map(r -> (r#w, r#h));
        Assert.assertEq(expected = (Some((4, 3)), Some((2, 1)), 16),
            (dims(("guy", "f0")), dims(("guy", "f1")), baked#side))

    /// 画素: 'a' は resolver(body)=赤・'b' は resolver(hair)=青・'.' は透明(ARGB 0)。
    @Test
    def testBakePixelsResolveLegend(): Unit \ Assert =
        let baked = PxSpriteAtlas.bake(doc(), resolver);
        match Map.get(("guy", "f0"), baked#regions) {
            case None    => Assert.assertEq(expected = true, false)
            case Some(r) =>
                // f0 の行 0 = ".aa." → (0,0)=透明, (1,0)=赤。行 2 = "b.b." → (0,2)=青。
                Assert.assertEq(expected =
                    (0, PxSpriteAtlas.argbOf(red()), PxSpriteAtlas.argbOf(blue())),
                    (PxSpriteAtlas.pixelAt(baked, r#x, r#y),
                     PxSpriteAtlas.pixelAt(baked, r#x + 1, r#y),
                     PxSpriteAtlas.pixelAt(baked, r#x, r#y + 2)))
        }

    /// argbOf の丸めは SoftRaster.byteOf と同じ round(0.5 切り上げ)・不透明。
    @Test
    def testArgbOfRounds(): Unit \ Assert =
        // 0.5 → 127.5+0.5 = 128。
        let c: Color = { r = 0.5, g = 0.0, b = 1.0 };
        let p = PxSpriteAtlas.argbOf(c);
        let ch = shift -> Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, p), 255);
        Assert.assertEq(expected = (255, 128, 0, 255), (ch(24), ch(16), ch(8), ch(0)))

    // ── drawQuad(置き場所規約が box 列と一致)──

    /// クアッドの被覆範囲 = box 列(runs)の外接矩形と同じ式:
    /// 非反転は [at - ax·s, at + (w-ax)·s)、flipX は [at - (w-1-ax)·s, at + (ax+1)·s)。
    @Test
    def testDrawQuadCoversSameRectAsRuns(): Unit \ Assert =
        let d = doc();
        let baked = PxSpriteAtlas.bake(d, resolver);
        let at: Vec2.Vec2 = { x = 100.0, y = 50.0 };
        let s = 3;
        let quadRect = flip -> match PxSprite.drawQuad(d, baked, "px", "guy", "f0", at, flip, s, 7) {
            case placed :: Nil => match placed#item {
                case Render.Item.Sprite(sp) =>
                    // 表示寸法 = side × scale(Drawable 規約)。flipH は左へ伸びる。
                    let wPx = sp#scale#x * Int32.toFloat64(baked#side);
                    let hPx = sp#scale#y * Int32.toFloat64(baked#side);
                    if (sp#flipH)
                        Some((placed#at#x - wPx, placed#at#y, wPx, hPx))
                    else
                        Some((placed#at#x, placed#at#y, wPx, hPx))
                case _ => None
            }
            case _ => None
        };
        // anchor = (1,2)・格子 4×3・s=3: 非反転左上 = (100-3, 50-6)、
        // flipX 左上 = (100 - (4-1-1)*3, 50-6) = (94, 44)。幅 12・高 9。
        Assert.assertEq(expected =
            (Some((97.0, 44.0, 12.0, 9.0)), Some((94.0, 44.0, 12.0, 9.0))),
            (quadRect(false), quadRect(true)))

    /// 無いスプライト・無いコマ・scale 0 は何も描かない(fail-open)。
    @Test
    def testDrawQuadFailOpen(): Unit \ Assert =
        let d = doc();
        let baked = PxSpriteAtlas.bake(d, resolver);
        let at: Vec2.Vec2 = { x = 0.0, y = 0.0 };
        Assert.assertEq(expected = (0, 0, 0),
            (List.length(PxSprite.drawQuad(d, baked, "px", "nope", "f0", at, false, 1, 0)),
             List.length(PxSprite.drawQuad(d, baked, "px", "guy", "nope", at, false, 1, 0)),
             List.length(PxSprite.drawQuad(d, baked, "px", "guy", "f0", at, false, 0, 0))))
}
