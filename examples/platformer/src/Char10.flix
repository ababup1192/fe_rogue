// ムレボシ — ひとつの体を持たない、12 粒の光でできた群体。粒はつねに群れの「型」へ
// 集まろうとし、型のほうが動きに合わせて雲・彗星・鏃・柱・輪と姿を変える。
// 急停止では粒がばらばらに吹き散り、速度が抜けるほど元の群れへ吸い戻される。
// モードが変わるたび一瞬だけ雲へ緩んでから次の型へ組み直すのが、この群れの呼吸。

mod Char10 {

    // ── 色（DB32・粒の配色は全モードで不変。ダッシュの合図は隊形変化と光条）──

    def sparkCyan(): Color = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}  // #5fcde4
    def sparkPale(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    def sparkDeep(): Color = {r = 0.188235f32, g = 0.376471f32, b = 0.509804f32}  // #306082

    /// キャラ選択ギャラリーに出す ASCII ラベル。
    pub def name(): String = "10 MUREBOSHI"

    /// 群れの粒数。
    def moteCount(): Int32 = 12

    /// 舞台状態から 1 コマ分の描画リストを組む。粒 12 個 + ダッシュ時のみ光条を足す。
    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        let motes = List.range(0, moteCount()) |> List.map(i -> mote(stage, i));
        match stage#mode {
            case CharStage.Mode.DashMode => List.append(streaks(stage), motes)
            case _                       => motes
        }

    // ── 粒 1 個の描画 ──

    /// i 番目の粒。大きさと色は番号から決まる固有値（先頭の 1 粒だけ大きく、群れの芯になる）。
    def mote(stage: CharStage.Stage, i: Int32): Render.PlacedItem =
        let off = motePos(stage, i);
        let r = if (i == 0) 2.2 else 1.2 + 0.9 * hashA(i);
        let layer = if (i == 0) 11 else 10;
        { at = {x = stage#pos#x + off#x - r, y = stage#pos#y + off#y - r},
          item = Render.circle(r, moteColor(i), layer) }

    /// 粒の色: 5 粒に 1 粒を淡色・深色に混ぜて、群れに奥行きを出す。
    def moteColor(i: Int32): Color =
        if (Int32.modulo(i, 5) == 1) sparkPale()
        else if (Int32.modulo(i, 5) == 3) sparkDeep()
        else sparkCyan()

    /// 粒番号から作る決定的な擬似乱数 [0,1)。個体差（大きさ・散り方向）はぜんぶこれ。
    def hashA(i: Int32): Float64 =
        fract(Vec2.sin((Int32.toFloat64(i) + 1.0) * 7.13) * 137.77)

    /// hashA と独立なもうひとつの擬似乱数 [0,1)。
    def hashB(i: Int32): Float64 =
        fract(Vec2.sin((Int32.toFloat64(i) + 1.0) * 3.71) * 311.73)

    def fract(x: Float64): Float64 = x - Float64.floor(x)

    // ── 粒の位置（モード → 型の選択と組み直しの補間）──

    /// i 番目の粒の足元基準オフセット。モードごとの型へ、雲を経由して組み直す。
    def motePos(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        match stage#mode {
            case CharStage.Mode.IdleMode => cloud(stage, i)
            case CharStage.Mode.RunMode  => Vec2.lerp(cloud(stage, i), comet(stage, i), reform(stage, 6.0))
            case CharStage.Mode.DashMode => Vec2.lerp(cloud(stage, i), dart(stage, i), reform(stage, 6.0))
            case CharStage.Mode.SkidMode => scatter(stage, i)
            case CharStage.Mode.JumpMode => Vec2.lerp(cloud(stage, i), column(stage, i), reform(stage, 5.0))
            case CharStage.Mode.FallMode => Vec2.lerp(cloud(stage, i), ring(stage, i), reform(stage, 6.0))
            case CharStage.Mode.LandMode =>
                let q = stage#modeT / 0.2;
                Vec2.lerp(groundLine(i, q), cloud(stage, i), q * q)
        }

    /// 型への組み直し係数 0→1。モードに入った直後は雲寄り＝「一瞬ほどけて集まり直す」。
    def reform(stage: CharStage.Stage, rate: Float64): Float64 =
        Float64.min(1.0, stage#modeT * rate)

    /// 待機の型: 内外 2 重のリングを粒が互い違いの向きで周回する、呼吸する雲。
    def cloud(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let fi = Int32.toFloat64(i);
        let ringR = (if (i < 7) 5.5 else 9.5) * (1.0 + 0.08 * Curve.triWave(stage#t * 0.7));
        let dir = if (Int32.modulo(i, 2) == 0) 1.0 else -1.0;
        let a = fi * 0.9 + stage#t * 0.7 * dir;
        {x = ringR * Vec2.cos(a), y = -11.0 + ringR * 0.75 * Vec2.sin(a)}

    /// 走りの型: 先頭が密で尾が散る彗星。尾ほど上へ流れ、縦の散らばりが増す。
    def comet(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let u = Int32.toFloat64(i) / 11.0;
        let bob = 1.4 * Curve.triWave(stage#pos#x * 0.05);
        {x = (6.0 - u * 17.0) * stage#facing,
         y = -10.5 - 3.5 * u + (hashB(i) - 0.5) * 2.0 * (1.0 + 3.0 * u) + bob * (1.0 - u)}

    /// ダッシュの型: 粒が上下 2 本の腕に整列した、進行方向を向く鏃（やじり）。
    /// 速いほど腕が閉じて鋭くなる。
    def dart(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let band = dashBand(stage);
        let k = Int32.toFloat64(i / 2);
        let side = if (Int32.modulo(i, 2) == 0) -1.0 else 1.0;
        {x = (9.0 - k * 3.4) * stage#facing,
         y = -11.0 + side * (0.8 + k * 1.9) * (1.0 - 0.25 * band) + (hashB(i) - 0.5) * 0.8}

    /// スキッドの型: 進行方向へ扇状に吹き散る。散り幅は残速度に比例するので、
    /// 減速しきるにつれて自然に元の群れへ吸い戻される（巻き戻し不要の閉形式）。
    def scatter(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let grip = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        let base = cloud(stage, i);
        let a = stage#t * 9.0 + Int32.toFloat64(i);
        {x = base#x * 0.55 + stage#facing * (0.25 + 0.5 * hashA(i)) * 13.0 * grip + 2.0 * grip * Vec2.cos(a),
         y = base#y * 0.55 - 4.95 - (0.15 + 0.85 * hashB(i)) * 13.0 * grip + 2.0 * grip * Vec2.sin(a)}

    /// 上昇の型: 足元から頭上へ注がれる螺旋の柱。粒の列がそのまま体になる。
    def column(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let u = Int32.toFloat64(i) / 11.0;
        {x = 2.0 * Vec2.sin(stage#t * 7.0 + u * 5.0), y = -2.0 - 24.0 * u}

    /// 落下の型: 全粒がひとつの輪（横長の光輪）に並んで回る。体が輪そのものになる。
    def ring(stage: CharStage.Stage, i: Int32): Vec2.Vec2 =
        let a = Int32.toFloat64(i) * 0.52359878 + stage#t * 3.5;
        {x = 9.5 * Vec2.cos(a), y = -13.0 + 5.5 * Vec2.sin(a)}

    /// 着地の型: 地面すれすれの一列に散って着水し、粒ごとに小さく跳ね直す。
    def groundLine(i: Int32, q: Float64): Vec2.Vec2 =
        let hop = Curve.arch01(q);
        {x = (hashA(i) - 0.5) * 20.0, y = -1.6 - (2.0 + 5.0 * hashB(i)) * hop}

    // ── ダッシュ付随のエフェクト ──

    /// ダッシュ強度 0..1（見かけ速度 160→280 を正規化）。
    def dashBand(stage: CharStage.Stage): Float64 =
        Float64.min(1.0, Float64.max(0.0, (Float64.abs(stage#vx) - 160.0) / 120.0))

    /// ダッシュの合図: 鏃の後方にたなびく細い光条 3 本。速いほど長く濃い。
    def streaks(stage: CharStage.Stage): List[Render.PlacedItem] =
        let band = dashBand(stage);
        if (band < 0.05) Nil
        else
            List.range(0, 3) |> List.map(j ->
                let fj = Int32.toFloat64(j);
                let len = (7.0 + 9.0 * band) * (1.0 - fj * 0.18);
                let cx = stage#pos#x - stage#facing * (8.0 + fj * 6.0);
                { at = {x = cx - len * 0.5, y = -14.5 + fj * 3.2},
                  item = Render.box({x = len, y = 1.2}, sparkPale(), 8)
                      |> Render.fade(RenderUtil.f32((0.5 - 0.13 * fj) * band)) })
}
