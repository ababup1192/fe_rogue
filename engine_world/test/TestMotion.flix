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

    /// 往復のずれ: 横軸・振幅 8・周期 4 は t=1（1/4 周期）で +8、t=2 で 0、t=3 で -8。
    /// 三角波なので丸めの出ない値で厳密に固定できる。
    @Test
    def testOscillationOffsetQuarterPeriods(): Unit \ Assert =
        let osc = { axis = {x = 1.0, y = 0.0}, amplitude = 8.0, period = 4.0, phase = 0.0 };
        let at = t -> Motion.oscillationOffset(osc, t)#x;
        Assert.assertEq(expected = (0.0, 8.0, 0.0, -8.0), (at(0.0), at(1.0), at(2.0), at(3.0)))

    /// 位相 0.25 は 1/4 周期先から始まる（t=0 で振幅の頂点）。
    @Test
    def testOscillationOffsetPhaseShifts(): Unit \ Assert =
        let osc = { axis = {x = 0.0, y = -1.0}, amplitude = 6.0, period = 2.0, phase = 0.25 };
        Assert.assertEq(expected = -6.0, Motion.oscillationOffset(osc, 0.0)#y)
}
