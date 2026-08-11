// lint-view: 対象外 — 手触り検証台の箱組みキャラ。絵の見本にしない（新キャラは PxSprite+PxShade で作る）。
// ハシリドリ — 長い二本脚で地を蹴る、飛べない走鳥。細い脚のハサミ運びと伸び縮みする首が体幹。
// ダッシュは首が水平に伸びて羽毛が舞い散り、スキッドは全身をのけぞらせ尾羽を扇に開いて踏ん張る。
// この箱組みは旧様式(RawDraw 大量使用の前例にしない)。新キャラは PxSprite+PxShade を第一候補に。

mod Char02 {

    use CharStage.Mode

    /// ギャラリーに出す ASCII ラベル。
    pub def name(): String = "02 STRIDER"

    // ── 配色（DB32・ダッシュ中も体色は変えない）──

    /// 胴・首・頭の橙。 df7126
    def bodyColor(): Color  = { r = 223.0f32 / 255.0f32, g = 113.0f32 / 255.0f32, b = 38.0f32 / 255.0f32 }
    /// 腹あての明るい肌色。 eec39a
    def bellyColor(): Color = { r = 238.0f32 / 255.0f32, g = 195.0f32 / 255.0f32, b = 154.0f32 / 255.0f32 }
    /// 脚と畳んだ風切羽の焦げ茶。 8f563b
    def legColor(): Color   = { r = 143.0f32 / 255.0f32, g = 86.0f32 / 255.0f32, b = 59.0f32 / 255.0f32 }
    /// くちばしの黄。 fbf236
    def beakColor(): Color  = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b = 54.0f32 / 255.0f32 }
    /// とさかの赤。 ac3232
    def crestColor(): Color = { r = 172.0f32 / 255.0f32, g = 50.0f32 / 255.0f32, b = 50.0f32 / 255.0f32 }
    /// 目の白。 ffffff
    def eyeWhite(): Color   = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 }
    /// 瞳の黒。 000000
    def eyeDark(): Color    = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }

    // 演技区分から導くポーズ量。全部 0..1 前後の係数で、状態は持たない。
    type alias Pose = {
        lean = Float64,     // 前傾(+) / のけぞり(-)
        crouch = Float64,   // しゃがみ・着地のつぶれ
        neck = Float64,     // 首の前伸ばし（0 = S 字に立てる / 1 = 水平）
        tuck = Float64,     // 空中で脚と首を畳んで丸まる量
        wing = Float64,     // 羽の広げ（落下の羽ばたき・着地のバサッ）
        fan = Float64,      // 尾羽の扇の開き
        brace = Float64     // スキッドの踏ん張り（足を前へ突っ張る）
    }

    /// 演技区分ごとのポーズ。区分に入ってからの経過秒で立ち上げて、境界の飛びを消す。
    def poseOf(stage: CharStage.Stage): Pose =
        match stage#mode {
            case Mode.IdleMode =>
                // 待機: 胸がゆっくり膨らみ、首がわずかに揺れる呼吸。
                { lean = 0.0, crouch = 0.06 + 0.05 * Curve.tri(2.6, stage#t),
                  neck = 0.18 + 0.05 * Curve.triWave(stage#t * 0.4),
                  tuck = 0.0, wing = 0.0, fan = 0.12, brace = 0.0 }
            case Mode.RunMode  =>
                { lean = 0.35, crouch = 0.1, neck = 0.45, tuck = 0.0, wing = 0.0, fan = 0.15, brace = 0.0 }
            case Mode.DashMode =>
                // ダッシュ: 前傾が深まり、首が水平いっぱいまで伸びる。
                let rise = clamp01(stage#modeT / 0.3);
                { lean = 0.35 + 0.3 * rise, crouch = 0.08, neck = 0.45 + 0.55 * rise,
                  tuck = 0.0, wing = 0.0, fan = 0.1, brace = 0.0 }
            case Mode.SkidMode =>
                // スキッド: 全身をのけぞらせ、尾羽を全開にして両足を前へ突っ張る。
                let dig = clamp01(stage#modeT / 0.12);
                { lean = -1.0 * dig, crouch = 0.3 * dig, neck = 0.15,
                  tuck = 0.0, wing = 0.0, fan = dig, brace = dig }
            case Mode.JumpMode =>
                // 上昇: 脚と首を畳んで弾丸のように丸まる。
                let fold = clamp01(stage#modeT / 0.15);
                { lean = 0.15, crouch = 0.0, neck = 0.1, tuck = fold, wing = 0.0, fan = 0.2, brace = 0.0 }
            case Mode.FallMode =>
                // 落下: 小さな羽を広げてバタバタ羽ばたく（飛べないのに）。
                { lean = 0.05, crouch = 0.0, neck = 0.35, tuck = 0.25, wing = 1.0, fan = 0.5, brace = 0.0 }
            case Mode.LandMode =>
                // 着地: 深くしゃがんで潰れ、羽がバサッと浮く。0.2 秒で立ち直る。
                let squash = 1.0 - clamp01(stage#modeT / 0.2);
                { lean = 0.1, crouch = squash, neck = 0.3, tuck = 0.0,
                  wing = 0.35 * squash, fan = 0.3, brace = 0.0 }
        }

    /// 舞台状態から 1 コマ分の描画列を導く（閉形式・状態なし）。
    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        let face = stage#facing;
        let px = stage#pos#x;
        let py = stage#pos#y;
        let pose = poseOf(stage);
        let strideAmp = Float64.min(1.0, Float64.abs(stage#vx) / 160.0);
        let gait = px * 0.10;
        // 骨格の基準点: 腰の高さから胴の中心を導く。
        let hipY = py - 13.5 + pose#crouch * 6.0;
        let bodyCx = px + face * pose#lean * 3.5;
        let bodyCy = hipY - 5.0;
        let bodyW = 14.0 * (1.0 + 0.25 * pose#crouch) * (1.0 - 0.12 * pose#tuck);
        let bodyH = 10.0 * (1.0 - 0.3 * pose#crouch) * (1.0 + 0.25 * pose#tuck);
        // 足先: 歩行サイクル・踏ん張り・空中畳み・落下ぶら下がりを係数で混ぜる。
        // 歩行は距離駆動（px から位相を取る）ので足が滑らない。
        let footOf = (phase: Float64, spreadIdx: Float64) -> {
            let onGround = { x = px + face * (1.0 + 7.5 * strideAmp * Curve.triWave(gait + phase)),
                             y = py - 5.0 * strideAmp * Float64.max(0.0, Curve.triWave(gait + phase + 0.25)) };
            let braced = { x = px + face * (6.5 + spreadIdx * 2.0), y = py };
            let tucked = { x = bodyCx - face * 1.0, y = hipY + 3.5 };
            let dangled = { x = bodyCx - face * 3.0 + 1.2 * Curve.triWave(stage#t * 9.0 + phase),
                            y = hipY + 9.5 };
            mixV(mixV(mixV(onGround, braced, pose#brace), tucked, pose#tuck), dangled, pose#wing)
        };
        // 脚 1 本: 腰 → かかと（後ろへ曲がる鳥の関節）→ 足先 → つま先の 3 節。
        let legOf = (hipX: Float64, phase: Float64, spreadIdx: Float64, layer: Int32) -> {
            let hip = { x = hipX, y = hipY };
            let foot = footOf(phase, spreadIdx);
            let knee = { x = (hip#x + foot#x) / 2.0 - face * (3.0 + pose#crouch * 2.5 + pose#tuck * 2.0),
                         y = (hip#y + foot#y) / 2.0 };
            strut(hip, knee, 2.2, legColor(), layer)
                :: strut(knee, foot, 1.6, legColor(), layer)
                :: strut(foot, { x = foot#x + face * 3.0, y = foot#y - 0.4 }, 1.3, legColor(), layer)
                :: Nil
        };
        // 首と頭: S 字に立てた首と水平に伸ばした首を pose#neck で混ぜる。
        let neckBase = { x = bodyCx + face * 4.0, y = bodyCy - 2.0 };
        let headRaised = { x = neckBase#x + face * 1.5, y = neckBase#y - 7.0 };
        let headForward = { x = neckBase#x + face * 5.5, y = neckBase#y - 2.5 };
        let headFree = mixV(headRaised, headForward, pose#neck);
        let headTucked = { x = bodyCx + face * 4.0, y = bodyCy - 3.0 };
        let headBase = mixV(headFree, headTucked, pose#tuck);
        // スキッドでは首ごと後ろへ振りかぶる（のけぞりの芯）。
        let head = { x = headBase#x - face * pose#brace * 7.0, y = headBase#y - pose#brace * 5.0 };
        List.flatten(
            dashPlumes(stage)
            :: tailFeathers(stage, bodyCx, bodyCy, face, pose)
            :: legOf(bodyCx - face * 2.5, 0.5, 1.0, 9)
            :: ({ at = { x = bodyCx - bodyW / 2.0, y = bodyCy - bodyH / 2.0 },
                  item = RawDraw.box({ x = bodyW, y = bodyH }, bodyColor(), 10) |> Render.rounded(4.0) } :: Nil)
            :: ({ at = { x = bodyCx + face * 1.0 - bodyW * 0.275, y = bodyCy + 0.5 },
                  item = RawDraw.box({ x = bodyW * 0.55, y = bodyH * 0.45 }, bellyColor(), 11) |> Render.rounded(2.5) } :: Nil)
            :: wingItems(stage, bodyCx, bodyCy, face, pose)
            :: legOf(bodyCx + face * 2.5, 0.0, 0.0, 11)
            :: (strut(neckBase, head, 3.0, bodyColor(), 11) :: Nil)
            :: headItems(head, face, pose)
            :: Nil)

    /// 頭まわり: 頭・くちばし・とさか・目。とさかはダッシュで寝て、待機で立つ。
    def headItems(head: Vec2.Vec2, face: Float64, pose: Pose): List[Render.PlacedItem] =
        { at = { x = head#x - 3.2, y = head#y - 3.2 }, item = RawDraw.circle(3.2, bodyColor(), 12) }
        :: { at = { x = head#x, y = head#y },
             item = RawDraw.polygon({ x = face * 2.4, y = -1.2 } :: { x = face * 5.0, y = 0.0 }
                            :: { x = face * 2.4, y = 1.4 } :: Nil, beakColor(), 12) }
        :: { at = { x = head#x, y = head#y },
             item = RawDraw.polygon({ x = -face * 0.3, y = -2.2 }
                            :: { x = -face * (1.8 + 2.2 * pose#neck), y = -4.6 + 2.2 * pose#neck }
                            :: { x = face * 1.2, y = -2.6 } :: Nil, crestColor(), 12) }
        :: { at = { x = head#x + face * 0.9 - 1.4, y = head#y - 0.7 - 1.4 }, item = RawDraw.circle(1.4, eyeWhite(), 13) }
        :: { at = { x = head#x + face * 1.6 - 0.7, y = head#y - 0.7 - 0.7 }, item = RawDraw.circle(0.7, eyeDark(), 13) }
        :: Nil

    /// 尾羽 3 枚の扇。スキッドで全開になり、走りの速さに応じてはためく。
    def tailFeathers(stage: CharStage.Stage, bodyCx: Float64, bodyCy: Float64,
                     face: Float64, pose: Pose): List[Render.PlacedItem] =
        let flutterAmp = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        List.range(0, 3) |> List.map(k -> {
            let fk = Int32.toFloat64(k);
            let spreadY = (fk - 1.0) * (2.2 + 5.0 * pose#fan);
            let flutter = 1.2 * Curve.triWave(stage#t * 8.0 + fk * 0.3) * flutterAmp;
            let baseX = bodyCx - face * 5.0;
            let baseY = bodyCy - 1.0;
            { at = { x = 0.0, y = 0.0 },
              item = RawDraw.polygon({ x = baseX, y = baseY - 1.3 } :: { x = baseX, y = baseY + 1.3 }
                             :: { x = baseX - face * 3.8, y = baseY - 2.2 - spreadY + flutter } :: Nil,
                             legColor(), 9) }
        })

    /// 羽: ふだんは畳んだ茶の風切羽、落下と着地では広げてはためかせる（空中の変形）。
    def wingItems(stage: CharStage.Stage, bodyCx: Float64, bodyCy: Float64,
                  face: Float64, pose: Pose): List[Render.PlacedItem] =
        if (pose#wing < 0.01)
            { at = { x = bodyCx - face * 1.0 - 3.25, y = bodyCy - 3.5 },
              item = RawDraw.box({ x = 6.5, y = 4.0 }, legColor(), 11) |> Render.rounded(2.0) } :: Nil
        else {
            let flap = -7.5 + 4.5 * Curve.triWave(stage#t * 11.0);
            let shoulder = { x = bodyCx + face * 0.5, y = bodyCy - 2.0 };
            // 奥の羽（薄く）と手前の羽。羽ばたきは時刻駆動の三角波。
            { at = { x = shoulder#x, y = shoulder#y },
              item = RawDraw.polygon({ x = 0.0, y = 0.0 }
                             :: { x = -face * 5.5 * pose#wing, y = (flap * 0.8 - 1.0) * pose#wing }
                             :: { x = -face * 1.5, y = 1.2 } :: Nil, legColor(), 9)
                 |> Render.fade(0.7) }
            :: { at = { x = shoulder#x, y = shoulder#y },
                 item = RawDraw.polygon({ x = 0.0, y = 0.0 }
                                :: { x = -face * 7.0 * pose#wing, y = flap * pose#wing }
                                :: { x = -face * 2.0, y = 1.5 } :: Nil, bellyColor(), 12) }
            :: Nil
        }

    /// ダッシュ演出: 走りの勢いでむしれた羽毛が後ろへ舞い散る（体色は変えない）。
    def dashPlumes(stage: CharStage.Stage): List[Render.PlacedItem] =
        match stage#mode {
            case Mode.DashMode =>
                List.range(0, 4) |> List.map(k -> {
                    let fk = Int32.toFloat64(k);
                    let drift = fract01(stage#modeT * 1.8 + fk * 0.27);
                    let plumeX = stage#pos#x - stage#facing * (10.0 + 26.0 * drift);
                    let plumeY = stage#pos#y - 13.0 + 6.0 * drift
                                 + 1.5 * Curve.triWave(stage#t * 7.0 + fk);
                    { at = { x = plumeX, y = plumeY },
                      item = RawDraw.polygon({ x = 0.0, y = 0.0 } :: { x = -stage#facing * 3.2, y = -1.2 }
                                     :: { x = -stage#facing * 1.4, y = 1.6 } :: Nil, bellyColor(), 8)
                         |> Render.fade(0.8 * (1.0 - drift)) }
                })
            case _ => Nil
        }

    // ── 小さな数学（このキャラ専用）──

    /// 2 点を幅 width で結ぶ四角形。脚の節と首に使う。置き場所は原点に固定し頂点を絶対座標で渡す。
    def strut(a: Vec2.Vec2, b: Vec2.Vec2, width: Float64, color: Color, layer: Int32): Render.PlacedItem =
        let dx = b#x - a#x;
        let dy = b#y - a#y;
        let len = Float64.max(0.001, Vec2.sqrt(dx * dx + dy * dy));
        let nx = -dy / len * width * 0.5;
        let ny = dx / len * width * 0.5;
        { at = { x = 0.0, y = 0.0 },
          item = RawDraw.polygon({ x = a#x + nx, y = a#y + ny } :: { x = b#x + nx, y = b#y + ny }
                         :: { x = b#x - nx, y = b#y - ny } :: { x = a#x - nx, y = a#y - ny } :: Nil,
                         color, layer) }

    /// 線形補間（k は 0..1）。
    def mix(a: Float64, b: Float64, k: Float64): Float64 = a + (b - a) * k

    /// 位置の線形補間。
    def mixV(a: Vec2.Vec2, b: Vec2.Vec2, k: Float64): Vec2.Vec2 =
        { x = mix(a#x, b#x, k), y = mix(a#y, b#y, k) }

    /// 0..1 に折り返す。
    def fract01(v: Float64): Float64 = v - Float64.floor(v)

    /// 0..1 に留める。
    def clamp01(v: Float64): Float64 = Float64.min(1.0, Float64.max(0.0, v))
}
