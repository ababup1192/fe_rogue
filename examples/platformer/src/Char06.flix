// 鬼火ランタン（WISP-LANTERN） — 持ち主を失った吊りランタンに、青白い鬼火が棲みついた。
// 鉄枠と真鍮の「機械」の殻 × 中で燃える鬼火の「幻想」。浮遊ボブで進み、ブレーキは正面格子
// からの逆噴射、空中はガラス 4 枚が展開して鬼火が剥き出しの火柱になる。

mod Char06 {

    use CharStage.Mode

    pub def name(): String = "WISP-LANTERN"

    // ── 色（DB32 / 255）──

    def ironDark(): Color   = { r =  50.0f32 / 255.0f32, g =  60.0f32 / 255.0f32, b =  57.0f32 / 255.0f32 }  // 323c39 支柱の鉄
    def iron(): Color       = { r =  89.0f32 / 255.0f32, g =  86.0f32 / 255.0f32, b =  82.0f32 / 255.0f32 }  // 595652 底板と笠
    def brass(): Color      = { r = 138.0f32 / 255.0f32, g = 111.0f32 / 255.0f32, b =  48.0f32 / 255.0f32 }  // 8a6f30 真鍮の飾り
    def glassGlow(): Color  = { r =  48.0f32 / 255.0f32, g =  96.0f32 / 255.0f32, b = 130.0f32 / 255.0f32 }  // 306082 ガラスの奥の照り
    def flameOuter(): Color = { r =  99.0f32 / 255.0f32, g = 155.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 }  // 639bff 炎の外縁・尾
    def flameMid(): Color   = { r =  95.0f32 / 255.0f32, g = 205.0f32 / 255.0f32, b = 228.0f32 / 255.0f32 }  // 5fcde4 炎の中身
    def flameCore(): Color  = { r = 203.0f32 / 255.0f32, g = 219.0f32 / 255.0f32, b = 252.0f32 / 255.0f32 }  // cbdbfc 炎の芯

    // ── 小道具 ──

    def clamp01(v: Float64): Float64 = Float64.min(1.0, Float64.max(0.0, v))

    /// 足元中心 base からのオフセットで置く。
    def at(base: Vec2.Vec2, dx: Float64, dy: Float64, item: Render.RenderItem): Render.Placed =
        { at = { x = base#x + dx, y = base#y + dy }, item = item }

    /// 足元の照り返し（浮遊している証拠の光だまり）。空中では高さに応じて薄くなる。
    def groundGlow(base: Vec2.Vec2, strength: Float64): List[Render.Placed] =
        let lift = clamp01((0.0 - base#y) / 60.0);
        let a = RenderUtil.f32(Float64.max(0.0, strength * (1.0 - lift)));
        ({ at = { x = base#x - 9.0, y = -2.0 },
           item = Render.box({ x = 18.0, y = 3.0 }, glassGlow(), 8) |> Render.rounded(1.5) |> Render.fade(a) }) :: Nil

    /// ランタン本体（鉄枠+ガラス+吊り具）。hover = 底板の高さ / capShift = 笠のシアー量
    /// （前傾・後傾を上部のずれで表す）/ ringSway = 吊りリングの揺れ / wS,hS = スカッシュ比 /
    /// panelOpen = ガラス展開量（0 = 閉・空中で開く）。
    def lantern(base: Vec2.Vec2, hover: Float64, capShift: Float64, ringSway: Float64,
                wS: Float64, hS: Float64, panelOpen: Float64): List[Render.Placed] =
        let h = hover;
        let capY = 0.0 - h - 14.0 * hS - 2.5 * Float64.min(panelOpen, 1.0);
        let glass =
            if (panelOpen <= 0.01)
                at(base, -4.0 * wS, 0.0 - h - 12.0 * hS,
                   Render.box({ x = 8.0 * wS, y = 10.0 * hS }, glassGlow(), 9)) :: Nil
            else {
                // ガラス 4 枚が蝶番から外へ跳ね開く（空中の変形）。鬼火が剥き出しになる。
                let o = panelOpen;
                at(base, -6.0 - 4.5 * o, 0.0 - h - 13.0 - 1.5 * o,
                   Render.box({ x = 2.0, y = 4.5 }, glassGlow(), 10)) ::
                at(base, -6.0 - 2.5 * o, 0.0 - h - 7.5 + 0.5 * o,
                   Render.box({ x = 2.0, y = 4.5 }, glassGlow(), 10)) ::
                at(base, 4.0 + 4.5 * o, 0.0 - h - 13.0 - 1.5 * o,
                   Render.box({ x = 2.0, y = 4.5 }, glassGlow(), 10)) ::
                at(base, 4.0 + 2.5 * o, 0.0 - h - 7.5 + 0.5 * o,
                   Render.box({ x = 2.0, y = 4.5 }, glassGlow(), 10)) :: Nil
            };
        let frame =
            at(base, -6.0 * wS, 0.0 - h - 2.0 * hS,
               Render.box({ x = 12.0 * wS, y = 2.0 * hS }, iron(), 10)) ::
            at(base, -6.0 * wS, 0.0 - h - 12.0 * hS,
               Render.box({ x = 2.0 * wS, y = 10.0 * hS }, ironDark(), 10)) ::
            at(base, 4.0 * wS, 0.0 - h - 12.0 * hS,
               Render.box({ x = 2.0 * wS, y = 10.0 * hS }, ironDark(), 10)) ::
            at(base, -6.0 * wS + capShift, capY - 2.0 * hS,
               Render.box({ x = 12.0 * wS, y = 2.0 * hS }, iron(), 10)) ::
            at(base, -2.0 + capShift, capY - 4.0 * hS,
               Render.box({ x = 4.0, y = 2.0 * hS }, brass(), 10)) :: Nil;
        // 吊りリング: 真鍮の輪の中を暗色で抜いて輪に見せる。
        let ringX = capShift + ringSway;
        let ringCy = capY - 4.0 * hS - 2.0;
        let ring =
            at(base, ringX - 2.2, ringCy - 2.2, Render.circle(2.2, brass(), 9)) ::
            at(base, ringX - 1.1, ringCy - 1.1, Render.circle(1.1, ironDark(), 10)) :: Nil;
        List.flatten(glass :: frame :: ring :: Nil)

    /// 鬼火本体（芯 + 中身 + 後方へたなびく尾）。tipDx = 尾の先端の相対 x（0 なら尾なし）。
    def wisp(base: Vec2.Vec2, cx: Float64, cy: Float64, coreR: Float64, midR: Float64,
             tipDx: Float64): List[Render.Placed] =
        let tail =
            if (Float64.abs(tipDx) <= 0.3) Nil
            else at(base, cx, cy,
                    Render.polygon({ x = tipDx, y = 0.0 } :: { x = 0.0, y = 0.0 - midR * 0.75 } ::
                                   { x = 0.0, y = midR * 0.75 } :: Nil,
                                   flameOuter(), 10) |> Render.fade(0.75f32)) :: Nil;
        let body =
            at(base, cx - midR, cy - midR, Render.circle(midR, flameMid(), 11)) ::
            at(base, cx - coreR, cy - coreR * 1.25, Render.circle(coreR, flameCore(), 12)) :: Nil;
        List.flatten(tail :: body :: Nil)

    /// 走り・ダッシュで後方へこぼれる火の粉。t と番号だけから位置を導く（閉形式）。
    def ember(base: Vec2.Vec2, f: Float64, hover: Float64, t: Float64, i: Int32): Render.Placed =
        let fi = Int32.toFloat64(i);
        let dx = 0.0 - f * (2.5 + 3.2 * fi + 1.2 * Curve.triWave(t * 2.3 + fi * 0.37));
        let dy = 0.0 - hover - 7.0 + 2.2 * Curve.triWave(t * 3.1 + fi * 0.71);
        let a = RenderUtil.f32(0.55 - 0.15 * fi);
        at(base, dx - 1.0, dy - 1.0, Render.circle(1.0, flameMid(), 11) |> Render.fade(a))

    // ── 本体 ──

    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        let base = stage#pos;
        let f = stage#facing;
        let t = stage#t;
        let sp = clamp01(Float64.abs(stage#vx) / 280.0);
        match stage#mode {
            case Mode.RunMode =>
                // 浮遊ボブ走行: 位置駆動のボブ（足が無いので滑らない）+ 上部だけ前へ倒れる
                // シアー + 鬼火が後方へたなびく。速いほど火の粉がこぼれる。
                let hover = 5.0 + 1.5 * Curve.triWave(base#x * 0.045);
                let lean = 3.5 * sp * f;
                let cy = 0.0 - hover - 7.0;
                let sparks =
                    if (sp > 0.25) ember(base, f, hover, t, 0) :: ember(base, f, hover, t, 1) :: Nil
                    else Nil;
                List.flatten(
                    groundGlow(base, 0.3) ::
                    lantern(base, hover, lean, lean * 0.4, 1.0, 1.0, 0.0) ::
                    wisp(base, f * 0.8, cy, 2.4, 3.8, 0.0 - f * (3.0 + 5.0 * sp)) ::
                    sparks :: Nil)
            case Mode.DashMode =>
                // ダッシュの見せ場: 底の真鍮扉が開き、火の粉の帯が 2 本 後方へ流れる。
                // 尾も倍にたなびく（体色は不変・光の帯だけが増える）。
                let dashK = clamp01(stage#modeT / 0.4) * sp;
                let hover = 4.5 + 1.0 * Curve.triWave(base#x * 0.045);
                let lean = f * (3.5 * sp + 2.5 * dashK);
                let cy = 0.0 - hover - 7.0;
                let len1 = 8.0 + 10.0 * dashK;
                let len2 = 5.0 + 8.0 * dashK;
                let bx1 = if (f > 0.0) -4.0 - len1 else 4.0;
                let bx2 = if (f > 0.0) -4.0 - len2 else 4.0;
                let hatchX = if (f > 0.0) -7.5 else 4.5;
                let streams =
                    at(base, bx1, 0.0 - hover - 3.0,
                       Render.box({ x = len1, y = 1.5 }, flameOuter(), 9)
                       |> Render.rounded(0.75) |> Render.fade(RenderUtil.f32(0.35 + 0.3 * dashK))) ::
                    at(base, bx2, 0.0 - hover - 5.5,
                       Render.box({ x = len2, y = 1.2 }, flameMid(), 9)
                       |> Render.rounded(0.6) |> Render.fade(RenderUtil.f32(0.25 + 0.25 * dashK))) ::
                    at(base, hatchX, 0.0 - hover - 1.0,
                       Render.box({ x = 3.0, y = 1.5 }, brass(), 10)) :: Nil;
                List.flatten(
                    groundGlow(base, 0.35) ::
                    lantern(base, hover, lean, lean * 0.4, 1.0, 1.0, 0.0) ::
                    wisp(base, f * 1.2, cy, 2.5, 4.0, 0.0 - f * (6.0 + 6.0 * dashK)) ::
                    streams ::
                    (ember(base, f, hover, t, 0) :: ember(base, f, hover, t, 1) ::
                     ember(base, f, hover, t, 2) :: Nil) :: Nil)
            case Mode.SkidMode =>
                // 逆噴射ブレーキ: 笠が大きく後ろへ倒れ、正面格子から鬼火を噴き出して止まる。
                // 噴射の長さは残速に比例（止まるほど細る）。
                let k = sp;
                let hover = 2.2;
                let cy = 0.0 - hover - 7.0;
                let blastLen = 3.5 + 7.0 * k;
                let blast =
                    at(base, f * 5.0, cy,
                       Render.polygon({ x = f * blastLen, y = 0.0 } :: { x = 0.0, y = -3.5 - 1.5 * k } ::
                                      { x = 0.0, y = 3.5 + 1.5 * k } :: Nil,
                                      flameMid(), 11) |> Render.fade(0.85f32)) ::
                    at(base, f * 5.0, cy,
                       Render.polygon({ x = f * (2.0 + 4.0 * k), y = 0.0 } :: { x = 0.0, y = -1.8 } ::
                                      { x = 0.0, y = 1.8 } :: Nil, flameCore(), 12)) ::
                    at(base, f * (6.0 + 6.5 * k) - 1.0, cy + 2.0,
                       Render.circle(1.0, flameCore(), 12) |> Render.fade(RenderUtil.f32(0.2 + 0.6 * k))) ::
                    at(base, f * (5.0 + 5.5 * k) - 0.8, cy - 4.8,
                       Render.circle(0.8, flameMid(), 12) |> Render.fade(RenderUtil.f32(0.15 + 0.55 * k))) :: Nil;
                List.flatten(
                    groundGlow(base, 0.4) ::
                    lantern(base, hover, 0.0 - f * 6.5, 0.0 - f * 2.0, 1.0, 1.0, 0.0) ::
                    wisp(base, f * 2.5, cy, 2.2, 3.4, 0.0) ::
                    blast :: Nil)
            case Mode.JumpMode =>
                // 展開: ガラス 4 枚が跳ね開き、笠が持ち上がり、鬼火が火柱になって立ち上る。
                let opn = clamp01(stage#modeT / 0.15);
                let hover = 5.0;
                let cy = 0.0 - hover - 8.0;
                let pillarLen = 5.0 + 7.0 * opn;
                let glowR = 5.0 + 3.0 * opn;
                let coreR = 2.6 + 0.8 * opn;
                let pillar =
                    at(base, 0.0, cy,
                       Render.polygon({ x = 0.0, y = 0.0 - pillarLen } :: { x = -3.2, y = 2.5 } ::
                                      { x = 3.2, y = 2.5 } :: Nil, flameMid(), 11)) ::
                    at(base, 0.0 - coreR, cy - coreR - 1.0, Render.circle(coreR, flameCore(), 12)) ::
                    at(base, 0.0 - glowR, cy - glowR,
                       Render.circle(glowR, flameOuter(), 8) |> Render.fade(0.3f32)) :: Nil;
                List.flatten(
                    groundGlow(base, 0.3) ::
                    lantern(base, hover, 0.0, 0.0, 1.0, 1.0, opn) ::
                    pillar :: Nil)
            case Mode.FallMode =>
                // 落下: パネルは開いたまま少しずつ広がり、炎は落下風で上へたなびく。
                let opn = 1.0 + clamp01(stage#modeT / 0.3) * 0.3;
                let hover = 5.0;
                let cy = 0.0 - hover - 7.5;
                let flut = Curve.tri(0.25, t);
                let streamUp =
                    at(base, 0.0, cy,
                       Render.polygon({ x = 0.0, y = 0.0 - (8.0 + 3.0 * flut) } :: { x = -2.4, y = 1.8 } ::
                                      { x = 2.4, y = 1.8 } :: Nil,
                                      flameOuter(), 10) |> Render.fade(0.7f32)) ::
                    at(base, -3.4, cy - 3.4, Render.circle(3.4, flameMid(), 11)) ::
                    at(base, -2.2, cy - 3.2, Render.circle(2.2, flameCore(), 12)) :: Nil;
                List.flatten(
                    groundGlow(base, 0.3) ::
                    lantern(base, hover, 0.0, 0.0, 1.0, 1.0, opn) ::
                    streamUp :: Nil)
            case Mode.LandMode =>
                // 着地: パネルが閉じて殻ごとスカッシュ、炎はガラスの底で横に潰れ、火花が散る。
                let k = clamp01(stage#modeT / 0.2);
                let sq = 1.0 - k;
                let hover = 1.0;
                let wS = 1.0 + 0.3 * sq;
                let hS = 1.0 - 0.28 * sq;
                let splatW = 9.0 + 4.0 * sq;
                let splat =
                    at(base, 0.0 - splatW / 2.0, 0.0 - hover - 5.5,
                       Render.box({ x = splatW, y = 3.0 }, flameMid(), 11) |> Render.rounded(1.5)) ::
                    at(base, -2.0, 0.0 - hover - 6.5, Render.circle(2.0, flameCore(), 12)) :: Nil;
                let sparkA = RenderUtil.f32((1.0 - k) * 0.65);
                let sparks =
                    at(base, 2.5 + 6.0 * k, -1.5 - 3.0 * k,
                       Render.circle(1.1, flameMid(), 12) |> Render.fade(sparkA)) ::
                    at(base, 0.0 - (2.5 + 6.0 * k) - 2.2, -1.5 - 3.0 * k,
                       Render.circle(1.1, flameMid(), 12) |> Render.fade(sparkA)) ::
                    at(base, 1.5 + 4.0 * k, -0.5 - 5.5 * k,
                       Render.circle(0.8, flameCore(), 12) |> Render.fade(sparkA)) ::
                    at(base, 0.0 - (1.5 + 4.0 * k) - 1.6, -0.5 - 5.5 * k,
                       Render.circle(0.8, flameCore(), 12) |> Render.fade(sparkA)) :: Nil;
                List.flatten(
                    groundGlow(base, 0.3 + 0.3 * sq) ::
                    lantern(base, hover, 0.0, 0.0, wS, hS, 0.0) ::
                    splat :: sparks :: Nil)
            case Mode.IdleMode =>
                // 待機: ゆっくり浮き沈み、炎は 2 周波の呼吸フリッカ、吊りリングが揺れる。
                let hover = 5.0 + 1.3 * Curve.triWave(t * 0.45);
                let flick = 1.0 + 0.16 * Curve.tri(0.9, t) + 0.08 * Curve.tri(0.23, t + 0.1);
                let sway = 1.6 * Curve.triWave(t * 0.4 + 0.3);
                let cy = 0.0 - hover - 7.0;
                let wanderX = 0.8 * Curve.triWave(t * 0.6);
                List.flatten(
                    groundGlow(base, 0.25) ::
                    lantern(base, hover, 0.0, sway, 1.0, 1.0, 0.0) ::
                    wisp(base, wanderX, cy, 2.4 * flick, 3.8 * flick, 0.0) :: Nil)
        }
}
