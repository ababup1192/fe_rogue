/// CatalogId / 各カタログ idOf の往復テスト。
///
/// スナップショット保存は「実行時 resource → カタログ id」の逆引き（name 一致）に依存する。
/// 全 entry で `idOf(lookup(id)) == Some(id)` が成り立つこと（= name が一意で逆引きが安定）を固定する。
mod TestCatalogId {

    /// 武器カタログ: 全 id について idOf(lookup(id)) が Some(同じ id) を返す。
    @Test
    def testWeaponIdRoundTrip(): Unit \ {Assert, Fs.FileRead} =
        let catalog = WeaponCatalog.load();
        let ids = WeaponCatalog.weaponsOf(catalog) |> Map.keysOf |> Set.toList;
        Assert.assertEq(
            expected = List.map(id -> Some(id), ids),
            List.map(id -> WeaponCatalog.idOf(WeaponCatalog.lookup(id, catalog), catalog), ids))

    /// カタログに無い resource（name を書き換えた偽物）は idOf が None を返す。
    @Test
    def testWeaponIdOfUnknownIsNone(): Unit \ {Assert, Fs.FileRead} =
        let catalog = WeaponCatalog.load();
        let ids = WeaponCatalog.weaponsOf(catalog) |> Map.keysOf |> Set.toList;
        let sample = List.head(ids) |> Option.getWithDefault("");
        let bogus = {name = "____存在しない武器名____" | WeaponCatalog.lookup(sample, catalog)};
        Assert.assertEq(expected = None, WeaponCatalog.idOf(bogus, catalog))
}
