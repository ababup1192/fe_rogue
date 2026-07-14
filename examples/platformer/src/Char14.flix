// 鍛冶屋ガンテツ — 大鎚と生きる重量級の職人。
// 肩幅より広い胸板に革前掛けと赤鉢巻。相棒の大鎚を肩に担ぎ、一歩ごとに体が沈む
// 重い足取りで走る。急停止は大鎚を背後の地面へ突き立てて錨にし、火花を散らす。
// 跳ぶときは大鎚を頭上へ振りかぶり、着地は打ち下ろしと同時に地面がひび割れる。

mod Char14 {

    pub def name(): String = "14 SMITH"

    // ── 色（DB32・体色は不変）──
    def skin(): Color    = { r = 0.933333f32, g = 0.764706f32, b = 0.603922f32 } // eec39a
    def shirt(): Color   = { r = 0.270588f32, g = 0.156863f32, b = 0.235294f32 } // 45283c
    def apron(): Color   = { r = 0.400000f32, g = 0.223529f32, b = 0.192157f32 } // 663931
    def pants(): Color   = { r = 0.247059f32, g = 0.247059f32, b = 0.454902f32 } // 3f3f74
    def boot(): Color    = { r = 0.133333f32, g = 0.125490f32, b = 0.203922f32 } // 222034
    def hachimaki(): Color = { r = 0.674510f32, g = 0.196078f32, b = 0.196078f32 } // ac3232
    def beardC(): Color  = { r = 0.541176f32, g = 0.435294f32, b = 0.188235f32 } // 8a6f30
    def wood(): Color    = { r = 0.850980f32, g = 0.627451f32, b = 0.400000f32 } // d9a066
    def steel(): Color   = { r = 0.517647f32, g = 0.494118f32, b = 0.529412f32 } // 847e87
    def steelHi(): Color = { r = 0.607843f32, g = 0.678431f32, b = 0.717647f32 } // 9badb7
    def sparkY(): Color  = { r = 0.984314f32, g = 0.949020f32, b = 0.211765f32 } // fbf236
    def sparkO(): Color  = { r = 0.874510f32, g = 0.443137f32, b = 0.149020f32 } // df7126
    def whiteC(): Color  = { r = 1.000000f32, g = 1.000000f32, b = 1.000000f32 } // ffffff
    def blackC(): Color  = { r = 0.000000f32, g = 0.000000f32, b = 0.000000f32 } // 000000
    def dustC(): Color   = { r = 0.411765f32, g = 0.415686f32, b = 0.415686f32 } // 696a6a
    def stone(): Color   = { r = 0.349020f32, g = 0.337255f32, b = 0.321569f32 } // 595652
    def sweat(): Color   = { r = 0.372549f32, g = 0.803922f32, b = 0.894118f32 } // 5fcde4

    // ── 配置ヘルパ（足元中心のローカル座標・facing で x を鏡映）──

    def at(stage: CharStage.Stage, dx: Float64, dy: Float64): Vec2.Vec2 =
        { x = stage#pos#x + stage#facing * dx, y = stage#pos#y + dy }

    /// 中心 (dx, dy) の矩形。
    def boxC(stage: CharStage.Stage, dx: Float64, dy: Float64,
             w: Float64, h: Float64, c: Color, z: Int32): Render.PlacedItem =
        let p = at(stage, dx, dy);
        { at = { x = p#x - w / 2.0, y = p#y - h / 2.0 }, item = Render.box({ x = w, y = h }, c, z) }

    /// 中心 (dx, dy) の円。
    def circC(stage: CharStage.Stage, dx: Float64, dy: Float64,
              r: Float64, c: Color, z: Int32): Render.PlacedItem =
        let p = at(stage, dx, dy);
        { at = { x = p#x - r, y = p#y - r }, item = Render.circle(r, c, z) }

    /// (dx, dy) 起点の相対頂点ポリゴン。
    def polyC(stage: CharStage.Stage, dx: Float64, dy: Float64,
              verts: List[Vec2.Vec2], c: Color, z: Int32): Render.PlacedItem =
        let p = at(stage, dx, dy);
        let f = stage#facing;
        { at = { x = p#x, y = p#y },
          item = Render.polygon(List.map(v -> { x = f * v#x, y = v#y }, verts), c, z) }

    /// 2 点を結ぶ太さ th の棒（腕や柄を斜めに描く）。
    def strut(stage: CharStage.Stage, ax: Float64, ay: Float64,
              bx: Float64, by: Float64, th: Float64, c: Color, z: Int32): Render.PlacedItem =
        let ddx = bx - ax;
        let ddy = by - ay;
        let len0 = RenderUtil.sqrtF(ddx * ddx + ddy * ddy);
        let len = if (len0 < 0.001) 0.001 else len0;
        let nx = (0.0 - ddy) / len * th / 2.0;
        let ny = ddx / len * th / 2.0;
        polyC(stage, ax, ay,
              { x = nx, y = ny } :: { x = ddx + nx, y = ddy + ny } ::
              { x = ddx - nx, y = ddy - ny } :: { x = 0.0 - nx, y = 0.0 - ny } :: Nil,
              c, z)

    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))

    def fadeP(a: Float64, pl: Render.PlacedItem): Render.PlacedItem =
        { item = Render.fade(RenderUtil.f32(clamp01(a)), pl#item) | pl }

    def roundP(r: Float64, pl: Render.PlacedItem): Render.PlacedItem =
        { item = Render.rounded(r, pl#item) | pl }

    // ── 体の部品（dip = 沈み込み・lean = 前傾・sq/wd = 縦横のつぶし）──

    def body(stage: CharStage.Stage,
             p: { dip = Float64, lean = Float64, sq = Float64, wd = Float64,
                  legF = (Float64, Float64), legFh = Float64,
                  legB = (Float64, Float64), legBh = Float64,
                  handF = (Float64, Float64), handB = (Float64, Float64),
                  pupilDy = Float64 }): List[Render.PlacedItem] =
        let (lfx, lfy) = p#legF;
        let (lbx, lby) = p#legB;
        let (hfx, hfy) = p#handF;
        let (hbx, hby) = p#handB;
        let dip = p#dip;
        let lean = p#lean;
        let sq = p#sq;
        let wd = p#wd;
        let headX = 2.0 + lean * 1.8;
        let headY = (0.0 - 23.5) * sq + dip;
        let shY = (0.0 - 17.5) * sq + dip;
        // 脚 + ブーツ（足元は沈み込みの影響を受けない）
        let legs =
            boxC(stage, lfx, lfy, 4.5 * wd, p#legFh, pants(), 10) ::
            boxC(stage, lbx, lby, 4.5 * wd, p#legBh, pants(), 10) ::
            boxC(stage, lfx + 0.6, 0.0 - 1.2, 5.2 * wd, 2.4, boot(), 11) ::
            boxC(stage, lbx + 0.6, 0.0 - 1.2, 5.2 * wd, 2.4, boot(), 11) :: Nil;
        // 胴 = 肩の広い台形。革前掛けと胸ひもを重ねる。
        let torso =
            polyC(stage, lean, (0.0 - 14.0) * sq + dip,
                  { x = (0.0 - 9.0) * wd, y = (0.0 - 5.5) * sq } ::
                  { x = 9.0 * wd, y = (0.0 - 5.5) * sq } ::
                  { x = 6.0 * wd, y = 5.5 * sq } ::
                  { x = (0.0 - 6.0) * wd, y = 5.5 * sq } :: Nil, shirt(), 10) ::
            roundP(1.5, boxC(stage, lean + 0.8, (0.0 - 11.5) * sq + dip, 9.0 * wd, 8.0 * sq, apron(), 11)) ::
            boxC(stage, lean, shY + 0.5, 7.0 * wd, 1.4, boot(), 11) :: Nil;
        // 腕は肩から拳へ渡す棒。前腕が体の手前、後腕は奥。
        let arms =
            strut(stage, lean + 6.5 * wd, shY, hfx, hfy, 3.2, skin(), 12) ::
            circC(stage, hfx, hfy, 1.7, skin(), 12) ::
            strut(stage, lean - 6.5 * wd, shY, hbx, hby, 3.2, skin(), 9) ::
            circC(stage, hbx, hby, 1.7, skin(), 9) :: Nil;
        // 頭: 鉢巻 + ひげ + 片目。
        let head =
            roundP(2.0, boxC(stage, headX, headY, 8.0, 7.0, skin(), 10)) ::
            boxC(stage, headX, headY - 2.8, 8.4, 1.8, hachimaki(), 11) ::
            roundP(1.2, boxC(stage, headX + 1.0, headY + 3.6, 6.0, 3.0, beardC(), 11)) ::
            circC(stage, headX + 2.4, headY - 0.6, 1.4, whiteC(), 11) ::
            circC(stage, headX + 3.0, headY - 0.6 + p#pupilDy, 0.7, blackC(), 12) :: Nil;
        List.flatten(legs :: torso :: arms :: head :: Nil)

    /// 大鎚: 握り (gx,gy) から鎚頭の中心 (hx,hy) へ柄を渡し、鋼の頭を載せる。
    def hammerAt(stage: CharStage.Stage, gx: Float64, gy: Float64,
                 hx: Float64, hy: Float64, z: Int32): List[Render.PlacedItem] =
        strut(stage, gx, gy, hx, hy, 2.0, wood(), z) ::
        roundP(1.0, boxC(stage, hx, hy, 9.0, 6.0, steel(), z)) ::
        boxC(stage, hx, hy - 1.8, 9.0, 1.5, steelHi(), z + 1) :: Nil

    // ── モードごとの演技 ──

    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        match stage#mode {
            case CharStage.Mode.IdleMode => idle(stage)
            case CharStage.Mode.RunMode  => runPose(stage)
            case CharStage.Mode.DashMode => dash(stage)
            case CharStage.Mode.SkidMode => skid(stage)
            case CharStage.Mode.JumpMode => jump(stage)
            case CharStage.Mode.FallMode => fall(stage)
            case CharStage.Mode.LandMode => land(stage)
        }

    /// 待機: 立てた大鎚に手を預けて呼吸し、後腕で額の汗を拭う。汗の粒がこぼれる。
    def idle(stage: CharStage.Stage): List[Render.PlacedItem] =
        let b = Curve.tri(1.3, stage#t) * 0.8;
        let m = stage#modeT;
        let wiping = m >= 0.35 and m <= 0.95;
        let hb = if (wiping) (4.6, 0.0 - 25.0 + b) else (0.0 - 6.0, 0.0 - 10.5 + b);
        let core = body(stage, { dip = b, lean = 0.0, sq = 1.0, wd = 1.0,
                                 legF = (3.0, -4.0), legFh = 8.0,
                                 legB = (-3.0, -4.0), legBh = 8.0,
                                 handF = (4.5, 0.0 - 13.0 + b), handB = hb, pupilDy = 0.0 });
        let ham = hammerAt(stage, 4.5, 0.0 - 13.0 + b, 10.0, -3.0, 12);
        let drop =
            if (m >= 0.55 and m <= 1.0) {
                let u = (m - 0.55) / 0.45;
                fadeP((1.0 - u) * 0.8, circC(stage, 5.4, 0.0 - 23.0 + u * 10.0, 0.9, sweat(), 13)) :: Nil
            } else Nil;
        List.flatten(core :: ham :: drop :: Nil)

    /// 走り: 重い足取り。歩幅は距離駆動で、足が交差する瞬間に体が沈み、
    /// 肩に担いだ大鎚が上下に跳ねる。足音の位置に土埃が立つ。
    def runPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let sw = Curve.triWave(stage#pos#x * 0.055);
        let dip = (1.0 - Float64.abs(sw)) * 1.8;
        let hop = sw * 1.2;
        let core = body(stage, { dip = dip, lean = 1.5, sq = 1.0, wd = 1.0,
                                 legF = (1.5 + sw * 4.0, -4.0), legFh = 8.0,
                                 legB = (1.5 - sw * 4.0, -4.0), legBh = 8.0,
                                 handF = (5.5, 0.0 - 14.0 + dip),
                                 handB = (0.0 - 1.0 - sw * 3.0, 0.0 - 10.0 + dip),
                                 pupilDy = 0.0 });
        let ham = hammerAt(stage, 5.5, 0.0 - 14.0 + dip, -4.0, 0.0 - 25.5 + dip + hop, 8);
        let a = (Float64.abs(sw) - 0.85) / 0.15;
        let puff =
            if (a > 0.0)
                fadeP(a * 0.4, circC(stage, 0.0 - sw * 4.0, -1.0, 1.6, dustC(), 8)) :: Nil
            else Nil;
        List.flatten(core :: ham :: puff :: Nil)

    /// ダッシュ: 大鎚を脇に抱えて槍のように構え、背後にふいごの蒸気と炉の火の粉が流れる。
    def dash(stage: CharStage.Stage): List[Render.PlacedItem] =
        let bandV = clamp01((Float64.abs(stage#vx) - 160.0) / 120.0);
        let sw = Curve.triWave(stage#pos#x * 0.055);
        let dip = (1.0 - Float64.abs(sw)) * 1.2;
        let core = body(stage, { dip = dip, lean = 3.0, sq = 1.0, wd = 1.0,
                                 legF = (2.0 + sw * 4.5, -4.0), legFh = 8.0,
                                 legB = (2.0 - sw * 4.5, -4.0), legBh = 8.0,
                                 handF = (6.0, 0.0 - 13.0 + dip),
                                 handB = (1.5, 0.0 - 12.5 + dip),
                                 pupilDy = 0.0 });
        let ham = hammerAt(stage, 0.0, 0.0 - 12.5 + dip, 8.5, 0.0 - 12.5 + dip, 12);
        let steam = List.map(k ->
            fadeP((0.5 - 0.13 * k) * bandV,
                  circC(stage, 0.0 - 9.5 - 4.5 * k,
                        0.0 - 12.0 + Curve.triWave(stage#t * 2.6 + 0.33 * k) * 2.0,
                        (1.8 + 1.1 * k) * (0.5 + 0.5 * bandV), whiteC(), 8)),
            0.0 :: 1.0 :: 2.0 :: Nil);
        let embers = List.map(match (i, c) -> {
            let s = Curve.loop(55.0, 13.0, stage#t + i * 0.53);
            fadeP((1.0 - s / 13.0) * bandV * 0.9,
                  circC(stage, 0.0 - 5.0 - s,
                        0.0 - 9.0 + Curve.triWave(stage#t * 6.0 + i * 0.29) * 2.5,
                        0.9, c, 13))
            },
            (0.0, sparkY()) :: (1.0, sparkO()) :: (2.0, sparkY()) :: (3.0, sparkO()) :: Nil);
        List.flatten(core :: ham :: steam :: embers :: Nil)

    /// スキッド: 大鎚を背後の地面へ突き立てて錨にする。鎚頭が地面を削って
    /// 火花が散り、後ろへ研削の土埃が流れる。強さは残っている速度に比例。
    def skid(stage: CharStage.Stage): List[Render.PlacedItem] =
        let sI = clamp01(Float64.abs(stage#vx) / 280.0);
        let core = body(stage, { dip = 0.5, lean = -2.0, sq = 1.0, wd = 1.0,
                                 legF = (5.0, -4.0), legFh = 8.0,
                                 legB = (-2.5, -4.5), legBh = 7.0,
                                 handF = (0.5, -12.0), handB = (-3.5, -11.0),
                                 pupilDy = 0.0 });
        let ham = hammerAt(stage, -2.0, -11.0, -8.5, -3.0, 12);
        let sparks = List.map(match (i, c) -> {
            let on = Curve.tri(0.09, stage#t + i * 0.031) > 0.45;
            let alpha = if (on) sI else 0.0;
            fadeP(alpha, circC(stage, 0.0 - 10.0 - i * 1.3, 0.0 - 1.6 - i * 1.7, 0.7, c, 13))
            },
            (0.0, whiteC()) :: (1.0, sparkY()) :: (2.0, sparkO()) :: Nil);
        let grind =
            fadeP(0.35 * sI, circC(stage, -6.5, -1.0, 1.8, dustC(), 8)) ::
            fadeP(0.25 * sI, circC(stage, -4.0, -0.6, 1.2, dustC(), 8)) ::
            fadeP(0.30 * sI, circC(stage, 6.0, -0.8, 1.4, dustC(), 8)) :: Nil;
        List.flatten(core :: ham :: sparks :: grind :: Nil)

    /// ジャンプ: 大鎚を両手で頭上に振りかぶり、体は縦に伸びる。
    def jump(stage: CharStage.Stage): List[Render.PlacedItem] =
        let core = body(stage, { dip = 0.0, lean = 0.5, sq = 1.06, wd = 0.96,
                                 legF = (2.5, -5.0), legFh = 6.5,
                                 legB = (-2.5, -5.5), legBh = 6.0,
                                 handF = (1.5, -24.5), handB = (-2.5, -24.0),
                                 pupilDy = -0.3 });
        let ham = hammerAt(stage, -3.0, -25.5, 4.0, -28.0, 12);
        List.flatten(core :: ham :: Nil)

    /// 落下: 振りかぶった大鎚を前下方へ振り下ろしながら体を縮め、打ち下ろしに備える。
    def fall(stage: CharStage.Stage): List[Render.PlacedItem] =
        let core = body(stage, { dip = 0.0, lean = 1.0, sq = 0.96, wd = 1.04,
                                 legF = (2.5, -5.5), legFh = 5.5,
                                 legB = (-2.5, -5.0), legBh = 6.0,
                                 handF = (4.5, -11.5), handB = (1.5, -10.0),
                                 pupilDy = 0.5 });
        let ham = hammerAt(stage, 2.0, -10.5, 8.0, -5.0, 12);
        List.flatten(core :: ham :: Nil)

    /// 着地: 鎚頭が地面を打ち、体は深くつぶれる。前方の地面にひびが走り、
    /// 左右へ土煙が広がって小石が跳ねる（地響きの誇張）。
    def land(stage: CharStage.Stage): List[Render.PlacedItem] =
        let k = 1.0 - clamp01(stage#modeT / 0.2);
        let sq = 1.0 - 0.3 * k;
        let wd = 1.0 + 0.35 * k;
        let core = body(stage, { dip = 0.0, lean = 0.5, sq = sq, wd = wd,
                                 legF = (4.0 * wd, -3.5), legFh = 7.0 * sq,
                                 legB = ((0.0 - 4.0) * wd, -3.5), legBh = 7.0 * sq,
                                 handF = (3.0, (0.0 - 12.0) * sq),
                                 handB = (-1.0, (0.0 - 11.0) * sq),
                                 pupilDy = 0.4 });
        let ham = hammerAt(stage, 2.5, (0.0 - 11.5) * sq, 8.5, -3.0, 12);
        let crack =
            fadeP(k * 0.7,
                  polyC(stage, 8.5, -0.5,
                        { x = -4.5, y = 0.0 } :: { x = 0.0, y = -1.4 } ::
                        { x = 4.5, y = 0.0 } :: { x = 0.0, y = 1.0 } :: Nil,
                        boot(), 8)) :: Nil;
        let e = 1.0 - k;
        let smoke = List.map(i -> {
            let dxD = 3.0 + e * 4.5 + i * 1.2;
            let r = 2.2 - 0.5 * i;
            fadeP((0.5 - 0.12 * i) * k, circC(stage, dxD, 0.0 - 1.4 - i * 0.7, r, dustC(), 8))
            }, 0.0 :: 1.0 :: 2.0 :: Nil);
        let smokeL = List.map(i -> {
            let dxD = 3.0 + e * 4.5 + i * 1.2;
            let r = 2.2 - 0.5 * i;
            fadeP((0.5 - 0.12 * i) * k, circC(stage, 0.0 - dxD, 0.0 - 1.4 - i * 0.7, r, dustC(), 8))
            }, 0.0 :: 1.0 :: 2.0 :: Nil);
        let hopY = Curve.tri(0.2, stage#modeT) * 4.0;
        let pebbles =
            fadeP(k, boxC(stage, 7.0 + e * 3.5, 0.0 - 1.5 - hopY, 1.3, 1.3, stone(), 13)) ::
            fadeP(k, boxC(stage, 0.0 - 6.0 - e * 3.5, 0.0 - 1.0 - hopY * 0.7, 1.1, 1.1, stone(), 13)) :: Nil;
        List.flatten(core :: ham :: crack :: smoke :: smokeL :: pebbles :: Nil)
}
