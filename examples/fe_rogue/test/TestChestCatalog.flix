// ChestCatalog のテスト
//
// 宝箱カタログ（種別 → 中身の重み付きプール）の decode と、ローグだけが持つ
// canOpenChests フラグが units.json から正しく読めることを固定する。
// いずれも Option チェーン + assertEq で「期待ケースだけ」を比較し、分岐を持たない。

mod TestChestCatalog {

    /// chests.json と同じ構造の JSON 文字列リテラル（wooden 1 種）。
    def sampleChestsJson(): String = String.unlines(
        "{" ::
        "  \"chests\": {" ::
        "    \"wooden\": {" ::
        "      \"label\": \"木の宝箱\"," ::
        "      \"contents\": [{\"id\": \"vulnerary\", \"percent\": 40}, {\"id\": \"iron_sword\", \"percent\": 60}]," ::
        "      \"sprite\": { \"texture\": \"item_icons\", \"hframes\": 16, \"vframes\": 39, \"frame\": 0 }" ::
        "    }" ::
        "  }" ::
        "}" :: Nil)

    /// wooden が id でひけて、label / contents 件数 / sprite#frame が期待通りに読める。
    @Test
    def testDecodeSampleChests(): Unit \ Assert =
        let chests = JsonCompat.parse(sampleChestsJson())
            |> Option.flatMap(Saveable.fromJson)
            |> Option.map(ChestCatalog.chestsOf)
            |> Option.getWithDefault(Map.empty());
        let found = Map.get("wooden", chests)
            |> Option.map(c -> (c#label, List.length(c#contents), c#sprite#frame));
        Assert.assertEq(
            expected = (1, Some(("木の宝箱", 2, 0))),
            (Map.size(chests), found))

    /// 実 chests.json をロードすると wooden / golden が引け、golden の中身件数が読める。
    @Test
    def testLoadRealChestsCatalog(): Unit \ {Assert, Fs.FileRead} =
        let chests = ChestCatalog.chestsOf(ChestCatalog.load());
        Assert.assertEq(
            expected = (Some("木の宝箱"), Some("金の宝箱"), true),
            (Map.get("wooden", chests) |> Option.map(c -> c#label),
             Map.get("golden", chests) |> Option.map(c -> c#label),
             Map.get("golden", chests) |> Option.map(c -> List.length(c#contents) > 0)
                 |> Option.getWithDefault(false)))

    /// units.json で「宝箱を開けられる」のはローグだけ（rogue=true / knight=false）。
    @Test
    def testRogueCanOpenChestsKnightCannot(): Unit \ {Assert, Fs.FileRead} =
        let weapons = WeaponCatalog.load();
        let units = UnitCatalog.unitsOf(
            UnitCatalog.load(AssetPath.resolve("resources/units.json"), weapons));
        Assert.assertEq(
            expected = (Some(true), Some(false)),
            (Map.get("rogue", units)  |> Option.map(u -> u#canOpenChests),
             Map.get("knight", units) |> Option.map(u -> u#canOpenChests)))
}
