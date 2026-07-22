// PxSprite — PxSpriteDoc(文字格子)を PlacedItem の列に描く(第一段: box 列)。
// 1 文字 = scale×scale の矩形。横に連続する同色キーの文字は 1 つの矩形へ結合して
// 数を減らす(被覆する面積と最終色は結合前と同一 — 格子はセル重なりを持たないので、
// どう矩形に分けても画素は変わらない)。
// 規約:
//   - legend に無い文字は透明(fail-open)。スプライト名・コマ名が無ければ何も描かない。
//   - anchor: 格子内の基準セル。draw の at がこのセルの左上に来る。
//   - flipX: 列を左右反転する。anchor の鏡映は draw 側の規約 — 反転後も
//     「anchor セルの左上 = at」のまま(anchor x は幅 w に対し w-1-ax へ写る)。
//   - scale は整数のみ(NEAREST 前提)。0 以下は何も描かない。
//   - 色は resolver(意味色キー → 実色)が解決する。テーマ替え・個体差(体色)は
//     resolver の差し替えで行い、格子は共有する。
mod PxSprite {

    /// 結合済みの矩形 1 個(セル単位を px へ展開済み・key は未解決の意味色キー)。
    pub type alias Run = { x = Float64, y = Float64, w = Float64, h = Float64, key = String }

    /// コマを描く。出力は box(単色多角形)の列 — 呼び手の z にすべて載る。
    pub def draw(doc: PxSpriteDoc.Doc, sprite: String, frame: String, at: Vec2.Vec2,
                 flipX: Bool, scale: Int32, resolver: String -> Color, z: Int32): List[Render.PlacedItem] =
        runs(doc, sprite, frame, at, flipX, scale)
            |> List.map(r -> {
                { at = { x = r#x, y = r#y },
                  item = Render.polygon(
                      { x = 0.0, y = 0.0 } :: { x = r#w, y = 0.0 } ::
                      { x = r#w, y = r#h } :: { x = 0.0, y = r#h } :: Nil,
                      resolver(r#key), z) }
            })

    /// コマを「アトラス 1 クアッド」で描く(opt-in の GL 実行時最適化)。
    /// baked(PxSpriteAtlas.bake 済み)の regionRect を貼った Item.Sprite 1 個を返す —
    /// box 列(draw)と同じ画素を被覆する(NEAREST・整数 scale・色は argbOf で同一丸め)。
    /// texture はアトラスを登録した論理名(GL は TextureRegistry、SoftRaster は texturePath の鍵)。
    /// 注意: regionRect 付き Sprite は Render.drawWith(textureInfoOf)経路でだけ解決される。
    /// 既定の box 列と違い tint/blend は持たない最小形 — 必要なら呼び手がパイプ修飾で足す。
    pub def drawQuad(doc: PxSpriteDoc.Doc, baked: PxSpriteAtlas.Baked, texture: String,
                     sprite: String, frame: String, at: Vec2.Vec2,
                     flipX: Bool, scale: Int32, z: Int32): List[Render.PlacedItem] =
        if (scale <= 0 or baked#side <= 0) Nil
        else match (Map.get(sprite, doc#sprites), PxSpriteAtlas.regionOf(baked, sprite, frame)) {
            case (Some(sp), Some(rect)) => {
                let s = Int32.toFloat64(scale);
                let sideF = Int32.toFloat64(baked#side);
                let ax = sp#anchor#x;
                let ay = sp#anchor#y;
                // 置き場所の規約は draw(box 列)と同一: 「anchor セルの左上 = at」。
                // flipX は Item.Sprite の flipH(scale 符号)で行うので、描画は pos から
                // 左へ w×s 伸びる — 右端が at + (ax+1)×s に来るよう pos を置く。
                let pos: Vec2.Vec2 =
                    if (flipX) { x = at#x + (ax + 1.0) * s, y = at#y - ay * s }
                    else       { x = at#x - ax * s,         y = at#y - ay * s };
                { at = pos,
                  item = Render.Item.Sprite({
                      texture = texture,
                      tint = { r = 1.0f32, g = 1.0f32, b = 1.0f32 },
                      alpha = 1.0f32,
                      // Drawable の表示寸法 = テクスチャ全寸 × scale なので、
                      // 「コマ px × 整数 scale」になるよう辺長で割り戻す。
                      scale = { x = s * rect#size#x / sideF, y = s * rect#size#y / sideF },
                      rotation = 0.0, centered = false,
                      flipH = flipX, flipV = false,
                      regionRect = Some(rect), zIndex = z,
                      blend = DrawCmd.BlendMode.Normal }) } :: Nil
            }
            case _ => Nil
        }

    /// draw の座標計算だけ(テストと当たり判定用)。矩形は行ごと・左から右の順。
    pub def runs(doc: PxSpriteDoc.Doc, sprite: String, frame: String, at: Vec2.Vec2,
                 flipX: Bool, scale: Int32): List[Run] =
        if (scale <= 0) Nil
        else match Map.get(sprite, doc#sprites) {
            case None     => Nil
            case Some(sp) => match Map.get(frame, sp#frames) {
                case None       => Nil
                case Some(rows) => {
                    let s = Int32.toFloat64(scale);
                    let ax = if (flipX) mirroredAnchorX(rows, sp#anchor#x) else sp#anchor#x;
                    let ay = sp#anchor#y;
                    rows |> List.zipWithIndex |> List.flatMap(entry -> {
                        let (r, row) = entry;
                        let y = at#y + (Int32.toFloat64(r) - ay) * s;
                        rowRuns(doc#legend, row) |> List.map(rn -> {
                            let (c0, n, key) = rn;
                            let x = if (flipX)
                                    at#x + (ax - Int32.toFloat64(c0 + n) + 1.0) * s
                                else at#x + (Int32.toFloat64(c0) - ax) * s;
                            ({ x = x, y = y, w = Int32.toFloat64(n) * s, h = s, key = key }: Run)
                        })
                    })
                }
            }
        }

    /// flipX 時の anchor の鏡映: 幅 w の格子で x は w-1-x へ写る(draw 側の規約)。
    def mirroredAnchorX(rows: List[String], ax: Float64): Float64 =
        let w = rows |> List.foldLeft((acc, row) -> Int32.max(acc, String.length(row)), 0);
        Int32.toFloat64(w - 1) - ax

    /// 1 行を (開始列, 長さ, 色キー) の rn 列へ。legend に無い文字は透明で rn を切る。
    def rowRuns(legend: Map[Char, String], row: String): List[(Int32, Int32, String)] =
        let cells = String.toList(row) |> List.zipWithIndex
            |> List.map(entry -> { let (i, ch) = entry; (i, Map.get(ch, legend)) });
        let step = (acc: (List[(Int32, Int32, String)], Option[(Int32, Int32, String)]),
                    cell: (Int32, Option[String])) -> {
            let (done, cur) = acc;
            let (i, keyOpt) = cell;
            match (cur, keyOpt) {
                case (None, None)           => (done, None)
                case (None, Some(k))        => (done, Some((i, 1, k)))
                case (Some(rn), None)      => (rn :: done, None)
                case (Some(rn), Some(k))   => {
                    let (c0, n, k0) = rn;
                    if (k == k0) (done, Some((c0, n + 1, k0)))
                    else (rn :: done, Some((i, 1, k)))
                }
            }
        };
        let (done, cur) = List.foldLeft(step, (Nil, None), cells);
        let all = match cur { case Some(rn) => rn :: done case None => done };
        List.reverse(all)
}
