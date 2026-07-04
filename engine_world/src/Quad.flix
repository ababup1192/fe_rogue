// Quad — 四角形（回転した矩形や、太さのある線）の四隅の座標を計算する。
// 頂点を出すことだけに徹するので、同じ四隅を色や不透明度を変えて何にでも描き回せる。
// 利用例: 回転する箱や紙片を描く / 太線や針を描く / 輪郭の縁取りを片側ずつ作る。
// 注意: 作るのは点だけ。色・不透明度・重なり順の指定は呼び側の仕事。

mod Quad {

    /// 幅 `2*halfW`・高さ `2*halfH` の矩形を `center` を中心に `angle` ラジアン回した
    /// 四隅。`angle = 0` は軸並行の箱で、ローカル +x 軸（halfW 方向）が `angle` の向きへ
    /// 回る。隅は (-halfW, -halfH) の角から巻いて返す。
    pub def rotated(center: Vec2.Vec2, halfW: Float64, halfH: Float64, angle: Float64): List[Vec2.Vec2] =
        let u = { x = RenderUtil.cosF(angle), y = RenderUtil.sinF(angle) };  // 回転後のローカル +x 軸
        let v = { x = -u#y, y = u#x };                                       // 回転後のローカル +y 軸
        let corner = (sx, sy) -> Vec2.add(center, Vec2.add(Vec2.mul(u, sx * halfW), Vec2.mul(v, sy * halfH)));
        corner(-1.0, -1.0) :: corner(1.0, -1.0) :: corner(1.0, 1.0) :: corner(-1.0, 1.0) :: Nil

    /// `p0` から `p1` への線分に沿った一定幅の帯で、中心線の両側の符号つき法線オフセット
    /// `o1..o2` を覆う。帯の長辺は p0->p1 に平行に走り、厚み (o2 - o1) はどこでも同じ
    /// （両縁とも線分の法線に沿って作るため）。太線・針・輪郭の片側レール（o1..o2 を片側に
    /// 寄せて取る）に使う。`p0` と `p1` は異なる必要がある。
    pub def strip(p0: Vec2.Vec2, p1: Vec2.Vec2, o1: Float64, o2: Float64): List[Vec2.Vec2] =
        let along = Vec2.normalized(Vec2.sub(p1, p0));
        let normal = { x = -along#y, y = along#x };
        Vec2.add(p0, Vec2.mul(normal, o1)) :: Vec2.add(p1, Vec2.mul(normal, o1)) ::
        Vec2.add(p1, Vec2.mul(normal, o2)) :: Vec2.add(p0, Vec2.mul(normal, o2)) :: Nil
}
