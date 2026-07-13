// ヨイボタル — 尻の提灯を灯して低空を飛ぶ甲虫。地上では六肢で立って提灯が呼吸のように明滅し、
// 飛べば体が進行方向へ傾いて羽がブレ、ダッシュは提灯の光の残跡を曳く。急停止は羽を前へ突き出す空気ブレーキ。

mod Char04 {

    use CharStage.Mode

    /// ギャラリーに出す ASCII ラベル。
    pub def name(): String = "04 FIREFLY"

    // ── 配色（DB32・ダッシュ中も体色は変えない）──

    /// 腹部の濃い紫がかった黒。 45283c
    def abdomenColor(): Color = { r = 69.0f32 / 255.0f32, g = 40.0f32 / 255.0f32, b = 60.0f32 / 255.0f32 }
    /// 鞘翅（羽の覆い）の暗い青緑。 323c39
    def elytraColor(): Color  = { r = 50.0f32 / 255.0f32, g = 60.0f32 / 255.0f32, b = 57.0f32 / 255.0f32 }
    /// 前胸の赤（ホタルの首飾り）。 d95763
    def collarColor(): Color  = { r = 217.0f32 / 255.0f32, g = 87.0f32 / 255.0f32, b = 99.0f32 / 255.0f32 }
    /// 頭と脚と触角の黒に近い紺。 222034
    def darkColor(): Color    = { r = 34.0f32 / 255.0f32, g = 32.0f32 / 255.0f32, b = 52.0f32 / 255.0f32 }
    /// 提灯と光の残跡の黄。 fbf236
    def glowColor(): Color    = { r = 251.0f32 / 255.0f32, g = 242.0f32 / 255.0f32, b = 54.0f32 / 255.0f32 }
    /// 羽の薄青。 cbdbfc
    def wingColor(): Color    = { r = 203.0f32 / 255.0f32, g = 219.0f32 / 255.0f32, b = 252.0f32 / 255.0f32 }
    /// 目の白。 ffffff
    def eyeWhite(): Color     = { r = 255.0f32 / 255.0f32, g = 255.0f32 / 255.0f32, b = 255.0f32 / 255.0f32 }
    /// 瞳の黒。 000000
    def eyeDark(): Color      = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }

    // 演技区分から導く飛行姿勢。体の各部品はこの係数で吊るす（状態は持たない）。
    type alias Flight = {
        alt = Float64,      // 体の中心の高さ（足元からの浮き）
        pitch = Float64,    // 前傾(+) / のけぞり(-)。前後の部品を剪断で傾ける
        air = Float64,      // 0 = 地上に立つ / 1 = 飛んで脚がぶら下がる
        tuck = Float64,     // 上昇のしずく形（脚をたたみ腹を縦に伸ばす）
        squash = Float64,   // 着地のべちゃり
        breath = Float64    // 待機の呼吸（腹の膨らみと提灯の明滅をゆっくりに）
    }

    /// 演技区分ごとの飛行姿勢。浮きの上下は距離駆動 + 時刻の三角波で導く。
    def flightOf(stage: CharStage.Stage): Flight =
        let bob = 1.6 * Curve.triWave(stage#pos#x * 0.07) + 0.5 * Curve.triWave(stage#t * 2.3);
        match stage#mode {
            case Mode.IdleMode =>
                // 待機: 地面に立ち、腹が呼吸で膨らむ。
                { alt = 6.5 + 0.4 * Curve.tri(1.8, stage#t), pitch = 0.0, air = 0.0,
                  tuck = 0.0, squash = 0.0, breath = 1.0 }
            case Mode.RunMode  =>
                { alt = 11.5 + bob, pitch = 0.45 * Float64.min(1.0, Float64.abs(stage#vx) / 280.0),
                  air = 1.0, tuck = 0.0, squash = 0.0, breath = 0.0 }
            case Mode.DashMode =>
                // ダッシュ: さらに深く前傾して光の残跡を曳く。
                { alt = 11.5 + bob, pitch = 0.45 + 0.4 * Float64.min(1.0, stage#modeT / 0.25),
                  air = 1.0, tuck = 0.0, squash = 0.0, breath = 0.0 }
            case Mode.SkidMode =>
                // スキッド: 大きくのけぞって羽を前へ突き出す空気ブレーキ。
                { alt = 11.0 + bob * 0.5, pitch = -1.1 * Float64.min(1.0, stage#modeT / 0.1),
                  air = 1.0, tuck = 0.0, squash = 0.0, breath = 0.0 }
            case Mode.JumpMode =>
                // 上昇: 羽をたたんでしずく形の弾になる（空中の変形・その 1）。
                { alt = 8.5, pitch = 0.15, air = 1.0,
                  tuck = Float64.min(1.0, stage#modeT / 0.12), squash = 0.0, breath = 0.0 }
            case Mode.FallMode =>
                // 落下: 羽を傘のように全開にしてゆっくり羽ばたく（空中の変形・その 2）。
                { alt = 9.5, pitch = 0.0, air = 1.0, tuck = 0.0, squash = 0.0, breath = 0.0 }
            case Mode.LandMode =>
                // 着地: 腹からべちゃりと潰れ、羽が反動でバサッと開く。
                let squash = 1.0 - Float64.min(1.0, stage#modeT / 0.2);
                { alt = 5.0, pitch = 0.0, air = 0.0, tuck = 0.0, squash = squash, breath = 0.0 }
        }

    /// 舞台状態から 1 コマ分の描画列を導く（閉形式・状態なし）。
    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        let flight = flightOf(stage);
        let face = stage#facing;
        let bodyCx = stage#pos#x;
        let bodyCy = stage#pos#y - flight#alt;
        // 前傾の剪断: 前(ox>0)ほど沈み、のけぞりでは前が浮く。回転の代わりの安い傾き。
        let seat = (ox: Float64, oy: Float64) ->
            { x = bodyCx + face * ox, y = bodyCy + oy + flight#pitch * ox * 0.45 };
        // 腹: 潰れで平たく、しずく形で縦長になる。
        let abdomenW = 9.5 * (1.0 + 0.35 * flight#squash) * (1.0 - 0.25 * flight#tuck);
        let abdomenH = 7.5 * (1.0 - 0.4 * flight#squash) * (1.0 + 0.45 * flight#tuck)
                       * (1.0 + 0.08 * flight#breath * Curve.tri(1.8, stage#t));
        let abdomen = seat(-3.0, 1.0);
        let lantern = seat(-5.5, 2.8);
        let pulse = match stage#mode {
            case Mode.DashMode => 0.5 + 0.5 * Curve.tri(0.5, stage#t)
            case _             => 0.5 + 0.5 * Curve.tri(1.6, stage#t)
        };
        List.flatten(
            dashTrail(stage, flight)
            // 提灯の光暈: ゆっくり明滅する呼吸の光（ダッシュ中は速く脈打つ）。
            :: ({ at = { x = lantern#x - (4.5 + 1.5 * pulse), y = lantern#y - (4.5 + 1.5 * pulse) },
                  item = Render.circle(4.5 + 1.5 * pulse, glowColor(), 9)
                     |> Render.fade(RenderUtil.f32(0.16 + 0.24 * pulse)) } :: Nil)
            :: legItems(stage, flight, seat, false)
            :: farWing(stage, seat)
            :: ({ at = { x = abdomen#x - abdomenW / 2.0, y = abdomen#y - abdomenH / 2.0 },
                  item = Render.box({ x = abdomenW, y = abdomenH }, abdomenColor(), 10)
                     |> Render.rounded(3.5) } :: Nil)
            :: ({ at = { x = lantern#x - 2.5, y = lantern#y - 1.5 },
                  item = Render.box({ x = 5.0, y = 3.0 }, glowColor(), 11) |> Render.rounded(1.5) } :: Nil)
            :: elytraItems(flight, seat)
            :: ({ at = { x = seat(1.0, -1.5)#x - 3.0, y = seat(1.0, -1.5)#y - 3.0 },
                  item = Render.circle(3.0, collarColor(), 11) } :: Nil)
            :: legItems(stage, flight, seat, true)
            :: headItems(stage, flight, seat)
            :: nearWing(stage, flight, seat)
            :: Nil)

    // ── 頭と触角 ──

    /// 頭・複眼・触角 2 本。触角は待機でゆらゆら、しずく形では後ろへなびく。
    def headItems(stage: CharStage.Stage, flight: Flight,
                  seat: (Float64, Float64) -> Vec2.Vec2): List[Render.Placed] =
        let face = stage#facing;
        let head = seat(4.2, -1.0);
        let sway = 0.8 * Curve.triWave(stage#t * 0.6);
        let sway2 = 0.8 * Curve.triWave(stage#t * 0.6 + 0.3);
        // しずく形では触角の先を後ろへ流す。
        let tipA = blendV(seat(7.6, -5.2 + sway), seat(1.8, -6.0), flight#tuck);
        let tipB = blendV(seat(8.4, -3.6 + sway2), seat(2.6, -5.0), flight#tuck);
        { at = { x = head#x - 2.4, y = head#y - 2.4 }, item = Render.circle(2.4, darkColor(), 12) }
        :: rod(seat(5.0, -2.6), tipA, 0.6, darkColor(), 12)
        :: rod(seat(5.4, -1.8), tipB, 0.6, darkColor(), 12)
        :: { at = { x = head#x + face * 1.0 - 1.0, y = head#y - 0.6 - 1.0 },
             item = Render.circle(1.0, eyeWhite(), 13) }
        :: { at = { x = head#x + face * 1.4 - 0.5, y = head#y - 0.6 - 0.5 },
             item = Render.circle(0.5, eyeDark(), 13) }
        :: Nil

    // ── 鞘翅（羽の覆い）: 飛ぶと持ち上がって開く ──

    /// 腹の上に被さる硬い羽覆い。飛行中は付け根から持ち上がる。
    def elytraItems(flight: Flight,
                    seat: (Float64, Float64) -> Vec2.Vec2): List[Render.Placed] =
        let lift = -1.8 * flight#air - 1.2 * flight#squash;
        let anchor = seat(2.5, -2.0);
        let a = seat(0.5, -3.6 + lift);
        let b = seat(-6.5, -2.6 + lift * 1.4);
        let c = seat(-7.5, -0.2 + lift * 0.8);
        let d = seat(-3.0, 0.6);
        { at = { x = anchor#x, y = anchor#y },
          item = Render.polygon({ x = 0.0, y = 0.0 }
                         :: { x = a#x - anchor#x, y = a#y - anchor#y }
                         :: { x = b#x - anchor#x, y = b#y - anchor#y }
                         :: { x = c#x - anchor#x, y = c#y - anchor#y }
                         :: { x = d#x - anchor#x, y = d#y - anchor#y } :: Nil,
                         elytraColor(), 11) } :: Nil

    // ── 羽（半透明のブレ・区分ごとに形を変える）──

    /// 手前の羽。走りは高速ブレ 2 枚重ね、スキッドは前へ突き出す空気ブレーキ、
    /// 落下は傘のようにゆっくり、上昇はたたんで消える、着地は反動でバサッと開く。
    def nearWing(stage: CharStage.Stage, flight: Flight,
                 seat: (Float64, Float64) -> Vec2.Vec2): List[Render.Placed] =
        let shoulder = seat(0.0, -3.0);
        match stage#mode {
            case Mode.JumpMode => Nil
            case Mode.SkidMode =>
                let dig = Float64.min(1.0, stage#modeT / 0.1);
                wingPoly(shoulder, stage#facing,
                         (5.5 * dig, -6.0) :: (8.5 * dig, -2.5) :: (3.0, 0.5) :: Nil, 0.55f32, 12)
            case Mode.FallMode =>
                let slowFlap = 1.8 * Curve.triWave(stage#t * 7.0);
                wingPoly(shoulder, stage#facing,
                         (-5.0, -5.5 + slowFlap) :: (-8.5, -3.0 + slowFlap) :: (-3.5, 0.8) :: Nil,
                         0.5f32, 12)
            case Mode.LandMode =>
                let pop = 0.4 + 0.6 * flight#squash;
                wingPoly(shoulder, stage#facing,
                         (-2.5 * pop, -5.5 * pop) :: (-5.0 * pop, -3.5 * pop) :: (-1.5, 0.0) :: Nil,
                         0.5f32, 12)
            case Mode.IdleMode => Nil
            case _ =>
                // 走り・ダッシュ: 三角波の羽ばたきと、半位相ずらした残像の 2 枚でブレを描く。
                let flap = 2.8 * Curve.triWave(stage#t * 16.0);
                let ghost = 2.8 * Curve.triWave(stage#t * 16.0 + 0.5);
                List.append(
                    wingPoly(shoulder, stage#facing,
                             (-3.5, -6.5 + flap) :: (-7.0, -4.0 + flap * 0.6) :: (-2.5, -0.5) :: Nil,
                             0.45f32, 12),
                    wingPoly(shoulder, stage#facing,
                             (-3.5, -6.5 + ghost) :: (-7.0, -4.0 + ghost * 0.6) :: (-2.5, -0.5) :: Nil,
                             0.15f32, 12))
        }

    /// 奥の羽。手前より小さく薄く、半拍ずれて羽ばたく。
    def farWing(stage: CharStage.Stage,
                seat: (Float64, Float64) -> Vec2.Vec2): List[Render.Placed] =
        let shoulder = seat(0.8, -2.6);
        match stage#mode {
            case Mode.JumpMode => Nil
            case Mode.IdleMode => Nil
            case Mode.FallMode =>
                let slowFlap = 1.8 * Curve.triWave(stage#t * 7.0 + 0.4);
                wingPoly(shoulder, stage#facing,
                         (4.5, -5.0 + slowFlap) :: (8.0, -2.5 + slowFlap) :: (3.0, 0.8) :: Nil,
                         0.3f32, 9)
            case Mode.SkidMode =>
                let dig = Float64.min(1.0, stage#modeT / 0.1);
                wingPoly(shoulder, stage#facing,
                         (4.0 * dig, -5.5) :: (6.5 * dig, -2.0) :: (2.0, 0.5) :: Nil, 0.3f32, 9)
            case _ =>
                let flap = 2.8 * Curve.triWave(stage#t * 16.0 + 0.5);
                wingPoly(shoulder, stage#facing,
                         (-2.5, -5.5 + flap) :: (-5.5, -3.2 + flap * 0.6) :: (-1.8, -0.4) :: Nil,
                         0.3f32, 9)
        }

    /// 羽 1 枚: 肩を原点に相対頂点（x は向きで反転）で張る半透明の三角形。
    def wingPoly(shoulder: Vec2.Vec2, face: Float64, tips: List[(Float64, Float64)],
                 alpha: Float32, layer: Int32): List[Render.Placed] =
        { at = { x = shoulder#x, y = shoulder#y },
          item = Render.polygon({ x = 0.0, y = 0.0 }
                         :: (tips |> List.map(tip -> { let (tx, ty) = tip; { x = face * tx, y = ty } })),
                         wingColor(), layer)
             |> Render.fade(alpha) } :: Nil

    // ── 六肢（見えるのは近側 3 本 + 奥側 2 本）──

    /// 脚。地上は踏ん張って立ち、飛行中は後ろへぶら下がり、しずく形では畳む。
    def legItems(stage: CharStage.Stage, flight: Flight,
                 seat: (Float64, Float64) -> Vec2.Vec2, near: Bool): List[Render.Placed] =
        let face = stage#facing;
        let dragK = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        let color = darkColor();
        let layer = if (near) 11 else 9;
        let anchors = if (near) (3.0, 1.2) :: (1.0, 1.8) :: (-1.0, 2.2) :: Nil
                      else (2.0, 1.5) :: (0.0, 2.0) :: Nil;
        anchors |> List.map(a -> {
            let (ax, ay) = a;
            let hip = seat(ax, ay);
            let swing = 0.6 * Curve.triWave(stage#t * 4.5 + ax * 0.37);
            // 立ち: 足を外へ開いて接地（着地の潰れでさらに開く）。
            let standing = { x = stage#pos#x + face * ax * (2.0 + 1.3 * flight#squash),
                             y = stage#pos#y };
            // 飛行: 進行方向と逆へ引きずられてぶら下がる。
            let dangling = { x = hip#x - face * (1.8 + 2.2 * dragK) + swing, y = hip#y + 3.8 };
            let folded = { x = hip#x + face * 0.3, y = hip#y + 1.2 };
            let foot = blendV(blendV(standing, dangling, flight#air), folded, flight#tuck);
            rod(hip, foot, 0.7, color, layer)
        })

    // ── ダッシュ演出: 提灯が曳く光の残跡（体色は変えない）──

    /// 少し前の浮き位置をなぞる光の点列。後ろほど小さく薄い。
    def dashTrail(stage: CharStage.Stage, flight: Flight): List[Render.Placed] =
        match stage#mode {
            case Mode.DashMode =>
                let face = stage#facing;
                let ramp = Float64.min(1.0, stage#modeT / 0.2);
                List.range(0, 6) |> List.map(k -> {
                    let fk = Int32.toFloat64(k);
                    let backX = stage#pos#x - face * (6.0 + 6.0 * fk);
                    // その位置を通ったときの浮きの揺れを再現して、軌跡が波を描く。
                    let backY = stage#pos#y - flight#alt + 2.8
                                + 1.6 * Curve.triWave(backX * 0.07);
                    let radius = 2.4 - 0.22 * fk;
                    { at = { x = backX - radius, y = backY - radius },
                      item = Render.circle(radius, glowColor(), 8)
                         |> Render.fade(RenderUtil.f32(0.5 * (1.0 - fk / 6.0) * ramp)) }
                })
            case _ => Nil
        }

    // ── 小さな数学（このキャラ専用）──

    /// 細い節: 2 点を幅 width で結ぶ（脚・触角）。
    def rod(a: Vec2.Vec2, b: Vec2.Vec2, width: Float64, color: Color, layer: Int32): Render.Placed =
        let dx = b#x - a#x;
        let dy = b#y - a#y;
        let len = Float64.max(0.001, Vec2.sqrt(dx * dx + dy * dy));
        let half = width * 0.5;
        { at = { x = a#x, y = a#y },
          item = Render.polygon({ x = -dy / len * half, y = dx / len * half }
                         :: { x = dx - dy / len * half, y = dy + dx / len * half }
                         :: { x = dx + dy / len * half, y = dy - dx / len * half }
                         :: { x = dy / len * half, y = -dx / len * half } :: Nil,
                         color, layer) }

    /// 位置の線形補間（k は 0..1）。
    def blendV(a: Vec2.Vec2, b: Vec2.Vec2, k: Float64): Vec2.Vec2 =
        { x = a#x + (b#x - a#x) * k, y = a#y + (b#y - a#y) * k }
}
