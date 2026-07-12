// 韋駄天の源太（いだてんのげんた）— 江戸の宿場を風のように繋ぐ長身痩躯の飛脚。
// 深い前傾と跳ぶような大股のバウンディング走法。担いだ文箱が慣性で振れ、
// 赤い鉢巻の尾と巻き上がる砂塵の壁が「今日も御用」の勢いを物語る。

mod Char11 {

    pub def name(): String = "11 HIKYAKU"

    // ── DB32 ローカルパレット ──
    def skinC(): Color  = { r = 143.0f32 / 255.0f32, g =  86.0f32 / 255.0f32, b =  59.0f32 / 255.0f32 } // 8f563b 日焼け肌
    def coatC(): Color  = { r =  63.0f32 / 255.0f32, g =  63.0f32 / 255.0f32, b = 116.0f32 / 255.0f32 } // 3f3f74 藍の半纏
    def wrapC(): Color  = { r = 203.0f32 / 255.0f32, g = 219.0f32 / 255.0f32, b = 252.0f32 / 255.0f32 } // cbdbfc 脚絆と団扇
    def redC(): Color   = { r = 172.0f32 / 255.0f32, g =  50.0f32 / 255.0f32, b =  50.0f32 / 255.0f32 } // ac3232 鉢巻と吊り紐
    def woodC(): Color  = { r = 102.0f32 / 255.0f32, g =  57.0f32 / 255.0f32, b =  49.0f32 / 255.0f32 } // 663931 天秤棒と文箱
    def sealC(): Color  = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b =  54.0f32 / 255.0f32 } // fbf236 御用の封
    def hairC(): Color  = { r =  34.0f32 / 255.0f32, g =  32.0f32 / 255.0f32, b =  52.0f32 / 255.0f32 } // 222034 髷と瞳
    def dustC(): Color  = { r = 217.0f32 / 255.0f32, g = 160.0f32 / 255.0f32, b = 102.0f32 / 255.0f32 } // d9a066 砂塵
    def strawC(): Color = { r =  82.0f32 / 255.0f32, g =  75.0f32 / 255.0f32, b =  36.0f32 / 255.0f32 } // 524b24 草鞋
    def whiteC(): Color = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 } // ffffff 白目

    // ── ポーズ（足元中心ローカル・上が負 y・x は facing 方向）──
    type alias Pose = {
        lean = Float64,      // 前傾の深さ（+で進行方向へ倒れる）
        sink = Float64,      // 腰の沈み込み（+で低くなる）
        fFoot = Vec2.Vec2,   // 前側の足先
        bFoot = Vec2.Vec2,   // 奥側の足先
        hand = Vec2.Vec2,    // 空いた腕の手先
        tailDx = Float64,    // 鉢巻の尾の流れ（-1=後方 / +1=前方 = スキッドの慣性）
        boxSwing = Float64   // 文箱の慣性振れ（-で後ろへ遅れ / +で前へ飛び出す）
    }

    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        match stage#mode {
            case CharStage.Mode.IdleMode => List.append(body(stage, idlePose(stage)), uchiwa(stage))
            case CharStage.Mode.RunMode  => body(stage, runPose(stage))
            case CharStage.Mode.DashMode => List.append(sandWall(stage), body(stage, runPose(stage)))
            case CharStage.Mode.SkidMode => List.append(body(stage, skidPose()), skidDirt(stage))
            case CharStage.Mode.JumpMode => body(stage, jumpPose())
            case CharStage.Mode.FallMode => body(stage, fallPose())
            case CharStage.Mode.LandMode => List.append(body(stage, landPose(stage)), landDust(stage))
        }

    // ── ポーズ表 ──

    /// 大股バウンディング走: 歩幅 ±8.5px・低ケイデンス（距離駆動で足が滑らない）。
    /// 足が交差する瞬間に両足が浮く「跳ぶ走り」が飛脚の性格。
    def runPose(st: CharStage.Stage): Pose =
        let s = Curve.triWave(st#pos#x * 0.055);
        let air = 1.0 - Float64.abs(s);
        let lean = 3.6 + band(st) * 2.6;   // 速いほど前傾が深くなる
        { lean = lean,
          sink = 1.1 * Float64.abs(s) - 0.4,
          fFoot = { x = s * 8.5, y = -2.8 * air },
          bFoot = { x = -8.5 * s, y = -2.8 * air },
          hand = { x = lean - 1.5 - s * 6.5, y = -13.5 - s * 1.5 },   // 空き腕の大振り
          tailDx = -1.0,
          boxSwing = -1.0 * Float64.min(3.2, relVx(st) * 0.012) }     // 文箱は速さに遅れる

    /// スキッド: 前脚を突っ張った深い前のめり。鉢巻と文箱は慣性で前へ飛ぶ。
    def skidPose(): Pose =
        { lean = 7.5, sink = 2.2,
          fFoot = { x = 8.0, y = 0.0 }, bFoot = { x = -3.0, y = -1.8 },
          hand = { x = -6.8, y = -17.5 },   // 後ろ手を跳ね上げてバランス
          tailDx = 1.0, boxSwing = 3.4 }

    /// 跳躍: ハードル跳びの伸身。前脚を水平に突き出し、腕は行き先へ。
    def jumpPose(): Pose =
        { lean = 5.0, sink = -0.8,
          fFoot = { x = 10.0, y = -6.5 }, bFoot = { x = -8.0, y = -2.5 },
          hand = { x = 6.5, y = -19.0 },
          tailDx = -1.0, boxSwing = 0.8 }

    /// 落下: 脚をたたんで着地に備え、腕を上げて姿勢を保つ。
    def fallPose(): Pose =
        { lean = 2.0, sink = 0.0,
          fFoot = { x = 3.2, y = -3.0 }, bFoot = { x = -2.0, y = -1.5 },
          hand = { x = 1.5, y = -21.0 },
          tailDx = -1.0, boxSwing = -0.6 }

    /// 着地: 深く沈んで 0.2 秒で立ち上がる（modeT で閉形式に戻す）。
    def landPose(st: CharStage.Stage): Pose =
        let ease = 1.0 - clamp01(st#modeT / 0.2);
        { lean = 3.0, sink = 1.0 + 3.8 * ease,
          fFoot = { x = 4.8, y = 0.0 }, bFoot = { x = -4.8, y = 0.0 },
          hand = { x = 3.5, y = -11.5 },
          tailDx = -1.0, boxSwing = 1.5 * ease }

    /// 待機: 呼吸で肩が上下し、空き手の団扇でぱたぱたと顔を扇ぐ（汗っかき）。
    def idlePose(st: CharStage.Stage): Pose =
        let br = Curve.triWave(st#t * 0.9);
        { lean = 1.2, sink = 0.6 - br * 0.5,
          fFoot = { x = 2.8, y = 0.0 }, bFoot = { x = -2.8, y = 0.0 },
          hand = idleHand(st),
          tailDx = -1.0, boxSwing = 0.0 }

    def idleHand(st: CharStage.Stage): Vec2.Vec2 =
        let fan = Curve.triWave(st#modeT * 1.7);
        { x = 4.2, y = -17.5 - fan * 1.8 }

    // ── 体の組み立て ──

    def body(st: CharStage.Stage, p: Pose): List[Render.Placed] =
        let hipY = -11.0 + p#sink;
        let shX = p#lean;
        let shY = hipY - 9.0 + p#sink * 0.3;
        let hdX = shX + 1.4;
        let hdY = shY - 4.6;
        let hand = { x = p#hand#x, y = p#hand#y + p#sink };
        let flap = 1.0 + Float64.abs(st#vx) * 0.006;   // 布のなびきは速さで育つ
        List.flatten(
            leg(st, hipY, p#bFoot, 9) ::
            leg(st, hipY, p#fFoot, 11) ::
            arm(st, shX - 1.0, shY + 1.0, hand, 9) ::
            (limb(st, 0.0, hipY, shX, shY, 5.6, coatC(), 10) ::            // 胴 = 藍の半纏（前傾がそのまま出る）
             polyAt(st, { x = -2.6, y = hipY + 1.0 }                        // 裾のはためき
                     :: { x = -4.2 - flap * 0.7, y = hipY - 1.5 }
                     :: { x = -2.0, y = hipY - 3.5 } :: Nil, coatC(), 9) ::
             circleAt(st, hdX, hdY, 3.5, skinC(), 10) ::                    // 頭
             circleAt(st, hdX - 0.8, hdY - 4.0, 1.4, hairC(), 11) ::        // 髷
             boxAt(st, hdX, hdY - 1.3, 7.4, 1.7, redC(), 11) ::             // 鉢巻
             boxAt(st, hdX + 2.1, hdY + 0.6, 1.4, 1.5, whiteC(), 12) ::     // 白目
             boxAt(st, hdX + 2.6, hdY + 0.6, 0.7, 1.5, hairC(), 13) ::      // 瞳（進行方向を見る）
             Nil) ::
            hachimakiTails(st, hdX - 3.2, hdY - 1.3, p#tailDx, flap) ::
            poleAndBox(st, shX, shY, p#boxSwing) ::
            Nil)

    /// 脚: 腰→膝→足の 2 節。膝は常に進行方向へ曲がる。脛は白の脚絆・足は草鞋。
    def leg(st: CharStage.Stage, hipY: Float64, foot: Vec2.Vec2, z: Int32): List[Render.Placed] =
        let kneeX = foot#x * 0.5 + 1.8;
        let kneeY = (hipY + foot#y) * 0.5 - 0.4;
        limb(st, 0.0, hipY, kneeX, kneeY, 2.6, skinC(), z) ::
        limb(st, kneeX, kneeY, foot#x, foot#y - 0.8, 2.0, wrapC(), z) ::
        boxAt(st, foot#x + 0.9, foot#y - 0.7, 3.2, 1.4, strawC(), z) :: Nil

    /// 腕: 袖（半纏色）→前腕（肌）→拳。肘はやや下がる労働者の振り。
    def arm(st: CharStage.Stage, shX: Float64, shY: Float64, hand: Vec2.Vec2, z: Int32): List[Render.Placed] =
        let elX = shX + (hand#x - shX) * 0.45;
        let elY = shY + (hand#y - shY) * 0.5 + 1.6;
        limb(st, shX, shY, elX, elY, 2.2, coatC(), z) ::
        limb(st, elX, elY, hand#x, hand#y, 1.7, skinC(), z) ::
        circleAt(st, hand#x, hand#y, 1.2, skinC(), z) :: Nil

    /// 鉢巻の尾 2 節。走りでは後方へ、スキッドでは慣性で前方へ流れる。
    def hachimakiTails(st: CharStage.Stage, bx: Float64, by: Float64, dir: Float64, flap: Float64): List[Render.Placed] =
        let w1 = Curve.triWave(st#t * 3.1) * 1.4 * flap;
        let w2 = Curve.triWave(st#t * 3.1 + 0.35) * 2.2 * flap;
        limb(st, bx, by, bx + dir * 4.2, by - 1.0 + w1, 1.3, redC(), 9) ::
        limb(st, bx + dir * 4.2, by - 1.0 + w1, bx + dir * 8.0, by - 0.5 + w2, 1.1, redC(), 9) :: Nil

    /// 天秤棒と文箱。前手で握り、後端の吊り紐から御用の封つき文箱が下がる。
    /// swing が文箱の慣性 — 走ると遅れ、スキッドで前へ振り出す。
    def poleAndBox(st: CharStage.Stage, shX: Float64, shY: Float64, swing: Float64): List[Render.Placed] =
        let gripX = shX + 4.6;
        let gripY = shY + 0.6;
        let tipX = shX - 8.5;
        let tipY = shY - 3.0;
        let bx = tipX + swing;
        let topY = tipY + 2.6;
        List.append(
            arm(st, shX + 0.8, shY, { x = gripX, y = gripY }, 11),
            limb(st, tipX, tipY, gripX, gripY, 1.2, woodC(), 11) ::
            limb(st, tipX, tipY, bx, topY, 0.9, redC(), 10) ::
            boxAt(st, bx, topY + 2.3, 5.0, 4.6, woodC(), 10) ::
            boxAt(st, bx, topY + 0.9, 5.0, 1.2, sealC(), 11) :: Nil)

    // ── 演出 ──

    /// ダッシュ演出: 背後に巻き上がる砂塵の壁。遠いほど大きく薄い（速さで濃くなる）。
    def sandWall(st: CharStage.Stage): List[Render.Placed] =
        let strength = 0.25 + band(st) * 0.45;
        (1.0 :: 2.0 :: 3.0 :: 4.0 :: Nil) |> List.map(kf -> {
            let a = RenderUtil.f32(Float64.max(0.05, strength * (1.0 - kf * 0.18)));
            fadePlaced(a, circleAt(st, -5.0 - kf * 6.5, -1.6 - kf * 0.7, 1.8 + kf * 0.9, dustC(), 8))
        })

    /// スキッドの土蹴り: 前足の先へ砂粒が飛び、足元に白い擦過線が残る。
    def skidDirt(st: CharStage.Stage): List[Render.Placed] =
        let u = clamp01(st#modeT / 0.35);
        let a = RenderUtil.f32(0.5 * (1.0 - u));
        fadePlaced(a, circleAt(st, 8.0 + u * 1.0, -2.0 - u * 3.0, 2.0, dustC(), 12)) ::
        fadePlaced(a, circleAt(st, 9.5 + u * 0.5, -1.0 - u * 1.5, 1.2, dustC(), 12)) ::
        fadePlaced(a, boxAt(st, 3.0, -0.6, 7.0, 0.9, wrapC(), 8)) :: Nil

    /// 着地の土煙: 左右へひと吹き（0.14 秒で消える）。
    def landDust(st: CharStage.Stage): List[Render.Placed] =
        let u = clamp01(st#modeT / 0.14);
        if (u >= 1.0) Nil
        else {
            let a = RenderUtil.f32(0.45 * (1.0 - u));
            fadePlaced(a, circleAt(st, 6.0 + u * 3.0, -1.5, 2.0 - u, dustC(), 12)) ::
            fadePlaced(a, circleAt(st, -6.0 - u * 3.0, -1.5, 2.0 - u, dustC(), 12)) :: Nil
        }

    /// 待機の団扇（空き手の位置に追従してぱたぱた動く）。
    def uchiwa(st: CharStage.Stage): List[Render.Placed] =
        let hand = idleHand(st);
        boxAt(st, hand#x + 1.2, hand#y - 2.2 + 0.6, 3.0, 2.4, wrapC(), 12) :: Nil

    // ── 置き方ヘルパ（足元中心ローカル・facing で x 反転）──

    /// 中心 (cx, cy)・寸法 (w, h) の箱。
    def boxAt(st: CharStage.Stage, cx: Float64, cy: Float64, w: Float64, h: Float64,
              color: Color, z: Int32): Render.Placed =
        ({ x = st#pos#x + st#facing * cx - w / 2.0, y = st#pos#y + cy - h / 2.0 },
         Render.box({ x = w, y = h }, color, z))

    /// 中心 (cx, cy)・半径 r の円。
    def circleAt(st: CharStage.Stage, cx: Float64, cy: Float64, r: Float64,
                 color: Color, z: Int32): Render.Placed =
        ({ x = st#pos#x + st#facing * cx - r, y = st#pos#y + cy - r },
         Render.circle(r, color, z))

    /// 相対頂点列を facing で鏡映して置く（凸多角形・反転時は巻き順も戻す）。
    def polyAt(st: CharStage.Stage, verts: List[Vec2.Vec2], color: Color, z: Int32): Render.Placed =
        let vs = List.map(v -> { x = st#facing * v#x, y = v#y }, verts);
        let ordered = if (st#facing >= 0.0) vs else List.reverse(vs);
        ({ x = st#pos#x, y = st#pos#y }, Render.polygon(ordered, color, z))

    /// (x0,y0)→(x1,y1) を結ぶ太さ w の棒。手足・棒・布のひと節。
    def limb(st: CharStage.Stage, x0: Float64, y0: Float64, x1: Float64, y1: Float64,
             w: Float64, color: Color, z: Int32): Render.Placed =
        let dx = x1 - x0;
        let dy = y1 - y0;
        let len = Float64.max(0.001, Vec2.sqrt(dx * dx + dy * dy));
        let px = -1.0 * dy / len * (w / 2.0);
        let py = dx / len * (w / 2.0);
        polyAt(st, { x = x0 + px, y = y0 + py } :: { x = x1 + px, y = y1 + py }
                :: { x = x1 - px, y = y1 - py } :: { x = x0 - px, y = y0 - py } :: Nil,
               color, z)

    // ── 小物ヘルパ ──

    def fadePlaced(a: Float32, placed: Render.Placed): Render.Placed =
        let (pos, item) = placed;
        (pos, Render.fade(a, item))

    def clamp01(v: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, v))

    /// ダッシュ帯の進み具合（|vx| 160→280 を 0→1 に写す）。
    def band(st: CharStage.Stage): Float64 = clamp01((Float64.abs(st#vx) - 160.0) / 120.0)

    /// 進行方向成分の速度（前向きが正）。
    def relVx(st: CharStage.Stage): Float64 = st#vx * st#facing
}
