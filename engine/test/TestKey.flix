// Tests for GameEngine.Key / allKeys

// allKeys は手書きリストで、enum とは別管理。enum にキーを足して
// allKeys に足し忘れると、isKeyPressed 直呼びでは動くのに
// InputEvent.currentKeys 経由(＝ほぼ全ゲーム)では反応しない壊れ方をする。
// その事故を個数と重複の 2 点で見張る。

/// enum の全キーが allKeys に載っているか、個数で確かめる
/// (内訳: 英字26 + 数字10 + 矢印4 + 制御・編集12 + ファンクション12
///  + 記号11 + 修飾9 + テンキー17 = 101)
@Test
def testAllKeysCoversAllVariants(): Unit \ Assert =
    Assert.assertEq(expected = 101, List.length(GameEngine.allKeys()))

/// allKeys に同じキーが二重に載っていないか
/// (重複があると Set に畳んだとき 101 より縮む)
@Test
def testAllKeysHasNoDuplicates(): Unit \ Assert =
    Assert.assertEq(expected = 101, Set.size(List.toSet(GameEngine.allKeys())))
