// カドリン — 五角形の結晶がそのまま生きている幾何生命体。足は無く、角を順に
// 地面へ倒して転がって進む（回転角は移動距離から閉形式で決まる＝滑らない）。
// 跳べば上へ尖った欠片に絞られ、落下では 8 枚刃の星に開いて回り、着地で潰れて
// 元の五角形へ戻る。中心の核（目）だけは何があっても水平を保つ。

mod Char09 {

    // ── 色（DB32・体色は全モードで不変。ダッシュの合図は周回する光の欠片）──

    def bodyCrys(): Color = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    def chipLight(): Color = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32} // #cbdbfc
    def nucleusInk(): Color = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32} // #222034
    def glintWhite(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32} // #ffffff

    /// キャラ選択ギャラリーに出す ASCII ラベル。
    pub def name(): String = "09 KADORIN"

    /// 外接円の半径（体の基本サイズ）。
    def bodyR(): Float64 = 11.0

    /// 内接円の半径（辺が接地しているときの中心高さ）= R × cos(36°)。
    def apothem(): Float64 = 8.899187

    /// 転がりの回転角。移動距離 ÷ 半径（滑らずに転がる条件そのもの）。
    def rollAngle(stage: CharStage.Stage): Float64 =
        stage#pos#x / bodyR()

    /// 接地中の中心高さ。辺で立つと低く（内接円）、角で立つと高く（外接円）なり、
    /// 転がるたびに 1 辺ぶんの周期でゴトゴトと上下する。
    def groundCenterY(theta: Float64): Float64 =
        -(apothem() + (bodyR() - apothem()) * Float64.abs(Vec2.cos(2.5 * theta)))

    /// 舞台状態から 1 コマ分の描画リストを組む（体はモードごとに頂点列そのものを変える）。
    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        match stage#mode {
            case CharStage.Mode.IdleMode => idleBody(stage)
            case CharStage.Mode.RunMode  => rollBody(stage)
            case CharStage.Mode.DashMode => List.append(satellites(stage), rollBody(stage))
            case CharStage.Mode.SkidMode => skidBody(stage)
            case CharStage.Mode.JumpMode => shardBody(stage)
            case CharStage.Mode.FallMode => sawBody(stage)
            case CharStage.Mode.LandMode => crashBody(stage)
        }

    // ── 頂点列の組み立て ──

    /// 五角形の頂点列（回転 rot・頂点 0 は真上基準）。spike を上げると頂点 0 が伸びて
    /// 他が締まり、五角形のまま連続に「上へ尖った欠片」へ変形する。sx/sy は縦横の伸縮。
    def pentaVerts(rot: Float64, spike: Float64, sx: Float64, sy: Float64): List[Vec2.Vec2] =
        List.range(0, 5) |> List.map(k ->
            let a = -1.57079633 + rot + Int32.toFloat64(k) * 1.25663706;
            let rr = if (k == 0) bodyR() * (1.0 + 0.7 * spike)
                     else if (k == 2 or k == 3) bodyR() * (1.0 - 0.25 * spike)
                     else bodyR() * (1.0 - 0.4 * spike);
            {x = rr * Vec2.cos(a) * sx, y = rr * Vec2.sin(a) * sy})

    /// 落下形態: 外径と内径を交互に並べた 8 枚刃の星（縦をやや潰した円盤）。
    def starVerts(rot: Float64): List[Vec2.Vec2] =
        List.range(0, 16) |> List.map(k ->
            let a = rot + Int32.toFloat64(k) * 0.39269908;
            let rr = if (Int32.modulo(k, 2) == 0) bodyR() else 5.0;
            {x = rr * Vec2.cos(a), y = rr * Vec2.sin(a) * 0.85})

    /// 破片・衛星用の小さな正三角形。
    def triVerts(rot: Float64, r: Float64): List[Vec2.Vec2] =
        List.range(0, 3) |> List.map(k ->
            let a = rot + Int32.toFloat64(k) * 2.09439510;
            {x = r * Vec2.cos(a), y = r * Vec2.sin(a)})

    /// 中心の核（目）。体がどれだけ回っても傾かず、視線だけ進行方向へ寄る。
    def nucleus(cx: Float64, cy: Float64, facing: Float64): List[Render.Placed] =
        let nx = cx + facing * 1.5;
        List#{
            ({x = nx - 2.6, y = cy - 2.6}, Render.circle(2.6, nucleusInk(), 11)),
            ({x = nx - 1.8, y = cy - 1.8}, Render.circle(0.9, glintWhite(), 12) |> Render.fade(0.9f32))
        }

    // ── モードごとの体 ──

    /// 待機: その場でわずかに揺りかご運動しつつ、外周が呼吸で脈打つ。
    def idleBody(stage: CharStage.Stage): List[Render.Placed] =
        let rot = rollAngle(stage) + 0.13 * Curve.triWave(stage#modeT * 0.45);
        let pulse = 1.0 + 0.05 * Curve.triWave(stage#modeT * 0.8);
        let cy = groundCenterY(rollAngle(stage)) * pulse;
        ({x = stage#pos#x, y = cy}, Render.polygon(pentaVerts(rot, 0.0, pulse, pulse), bodyCrys(), 10))
            :: nucleus(stage#pos#x, cy, stage#facing)

    /// 走り・ダッシュ共通の転がる体。中心は辺と角の高低差でゴトゴト上下する。
    def rollBody(stage: CharStage.Stage): List[Render.Placed] =
        let rot = rollAngle(stage);
        let cy = groundCenterY(rot);
        ({x = stage#pos#x, y = cy}, Render.polygon(pentaVerts(rot, 0.0, 1.0, 1.0), bodyCrys(), 10))
            :: nucleus(stage#pos#x, cy, stage#facing)

    /// スキッド: 逆回転ぎみに角を立てて地面へ食い込み、残像 2 枚と研削の火花破片を散らす。
    def skidBody(stage: CharStage.Stage): List[Render.Placed] =
        let grip = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        let rot = rollAngle(stage) - stage#facing * 0.55 * grip;
        let cy = groundCenterY(rollAngle(stage));
        let core = ({x = stage#pos#x, y = cy}, Render.polygon(pentaVerts(rot, 0.0, 1.0, 1.0), bodyCrys(), 10));
        let ghosts = List.range(0, 2) |> List.map(g ->
            let fg = Int32.toFloat64(g);
            let scale = 0.92 - 0.1 * fg;
            ({x = stage#pos#x - stage#facing * (7.0 + 7.0 * fg), y = cy},
             Render.polygon(pentaVerts(rot + stage#facing * 0.35 * (fg + 1.0), 0.0, scale, scale), bodyCrys(), 8)
                 |> Render.fade(RenderUtil.f32((0.38 - 0.16 * fg) * grip))));
        List.flatten(List#{ghosts, core :: Nil, grindChips(stage, grip), nucleus(stage#pos#x, cy, stage#facing)})

    /// 上昇: 回転をほどいて真上へ整列しながら、頂点 0 が伸びる「欠片」へ絞られる。
    def shardBody(stage: CharStage.Stage): List[Render.Placed] =
        let e = Float64.min(1.0, stage#modeT * 4.5);
        let rot = rollAngle(stage) * (1.0 - e);
        let cy = stage#pos#y - bodyR();
        ({x = stage#pos#x, y = cy}, Render.polygon(pentaVerts(rot, e, 1.0 - 0.25 * e, 1.0), bodyCrys(), 10))
            :: nucleus(stage#pos#x, cy, stage#facing)

    /// 落下: 8 枚刃の星に開き、回転しながら落ちる（頂点数ごと切り替わる「割れ」の瞬間が頂点）。
    def sawBody(stage: CharStage.Stage): List[Render.Placed] =
        let spin = rollAngle(stage) + stage#modeT * 13.0;
        let cy = stage#pos#y - bodyR() - 0.5;
        ({x = stage#pos#x, y = cy}, Render.polygon(starVerts(spin), bodyCrys(), 10))
            :: nucleus(stage#pos#x, cy, stage#facing)

    /// 着地: 低い台形状に潰れ、左右へ破片が跳ねる。窓の終わりで元の五角形へ戻る。
    def crashBody(stage: CharStage.Stage): List[Render.Placed] =
        let squash = 1.0 - stage#modeT / 0.2;
        let cy = groundCenterY(rollAngle(stage)) * (1.0 - 0.45 * squash);
        let core = ({x = stage#pos#x, y = cy},
                    Render.polygon(pentaVerts(rollAngle(stage), 0.0, 1.0 + 0.08 * squash, 1.0 - 0.45 * squash), bodyCrys(), 10));
        List.flatten(List#{core :: Nil, popChips(stage), nucleus(stage#pos#x, cy, stage#facing)})

    // ── モード付随のエフェクト ──

    /// ダッシュの合図: 体の周りを楕円軌道で周回する光の欠片 3 枚。速いほど速く濃く回り、
    /// 手前を通るときは体の前、奥では体の後ろに描かれて立体感が出る。体色は変えない。
    def satellites(stage: CharStage.Stage): List[Render.Placed] =
        let band = Float64.min(1.0, Float64.max(0.0, (Float64.abs(stage#vx) - 160.0) / 120.0));
        if (band < 0.05) Nil
        else
            List.range(0, 3) |> List.map(s ->
                let a = stage#t * (5.0 + 8.0 * band) + Int32.toFloat64(s) * 2.09439510;
                let cx = stage#pos#x + 16.0 * Vec2.cos(a);
                let cyv = stage#pos#y - bodyR() + 9.0 * Vec2.sin(a);
                let layer = if (Vec2.sin(a) > 0.0) 12 else 8;
                ({x = cx, y = cyv},
                 Render.polygon(triVerts(a * 2.0, 2.8), chipLight(), layer)
                     |> Render.fade(RenderUtil.f32(0.85 * band))))

    /// スキッドの研削破片: 進行方向の足元へ低く跳ねる小さな三角形 3 枚。
    def grindChips(stage: CharStage.Stage, grip: Float64): List[Render.Placed] =
        let e = Float64.min(1.0, stage#modeT * 5.0);
        List.range(0, 3) |> List.map(c ->
            let fc = Int32.toFloat64(c);
            let hop = 4.0 * e * (1.0 - e);
            let cx = stage#pos#x + stage#facing * (6.0 + 3.0 * fc) * e;
            let cyv = -1.5 - (3.0 + 1.5 * fc) * hop;
            ({x = cx, y = cyv},
             Render.polygon(triVerts(e * 10.0 + fc, 1.6), chipLight(), 11)
                 |> Render.fade(RenderUtil.f32(Float64.max(0.0, (1.0 - e) * grip)))))

    /// 着地の破片: 左右へ弾け飛ぶ三角形。上がって落ちる小さな山なりで消える。
    def popChips(stage: CharStage.Stage): List[Render.Placed] =
        let q = stage#modeT / 0.2;
        let hop = 4.0 * q * (1.0 - q);
        List#{-1.0, 1.0} |> List.map(side ->
            let cx = stage#pos#x + side * (5.0 + 18.0 * stage#modeT);
            let cyv = -2.5 - 5.0 * hop;
            ({x = cx, y = cyv},
             Render.polygon(triVerts(q * 8.0 * side, 1.8), chipLight(), 12)
                 |> Render.fade(RenderUtil.f32(Float64.max(0.0, 1.0 - q)))))
}
