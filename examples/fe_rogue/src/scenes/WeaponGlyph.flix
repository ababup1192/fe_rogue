/// WeaponGlyph — 武器系統（剣/斧/槍/弓/魔法）を engine の塗りプリミティブで直接描く白の塗りシルエット。
///
/// なぜスプライトでなくノード直描きか:
///   ビットマップは拡大で甘くなり、盤上の小さなサイズだと系統の区別が付きづらい。`Polygon2D`
///   （凸塗り）と `Arc2D`（弧）の合成なら、どの zoom でも輪郭がくっきり出る。全系統とも白で統一し、
///   形は FE3H のマップ武器アイコン（斜めの刀身/穂先、斧、弓、魔道書）に寄せる。
///
/// 設計上の制約（描画系から決まる、変更不可の前提）:
///   - **回転は描画時に無視される**（`Polygon2D.toRenderCmd` / `Arc2D.toRenderCmds` は position+scale のみ）。
///     よって斜めの刃などは頂点を「最終的な向き」のまま局所座標で直書きする（`setRotation` は使わない）。
///     斜めバーは `bar`（中心・軸・半長・半厚）で、対角基底 `diagD`(=cos45=sin45) を使って組む。
///   - **塗りは凸のみ**（GL_TRIANGLE_FAN）。本/斧刃など凹形状は複数の凸ピースに分割して重ねる。
///   - **アンチエイリアス無し**（plain fill, 本番 ~5x 拡大）。斜めは階段になるが、スクショ準拠を優先する。
///
/// 座標系: 原点中心・+y は下・上右(=(+x,-y))が刀身の向き・WeaponIcon の内寸 ~11px に収める（おおむね ±5.5）。
/// 各ピースは `EngineNode.Polygon2DWithState` / `Arc2DWithState`（`NodeTag.NoTag`）で、`WeaponIconScene`
/// が `WeaponIcon`(Marker2D) の子として attach する。白は濃色プレート背景の上で読ませる（[[WeaponIconScene]]）。
mod WeaponGlyph {

    /// 各ピースの基準 zIndex（WeaponIconScene の Bg=61 より手前）。ピースは base+i で重ねる。
    def baseZIndex(): Int32 = 62

    /// 対角の単位成分（cos45° = sin45°）。上右向き軸 = (diagD, -diagD)。
    def diagD(): Float64 = 0.7071067811865476

    /// 全系統とも白で統一（濃色プレートの上で視認）。形だけで系統を区別する。
    pub def glyphColor(_wt: WeaponCatalog.WeaponType): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// 武器系統 → 子ノード（名前 × EngineNode）列。WeaponIconScene が addChildAt で順に生やす。
    /// 名前は "G0","G1",… の安定名（重複しない・reconcile しない静的アイコン）。
    pub def weaponGlyph(wt: WeaponCatalog.WeaponType): List[(String, EngineNode[NodeTag])] =
        named(pieces(wt, glyphColor(wt)))

    /// weaponGlyph を原点（グリフ中心）基準で一様に scale 倍した版。各ピースの node 位置を scale 倍し
    /// node スケールを scale にすることで、全体が原点まわりに縮小/拡大する（祖先スケールは描画へ
    /// 伝播しないため、ピース側で吸収する）。キャラ選択など小さく横並びにしたい場所で使う。
    pub def weaponGlyphScaled(wt: WeaponCatalog.WeaponType, scale: Float64): List[(String, EngineNode[NodeTag])] =
        weaponGlyph(wt) |> List.map(ne ->
            let (name, node) = ne;
            let p = Node2D.getPosition(node);
            let scaled = node
                |> Node2D.setPosition({x = p#x * scale, y = p#y * scale})
                |> Node2D.setScale({x = scale, y = scale});
            (name, scaled))

    // ─── 系統ごとのピース合成（すべて凸・向き付き直書き） ───────────────────

    // 全系統とも斜め（左下→右上、軸 u=(d,-d)）に統一する。
    def pieces(wt: WeaponCatalog.WeaponType, color: Color): List[EngineNode[NodeTag]] =
        let d = diagD();
        match wt {
            // 剣（据え置き=OK）: 太い斜め刀身 + 切先三角 + 柄元の斜め鍔 + 柄頭。
            case WeaponCatalog.WeaponType.Sword =>
                poly(bar(1.0, -1.0, 4.3, 0.9, d, 0.0 - d), color)
                :: poly(tri(5.6, -5.6, 4.6, -3.8, 3.8, -4.6), color)
                :: poly(bar(-1.7, 1.7, 2.1, 0.55, d, d), color)
                :: poly(bar(-3.0, 3.0, 0.7, 0.7, d, d), color)
                :: Nil
            // 槍: 細い斜めシャフト + 広い菱形の穂先 + 穂の付け根でシャフトに直交する左右対称の返し
            // （両端が尖った細い菱形のクロスブレード）。穂先(上右)+左右の刃+柄(下左)でテトラポット状。
            case WeaponCatalog.WeaponType.Lance =>
                poly(bar(-0.3, 0.3, 3.7, 0.42, d, 0.0 - d), color)
                :: poly(v(5.5, -5.5) :: v(4.72, -3.38) :: v(2.8, -2.8) :: v(3.38, -4.72) :: Nil, color)  // 穂先
                :: poly(v(4.03, -0.77) :: v(2.75, -2.75) :: v(0.77, -4.03) :: v(2.05, -2.05) :: Nil, color)  // 返し（左右対称の刃）
                :: Nil
            // 斧（ラブリュス＝両刃の対称斧）: 中央の柄 + 中央ハブ + 左右対称の刃 2 枚（上左・下右へ
            // 反対方向に広がる三日月状）。各刃はリング状の扇形（Arc2D, 内半径 1.0）で、刃元が点に
            // 尖らず幅を持って柄(ハブ)に付く。刃先は外周の丸い弧。頭はやや上(上右)寄り。
            case WeaponCatalog.WeaponType.Axe =>
                poly(bar(0.0, 0.0, 4.9, 0.4, d, 0.0 - d), color)                                            // 中央の柄
                :: circlePiece(1.7, 1.0, 0.0 - 1.0, color)                                                  // 刃と柄をつなぐ中央ハブ（太め）
                :: arc(4.2, 2.6, Arc2D.tau() * 185.0 / 360.0, Arc2D.tau() * 265.0 / 360.0, color, v(1.0, 0.0 - 1.0))  // 上左の刃（刃元を太く＝内半径1.6）
                :: arc(4.2, 2.6, Arc2D.tau() * 5.0 / 360.0, Arc2D.tau() * 85.0 / 360.0, color, v(1.0, 0.0 - 1.0))     // 下右の刃
                :: Nil
            // 弓: 斜めの細い半円弧（弓幹、上左へ膨らむ）+ 細い斜めの弦 + つがえた矢。
            // 矢は弦に直交（上左向き）で、先端に矢尻の三角、末尾に矢羽根の三角を付ける。
            case WeaponCatalog.WeaponType.Bow =>
                arc(4.4, 1.2, 3.0 * Arc2D.tau() / 8.0, 7.0 * Arc2D.tau() / 8.0, color, v(0.9, 0.9))  // 弓幹
                :: poly(bar(0.9, 0.9, 4.4, 0.28, d, 0.0 - d), color)                                 // 弦（細い）
                :: poly(bar(0.0, 0.0, 3.6, 0.2, d, d), color)                                        // 矢柄
                :: poly(tri(0.0 - 3.6, 0.0 - 3.6, 0.0 - 1.94, 0.0 - 2.86, 0.0 - 2.86, 0.0 - 1.94), color)  // 矢尻（上左＝先端の尖り）
                :: poly(v(1.81, 1.39) :: v(3.61, 2.19) :: v(2.19, 3.61) :: v(1.39, 1.81) :: Nil, color)    // 矢羽根（下右＝末尾、広がる台形）
                :: Nil
            // 魔法: 直立の魔道書（参照画像準拠）。表紙の装飾枠（白縁＋暗い中央）+ 中央の紋章（菱形）
            // + 下のページ小口（厚み）+ 右のしおりタブ。暗いプレート背景が枠の内側として効く。
            case WeaponCatalog.WeaponType.Magic =>
                poly(rect(0.0 - 3.8, 0.0 - 5.0, 3.0, 0.0 - 3.8), color)   // 上枠
                :: poly(rect(0.0 - 3.8, 1.4, 3.0, 2.6), color)            // 下枠
                :: poly(rect(0.0 - 3.8, 0.0 - 5.0, 0.0 - 2.7, 2.6), color) // 左枠
                :: poly(rect(1.9, 0.0 - 5.0, 3.0, 2.6), color)            // 右枠
                :: poly(v(0.0 - 0.4, 0.0 - 3.6) :: v(1.1, 0.0 - 1.2) :: v(0.0 - 0.4, 1.2) :: v(0.0 - 1.9, 0.0 - 1.2) :: Nil, color)  // 中央の紋章
                :: poly(rect(0.0 - 3.4, 2.9, 2.6, 4.1), color)            // 下のページ小口（厚み）
                :: poly(rect(3.0, 0.0 - 3.4, 3.9, 0.0 - 1.6), color)      // 右上のしおりタブ
                :: Nil
        }

    // ─── 内部ヘルパー ───────────────────────────────────────────────────

    /// 頂点リテラルの短縮（Vec2.Vec2）。
    def v(x: Float64, y: Float64): Vec2.Vec2 = {x = x, y = y}

    /// 中心 (cx,cy)・単位軸 (ax,ay)・軸方向半長 halfLen・直交方向半厚 halfThick の回転矩形（凸）。
    /// 直交方向は軸を左 90° 回した (-ay, ax)。GL_TRIANGLE_FAN 用に外周順で頂点を並べる。
    def bar(cx: Float64, cy: Float64, halfLen: Float64, halfThick: Float64,
            ax: Float64, ay: Float64): List[Vec2.Vec2] =
        let px = 0.0 - ay;
        let py = ax;
        let ux = ax * halfLen; let uy = ay * halfLen;
        let wx = px * halfThick; let wy = py * halfThick;
        v(cx + ux + wx, cy + uy + wy) :: v(cx + ux - wx, cy + uy - wy) ::
        v(cx - ux - wx, cy - uy - wy) :: v(cx - ux + wx, cy - uy + wy) :: Nil

    /// 三角形（常に凸）。
    def tri(x0: Float64, y0: Float64, x1: Float64, y1: Float64,
            x2: Float64, y2: Float64): List[Vec2.Vec2] =
        v(x0, y0) :: v(x1, y1) :: v(x2, y2) :: Nil

    /// 軸並行の矩形（(x0,y0)=左上, (x1,y1)=右下, +y は下）。外周順で凸四角を返す。
    def rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64): List[Vec2.Vec2] =
        v(x0, y0) :: v(x1, y0) :: v(x1, y1) :: v(x0, y1) :: Nil

    /// 凸塗りピースを EngineNode 子として組む（位置は原点・z は後で named で確定）。
    def poly(points: List[Vec2.Vec2], color: Color): EngineNode[NodeTag] =
        EngineNode.Polygon2DWithState(Polygon2D.make(points, color), NodeTag.NoTag)

    /// 中心 (cx,cy)・半径 radius の塗り潰し円ピース（12 角形）。刃と柄をつなぐハブ等に使う。
    def circlePiece(radius: Float64, cx: Float64, cy: Float64, color: Color): EngineNode[NodeTag] =
        let c = Polygon2D.circle(radius, color) |> Node2D.setPosition(v(cx, cy));
        EngineNode.Polygon2DWithState(c, NodeTag.NoTag)

    /// 弧ピース（弓用）。center は WeaponIcon 原点からのオフセット。segments は小サイズ向けに抑える。
    def arc(radius: Float64, width: Float64, startAngle: Float64, endAngle: Float64,
            color: Color, center: Vec2.Vec2): EngineNode[NodeTag] =
        let a = Arc2D.make(radius, width, startAngle, endAngle, color)
            |> Arc2D.setSegments(12)
            |> Node2D.setPosition(center);
        EngineNode.Arc2DWithState(a, NodeTag.NoTag)

    /// ピース列に安定名 "G0","G1",… と base+i の zIndex を与える。後勝ち（大きい i が手前）。
    def named(nodes: List[EngineNode[NodeTag]]): List[(String, EngineNode[NodeTag])] =
        nodes
            |> List.zipWithIndex
            |> List.map(in -> let (i, n) = in; ("G${i}", CanvasItem.setZIndex(baseZIndex() + i, n)))
}
