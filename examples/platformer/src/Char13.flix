// 屋根裏のカイト — 街の屋根と塀を近道にするパルクール少年。
// 頭でっかちの低頭身、刻みの速いピッチ走り、跳べば膝を抱えて前宙気味に丸まる。
// 止まるときは手を地面に擦らせるロースライド、着地は必ず三点。橙の鞄は今日も配達中。

mod Char13 {

    pub def name(): String = "13 TRACEUR"

    // ── DB32 ローカルパレット ──
    def skinC(): Color   = { r = 217.0f32 / 255.0f32, g = 160.0f32 / 255.0f32, b = 102.0f32 / 255.0f32 } // d9a066 肌
    def hoodieC(): Color = { r =  55.0f32 / 255.0f32, g = 148.0f32 / 255.0f32, b = 110.0f32 / 255.0f32 } // 37946e パーカー
    def hoodC(): Color   = { r =  75.0f32 / 255.0f32, g = 105.0f32 / 255.0f32, b =  47.0f32 / 255.0f32 } // 4b692f フード
    def pantsC(): Color  = { r =  89.0f32 / 255.0f32, g =  86.0f32 / 255.0f32, b =  82.0f32 / 255.0f32 } // 595652 ズボン
    def shoeC(): Color   = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b =  54.0f32 / 255.0f32 } // fbf236 黄色いスニーカー
    def bagC(): Color    = { r = 223.0f32 / 255.0f32, g = 113.0f32 / 255.0f32, b =  38.0f32 / 255.0f32 } // df7126 配達鞄
    def hairC(): Color   = { r =  34.0f32 / 255.0f32, g =  32.0f32 / 255.0f32, b =  52.0f32 / 255.0f32 } // 222034 前髪と瞳
    def dustC(): Color   = { r = 217.0f32 / 255.0f32, g = 160.0f32 / 255.0f32, b = 102.0f32 / 255.0f32 } // d9a066 土埃
    def whiteC(): Color  = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 } // ffffff 白目・ソール・風の筋

    // ── ポーズ（足元中心ローカル・上が負 y・x は facing 方向）──
    type alias Pose = {
        lean = Float64,       // 前傾（+で進行方向へ・-で後ろ倒れ = ロースライド）
        sink = Float64,       // 腰の沈み（+で低く）
        fFoot = Vec2.Vec2,    // 前側の足先
        bFoot = Vec2.Vec2,    // 奥側の足先
        handF = Vec2.Vec2,    // 前側の手先
        handB = Vec2.Vec2,    // 奥側の手先
        headTuck = Float64,   // 頭の抱え込み（+で前下へ = タック）
        hoodUp = Float64      // フードのはためき（+で浮き上がる）
    }

    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        match stage#mode {
            case CharStage.Mode.IdleMode => body(stage, idlePose(stage))
            case CharStage.Mode.RunMode  => body(stage, runPose(stage))
            case CharStage.Mode.DashMode => List.append(ghostsAndStreaks(stage), body(stage, runPose(stage)))
            case CharStage.Mode.SkidMode => List.append(body(stage, skidPose()), skidFx(stage))
            case CharStage.Mode.JumpMode => body(stage, jumpPose(stage))
            case CharStage.Mode.FallMode => body(stage, fallPose())
            case CharStage.Mode.LandMode => List.append(body(stage, landPose(stage)), landDust(stage))
        }

    // ── ポーズ表 ──

    /// ピッチ走: 歩幅 ±4.2px の細かい刻み・体は立て気味・上下動は最小。
    /// 両腕は 90 度に畳んで腰の高さを直線的に前後する（スプリンターの腕）。
    def runPose(st: CharStage.Stage): Pose =
        let s = Curve.triWave(st#pos#x * 0.13);
        let air = 1.0 - Float64.abs(s);
        { lean = 2.0 + band(st) * 2.0,
          sink = 0.5 * Float64.abs(s),
          fFoot = { x = s * 4.2, y = -2.0 * air },
          bFoot = { x = -4.2 * s, y = -2.0 * air },
          handF = { x = 0.5 + s * 4.0, y = -8.5 },
          handB = { x = 0.5 - s * 4.0, y = -8.5 },
          headTuck = 0.0,
          hoodUp = Float64.abs(st#vx) * 0.004 }

    /// スキッド: 腰を落として両足を前へ突っ張り、後ろ手を地面に擦らせるロースライド。
    def skidPose(): Pose =
        { lean = -4.5, sink = 3.2,
          fFoot = { x = 7.0, y = 0.0 }, bFoot = { x = 5.0, y = -1.2 },
          handF = { x = 4.5, y = -7.5 },     // 前手は宙でバランス
          handB = { x = -5.0, y = -0.6 },    // 後ろ手は地面すれすれ
          headTuck = 0.5, hoodUp = 1.5 }

    /// 跳躍: 膝抱えタック。modeT で徐々に丸まりが深くなり、前宙気味に体が回り込む。
    def jumpPose(st: CharStage.Stage): Pose =
        let roll = clamp01(st#modeT / 0.45);
        { lean = 1.5 + roll * 5.0,
          sink = -0.5,
          fFoot = { x = 3.0 + roll, y = -7.0 - roll * 1.5 },
          bFoot = { x = 1.2 + roll, y = -8.0 - roll * 1.5 },
          handF = { x = 4.2 + roll, y = -7.8 },     // 両手で膝を抱える
          handB = { x = 3.4 + roll, y = -9.0 },
          headTuck = 1.0 + roll * 2.5, hoodUp = 0.8 }

    /// 落下: タックを解いて手足を開き、足裏から着地点を探す。フードが浮く。
    def fallPose(): Pose =
        { lean = 0.5, sink = 0.0,
          fFoot = { x = 2.4, y = -2.2 }, bFoot = { x = -2.4, y = -1.6 },
          handF = { x = 6.0, y = -12.5 }, handB = { x = -6.0, y = -12.5 },
          headTuck = 0.0, hoodUp = 2.5 }

    /// 着地: 三点着地。深くしゃがみ、前手を地面へつき、後ろ手でバランスを取る。
    def landPose(st: CharStage.Stage): Pose =
        let ease = 1.0 - clamp01(st#modeT / 0.2);
        { lean = 3.0, sink = 1.2 + 2.6 * ease,
          fFoot = { x = 4.2, y = 0.0 }, bFoot = { x = -3.6, y = 0.0 },
          handF = { x = 6.2, y = -0.8 - p3(ease) },   // 地面についた手は立ち上がりで離れる
          handB = { x = -5.2, y = -10.5 },
          headTuck = 1.2 * ease, hoodUp = 0.0 }

    /// 着地の手離れ: ease が抜けるほど手が持ち上がる（1-ease に比例）。
    def p3(ease: Float64): Float64 = (1.0 - ease) * 6.0

    /// 待機: 両手を膝に置いてリズミカルに屈伸 — 次の走りへ体をあたためる。
    def idlePose(st: CharStage.Stage): Pose =
        let sq = (Curve.triWave(st#modeT * 0.75) + 1.0) * 0.5;   // 0..1 の屈伸
        { lean = 1.0, sink = sq * 2.4,
          fFoot = { x = 3.0, y = 0.0 }, bFoot = { x = -3.0, y = 0.0 },
          handF = { x = 3.4, y = -5.6 }, handB = { x = 2.6, y = -5.2 },
          headTuck = sq * 0.6, hoodUp = 0.0 }

    // ── 体の組み立て ──

    def body(st: CharStage.Stage, p: Pose): List[Render.PlacedItem] =
        let hipY = -6.0 + p#sink;
        let shX = p#lean * 0.6;
        let shY = hipY - 5.3 + p#sink * 0.15;
        let hdX = p#lean + p#headTuck * 0.8;
        let hdY = shY - 3.6 + p#headTuck;
        let hF = { x = p#handF#x, y = p#handF#y + p#sink };
        let hB = { x = p#handB#x, y = p#handB#y + p#sink };
        List.flatten(
            arm(st, shX - 1.6, shY + 0.8, hB, 9) ::
            (boxAt(st, -3.4 + shX * 0.5, shY + 1.8, 4.2, 3.4, bagC(), 9) :: Nil) ::   // 配達鞄
            leg(st, hipY, p#bFoot, 9) ::
            leg(st, hipY, p#fFoot, 11) ::
            (limb(st, 0.0, hipY, shX, shY, 6.0, hoodieC(), 10) ::                     // 胴 = パーカー
             limb(st, shX + 2.2, shY - 0.5, -1.8, hipY + 0.5, 1.0, bagC(), 11) ::     // 斜めがけストラップ
             circleAt(st, hdX - 1.3, hdY + 0.6 - p#hoodUp, 4.4, hoodC(), 9) ::        // フード（速さで浮く）
             circleAt(st, hdX + 0.6, hdY, 3.7, skinC(), 10) ::                        // 顔
             boxAt(st, hdX + 0.8, hdY - 2.7, 5.0, 1.8, hairC(), 11) ::                // 前髪
             boxAt(st, hdX + 2.2, hdY + 0.2, 1.5, 1.6, whiteC(), 12) ::               // 白目
             boxAt(st, hdX + 2.8, hdY + 0.2, 0.75, 1.6, hairC(), 13) ::               // 瞳
             Nil) ::
            arm(st, shX + 1.6, shY + 0.8, hF, 11) ::
            Nil)

    /// 脚: 腰→膝→足の 2 節 + 黄色いスニーカー（白ソール付きのじまん）。
    def leg(st: CharStage.Stage, hipY: Float64, foot: Vec2.Vec2, z: Int32): List[Render.PlacedItem] =
        let kneeX = foot#x * 0.5 + 1.4;
        let kneeY = (hipY + foot#y) * 0.5 - 0.3;
        limb(st, 0.0, hipY, kneeX, kneeY, 2.5, pantsC(), z) ::
        limb(st, kneeX, kneeY, foot#x, foot#y - 0.8, 2.1, pantsC(), z) ::
        boxAt(st, foot#x + 0.7, foot#y - 0.9, 3.2, 1.3, shoeC(), z) ::
        boxAt(st, foot#x + 0.7, foot#y - 0.25, 3.2, 0.6, whiteC(), z) :: Nil

    /// 腕: 肘を後ろ上に張った 90 度の畳み。袖はパーカー色・拳だけ肌。
    def arm(st: CharStage.Stage, shX: Float64, shY: Float64, hand: Vec2.Vec2, z: Int32): List[Render.PlacedItem] =
        let elX = shX + (hand#x - shX) * 0.35 - 0.8;
        let elY = shY + 1.4;
        limb(st, shX, shY, elX, elY, 2.0, hoodieC(), z) ::
        limb(st, elX, elY, hand#x, hand#y, 1.7, skinC(), z) ::
        circleAt(st, hand#x, hand#y, 1.2, skinC(), z) :: Nil

    // ── 演出 ──

    /// ダッシュ演出: 残像分身 2 体（体色そのまま薄く）+ 白い風の筋。速いほど濃い。
    def ghostsAndStreaks(st: CharStage.Stage): List[Render.PlacedItem] =
        let b = band(st);
        let ghost = (back: Float64, a: Float32) ->
            fadePlaced(a, circleAt(st, -1.0 - back, -13.5, 4.2, hoodC(), 8)) ::
            fadePlaced(a, circleAt(st, 0.5 - back, -12.8, 3.5, skinC(), 8)) ::
            fadePlaced(a, boxAt(st, 0.0 - back, -8.5, 6.0, 5.5, hoodieC(), 8)) ::
            fadePlaced(a, boxAt(st, 0.0 - back, -3.2, 4.6, 4.8, pantsC(), 8)) :: Nil;
        List.flatten(
            ghost(9.0, RenderUtil.f32(0.14 + 0.18 * b)) ::
            ghost(17.0, RenderUtil.f32(0.07 + 0.10 * b)) ::
            (fadePlaced(RenderUtil.f32(0.25 + 0.25 * b), boxAt(st, -12.0, -10.0, 7.0, 0.8, whiteC(), 8)) ::
             fadePlaced(RenderUtil.f32(0.18 + 0.20 * b), boxAt(st, -15.0, -5.0, 9.0, 0.8, whiteC(), 8)) :: Nil) ::
            Nil)

    /// スキッドの手擦り: 地面を擦る後ろ手から土埃、前足の下に白い滑り筋。
    def skidFx(st: CharStage.Stage): List[Render.PlacedItem] =
        let u = clamp01(st#modeT / 0.35);
        let a = RenderUtil.f32(0.5 * (1.0 - u));
        fadePlaced(a, circleAt(st, -6.5 - u * 2.0, -1.5 - u * 1.5, 1.6, dustC(), 12)) ::
        fadePlaced(a, circleAt(st, -8.0 - u * 3.0, -0.8, 1.1, dustC(), 12)) ::
        fadePlaced(a, boxAt(st, 6.0, -0.5, 6.0, 0.9, whiteC(), 8)) :: Nil

    /// 三点着地の土煙: ついた手の周りと左右へひと吹き。
    def landDust(st: CharStage.Stage): List[Render.PlacedItem] =
        let u = clamp01(st#modeT / 0.14);
        if (u >= 1.0) Nil
        else {
            let a = RenderUtil.f32(0.45 * (1.0 - u));
            fadePlaced(a, circleAt(st, 7.0 + u * 2.0, -1.2, 1.8 - u, dustC(), 12)) ::
            fadePlaced(a, circleAt(st, -5.0 - u * 3.0, -1.5, 1.6 - u, dustC(), 12)) :: Nil
        }

    // ── 置き方ヘルパ（足元中心ローカル・facing で x 反転）──

    /// 中心 (cx, cy)・寸法 (w, h) の箱。
    def boxAt(st: CharStage.Stage, cx: Float64, cy: Float64, w: Float64, h: Float64,
              color: Color, z: Int32): Render.PlacedItem =
        { at = { x = st#pos#x + st#facing * cx - w / 2.0, y = st#pos#y + cy - h / 2.0 },
          item = Render.box({ x = w, y = h }, color, z) }

    /// 中心 (cx, cy)・半径 r の円。
    def circleAt(st: CharStage.Stage, cx: Float64, cy: Float64, r: Float64,
                 color: Color, z: Int32): Render.PlacedItem =
        { at = { x = st#pos#x + st#facing * cx - r, y = st#pos#y + cy - r },
          item = Render.circle(r, color, z) }

    /// 相対頂点列を facing で鏡映して置く（凸多角形・反転時は巻き順も戻す）。
    def polyAt(st: CharStage.Stage, verts: List[Vec2.Vec2], color: Color, z: Int32): Render.PlacedItem =
        let vs = List.map(v -> { x = st#facing * v#x, y = v#y }, verts);
        let ordered = if (st#facing >= 0.0) vs else List.reverse(vs);
        { at = { x = st#pos#x, y = st#pos#y }, item = Render.polygon(ordered, color, z) }

    /// (x0,y0)→(x1,y1) を結ぶ太さ w の棒。手足のひと節。
    def limb(st: CharStage.Stage, x0: Float64, y0: Float64, x1: Float64, y1: Float64,
             w: Float64, color: Color, z: Int32): Render.PlacedItem =
        let dx = x1 - x0;
        let dy = y1 - y0;
        let len = Float64.max(0.001, Vec2.sqrt(dx * dx + dy * dy));
        let px = -1.0 * dy / len * (w / 2.0);
        let py = dx / len * (w / 2.0);
        polyAt(st, { x = x0 + px, y = y0 + py } :: { x = x1 + px, y = y1 + py }
                :: { x = x1 - px, y = y1 - py } :: { x = x0 - px, y = y0 - py } :: Nil,
               color, z)

    // ── 小物ヘルパ ──

    def fadePlaced(a: Float32, placed: Render.PlacedItem): Render.PlacedItem =
        { item = Render.fade(a, placed#item) | placed }

    def clamp01(v: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, v))

    /// ダッシュ帯の進み具合（|vx| 160→280 を 0→1 に写す）。
    def band(st: CharStage.Stage): Float64 = clamp01((Float64.abs(st#vx) - 160.0) / 120.0)
}
