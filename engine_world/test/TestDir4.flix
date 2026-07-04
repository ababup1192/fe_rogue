// Dir4 のテスト。4方向の delta / 逆向き / 鏡映 / 回転 / delta 復元の契約を固定する。
// Dir4 は Eq 導出済みなので方向どうしを直接 assertEq で比較できる。

mod TestDir4 {

    /// delta は 4方向を別々の単位ベクトルに写し、fromDelta がそれを厳密に復元する
    /// （＝全4方向が delta→fromDelta で自分自身に戻る／全射かつ単射）。
    @Test
    def testDeltaFromDeltaRoundTrip(): Unit \ Assert =
        let roundTrip = d -> { let (dx, dy) = Dir4.delta(d); Dir4.fromDelta(dx, dy) };
        Assert.assertEq(expected = List.map(Some, Dir4.all()), List.map(roundTrip, Dir4.all()))

    /// fromDelta は基本方位の単位ステップ以外（原点・斜め・2セル分）を None で弾く。
    @Test
    def testFromDeltaRejectsNonCardinal(): Unit \ Assert =
        Assert.assertEq(
            expected = (None, None, None),
            (Dir4.fromDelta(0, 0), Dir4.fromDelta(1, 1), Dir4.fromDelta(2, 0)))

    /// opposite は対合：2回かけると元の方向に戻る。
    @Test
    def testOppositeInvolution(): Unit \ Assert =
        Assert.assertEq(expected = Dir4.all(),
            List.map(d -> Dir4.opposite(Dir4.opposite(d)), Dir4.all()))

    /// mirrorX は Left/Right を入れ替え、Up/Down はそのまま。
    /// 入力順 Up, Down, Left, Right → 出力 Up, Down, Right, Left。
    @Test
    def testMirrorXSwapsLeftRight(): Unit \ Assert =
        Assert.assertEq(
            expected = Dir4.Up :: Dir4.Down :: Dir4.Right :: Dir4.Left :: Nil,
            List.map(Dir4.mirrorX, Dir4.all()))

    /// rotateCw の1ステップは Up -> Right -> Down -> Left の時計回り巡回。
    @Test
    def testRotateCwOneStep(): Unit \ Assert =
        Assert.assertEq(
            expected = Dir4.Right :: Dir4.Down :: Dir4.Left :: Dir4.Up :: Nil,
            List.map(Dir4.rotateCw, Dir4.Up :: Dir4.Right :: Dir4.Down :: Dir4.Left :: Nil))

    /// 時計回りに4回まわすと一周して元に戻る。
    @Test
    def testRotateCwFullCircle(): Unit \ Assert =
        let turn4 = d -> Dir4.rotateCw(Dir4.rotateCw(Dir4.rotateCw(Dir4.rotateCw(d))));
        Assert.assertEq(expected = Dir4.all(), List.map(turn4, Dir4.all()))
}
