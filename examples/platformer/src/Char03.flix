// マキオヤモリ — 地を這う低いシルエットのヤモリ。背骨を数珠玉の連なりで描き、尻尾は背中の上に
// くるりと巻く。走りは体を波打たせ、ダッシュは光る足跡を残し、ジャンプは C の字に丸まって落下で滑空に開く。

mod Char03 {

    use CharStage.Mode

    /// ギャラリーに出す ASCII ラベル。
    pub def name(): String = "03 GECKO"

    // ── 配色（DB32・ダッシュ中も体色は変えない）──

    /// 背中の緑。 6abe30
    def backColor(): Color    = { r = 106.0f32 / 255.0f32, g = 190.0f32 / 255.0f32, b = 48.0f32 / 255.0f32 }
    /// 腹と足跡の光の若草色。 99e550
    def paleColor(): Color    = { r = 153.0f32 / 255.0f32, g = 229.0f32 / 255.0f32, b = 80.0f32 / 255.0f32 }
    /// 奥側の脚の暗い緑。 4b692f
    def shadeColor(): Color   = { r = 75.0f32 / 255.0f32, g = 105.0f32 / 255.0f32, b = 47.0f32 / 255.0f32 }
    /// 目の虹彩の黄。 fbf236
    def irisColor(): Color    = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b = 54.0f32 / 255.0f32 }
    /// 瞳の縦スリットの黒。 000000
    def slitColor(): Color    = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }
    /// 舌の赤。 d95763
    def tongueColor(): Color  = { r = 217.0f32 / 255.0f32, g = 87.0f32 / 255.0f32, b = 99.0f32 / 255.0f32 }

    // 演技区分から導く体形の係数。背骨の並べ方をこれだけで決める（状態は持たない）。
    type alias Shape = {
        compress = Float64,  // スキッドの蛇腹圧縮（体が後ろへ縮む）
        arch = Float64,      // スキッドの背中の盛り上がり
        low = Float64,       // 体を地面へ低く伸ばす量（ダッシュ・着地のべしゃり）
        span = Float64,      // 体の前後の伸び（滑空で広がる）
        ball = Float64,      // ジャンプの C 字丸まり
        flut = Float64,      // 滑空のはためき
        breath = Float64,    // 待機の呼吸（胴の玉がふくらむ）
        brace = Float64,     // スキッドで四肢を前へ突っ張る
        splay = Float64      // 滑空で四肢を大の字に開く
    }

    /// 演技区分ごとの体形係数。区分に入ってからの経過秒で立ち上げて、境界の飛びを消す。
    def shapeOf(stage: CharStage.Stage): Shape =
        let zero = { compress = 0.0, arch = 0.0, low = 0.0, span = 1.0, ball = 0.0,
                     flut = 0.0, breath = 0.0, brace = 0.0, splay = 0.0 };
        match stage#mode {
            case Mode.IdleMode => { breath = 1.0 | zero }
            case Mode.RunMode  => zero
            case Mode.DashMode =>
                // ダッシュ: 体が低く伸びる。
                let rise = Float64.min(1.0, stage#modeT / 0.25);
                { low = 0.2 * rise, span = 1.0 + 0.05 * rise | zero }
            case Mode.SkidMode =>
                // スキッド: 蛇腹に縮んで背中が山なりに盛り上がり、四肢を前へ突っ張る。
                let dig = Float64.min(1.0, stage#modeT / 0.12);
                { compress = dig, arch = dig, brace = dig | zero }
            case Mode.JumpMode =>
                // 上昇: 尻尾ごと C の字に丸まって車輪のようになる。
                { ball = Float64.min(1.0, stage#modeT / 0.15) | zero }
            case Mode.FallMode =>
                // 落下: 平たく広がって滑空（ムササビ様の膜を張る）。
                let open = Float64.min(1.0, stage#modeT / 0.15);
                { low = 0.25 * open, span = 1.0 + 0.1 * open, flut = open, splay = open | zero }
            case Mode.LandMode =>
                // 着地: べしゃりと潰れて横に広がり、0.2 秒で戻る。
                let squash = 1.0 - Float64.min(1.0, stage#modeT / 0.2);
                { low = squash, span = 1.0 + 0.12 * squash | zero }
        }

    /// 舞台状態から 1 コマ分の描画列を導く（閉形式・状態なし）。
    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        let shape = shapeOf(stage);
        let head = headCenter(stage, shape);
        List.flatten(
            dashPrints(stage)
            :: legItems(stage, shape, false)
            :: tailItems(stage, shape)
            :: membraneItems(stage, shape)
            :: spineItems(stage, shape)
            :: bellyItems(stage, shape)
            :: legItems(stage, shape, true)
            :: headItems(stage, head)
            :: Nil)

    // ── 背骨の数珠玉 ──

    /// 背骨上の点（along は頭 0.0 → 腰 1.0）。歩きの波・スキッドの蛇腹・丸まりを全部ここで解く。
    def spinePoint(stage: CharStage.Stage, shape: Shape, along: Float64): Vec2.Vec2 =
        let face = stage#facing;
        let strideAmp = Float64.min(1.0, Float64.abs(stage#vx) / 160.0);
        // 接地の基本形: 頭が高く腰が低い、前上がりの低い構え。
        let groundX = stage#pos#x
                      + face * (8.0 - 12.0 * along) * shape#span * (1.0 - 0.35 * shape#compress)
                      - face * 3.5 * shape#compress;
        let baseY = -(6.2 - 2.2 * along) * (1.0 - 0.45 * shape#low);
        let wiggle = -1.4 * strideAmp * Curve.triWave(stage#pos#x * 0.13 + along * 0.55);
        let archY = -shape#arch * 6.0 * (4.0 * along * (1.0 - along));
        let flutY = shape#flut * 0.4 * Curve.triWave(stage#t * 13.0 + along * 2.0);
        let ground = { x = groundX, y = stage#pos#y + baseY + wiggle + archY + flutY };
        // 丸まり: 手で振り付けた C 字の並び（頭が前下、背が上へ巻く）。
        let curled = ballOffset(along);
        let ball = { x = stage#pos#x + face * curled#x, y = stage#pos#y - 8.5 + curled#y };
        vMix(ground, ball, shape#ball)

    /// C 字丸まりの並び（中心からのオフセット・頭 0.0 → 腰 1.0 を折れ線で読む）。
    def ballOffset(along: Float64): Vec2.Vec2 =
        { x = Curve.pieces((0.0, 4.6) :: (0.17, 5.2) :: (0.33, 3.4) :: (0.5, 0.2)
                           :: (0.67, -3.0) :: (0.83, -5.0) :: (1.0, -4.4) :: Nil, along),
          y = Curve.pieces((0.0, 3.0) :: (0.17, -0.6) :: (0.33, -3.8) :: (0.5, -5.2)
                           :: (0.67, -4.2) :: (0.83, -1.2) :: (1.0, 2.4) :: Nil, along) }

    /// 背骨 7 玉。頭側が太く腰へ細る。待機は胴がふくらむ呼吸つき。
    def spineItems(stage: CharStage.Stage, shape: Shape): List[Render.Placed] =
        List.range(0, 7) |> List.map(i -> {
            let along = Int32.toFloat64(i) / 6.0;
            let center = spinePoint(stage, shape, along);
            let radius = (4.2 - 1.0 * along)
                         * (1.0 + shape#breath * 0.07 * Curve.tri(2.2, stage#t));
            ({ x = center#x - radius, y = center#y - radius },
             Render.circle(radius, backColor(), 10))
        })

    /// 腹の若草色: 胴の下側に小さな玉を沿わせる。
    def bellyItems(stage: CharStage.Stage, shape: Shape): List[Render.Placed] =
        List.range(0, 3) |> List.map(i -> {
            let along = 0.33 + Int32.toFloat64(i) * 0.17;
            let center = spinePoint(stage, shape, along);
            let radius = 2.0 * (1.0 + shape#breath * 0.09 * Curve.tri(2.2, stage#t));
            ({ x = center#x - radius, y = center#y + 1.7 - radius },
             Render.circle(radius, paleColor(), 11))
        })

    // ── 頭 ──

    /// 頭の中心。スキッドでは体の圧縮に乗って引けつつ、あごを上げてのけぞる。
    def headCenter(stage: CharStage.Stage, shape: Shape): Vec2.Vec2 =
        let front = spinePoint(stage, shape, 0.0);
        { x = front#x + stage#facing * 2.6 * (1.0 - 0.4 * shape#compress),
          y = front#y - 0.8 - 3.5 * shape#arch }

    /// 頭・黄色い目・縦スリットの瞳・待機の舌チロチロ。
    def headItems(stage: CharStage.Stage, head: Vec2.Vec2): List[Render.Placed] =
        let face = stage#facing;
        let tongue = match stage#mode {
            case Mode.IdleMode =>
                // 待機の途中で一度だけ舌を出し入れする（0.35 秒の山なり）。
                if (stage#modeT >= 0.5 and stage#modeT <= 0.85) {
                    let out = 5.0 * Curve.tri(0.35, stage#modeT - 0.5);
                    ({ x = head#x + face * 3.5, y = head#y + 0.6 },
                     Render.polygon({ x = 0.0, y = -0.5 } :: { x = face * out, y = -0.2 }
                                    :: { x = 0.0, y = 0.5 } :: Nil, tongueColor(), 13)) :: Nil
                } else Nil
            case _ => Nil
        };
        List.append(
            ({ x = head#x - 4.3, y = head#y - 4.3 }, Render.circle(4.3, backColor(), 12))
            :: ({ x = head#x + face * 1.4 - 1.7, y = head#y - 1.6 - 1.7 },
                Render.circle(1.7, irisColor(), 13))
            :: ({ x = head#x + face * 1.7 - 0.4, y = head#y - 1.7 - 1.2 },
                Render.box({ x = 0.8, y = 2.4 }, slitColor(), 13) |> Render.rounded(0.4))
            :: Nil,
            tongue)

    // ── 尻尾（背中の上に巻く・ダッシュで流れ・スキッドで頭上へ振り上がる）──

    /// 尻尾 6 玉。腰の玉から相対オフセットの列を体形で選んで混ぜる。
    def tailItems(stage: CharStage.Stage, shape: Shape): List[Render.Placed] =
        let face = stage#facing;
        let hip = spinePoint(stage, shape, 1.0);
        let dashK = match stage#mode {
            case Mode.DashMode => Float64.min(1.0, stage#modeT / 0.25)
            case _             => 0.0
        };
        let wag = 0.6 * Curve.triWave(stage#t * 0.45) * shape#breath;
        List.range(0, 6) |> List.map(j -> {
            let along = Int32.toFloat64(j) / 5.0;
            // くるりと巻いた基本形（待機はゆっくり尻尾を振る）。
            let curled = { x = curledTailX(along) + wag * along, y = curledTailY(along) };
            // ダッシュ: 後ろへ流れてはためく尻尾。
            let stream = { x = -8.4 * along,
                           y = 0.5 - 0.9 * along + 0.9 * Curve.triWave(stage#t * 6.0 + along * 0.8) };
            // スキッド: 頭の上まで振り上がるムチ（のけぞりの誇張）。
            let whip = { x = 7.5 * along * along + 0.5 * along,
                         y = -14.0 * along * (2.0 - along) * 0.7 };
            // 落下: まっすぐ上へ立てて舵にする。
            let rudder = { x = -3.0 * along, y = -10.0 * along };
            let sel = vMix(vMix(vMix(curled, stream, dashK), whip, shape#brace), rudder, shape#splay);
            // ジャンプの丸まりでは巻きを小さくして体の内側へ収める。
            let inBall = 1.0 - 0.4 * shape#ball;
            let radius = 2.2 - 1.7 * along;
            let center = { x = hip#x + face * sel#x * inBall, y = hip#y + sel#y * inBall };
            ({ x = center#x - radius, y = center#y - radius },
             Render.circle(radius, backColor(), 9))
        })

    /// 巻き尻尾の x（腰からの相対・折れ線）。
    def curledTailX(along: Float64): Float64 =
        Curve.pieces((0.0, 0.0) :: (0.2, -1.4) :: (0.4, -2.2) :: (0.6, -1.4)
                     :: (0.8, 0.8) :: (1.0, 2.8) :: Nil, along)

    /// 巻き尻尾の y（腰からの相対・背中の上へ弧を描く）。
    def curledTailY(along: Float64): Float64 =
        Curve.pieces((0.0, 0.0) :: (0.2, -3.0) :: (0.4, -6.5) :: (0.6, -9.7)
                     :: (0.8, -11.7) :: (1.0, -10.2) :: Nil, along)

    // ── 四肢（近側 2 本 + 奥側 2 本のがに股）──

    /// 脚 4 本のうち近側か奥側かを描く。足は距離駆動のトロット（前後で対角の位相）。
    def legItems(stage: CharStage.Stage, shape: Shape, near: Bool): List[Render.Placed] =
        let face = stage#facing;
        let strideAmp = Float64.min(1.0, Float64.abs(stage#vx) / 160.0);
        let gait = stage#pos#x * 0.13;
        let color = if (near) backColor() else shadeColor();
        let layer = if (near) 12 else 9;
        let phaseShift = if (near) 0.0 else 0.5;
        // (付け根の背骨位置, 前脚か, 踏ん張り順)
        let plan = ({ along = 0.2, fore = 1.0, order = 0.0 })
                   :: ({ along = 0.82, fore = -1.0, order = 1.0 }) :: Nil;
        plan |> List.flatMap(leg -> {
            let anchor = spinePoint(stage, shape, leg#along);
            let cyc = gait + phaseShift + (if (leg#fore > 0.0) 0.0 else 0.5);
            let onGround = { x = anchor#x + face * (1.0 + 5.5 * strideAmp * Curve.triWave(cyc)),
                             y = stage#pos#y
                                 - 3.0 * strideAmp * Float64.max(0.0, Curve.triWave(cyc + 0.25)) };
            let braced = { x = stage#pos#x + face * (2.5 + (leg#order + phaseShift) * 1.7),
                           y = stage#pos#y };
            let splayed = { x = anchor#x + face * leg#fore * 6.0, y = anchor#y - 3.5 };
            let tucked = { x = stage#pos#x + face * 0.5, y = stage#pos#y - 7.0 };
            let foot = vMix(vMix(vMix(onGround, braced, shape#brace), splayed, shape#splay),
                            tucked, shape#ball);
            // がに股の脚: 付け根から足先へ細る三角形 + 指先の吸盤。
            ({ x = 0.0, y = 0.0 },
             Render.polygon({ x = anchor#x, y = anchor#y - 1.4 } :: { x = anchor#x, y = anchor#y + 1.4 }
                            :: { x = foot#x, y = foot#y } :: Nil, color, layer))
            :: ({ x = foot#x - 1.2, y = foot#y - 1.2 }, Render.circle(1.2, color, layer))
            :: Nil
        })

    // ── ダッシュ演出: ぺたぺた光る足跡（地面に貼り付いて後ろへ流れる）──

    /// 足跡は地面座標に量子化してあるので、走っても地面に貼り付いたまま薄れて消える。
    def dashPrints(stage: CharStage.Stage): List[Render.Placed] =
        match stage#mode {
            case Mode.DashMode =>
                let face = stage#facing;
                let px = stage#pos#x;
                let shift = (px * face / 9.0 - Float64.floor(px * face / 9.0)) * 9.0;
                List.range(0, 3) |> List.map(k -> {
                    let fk = Int32.toFloat64(k);
                    let age = (shift + 9.0 * fk) / 27.0;
                    let printX = px - face * (5.0 + shift + 9.0 * fk);
                    let alpha = RenderUtil.f32(Float64.max(0.0, 0.6 * (1.0 - age)));
                    ({ x = printX - 1.7, y = stage#pos#y - 1.2 - 1.7 },
                     Render.circle(1.7, paleColor(), 8) |> Render.fade(alpha))
                })
            case _ => Nil
        }

    // ── 滑空の膜（落下だけ・薄く張る）──

    /// ムササビ様の皮膜。落下で体の下に薄く張り、他の区分では描かない。
    def membraneItems(stage: CharStage.Stage, shape: Shape): List[Render.Placed] =
        if (shape#splay < 0.01)
            Nil
        else {
            let face = stage#facing;
            let sheet = ({ x = stage#pos#x, y = stage#pos#y - 4.0 },
                         Render.polygon({ x = face * 9.0, y = -1.0 } :: { x = -face * 8.5, y = -1.0 }
                                        :: { x = -face * 6.5, y = 3.0 } :: { x = face * 7.5, y = 3.0 } :: Nil,
                                        paleColor(), 9)
                            |> Render.fade(RenderUtil.f32(0.35 * shape#splay)));
            sheet :: Nil
        }

    /// 位置の線形補間（k は 0..1）。
    def vMix(a: Vec2.Vec2, b: Vec2.Vec2, k: Float64): Vec2.Vec2 =
        { x = a#x + (b#x - a#x) * k, y = a#y + (b#y - a#y) * k }
}
