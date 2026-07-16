// Shadow — 単一光源が壁（凸/凹の頂点列）に落とすハードシャドウの幾何を導く純関数。
// 光と壁の位置だけから「影の形（四角形の列）」を計算し、Light の穴あき暗幕と同じ
// 加法的な合成のしかたで PlacedItem に変換する。光そのもの・壁そのものには触れない。
// 利用例: shadowQuads(light#at, occluder, 400.0) で影四角形を得て、そのまま Render.polygon へ。
mod Shadow {

    /// 遮蔽物 1 個ぶんの頂点列（絶対座標・閉じたポリゴンとして扱う）に対して光が落とす
    /// 影の四角形の列を返す。頂点順は時計回り・反時計回りのどちらでもよい
    /// （Triangulate.signedArea の符号を見て毎回そろえるので、呼び側は向きを気にしなくてよい）。
    /// 辺ごとに「光から見て背を向けている辺か」を内積の符号で判定し、
    /// 背面の辺だけを光の反対方向へ extrudeLength ぶん伸ばして四角形にする。
    /// 光がポリゴンの内側にある・光と辺が一直線という縮退でも、全辺ぶんの四角形を返すだけで
    /// 例外を出さない（背面判定にちょうど0を含めているので必ずどちらかに倒れる）。
    /// n=2（閉じていない線分1本）の遮蔽物でも、辺2本（往復）のうち背面側の1本だけが
    /// 影四角形になり正しく1枚返る（薄い壁は多角形にせず線分で渡してよい）。
    pub def shadowQuads(lightAt: Vec2.Vec2, occluder: List[Vec2.Vec2],
                        extrudeLength: Float64): List[List[Vec2.Vec2]] =
        let n = List.length(occluder);
        if (n < 2)
            Nil
        else {
            let sign = if (Triangulate.signedArea(occluder) < 0.0) -1.0 else 1.0;
            let verts = List.toVector(occluder);
            List.range(0, n)
                |> List.filterMap(i -> shadowOfEdge(lightAt,
                    Vector.get(i, verts), Vector.get(Int32.modulo(i + 1, n), verts),
                    sign, extrudeLength))
        }

    /// 辺 (v1, v2) の外向き法線と「辺中点→光」方向の内積を見て、光に背を向けている
    /// （内積<=0。ちょうど0＝光と辺が一直線も背面側に倒す — 光が辺の真横にあるとき
    /// 「影を落とさない」方が、際どい角度で明るい面が影を持つ矛盾より自然なため）辺だけ
    /// 影四角形にする。前面の辺は None。
    def shadowOfEdge(lightAt: Vec2.Vec2, v1: Vec2.Vec2, v2: Vec2.Vec2,
                     sign: Float64, extrudeLength: Float64): Option[List[Vec2.Vec2]] =
        let d = Vec2.sub(v2, v1);
        let normal = Vec2.mul({ x = d#y, y = -d#x }, sign);
        let mid = Vec2.mul(Vec2.add(v1, v2), 0.5);
        let towardLight = Vec2.sub(lightAt, mid);
        if (Vec2.dot(normal, towardLight) > 0.0)
            None
        else {
            let v1p = extrudeAway(lightAt, v1, extrudeLength);
            let v2p = extrudeAway(lightAt, v2, extrudeLength);
            Some(v1 :: v2 :: v2p :: v1p :: Nil)
        }

    /// 頂点 v を「光→v」の方向へ length だけ延ばした点（光と v が重なる縮退では
    /// 方向が定まらないので v をそのまま返す＝退化四角形になるが例外は出ない）。
    def extrudeAway(lightAt: Vec2.Vec2, v: Vec2.Vec2, length: Float64): Vec2.Vec2 =
        let dir = Vec2.normalized(Vec2.sub(v, lightAt));
        Vec2.add(v, Vec2.mul(dir, length))

    /// 影を無限遠まで伸ばしたとみなせる目安の長さ（design解像度が数百px程度のゲーム向け）。
    /// 実際の値は画面対角線に応じて呼び側（feature_lab 等）が決めてよい。
    pub def infiniteExtrude(): Float64 = 2000.0

    // ── HitShape → 遮蔽ポリゴン ──

    /// 円をN角形近似した頂点列（絶対座標）。segments が大きいほど滑らかだが影四角形も増える。
    pub def occluderOfCircle(center: Vec2.Vec2, radius: Float64, segments: Int32): List[Vec2.Vec2] =
        List.range(0, segments) |> List.map(i ->
            Vec2.add(center, Vec2.onEllipse({ x = radius, y = radius },
                Int32.toFloat64(i) / Int32.toFloat64(segments))))

    /// 矩形の4頂点（絶対座標・中心+幅高さ）。左上→右上→右下→左下の順（画面上で時計回り）。
    pub def occluderOfBox(center: Vec2.Vec2, size: Vec2.Vec2): List[Vec2.Vec2] =
        let hw = size#x / 2.0;
        let hh = size#y / 2.0;
        { x = center#x - hw, y = center#y - hh } ::
        { x = center#x + hw, y = center#y - hh } ::
        { x = center#x + hw, y = center#y + hh } ::
        { x = center#x - hw, y = center#y + hh } ::
        Nil

    /// Hit.HitShape の宣言（持ち主位置からのオフセット）から遮蔽ポリゴンを作る。
    /// 円の分割数は固定（見た目の滑らかさと影四角形の枚数のバランスを取った既定値）。
    pub def occluderOf(pos: Vec2.Vec2, shape: Hit.HitShape): List[Vec2.Vec2] =
        match shape {
            case Hit.HitShape.CircleH(c) =>
                occluderOfCircle({ x = pos#x + c#dx, y = pos#y + c#dy }, c#r, 12)
            case Hit.HitShape.BoxH(b) =>
                occluderOfBox({ x = pos#x + b#dx, y = pos#y + b#dy }, { x = b#w, y = b#h })
        }

    // ── Light との合成 ──

    /// itemsFor の設定。darkness は影の濃さ0..1（1で完全な黒）、z は影のzIndex、
    /// extrudeLength は影を伸ばす長さ（画面対角線より十分大きい値を渡す。infiniteExtrude が目安）。
    pub type alias ShadowConfig = { darkness = Float64, z = Int32, extrudeLength = Float64 }

    /// occluders それぞれが light に対して落とす影を、Multiply の黒 Poly として並べる。
    /// Light.singleLightItems の結果と List.append で好きな順に重ねるのは呼び側の仕事
    /// （穴あき暗幕とハロのどちらの上に置くかはシーンの見た目次第のため、ここでは決めない）。
    /// 今は light#at（位置）しか見ない — radius はソフトシャドウ（影の縁のぼかし）の布石。
    pub def itemsFor(light: Light.Light, occluders: List[List[Vec2.Vec2]],
                     cfg: ShadowConfig): List[Render.PlacedItem] =
        occluders
            |> List.flatMap(occluder -> shadowQuads(light#at, occluder, cfg#extrudeLength))
            |> List.map(quad -> blackQuad(quad, cfg#darkness, cfg#z))

    /// 頂点列 quad を Multiply・alpha=darkness の黒 Poly にする（絶対座標のまま at=zero）。
    def blackQuad(quad: List[Vec2.Vec2], darkness: Float64, z: Int32): Render.PlacedItem =
        let black = { r = 0.0f32, g = 0.0f32, b = 0.0f32 };
        { at = Vec2.zero(),
          item = Render.polygon(quad, black, z)
              |> Render.blended(DrawCmd.BlendMode.Multiply)
              |> Render.fade(RenderUtil.f32(darkness)) }

    // ── 幾何ユーティリティ（テストの「影が壁を透過しない」検証にも使う） ──

    /// 点 p が凸四角形 quad（4頂点・向きは時計回り/反時計回りのどちらでもよい）の内側にあるか。
    /// shadowQuads が返す四角形は必ず凸なので、4辺との外積の符号がすべて揃えば内側。
    /// 境界は内側に含めない（Hit の「ちょうど接するのは外」の線引きに合わせる）。
    pub def containsPoint(quad: List[Vec2.Vec2], p: Vec2.Vec2): Bool =
        match quad {
            case a :: b :: c :: d :: Nil =>
                let edges = (a, b) :: (b, c) :: (c, d) :: (d, a) :: Nil;
                let signs = edges |> List.map(edge -> {
                    let (e1, e2) = edge;
                    Vec2.cross(Vec2.sub(e2, e1), Vec2.sub(p, e1))
                });
                List.forAll(s -> s > 0.0, signs) or List.forAll(s -> s < 0.0, signs)
            case _ => false
        }
}
