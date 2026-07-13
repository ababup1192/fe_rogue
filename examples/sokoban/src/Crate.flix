// Crate —押せる箱を手続き的に描画する: ボックスの積み重ねに、対角線のブレース
// 用の凸多角形を加えたもの。すべてのパーツはクレートの中心を基準に配置され、要
// 求されたタイルサイズを基準にスケールされるので、同じ関数が96pxのショーケース
// 用クレートも24pxのボードタイルも描く。

mod Crate {

    // 外枠のレールの太さ、タイルに対する割合。
    def railW(t: Float64): Float64 = t * 0.12

    // 描画順（zIndex）: 土台の板 -> 縦の継ぎ目 -> 対角線のブレース -> 枠のレール
    // -> 枠の継ぎ目と外側の輪郭。レールはブレースの後に描かれるので、ブレースの
    // 延長された両端はレールの下に隠れる。
    def zPlank(): Int32 = 0
    def zSeam(): Int32 = 1
    def zBraceEdge(): Int32 = 2
    def zBrace(): Int32 = 3
    def zRail(): Int32 = 4
    def zJoint(): Int32 = 5

    def topLeftOf(center: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        {x = center#x - t / 2.0, y = center#y - t / 2.0}

    /// ボックスのパーツ: 土台の板1 + 縦の継ぎ目5 + 枠のレール4 + 枠の継ぎ目4 +
    /// 輪郭の辺4。
    pub def boxes(center: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let tl = topLeftOf(center, t);
        plank(tl, t) :: List.flatten(seams(tl, t) :: rails(tl, t) :: frameJoints(tl, t) :: outline(tl, t) :: Nil)

    /// 土台の板: タイル全体を板の茶色で塗りつぶす。
    def plank(tl: Vec2.Vec2, t: Float64): Render.Placed =
        boxAt(tl#x, tl#y, t, t, Palette.cratePlank(), zPlank())

    /// 縦の継ぎ目: 等間隔に並んだ5本の細い線が、内部を6枚の板として読ませる。
    def seams(tl: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let w = t * 0.04;
        List.map(i ->
            let x = tl#x + t * Int32.toFloat64(i) / 6.0 - w / 2.0;
            boxAt(x, tl#y, w, t, Palette.crateSeam(), zSeam()),
            1 :: 2 :: 3 :: 4 :: 5 :: Nil)

    /// 外枠: 全幅の水平な板が2枚（上、下）、その間に挟まれる垂直な板が2枚
    /// （左、右）。
    def rails(tl: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let f = railW(t);
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + t - f, t, f, Palette.crateFrame(), zRail()) ::
        boxAt(x0, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) ::
        boxAt(x0 + t - f, y0 + f, f, t - 2.0 * f, Palette.crateFrame(), zRail()) :: Nil

    /// 枠の継ぎ目: 枠と内部の境界線。全幅の2本の水平線はその両端で四隅の突き合
    /// わせ継ぎ目を兼ね、垂直の2本はそれらの間だけを走る。
    def frameJoints(tl: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let f = railW(t);
        let w = t * 0.02;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0 + f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - f - w / 2.0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - f - w / 2.0, y0 + f, w, t - 2.0 * f, Palette.crateSeam(), zJoint()) :: Nil

    /// 外側の輪郭: クレート全体を囲む暗い1px（設計解像度）の線。
    def outline(tl: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let w = 1.0;
        let x0 = tl#x;
        let y0 = tl#y;
        boxAt(x0, y0, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0 + t - w, t, w, Palette.crateSeam(), zJoint()) ::
        boxAt(x0, y0, w, t, Palette.crateSeam(), zJoint()) ::
        boxAt(x0 + t - w, y0, w, t, Palette.crateSeam(), zJoint()) :: Nil

    def boxAt(x: Float64, y: Float64, w: Float64, h: Float64,
              c: Color, z: Int32): Render.Placed =
        { at = {x = x, y = y}, item = Render.solidBox({x = w, y = h}, c, z) }

    /// 対角線のブレース: 内側の左下から内側の右上へ伸びる1本の太い帯に、暗い縁
    /// 線を2本加えたもの。3本の帯はすべて同じ中心線と方向ベクトルを共有し、法線
    /// 方向のオフセット範囲だけが異なる（法線に沿って縁を作ることで、どこでも太
    /// さが一定に保たれる）。
    pub def polys(center: Vec2.Vec2, t: Float64): List[Render.Placed] =
        let tl = topLeftOf(center, t);
        let half = t * 0.09;    // 中央帯の半幅（厚さ 0.18T）
        let edge = t * 0.03;    // 縁線1本の太さ
        braceStrip(tl, t, -half - edge, -half, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, half, half + edge, Palette.crateFrame(), zBraceEdge()) ::
        braceStrip(tl, t, -half, half, Palette.crateBrace(), zBrace()) :: Nil

    /// 帯の中心線から法線方向オフセット o1..o2 を覆う平行四辺形（凸クアッド）。
    /// 中心線は内側の左下隅から内側の右上隅まで走り、両端を ext だけ延長したも
    /// の。延長された両端は後で描かれる枠のレールの下に隠れるので、帯の端を整形
    /// する必要はない。頂点は画面の絶対座標なので、置き場所は原点。
    def braceStrip(tl: Vec2.Vec2, t: Float64, o1: Float64, o2: Float64,
                   c: Color, z: Int32): Render.Placed =
        let f = railW(t);
        let ext = t * 0.04;
        let bl = {x = tl#x + f, y = tl#y + t - f};
        let tr = {x = tl#x + t - f, y = tl#y + f};
        let d = Vec2.mul(Vec2.sub(tr, bl), 1.0 / Vec2.length(Vec2.sub(tr, bl)));
        let p0 = Vec2.sub(bl, Vec2.mul(d, ext));
        let p1 = Vec2.add(tr, Vec2.mul(d, ext));
        { at = Vec2.zero(), item = Render.polygon(Quad.strip(p0, p1, o1, o2), c, z) }
}
