// 旅の踊り子・鈴（すず）— 祭りから祭りへ渡り歩く身軽な踊り子。
// 走りは弾むスキップ、跳べばグラン・ジュテの大開脚、止まるときはつま先滑り。
// 桃色のスカートと水色のスカーフが動きの余韻をぜんぶ引き受ける。

mod Char12 {

    pub def name(): String = "12 ODORIKO"

    // ── DB32 ローカルパレット ──
    def skinC(): Color    = { r = 238.0f32 / 255.0f32, g = 195.0f32 / 255.0f32, b = 154.0f32 / 255.0f32 } // eec39a 肌
    def bodiceC(): Color  = { r = 118.0f32 / 255.0f32, g =  68.0f32 / 255.0f32, b =  98.0f32 / 255.0f32 } // 764462 胴着
    def skirtC(): Color   = { r = 215.0f32 / 255.0f32, g = 123.0f32 / 255.0f32, b = 186.0f32 / 255.0f32 } // d77bba スカート
    def underC(): Color   = { r = 203.0f32 / 255.0f32, g = 219.0f32 / 255.0f32, b = 252.0f32 / 255.0f32 } // cbdbfc 下履きと舞踏靴
    def scarfC(): Color   = { r =  95.0f32 / 255.0f32, g = 205.0f32 / 255.0f32, b = 228.0f32 / 255.0f32 } // 5fcde4 スカーフ
    def hairC(): Color    = { r =  69.0f32 / 255.0f32, g =  40.0f32 / 255.0f32, b =  60.0f32 / 255.0f32 } // 45283c 髪
    def ribbonC(): Color  = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b =  54.0f32 / 255.0f32 } // fbf236 髪の結び紐
    def whiteC(): Color   = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 } // ffffff 白目と風の筋

    // ── ポーズ（足元中心ローカル・上が負 y・x は facing 方向）──
    type alias Pose = {
        bob = Float64,       // 全身の浮き沈み（-で浮く: スキップの弾み・つま先立ち）
        sink = Float64,      // 膝の沈み（+で低く: プリエ）
        fFoot = Vec2.Vec2,   // 前側の足先
        bFoot = Vec2.Vec2,   // 奥側の足先
        handF = Vec2.Vec2,   // 前側の手先
        handB = Vec2.Vec2,   // 奥側の手先
        flare = Float64,     // スカートの広がり
        sweep = Float64,     // スカートの流れ（+で前へ）
        hemLift = Float64,   // 裾のまくれ上がり（+で持ち上がる）
        tailDir = Float64    // 髪とスカーフの流れ（-1=後方 / +1=前方）
    }

    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        match stage#mode {
            case CharStage.Mode.IdleMode => body(stage, idlePose(stage))
            case CharStage.Mode.RunMode  => body(stage, runPose(stage))
            case CharStage.Mode.DashMode => List.append(windRibbon(stage), body(stage, runPose(stage)))
            case CharStage.Mode.SkidMode => List.append(body(stage, skidPose()), slideStreaks(stage))
            case CharStage.Mode.JumpMode => body(stage, jumpPose())
            case CharStage.Mode.FallMode => body(stage, fallPose())
            case CharStage.Mode.LandMode => List.append(body(stage, landPose(stage)), landRing(stage))
        }

    // ── ポーズ表 ──

    /// スキップ走: 歩幅は小さく ±4.5px・リズムは速く、足の交差で体が大きく弾む。
    /// 両腕は頭の上でひらひらと交互に波打つ — 走っていても踊っている。
    def runPose(st: CharStage.Stage): Pose =
        let s = Curve.triWave(st#pos#x * 0.10);
        let air = 1.0 - Float64.abs(s);
        { bob = -3.0 * air,
          sink = 0.2,
          fFoot = { x = s * 4.5, y = -2.0 * air },
          bFoot = { x = -4.5 * s, y = -1.2 * air },
          handF = { x = 3.0 + s * 1.6, y = -19.5 - s * 2.0 },
          handB = { x = -3.0 - s * 1.6, y = -19.5 + s * 2.0 },
          flare = 1.2 + Float64.abs(st#vx) * 0.008 + Curve.triWave(st#t * 5.0) * 0.7,
          sweep = -1.0 * Float64.min(3.5, relVx(st) * 0.014),   // 裾は速さに遅れてたなびく
          hemLift = 0.5 + Float64.abs(st#vx) * 0.004,
          tailDir = -1.0 }

    /// スキッド: バレエのつま先滑り。後脚をアティテュードに上げ、腕を後上へ投げ、
    /// スカートは慣性で前へ大きくふわり — 土でなく衣装で止まる人。
    def skidPose(): Pose =
        { bob = 0.0, sink = 0.8,
          fFoot = { x = 8.0, y = 0.0 }, bFoot = { x = -2.5, y = -4.5 },
          handF = { x = -3.5, y = -21.0 }, handB = { x = -5.5, y = -17.5 },
          flare = 3.2, sweep = 4.0, hemLift = 1.5, tailDir = 1.0 }

    /// 跳躍: グラン・ジュテ。前後へ完全な開脚、腕は頭上のアーチ、裾は満開。
    def jumpPose(): Pose =
        { bob = -1.0, sink = 0.0,
          fFoot = { x = 9.5, y = -7.0 }, bFoot = { x = -9.5, y = -6.0 },
          handF = { x = 1.8, y = -23.0 }, handB = { x = -1.8, y = -23.0 },
          flare = 4.0, sweep = 0.0, hemLift = 2.0, tailDir = -1.0 }

    /// 落下: 脚を揃えてつま先を伸ばし、腕を横に開いて浮遊。裾は風でめくれ上がる。
    def fallPose(): Pose =
        { bob = 0.0, sink = 0.0,
          fFoot = { x = 1.8, y = -1.5 }, bFoot = { x = -1.2, y = -2.5 },
          handF = { x = 6.5, y = -16.5 }, handB = { x = -6.5, y = -16.5 },
          flare = 3.5, sweep = 0.0, hemLift = 3.0, tailDir = -1.0 }

    /// 着地: プリエ。膝を深く折り、腕を水平に、スカートが床いっぱいに広がる。
    def landPose(st: CharStage.Stage): Pose =
        let ease = 1.0 - clamp01(st#modeT / 0.2);
        { bob = 0.0, sink = 1.0 + 2.8 * ease,
          fFoot = { x = 4.6, y = 0.0 }, bFoot = { x = -4.6, y = 0.0 },
          handF = { x = 7.0, y = -14.5 }, handB = { x = -7.0, y = -14.5 },
          flare = 3.0 + 1.5 * ease, sweep = 0.0, hemLift = -0.5, tailDir = -1.0 }

    /// 待機: つま先立ちでゆっくり上下しながら、片手で髪を直す。もう片手は腰。
    def idlePose(st: CharStage.Stage): Pose =
        let sway = Curve.triWave(st#t * 0.8);
        let reach = Curve.triWave(st#modeT * 0.9);
        { bob = -0.6 - sway * 0.4,
          sink = 0.0,
          fFoot = { x = 2.2, y = -0.8 }, bFoot = { x = -2.2, y = 0.0 },
          handF = { x = 0.5 + reach * 1.5, y = -21.5 },
          handB = { x = -3.2, y = -12.0 },
          flare = 1.5 + sway * 0.5, sweep = sway * 1.2, hemLift = 0.0, tailDir = -1.0 }

    // ── 体の組み立て ──

    def body(st: CharStage.Stage, p: Pose): List[Render.Placed] =
        let hipY = -9.0 + p#bob + p#sink;
        let shX = 0.4;                       // 胸を張って前傾しないのが踊り子の芯
        let shY = hipY - 6.5;
        let hdX = shX + 0.6;
        let hdY = shY - 4.0;
        let hF = { x = p#handF#x, y = p#handF#y + p#bob + p#sink };
        let hB = { x = p#handB#x, y = p#handB#y + p#bob + p#sink };
        List.flatten(
            arm(st, shX - 1.2, shY + 0.6, hB, 9) ::
            // 脚はバレエの真っ直ぐ 1 本線（膝を見せない）・奥脚は細く
            legLine(st, hipY, p#bFoot, 1.5, 9) ::
            legLine(st, hipY, p#fFoot, 1.9, 9) ::
            skirt(st, hipY, p) ::
            (limb(st, 0.0, hipY - 0.5, shX, shY, 4.8, bodiceC(), 10) ::     // 胴着
             circleAt(st, hdX - 0.6, hdY - 0.7, 3.9, hairC(), 9) ::         // 髪のシルエット
             circleAt(st, hdX + 0.4, hdY, 3.4, skinC(), 10) ::              // 顔
             boxAt(st, hdX + 0.8, hdY - 2.6, 4.6, 1.6, hairC(), 11) ::      // 前髪
             boxAt(st, hdX + 2.0, hdY + 0.4, 1.3, 1.4, whiteC(), 12) ::     // 白目
             boxAt(st, hdX + 2.5, hdY + 0.4, 0.65, 1.4, hairC(), 13) ::     // 瞳
             boxAt(st, hdX - 3.0, hdY - 1.0, 1.6, 1.6, ribbonC(), 11) ::    // 結び紐
             Nil) ::
            ponytail(st, hdX - 3.4, hdY - 0.6, p#tailDir) ::
            scarf(st, shX, shY - 1.0, p#tailDir) ::
            arm(st, shX + 1.2, shY + 0.6, hF, 11) ::
            Nil)

    /// 脚: 腰から足先まで 1 本の真っ直ぐな線 + 舞踏靴。foot#y を上げるとつま先が伸びる。
    def legLine(st: CharStage.Stage, hipY: Float64, foot: Vec2.Vec2, w: Float64, z: Int32): List[Render.Placed] =
        limb(st, 0.0, hipY, foot#x, foot#y - 0.5, w, skinC(), z) ::
        boxAt(st, foot#x + 0.8, foot#y - 0.5, 2.4, 1.1, underC(), z) :: Nil

    /// 腕: 肘を持ち上げた弧を描く 2 節（バレエのポール・ド・ブラ）。
    def arm(st: CharStage.Stage, shX: Float64, shY: Float64, hand: Vec2.Vec2, z: Int32): List[Render.Placed] =
        let elX = shX + (hand#x - shX) * 0.5;
        let elY = shY + (hand#y - shY) * 0.5 - 1.6;
        limb(st, shX, shY, elX, elY, 1.6, skinC(), z) ::
        limb(st, elX, elY, hand#x, hand#y, 1.4, skinC(), z) ::
        circleAt(st, hand#x, hand#y, 1.0, skinC(), z) :: Nil

    /// スカート 2 枚重ね: 表（桃）+ 下履き（白・裾から 1px 覗く）。
    /// flare で広がり・sweep で流れ・hemLift でめくれ上がりを閉形式に受ける。
    def skirt(st: CharStage.Stage, hipY: Float64, p: Pose): List[Render.Placed] =
        let waistY = hipY - 0.5;
        let hemY = -3.5 + p#bob + p#sink * 0.5 - p#hemLift;
        let half = 5.2 + p#flare;
        polyAt(st, { x = -2.6, y = waistY } :: { x = 2.6, y = waistY }
                :: { x = half + p#sweep, y = hemY } :: { x = -half + p#sweep, y = hemY } :: Nil,
               skirtC(), 10) ::
        polyAt(st, { x = -2.0, y = waistY + 1.0 } :: { x = 2.0, y = waistY + 1.0 }
                :: { x = (half - 1.4) + p#sweep, y = hemY + 1.0 }
                :: { x = -1.0 * (half - 1.4) + p#sweep, y = hemY + 1.0 } :: Nil,
               underC(), 9) :: Nil

    /// ポニーテール: 先細りの珠 3 つが速さに応じた振幅で波打つ。tailDir で前後に流れる。
    def ponytail(st: CharStage.Stage, bx: Float64, by: Float64, dir: Float64): List[Render.Placed] =
        let amp = 1.0 + Float64.abs(st#vx) * 0.006;
        (0.0 :: 1.0 :: 2.0 :: Nil) |> List.map(i -> {
            let wv = Curve.triWave(st#t * 2.6 + i * 0.22) * amp;
            circleAt(st, bx + dir * (2.0 + i * 2.2), by + 0.6 * i + wv, 1.9 - i * 0.35, hairC(), 9)
        })

    /// 肩のスカーフ 2 節。髪と同じ向きに、少し遅れた位相で流れる。
    def scarf(st: CharStage.Stage, bx: Float64, by: Float64, dir: Float64): List[Render.Placed] =
        let amp = 1.2 + Float64.abs(st#vx) * 0.008;
        let w1 = Curve.triWave(st#t * 3.4) * amp;
        let w2 = Curve.triWave(st#t * 3.4 + 0.3) * amp * 1.5;
        limb(st, bx, by, bx + dir * 4.5, by + 0.5 + w1, 1.7, scarfC(), 11) ::
        limb(st, bx + dir * 4.5, by + 0.5 + w1, bx + dir * 9.0, by + 1.5 + w2, 1.4, scarfC(), 11) :: Nil

    // ── 演出 ──

    /// ダッシュ演出: 背後に波打つ風のリボン 3 節。スカーフの残り香が空に描かれる。
    def windRibbon(st: CharStage.Stage): List[Render.Placed] =
        let baseA = 0.2 + band(st) * 0.4;
        (1.0 :: 2.0 :: 3.0 :: Nil) |> List.map(kf -> {
            let w0 = Curve.triWave(st#t * 4.2 - kf * 0.33) * 3.0;
            let w1 = Curve.triWave(st#t * 4.2 - (kf + 1.0) * 0.33) * 3.0;
            fadePlaced(RenderUtil.f32(baseA * (1.0 - kf * 0.24)),
                       limb(st, -3.0 - kf * 7.0, -13.0 + w0, -10.0 - kf * 7.0, -13.0 + w1,
                            1.6, scarfC(), 8))
        })

    /// スキッドの滑り筋: つま先の下に白い擦過線が 2 本伸びる（砂埃は立てない主義）。
    def slideStreaks(st: CharStage.Stage): List[Render.Placed] =
        let u = clamp01(st#modeT / 0.35);
        let a = RenderUtil.f32(0.5 * (1.0 - u));
        fadePlaced(a, boxAt(st, 4.0, -0.5, 8.0, 0.8, whiteC(), 8)) ::
        fadePlaced(a, boxAt(st, 1.0, -1.4, 5.0, 0.6, whiteC(), 8)) ::
        fadePlaced(a, circleAt(st, 8.8, -1.8, 1.4, whiteC(), 12)) :: Nil

    /// 着地の風の輪: 足元に細い白線がふわっと広がって消える。
    def landRing(st: CharStage.Stage): List[Render.Placed] =
        let u = clamp01(st#modeT / 0.14);
        if (u >= 1.0) Nil
        else {
            let a = RenderUtil.f32(0.35 * (1.0 - u));
            fadePlaced(a, boxAt(st, 0.0, -1.0, 10.0 + u * 6.0, 0.8, whiteC(), 8)) :: Nil
        }

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

    /// (x0,y0)→(x1,y1) を結ぶ太さ w の棒。手足・布のひと節。
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
