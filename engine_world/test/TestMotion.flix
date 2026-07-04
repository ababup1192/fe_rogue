// Motion.integrate のテスト。速度を持つ entity は p += v*dt、持たない entity は据え置き。
// Vec2 は構造レコード（Eq/ToString 非導出）なので、比較はスカラ成分で行う。

mod TestMotion {

    /// 速度を持つ entity は p += v*dt 進む（x: 0 + 4*0.5 = 2.0）。
    @Test
    def testIntegrateMovesWithVelocity(): Unit \ Assert =
        let pos = Map#{ 1 => {x = 0.0, y = 0.0} };
        let vel = Map#{ 1 => {x = 4.0, y = 0.0} };
        let out = Motion.integrate(pos, vel, 0.5);
        Assert.assertEq(expected = Some(2.0), Map.get(1, out) |> Option.map(p -> p#x))

    /// 速度を持たない entity は据え置き。
    @Test
    def testIntegrateKeepsEntityWithoutVelocity(): Unit \ Assert =
        let pos = Map#{ 2 => {x = 10.0, y = 10.0} };
        let vel = (Map.empty(): Map[EntityId, {x = Float64, y = Float64}]);
        let out = Motion.integrate(pos, vel, 0.5);
        Assert.assertEq(expected = Some(10.0), Map.get(2, out) |> Option.map(p -> p#x))
}
