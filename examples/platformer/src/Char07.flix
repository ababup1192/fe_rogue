// lint-view: 対象外 — 手触り検証台の箱組みキャラ。絵の見本にしない（新キャラは PxSprite+PxShade で作る）。
// ルーンの人工衛星（RUNE-ORBITER） — 古代文明が打ち上げた魔導コアが、地表に降りて旅をしている。
// ひし形の装甲コア（機械）の周りを 2 基のルーン衛星（幻想）が周回する。歩行は「光柱ブリンク」:
// 足元に光の柱を周期的に明滅させ、その位相でホップして進む。ブレーキは正面に展開するルーンの光壁。
// この箱組みは旧様式(RawDraw 大量使用の前例にしない)。新キャラは PxSprite+PxShade を第一候補に。

mod Char07 {

    use CharStage.Mode

    pub def name(): String = "RUNE-ORBITER"

    // ── 色（DB32 / 255）──

    def plate(): Color    = { r =  63.0f32 / 255.0f32, g =  63.0f32 / 255.0f32, b = 116.0f32 / 255.0f32 }  // 3f3f74 コア装甲
    def plateHi(): Color  = { r =  91.0f32 / 255.0f32, g = 110.0f32 / 255.0f32, b = 225.0f32 / 255.0f32 }  // 5b6ee1 装甲のハイライト
    def rune(): Color     = { r = 215.0f32 / 255.0f32, g = 123.0f32 / 255.0f32, b = 186.0f32 / 255.0f32 }  // d77bba ルーン光・衛星
    def runeDeep(): Color = { r = 118.0f32 / 255.0f32, g =  68.0f32 / 255.0f32, b =  98.0f32 / 255.0f32 }  // 764462 光壁のルーン刻印
    def beam(): Color     = { r = 203.0f32 / 255.0f32, g = 219.0f32 / 255.0f32, b = 252.0f32 / 255.0f32 }  // cbdbfc 光柱・光壁・光条
    def spark(): Color    = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 }  // ffffff 閃光

    // ── 小道具 ──

    def clamp01(v: Float64): Float64 = Float64.min(1.0, Float64.max(0.0, v))

    def fract(v: Float64): Float64 = v - Float64.floor(v)

    /// 足元中心 base からのオフセットで置く。
    def at(base: Vec2.Vec2, dx: Float64, dy: Float64, item: Render.Item): Render.PlacedItem =
        { at = { x = base#x + dx, y = base#y + dy }, item = item }

    /// コア本体。cy = コア中心の高さ / tilt = 上頂点の前後ずれ（前傾・後傾）/
    /// splitK = 上下分離量（空中の変形・0 で密着）/ wS,hS = スカッシュ比。
    /// 密着中はルーンのひし形が脈動し、分離中は内部の魔力光が露出する。
    def core(base: Vec2.Vec2, f: Float64, t: Float64, cx: Float64, cy: Float64,
             tilt: Float64, wS: Float64, hS: Float64, splitK: Float64): List[Render.PlacedItem] =
        let upper =
            at(base, cx, cy - splitK,
               RawDraw.polygon({ x = tilt, y = -7.0 * hS } :: { x = 6.0 * wS, y = 0.0 } ::
                              { x = -6.0 * wS, y = 0.0 } :: Nil, plate(), 10));
        let upperHi =
            at(base, cx, cy - splitK,
               RawDraw.polygon({ x = tilt, y = -7.0 * hS } :: { x = 6.0 * wS, y = 0.0 } ::
                              { x = tilt * 0.4, y = -4.2 * hS } :: Nil, plateHi(), 11));
        let lower =
            at(base, cx, cy + splitK,
               RawDraw.polygon({ x = 6.0 * wS, y = 0.0 } :: { x = 0.0, y = 7.0 * hS } ::
                              { x = -6.0 * wS, y = 0.0 } :: Nil, plate(), 10));
        let inner =
            if (splitK > 0.05) {
                // 分離中: 装甲の隙間から内部の魔力光が漏れる。
                at(base, cx - 4.0, cy - 4.0, RawDraw.circle(4.0, rune(), 8) |> Render.fade(0.45)) ::
                at(base, cx - 2.2, cy - 2.2, RawDraw.circle(2.2, spark(), 9)) :: Nil
            } else {
                // 密着中: 中央のルーンが脈動し、進行方向を見る光の目が灯る。
                let pw = 2.6 + 0.7 * Curve.tri(1.3, t);
                at(base, cx, cy,
                   RawDraw.polygon({ x = 0.0, y = 0.0 - pw * 1.4 } :: { x = pw, y = 0.0 } ::
                                  { x = 0.0, y = pw * 1.4 } :: { x = 0.0 - pw, y = 0.0 } :: Nil,
                                  rune(), 11)) ::
                at(base, cx + f * 1.6 - 1.1, cy - 1.6, RawDraw.circle(1.1, beam(), 12)) :: Nil
            };
        let haloA = 0.28 + 0.24 * Curve.tri(0.8, t);
        let halo =
            at(base, cx - 4.0 + tilt * 0.5, cy - 7.0 * hS - splitK - 4.0,
               RawDraw.box({ x = 8.0, y = 1.0 }, beam(), 9)
               |> Render.rounded(0.5) |> Render.fade(haloA)) :: Nil;
        List.flatten((upper :: upperHi :: lower :: Nil) :: inner :: halo :: Nil)

    /// ルーン衛星 1 基（小さなひし形 + 芯の光）。z は周回の前後で呼び手が決める。
    def shard(base: Vec2.Vec2, dx: Float64, dy: Float64, z: Int32): List[Render.PlacedItem] =
        at(base, dx, dy,
           RawDraw.polygon({ x = 0.0, y = -3.0 } :: { x = 2.2, y = 0.0 } ::
                          { x = 0.0, y = 3.0 } :: { x = -2.2, y = 0.0 } :: Nil, rune(), z)) ::
        at(base, dx - 0.8, dy - 0.8, RawDraw.circle(0.8, beam(), z + 1)) :: Nil

    /// 光柱ブリンク: 足元からコア中心まで立つ光の柱と、地面の照り。a が小さければ描かない。
    def pillar(base: Vec2.Vec2, w: Float64, cy: Float64, a: Float64): List[Render.PlacedItem] =
        if (a <= 0.02) Nil
        else {
            let aF = a;
            at(base, 0.0 - w / 2.0, cy,
               RawDraw.box({ x = w, y = 0.0 - cy }, beam(), 8)
               |> Render.rounded(w / 2.0) |> Render.fade(aF)) ::
            ({ at = { x = base#x - w * 1.4, y = -2.0 },
               item = RawDraw.box({ x = w * 2.8, y = 2.0 }, beam(), 8)
               |> Render.rounded(1.0) |> Render.fade(aF) }) :: Nil
        }

    /// ダッシュ中、後方へ流れて消える光のゲート（縦の光帯）。phase で 2 枚をずらす。
    def gate(base: Vec2.Vec2, f: Float64, cy: Float64, dashK: Float64, t: Float64,
             phase: Float64): List[Render.PlacedItem] =
        let g = fract(t * 2.6 + phase);
        let a = (1.0 - g) * 0.45 * dashK;
        if (a <= 0.02) Nil
        else
            at(base, 0.0 - f * (5.0 + 25.0 * g) - 0.8, cy - 9.0,
               RawDraw.box({ x = 1.6, y = 18.0 }, beam(), 8)
               |> Render.rounded(0.8) |> Render.fade(a)) :: Nil

    /// 光壁の面に浮かぶ小さなルーン刻印。
    def wallRune(base: Vec2.Vec2, f: Float64, dy: Float64, k: Float64): Render.PlacedItem =
        at(base, f * 10.0, dy,
           RawDraw.polygon({ x = 0.0, y = -2.0 } :: { x = 1.5, y = 0.0 } ::
                          { x = 0.0, y = 2.0 } :: { x = -1.5, y = 0.0 } :: Nil, runeDeep(), 10)
           |> Render.fade(0.35 + 0.45 * k))

    // ── 本体 ──

    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        let base = stage#pos;
        let f = stage#facing;
        let t = stage#t;
        let sp = clamp01(Float64.abs(stage#vx) / 280.0);
        match stage#mode {
            case Mode.RunMode =>
                // 光柱ブリンク歩行: 20px ごとに柱が鋭く明滅し、その位相でコアがホップする。
                // 衛星は速度に応じて周回の中心が後ろへ流れる（慣性の表現）。
                let s = Curve.tri(1.0, base#x * 0.05);
                let flashK = s * s * s * s * s;
                let cy = 0.0 - (11.5 + 2.2 * s);
                let tilt = f * 2.5 * sp;
                let ph = t * 0.9;
                let trail = 0.0 - f * 3.0 * sp;
                let sh1x = trail + 8.0 * Curve.triWave(ph);
                let sh1y = cy + 3.2 * Curve.triWave(ph + 0.25);
                let z1 = if (Curve.triWave(ph + 0.25) >= 0.0) 12 else 8;
                let sh2x = trail + 8.0 * Curve.triWave(ph + 0.5);
                let sh2y = cy + 3.2 * Curve.triWave(ph + 0.75);
                let z2 = if (Curve.triWave(ph + 0.75) >= 0.0) 12 else 8;
                List.flatten(
                    pillar(base, 3.0, cy, 0.1 + 0.45 * flashK) ::
                    core(base, f, t, 0.0, cy, tilt, 1.0, 1.0, 0.0) ::
                    shard(base, sh1x, sh1y, z1) ::
                    shard(base, sh2x, sh2y, z2) :: Nil)
            case Mode.DashMode =>
                // ダッシュの見せ場: 衛星が周回をやめて後方スラスタ隊形にドッキングし、
                // 光条を引く。さらに光のゲートが 2 枚、後方へ流れては消える（体色は不変）。
                let dashK = clamp01(stage#modeT / 0.35) * sp;
                let s = Curve.tri(1.0, base#x * 0.05);
                let flashK = s * s * s * s * s;
                let cy = 0.0 - (12.0 + 1.2 * Curve.triWave(base#x * 0.05));
                let tilt = f * (2.5 * sp + 2.0 * dashK);
                let sdx = 0.0 - f * 7.5;
                let len = 5.0 + 9.0 * dashK;
                let streakA = 0.28 + 0.34 * dashK;
                let sbx = if (f > 0.0) sdx - 1.0 - len else sdx + 1.0;
                let streaks =
                    at(base, sbx, cy - 4.1,
                       RawDraw.box({ x = len, y = 1.2 }, beam(), 9)
                       |> Render.rounded(0.6) |> Render.fade(streakA)) ::
                    at(base, sbx, cy + 2.9,
                       RawDraw.box({ x = len, y = 1.2 }, beam(), 9)
                       |> Render.rounded(0.6) |> Render.fade(streakA)) :: Nil;
                List.flatten(
                    pillar(base, 3.0, cy, 0.08 + 0.35 * flashK) ::
                    gate(base, f, cy, dashK, t, 0.0) ::
                    gate(base, f, cy, dashK, t, 0.5) ::
                    streaks ::
                    core(base, f, t, 0.0, cy, tilt, 1.0, 1.0, 0.0) ::
                    shard(base, sdx, cy - 3.5, 9) ::
                    shard(base, sdx, cy + 3.5, 9) :: Nil)
            case Mode.SkidMode =>
                // ルーンの光壁ブレーキ: 正面に縦の魔法障壁を展開し、衛星が壁に激突して
                // 押し止める。コアは大きく後傾し、接点に白い閃光が散る。強さは残速に比例。
                let k = sp;
                let cy = -11.0;
                let cx = 0.0 - f * 2.0;
                let wallA = 0.2 + 0.4 * k;
                let wall =
                    at(base, f * 10.0 - 1.0, -25.5,
                       RawDraw.box({ x = 2.0, y = 24.0 }, beam(), 9)
                       |> Render.rounded(1.0) |> Render.fade(wallA)) ::
                    wallRune(base, f, -6.0, k) ::
                    wallRune(base, f, -13.0, k) ::
                    wallRune(base, f, -20.0, k) :: Nil;
                let sparks =
                    at(base, f * 8.6 - 0.9, cy - 5.4,
                       RawDraw.circle(0.9, spark(), 13) |> Render.fade(0.25 + 0.55 * k)) ::
                    at(base, f * 8.4 - 0.9, cy + 1.1,
                       RawDraw.circle(0.9, spark(), 13) |> Render.fade(0.2 + 0.5 * k)) :: Nil;
                let drag =
                    ({ at = { x = base#x - 5.0, y = -2.0 },
                       item = RawDraw.box({ x = 10.0, y = 2.0 }, beam(), 8)
                       |> Render.rounded(1.0) |> Render.fade(0.35 * k) }) :: Nil;
                List.flatten(
                    wall :: drag ::
                    core(base, f, t, cx, cy, 0.0 - f * 4.5, 1.0, 1.0, 0.0) ::
                    shard(base, f * 6.5, cy - 3.5, 12) ::
                    shard(base, f * 6.5, cy + 3.0, 12) ::
                    sparks :: Nil)
            case Mode.JumpMode =>
                // 分離: コアが上下に割れて内部の魔力光が露出し、衛星は左右へ水平展開する。
                let opn = clamp01(stage#modeT / 0.18);
                let cy = -13.0;
                let splitK = 3.2 * opn;
                let spreadW = 6.5 + 3.0 * opn;
                List.flatten(
                    core(base, f, t, 0.0, cy, 0.0, 1.0, 1.0, splitK) ::
                    shard(base, spreadW, cy - 1.0, 12) ::
                    shard(base, 0.0 - spreadW, cy - 1.0, 12) :: Nil)
            case Mode.FallMode =>
                // 光傘降下: 衛星が頭上に回り込み、光の吊り糸でコアを吊るしてゆっくり揺れる。
                let cy = -12.0;
                let spreadW = 6.0 + 1.2 * Curve.triWave(t * 1.4);
                let cx = 1.2 * Curve.triWave(t * 1.4 + 0.25);
                let strings =
                    at(base, cx * 0.3 + spreadW - 0.4, cy - 10.0,
                       RawDraw.box({ x = 0.8, y = 9.0 }, beam(), 8) |> Render.fade(0.3)) ::
                    at(base, cx * 0.3 - spreadW - 0.4, cy - 10.0,
                       RawDraw.box({ x = 0.8, y = 9.0 }, beam(), 8) |> Render.fade(0.3)) :: Nil;
                List.flatten(
                    strings ::
                    core(base, f, t, cx, cy, 0.0, 1.0, 1.0, 0.0) ::
                    shard(base, cx * 0.3 + spreadW, cy - 11.5, 12) ::
                    shard(base, cx * 0.3 - spreadW, cy - 11.5, 12) :: Nil)
            case Mode.LandMode =>
                // 着地: 光柱が大きく閃き、衝撃リングが地を走り、衛星は先に地面へ突き刺さる。
                let k = clamp01(stage#modeT / 0.2);
                let cy = 0.0 - (8.5 + 3.5 * k);
                let wS = 1.0 + 0.32 * (1.0 - k);
                let hS = 1.0 - 0.3 * (1.0 - k);
                let ringW = 6.0 + 16.0 * k;
                let ring =
                    ({ at = { x = base#x - ringW / 2.0, y = -2.4 },
                       item = RawDraw.box({ x = ringW, y = 2.0 }, beam(), 9)
                       |> Render.rounded(1.0) |> Render.fade(0.5 * (1.0 - k)) }) :: Nil;
                let dustA = (1.0 - k) * 0.4;
                let dust =
                    at(base, 4.0 + 5.0 * k, -2.6, RawDraw.circle(1.0, rune(), 9) |> Render.fade(dustA)) ::
                    at(base, 0.0 - (4.0 + 5.0 * k) - 2.0, -2.6,
                       RawDraw.circle(1.0, rune(), 9) |> Render.fade(dustA)) :: Nil;
                List.flatten(
                    pillar(base, 5.0, cy, 0.55 * (1.0 - k) + 0.05) ::
                    ring :: dust ::
                    core(base, f, t, 0.0, cy, 0.0, wS, hS, 0.0) ::
                    shard(base, 6.5, -2.6, 12) ::
                    shard(base, -6.5, -2.6, 12) :: Nil)
            case Mode.IdleMode =>
                // 待機: 衛星がゆっくり周回し、ルーンが脈動し、駐機ビームがかすかに揺らめく。
                let ph = t * 0.4;
                let cy = 0.0 - (11.5 + 1.1 * Curve.triWave(t * 0.35));
                let sh1x = 9.0 * Curve.triWave(ph);
                let sh1y = cy + 3.5 * Curve.triWave(ph + 0.25);
                let z1 = if (Curve.triWave(ph + 0.25) >= 0.0) 12 else 8;
                let sh2x = 9.0 * Curve.triWave(ph + 0.5);
                let sh2y = cy + 3.5 * Curve.triWave(ph + 0.75);
                let z2 = if (Curve.triWave(ph + 0.75) >= 0.0) 12 else 8;
                List.flatten(
                    pillar(base, 3.0, cy, 0.06 + 0.05 * Curve.tri(1.9, t)) ::
                    core(base, f, t, 0.0, cy, 0.0, 1.0, 1.0, 0.0) ::
                    shard(base, sh1x, sh1y, z1) ::
                    shard(base, sh2x, sh2y, z2) :: Nil)
        }
}
