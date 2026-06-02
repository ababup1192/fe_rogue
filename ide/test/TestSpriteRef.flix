// Tests for SpritePreview.extractSpriteRefHere — Resources タブ preview の
// sprite 切り抜きに使う情報抽出ロジックの単体テスト
//
// extractSpriteRefHere は純粋関数なので、手作りの Json.JsonElement Map で
// 直接テストできる。検証の観点:
//   - sprite ブロック (texture + frame + hframes + vframes) を持つ object から
//     SpriteRef が抽出できるか
//   - texture だけの bare object でも SpriteRef が作られ、frame 系は None になるか
//   - textureNames に含まれない texture 文字列は無視され None が返るか
//   - frame 等が整数でない場合は None として扱われるか
//   - findFirstSpriteRef がネストした構造を DFS で辿って取り出せるか

mod TestSpriteRef {

    /// SpriteRef の Option フィールドを assertEq で比べやすい形に直す。
    /// Option[Int32] のタプルにすると 1 assert にまとめられる。
    def asTuple(spriteRefOpt: Option[SpritePreview.SpriteRef]):
            Option[(String, Option[Int32], Option[Int32], Option[Int32])] =
        spriteRefOpt |> Option.map(sr -> (sr#texture, sr#frame, sr#hframes, sr#vframes))

    // ========================================================================
    // extractSpriteRefHere — 単一 object 内の texture + sibling 抽出
    // ========================================================================

    /// sprite ブロック相当の object からすべてのフィールドが揃った SpriteRef が
    /// 抽出される。units.json の archer (frame=1, hframes=5, vframes=2) と同じ形。
    @Test
    def testExtractFullSpriteBlock(): Unit \ Assert =
        let m = Map#{
            "texture" => Json.JsonElement.JsonString("character_sheet"),
            "frame"   => Json.JsonElement.JsonNumber(1.0ff),
            "hframes" => Json.JsonElement.JsonNumber(5.0ff),
            "vframes" => Json.JsonElement.JsonNumber(2.0ff)
        };
        Assert.assertEq(
            expected = Some(("character_sheet", Some(1i32), Some(5i32), Some(2i32))),
            asTuple(SpritePreview.extractSpriteRefHere(m, Set#{"character_sheet"})))

    /// texture 文字列だけが入った bare object でも SpriteRef は作られるが、
    /// frame/hframes/vframes は None になる。updateSpritePreview 側の
    /// フォールバック (1, 1, 0) で全体表示になる経路。
    @Test
    def testExtractBareTextureNoSiblings(): Unit \ Assert =
        let m = Map#{
            "texture" => Json.JsonElement.JsonString("character_sheet")
        };
        Assert.assertEq(
            expected = Some(("character_sheet", (None: Option[Int32]),
                             (None: Option[Int32]), (None: Option[Int32]))),
            asTuple(SpritePreview.extractSpriteRefHere(m, Set#{"character_sheet"})))

    /// textureNames に登録されていない texture 文字列は無視され、抽出は None。
    /// (texture 候補が他になければ object として preview 対象外)
    @Test
    def testExtractUnregisteredTextureReturnsNone(): Unit \ Assert =
        let m = Map#{
            "texture" => Json.JsonElement.JsonString("character_sheet"),
            "frame"   => Json.JsonElement.JsonNumber(1.0ff)
        };
        Assert.assertEq(
            expected = (None: Option[(String, Option[Int32], Option[Int32], Option[Int32])]),
            asTuple(SpritePreview.extractSpriteRefHere(m, Set#{"other_atlas"})))

    /// frame が文字列など整数で表現できない場合は frame=None として扱う。
    /// (object 自体は texture を持つので SpriteRef は返るが、preview は全体表示に
    /// フォールバックする)
    @Test
    def testExtractInvalidFrameTypeBecomesNone(): Unit \ Assert =
        let m = Map#{
            "texture" => Json.JsonElement.JsonString("character_sheet"),
            "frame"   => Json.JsonElement.JsonString("not-a-number"),
            "hframes" => Json.JsonElement.JsonNumber(5.0ff),
            "vframes" => Json.JsonElement.JsonNumber(2.0ff)
        };
        Assert.assertEq(
            expected = Some(("character_sheet", (None: Option[Int32]),
                             Some(5i32), Some(2i32))),
            asTuple(SpritePreview.extractSpriteRefHere(m, Set#{"character_sheet"})))

    // ========================================================================
    // findFirstSpriteRef — DFS でネストを掘って最初に見つかった sprite 情報を返す
    // ========================================================================

    /// units.json の archer record と同じ構造 (top-level に attack/hp/sprite を
    /// 並べたもの) から sprite ブロックを掘り出して SpriteRef を返せる。
    ///
    /// 入力構造:
    ///   { attack: 5, defense: 2, hp: 8, moveTiles: 6, speed: 6,
    ///     sprite: { frame: 1, hframes: 5, texture: "character_sheet", vframes: 2 } }
    ///
    /// 期待:
    ///   Some(SpriteRef{texture="character_sheet", frame=Some(1),
    ///                   hframes=Some(5), vframes=Some(2)})
    @Test
    def testFindFirstSpriteRefNested(): Unit \ Assert =
        let sprite = Json.JsonElement.JsonObject(Map#{
            "frame"   => Json.JsonElement.JsonNumber(1.0ff),
            "hframes" => Json.JsonElement.JsonNumber(5.0ff),
            "texture" => Json.JsonElement.JsonString("character_sheet"),
            "vframes" => Json.JsonElement.JsonNumber(2.0ff)
        });
        let record = Json.JsonElement.JsonObject(Map#{
            "attack"    => Json.JsonElement.JsonNumber(5.0ff),
            "defense"   => Json.JsonElement.JsonNumber(2.0ff),
            "hp"        => Json.JsonElement.JsonNumber(8.0ff),
            "moveTiles" => Json.JsonElement.JsonNumber(6.0ff),
            "speed"     => Json.JsonElement.JsonNumber(6.0ff),
            "sprite"    => sprite
        });
        Assert.assertEq(
            expected = Some(("character_sheet", Some(1i32), Some(5i32), Some(2i32))),
            asTuple(SpritePreview.findFirstSpriteRef(record, "character_sheet" :: Nil)))

    // ========================================================================
    // pinchZoom — Preview のピンチズーム動作（連続値）
    // ========================================================================

    /// 連続するピンチイン factor を 100% から乗算したときの最終倍率。
    /// 1.05 を 5 回 ≒ 1.276 → 127.628%（クランプ無し）
    @Test
    def testPinchZoomAccumulates(): Unit \ Assert =
        let s0 = PropertyWidgets.ZoomMode.Percent(100.0);
        let s1 = PropertyWidgets.pinchZoom(s0, 1.05);
        let s2 = PropertyWidgets.pinchZoom(s1, 1.05);
        let actual = match s2 {
            case PropertyWidgets.ZoomMode.Percent(p) => p
        };
        // 100 * 1.05 * 1.05 = 110.25
        Assert.assertEq(expected = true, Float64.abs(actual - 110.25) < 0.001)

    /// 上限クランプ: 1600% を超える factor を渡しても 1600% にクランプされる
    @Test
    def testPinchZoomClampsUpper(): Unit \ Assert =
        let s = PropertyWidgets.pinchZoom(PropertyWidgets.ZoomMode.Percent(1000.0), 5.0);
        Assert.assertEq(expected = PropertyWidgets.ZoomMode.Percent(1600.0), s)

    /// 下限クランプ: 25% を下回る factor を渡しても 25% にクランプされる
    @Test
    def testPinchZoomClampsLower(): Unit \ Assert =
        let s = PropertyWidgets.pinchZoom(PropertyWidgets.ZoomMode.Percent(50.0), 0.1);
        Assert.assertEq(expected = PropertyWidgets.ZoomMode.Percent(25.0), s)

    /// ZoomMode の表示文字列は整数 % に丸める
    @Test
    def testZoomModeLabel(): Unit \ Assert =
        Assert.assertEq(
            expected = ("25%", "100%", "200%", "1600%"),
            (PropertyWidgets.zoomModeLabel(PropertyWidgets.ZoomMode.Percent(25.0)),
             PropertyWidgets.zoomModeLabel(PropertyWidgets.ZoomMode.Percent(100.0)),
             PropertyWidgets.zoomModeLabel(PropertyWidgets.ZoomMode.Percent(200.0)),
             PropertyWidgets.zoomModeLabel(PropertyWidgets.ZoomMode.Percent(1600.0))))
}
