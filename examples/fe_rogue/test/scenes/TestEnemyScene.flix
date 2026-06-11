/// EnemyScene の純粋ヘルパーテスト。
///
/// `idFromPath`: `World/Enemy_<id>` 形式の NodePath から敵 id を取り出す純粋関数。
/// `AnimationPlayer` の finished イベント振り分け（death_blink 完了 → 正しい敵ノード削除）に
/// 使われ、誤ると死亡演出後に別ノードを消す。NodePath（= List[NodeName]）だけで駆動＝純粋。
/// （`findIdAt` は `getAll(scene)` 経由で scene 構築が要るため、ここでは pure な `idFromPath` のみ。）
mod TestEnemyScene {

    /// `World :: Enemy_7` → `Some(7)`。
    @Test
    def testIdFromPathValid(): Unit \ Assert =
        Assert.assertEq(
            expected = Some(7),
            EnemyScene.idFromPath(MapScene.worldName() :: "Enemy_7" :: Nil))

    /// `Enemy_` 以外の prefix（味方など）は `None`。
    @Test
    def testIdFromPathWrongPrefix(): Unit \ Assert =
        Assert.assertEq(
            expected = (None: Option[Int32]),
            EnemyScene.idFromPath(MapScene.worldName() :: "Player_0" :: Nil))

    /// 数値でないサフィックスは `None`（`Int32.fromString` 失敗）。
    @Test
    def testIdFromPathNonNumeric(): Unit \ Assert =
        Assert.assertEq(
            expected = (None: Option[Int32]),
            EnemyScene.idFromPath(MapScene.worldName() :: "Enemy_x" :: Nil))

    /// World 直下でない / 要素数不一致は `None`（深さ違い・境界）。
    @Test
    def testIdFromPathWrongDepth(): Unit \ Assert =
        Assert.assertEq(
            expected = (None: Option[Int32]),
            EnemyScene.idFromPath(MapScene.worldName() :: Nil))
}
