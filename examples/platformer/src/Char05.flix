// 蒸気ゴーレム（05 STEAM-GOLEM）— ボイラー胴体・伸縮ピストン脚・単眼スリットの重量級機械人形。
// 歩きは脚の伸縮ストンプ、空中は脚を格納して炉心をさらし、減速は前脚アンカー + 接地火花で踏ん張る。

mod Char05 {

    /// キャラ選択に出す ASCII ラベル（14 文字以内）。
    pub def name(): String = "05 STEAM-GOLEM"

    // ── 色（DB32 の直値。採用されたら Palette へ昇格する）──

    def steelBody(): Color    = {r = 0.411765f32, g = 0.415686f32, b = 0.415686f32}  // #696a6a
    def steelDark(): Color    = {r = 0.349020f32, g = 0.337255f32, b = 0.321569f32}  // #595652
    def pistonSilver(): Color = {r = 0.607843f32, g = 0.678431f32, b = 0.717647f32}  // #9badb7
    def hatchNavy(): Color    = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    def eyeAmber(): Color     = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
    def flameOrange(): Color  = {r = 0.874510f32, g = 0.443137f32, b = 0.149020f32}  // #df7126
    def steamWhite(): Color   = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    def coreCyan(): Color     = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32}  // #5fcde4

    // ── 小さな数式 ──

    /// 0..1 に収める。
    def clamp01(x: Float64): Float64 = Float64.max(0.0, Float64.min(1.0, x))

    /// 小数部（蒸気ひと吹きのような繰り返し演出のサイクル位置に使う）。
    def cycleAt(x: Float64): Float64 = x - Float64.floor(x)

    // ── 本体: 状態区分ごとにポーズを選ぶ ──

    /// 演技の状態区分からポーズを組み立てる。ダッシュは走りの体にバーナー炎と火花を重ねる。
    pub def draw(stage: CharStage.Stage): List[Render.PlacedItem] =
        match stage#mode {
            case CharStage.Mode.IdleMode => idlePose(stage)
            case CharStage.Mode.RunMode  => stompPose(stage)
            case CharStage.Mode.DashMode =>
                List.flatten(stompPose(stage) :: burnerFlames(stage) :: dashSparks(stage) :: Nil)
            case CharStage.Mode.SkidMode => anchorPose(stage)
            case CharStage.Mode.JumpMode => tuckPose(stage)
            case CharStage.Mode.FallMode => gearDownPose(stage)
            case CharStage.Mode.LandMode => slamPose(stage)
        }

    // ── 体のパーツ ──

    /// 胴体まわりの置き方。bottom = 胴体下端の y / lean = 前後ずらし（facing 符号込みの px）/
    /// size = 胴体の幅と高さ（スカッシュ用）/ eyeGlow = 単眼スリットの明るさ。
    type alias HullSpec = { bottom = Float64, lean = Float64, size = Vec2.Vec2, eyeGlow = Float32 }

    /// 胴体 + 頭 + 単眼スリット + リベット 2 個。lean は頭ほど大きく効かせて前後の傾きを出す。
    def hull(centerX: Float64, facing: Float64, spec: HullSpec): List[Render.PlacedItem] =
        let torsoX = centerX + spec#lean * 0.4;
        let headX = centerX + spec#lean;
        let torsoTop = spec#bottom - spec#size#y;
        let headTop = torsoTop - 6.0;
        { at = {x = torsoX - spec#size#x / 2.0, y = torsoTop},
          item = Render.box(spec#size, steelBody(), 10) |> Render.rounded(1.5) } ::
        { at = {x = headX - 4.0, y = headTop},
          item = Render.box({x = 8.0, y = 6.0}, steelDark(), 11) |> Render.rounded(1.0) } ::
        { at = {x = headX - 2.5 + facing * 1.5, y = headTop + 2.0},
          item = Render.box({x = 5.0, y = 2.0}, eyeAmber(), 12) |> Render.fade(spec#eyeGlow) } ::
        { at = {x = torsoX - spec#size#x / 2.0 + 1.5, y = torsoTop + 2.0},
          item = Render.box({x = 1.0, y = 1.0}, pistonSilver(), 11) } ::
        { at = {x = torsoX + spec#size#x / 2.0 - 2.5, y = torsoTop + 2.0},
          item = Render.box({x = 1.0, y = 1.0}, pistonSilver(), 11) } :: Nil

    /// ピストン脚 1 本の置き方。footX = 足の中心 x / baseY = 足の基準面（接地時は 0・空中は pos の y）/
    /// footLift = 足の持ち上げ量 / hullBottom = 胴体下端の y。
    type alias LegSpec = { footX = Float64, baseY = Float64, footLift = Float64, hullBottom = Float64 }

    /// ピストン脚 1 本 = 付け根スリーブ + 伸縮ロッド + 足パッド。ロッドの長さが歩きの伸縮そのもの。
    def pistonLeg(spec: LegSpec): List[Render.PlacedItem] =
        let rodTop = spec#hullBottom + 4.0;
        let padTop = spec#baseY - spec#footLift - 2.0;
        { at = {x = spec#footX - 2.0, y = spec#hullBottom},
          item = Render.box({x = 4.0, y = 4.0}, steelDark(), 9) } ::
        { at = {x = spec#footX - 1.0, y = rodTop},
          item = Render.box({x = 2.0, y = Float64.max(1.0, padTop - rodTop)}, pistonSilver(), 9) } ::
        { at = {x = spec#footX - 3.0, y = padTop},
          item = Render.box({x = 6.0, y = 2.0}, steelDark(), 10) } :: Nil

    // ── ポーズ ──

    /// 走り = ピストンのストンプ。歩調は移動距離から取る（足が滑らない）。胴体は倍周期で弾み、
    /// 前後の脚が半周期ずれて交互に持ち上がる。
    def stompPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let gait = stage#pos#x * 0.14;
        let hullBottom = stage#pos#y - 13.0 + Curve.triWave(gait * 2.0);
        let liftFront = Float64.max(0.0, Curve.triWave(gait)) * 3.0;
        let liftBack = Float64.max(0.0, Curve.triWave(gait + 0.5)) * 3.0;
        List.flatten(
            hull(stage#pos#x, stage#facing,
                 {bottom = hullBottom, lean = stage#facing * 2.0, size = {x = 14.0, y = 10.0}, eyeGlow = 1.0f32}) ::
            pistonLeg({footX = stage#pos#x + 4.0, baseY = stage#pos#y, footLift = liftFront, hullBottom = hullBottom}) ::
            pistonLeg({footX = stage#pos#x - 4.0, baseY = stage#pos#y, footLift = liftBack, hullBottom = hullBottom}) :: Nil)

    /// ダッシュの演出その 1: 背面ブースターの排気炎（上下 2 本）。長さは vx の帯（160→280）で
    /// 伸び、先端は別位相で揺らめく。体の色は変えない — 火が速さの信号。
    def burnerFlames(stage: CharStage.Stage): List[Render.PlacedItem] =
        let band = clamp01((Float64.abs(stage#vx) - 160.0) / 120.0);
        let hullBottom = stage#pos#y - 13.0 + Curve.triWave(stage#pos#x * 0.14 * 2.0);
        let backX = stage#pos#x - 7.0 * stage#facing;
        List.flatMap(ventY -> flameAt(stage, band, backX, ventY),
                     (hullBottom - 7.5) :: (hullBottom - 3.0) :: Nil)

    /// 排気炎 1 本 = 橙の外炎 + 琥珀の芯。ventY を位相に混ぜて 2 本が同じ揺れにならないようにする。
    def flameAt(stage: CharStage.Stage, band: Float64, backX: Float64, ventY: Float64): List[Render.PlacedItem] =
        let len = 6.0 + 9.0 * band + 1.5 * Curve.triWave(stage#t * 13.0 + ventY * 0.2);
        let tipY = 0.9 * Curve.triWave(stage#t * 9.0 + ventY);
        { at = {x = backX, y = ventY},
          item = Render.polygon({x = 0.0, y = -1.6} :: {x = 0.0, y = 1.6} ::
                         {x = 0.0 - len * stage#facing, y = tipY} :: Nil, flameOrange(), 9) } ::
        { at = {x = backX, y = ventY},
          item = Render.polygon({x = 0.0, y = -0.9} :: {x = 0.0, y = 0.9} ::
                         {x = 0.0 - len * 0.55 * stage#facing, y = tipY * 0.6} :: Nil, eyeAmber(), 9) } :: Nil

    /// ダッシュの演出その 2: 足元から後ろへ散る接地火花。速度帯が高いほど濃く見える。
    def dashSparks(stage: CharStage.Stage): List[Render.PlacedItem] =
        let band = clamp01((Float64.abs(stage#vx) - 160.0) / 120.0);
        List.map(i -> {
            let seed = Int32.toFloat64(i);
            let jitter = Curve.triWave(stage#t * (17.0 + 4.0 * seed) + 0.31 * seed);
            { at = {x = stage#pos#x - (5.0 + 4.0 * seed + 3.0 * jitter) * stage#facing,
                    y = stage#pos#y - 1.0 - 1.5 * Float64.abs(jitter)},
              item = Render.box({x = 1.5, y = 1.5}, eyeAmber(), 12) |> Render.fade(RenderUtil.f32(band)) }
        }, List.range(0, 3))

    /// スキッド = 前脚アンカー。胴体を深くのけぞらせ、斜め前に突き出したストラットで地面を掴む。
    /// 接地点から火花が散り、肩の弁から制動蒸気がひと吹き。勢い（|vx|）が抜けるほど演出も薄まる。
    def anchorPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let facing = stage#facing;
        let heat = clamp01(Float64.abs(stage#vx) / 200.0);
        let strut =
            { at = {x = stage#pos#x, y = 0.0},
              item = Render.polygon({x = 1.0 * facing, y = -9.0} :: {x = 4.0 * facing, y = -9.0} ::
                             {x = 8.0 * facing, y = -1.0} :: {x = 5.0 * facing, y = -1.0} :: Nil,
                             pistonSilver(), 9) } ::
            { at = {x = stage#pos#x + 6.0 * facing - 3.0, y = -2.0},
              item = Render.box({x = 6.0, y = 2.0}, steelDark(), 10) } :: Nil;
        let sparks = List.map(i -> {
            let seed = Int32.toFloat64(i);
            let jitter = Curve.triWave(stage#t * (15.0 + 3.0 * seed) + 0.27 * seed);
            { at = {x = stage#pos#x + (8.0 + 3.0 * jitter) * facing, y = -1.5 - 2.0 * Float64.abs(jitter)},
              item = Render.box({x = 1.5, y = 1.5}, if (i == 1) flameOrange() else eyeAmber(), 12)
              |> Render.fade(RenderUtil.f32(heat)) }
        }, List.range(0, 3));
        let brakeSteam =
            { at = {x = stage#pos#x - 9.0 * facing - 2.0, y = -20.0},
              item = Render.circle(2.0, steamWhite(), 12) |> Render.fade(RenderUtil.f32(heat * 0.5)) };
        List.flatten(
            hull(stage#pos#x, facing,
                 {bottom = -10.0, lean = 0.0 - 5.0 * facing, size = {x = 14.0, y = 10.0}, eyeGlow = 1.0f32}) ::
            pistonLeg({footX = stage#pos#x - 2.0 * facing, baseY = 0.0, footLift = 0.0, hullBottom = -10.0}) ::
            strut :: sparks :: (brakeSteam :: Nil) :: Nil)

    /// 上昇 = 脚の格納。全ピストンを胴へ引き込んでコンパクトな箱形態になり、
    /// 開いたハッチから青い炉心が覗いて明滅する。
    def tuckPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let baseY = stage#pos#y;
        let coreFlick = 0.6 * Curve.triWave(stage#t * 10.0);
        { at = {x = stage#pos#x - 6.0, y = baseY - 12.0},
          item = Render.box({x = 12.0, y = 9.0}, steelBody(), 10) |> Render.rounded(2.0) } ::
        { at = {x = stage#pos#x - 4.5, y = baseY - 2.5}, item = Render.box({x = 4.0, y = 2.0}, steelDark(), 9) } ::
        { at = {x = stage#pos#x + 0.5, y = baseY - 2.5}, item = Render.box({x = 4.0, y = 2.0}, steelDark(), 9) } ::
        { at = {x = stage#pos#x - 3.0, y = baseY - 11.0}, item = Render.box({x = 6.0, y = 6.0}, hatchNavy(), 11) } ::
        { at = {x = stage#pos#x - 4.0, y = baseY - 17.0},
          item = Render.box({x = 8.0, y = 5.0}, steelDark(), 11) |> Render.rounded(1.0) } ::
        { at = {x = stage#pos#x - 2.5 + stage#facing * 1.5, y = baseY - 15.5},
          item = Render.box({x = 5.0, y = 2.0}, eyeAmber(), 12) } ::
        { at = {x = stage#pos#x - 2.2, y = baseY - 10.2}, item = Render.circle(2.2, coreCyan(), 12) } ::
        { at = {x = stage#pos#x - (4.0 + coreFlick), y = baseY - 12.0 - coreFlick},
          item = Render.circle(4.0 + coreFlick, coreCyan(), 11) |> Render.fade(0.3f32) } :: Nil

    /// 落下 = 着陸脚の展開。胴を高く保ってロッドを全伸ばしし、足を左右に開いて接地に備える。
    def gearDownPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let hullBottom = stage#pos#y - 14.0;
        List.flatten(
            hull(stage#pos#x, stage#facing,
                 {bottom = hullBottom, lean = 0.0, size = {x = 14.0, y = 10.0}, eyeGlow = 1.0f32}) ::
            pistonLeg({footX = stage#pos#x + 5.0, baseY = stage#pos#y, footLift = 0.0, hullBottom = hullBottom}) ::
            pistonLeg({footX = stage#pos#x - 5.0, baseY = stage#pos#y, footLift = 0.0, hullBottom = hullBottom}) :: Nil)

    /// 着地 = 全圧縮スラム。胴が横に潰れ、肩の弁から蒸気が左右へ抜け、地面に衝撃線が走る。
    def slamPose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let progress = clamp01(stage#modeT / 0.2);
        let ease = 1.0 - progress;
        let jetR = 2.0 + 1.5 * progress;
        let jets = List.map(side ->
            { at = {x = stage#pos#x + side * (9.0 + 6.0 * progress) - jetR, y = -6.0 - jetR},
              item = Render.circle(jetR, steamWhite(), 12) |> Render.fade(RenderUtil.f32(ease * 0.7)) },
            -1.0 :: 1.0 :: Nil);
        let shock =
            { at = {x = stage#pos#x - (10.0 + 5.0 * progress), y = -1.5},
              item = Render.box({x = 20.0 + 10.0 * progress, y = 1.5}, steamWhite(), 8)
              |> Render.rounded(0.75) |> Render.fade(RenderUtil.f32(ease * 0.5)) };
        List.flatten(
            hull(stage#pos#x, stage#facing,
                 {bottom = -9.0, lean = 0.0, size = {x = 18.0, y = 7.0}, eyeGlow = 0.8f32}) ::
            pistonLeg({footX = stage#pos#x + 5.0, baseY = 0.0, footLift = 0.0, hullBottom = -9.0}) ::
            pistonLeg({footX = stage#pos#x - 5.0, baseY = 0.0, footLift = 0.0, hullBottom = -9.0}) ::
            jets :: (shock :: Nil) :: Nil)

    /// 待機 = ボイラーの呼吸。胴がゆっくり上下し、肩の弁から蒸気がひと吹きずつ立ちのぼり、
    /// 単眼がとろとろ明滅する。
    def idlePose(stage: CharStage.Stage): List[Render.PlacedItem] =
        let hullBottom = -13.0 + 0.6 * Curve.triWave(stage#t * 0.7);
        let glow = RenderUtil.f32(0.7 + 0.3 * Curve.tri(1.6, stage#t));
        let puffCycle = cycleAt(stage#modeT / 1.1);
        let puffR = 1.5 + 2.0 * puffCycle;
        let puff =
            { at = {x = stage#pos#x - 5.0 * stage#facing - puffR,
                    y = hullBottom - 12.0 - 7.0 * puffCycle - puffR},
              item = Render.circle(puffR, steamWhite(), 12)
              |> Render.fade(RenderUtil.f32((1.0 - puffCycle) * 0.55)) };
        List.flatten(
            hull(stage#pos#x, stage#facing,
                 {bottom = hullBottom, lean = 0.0, size = {x = 14.0, y = 10.0}, eyeGlow = glow}) ::
            pistonLeg({footX = stage#pos#x + 4.0, baseY = 0.0, footLift = 0.0, hullBottom = hullBottom}) ::
            pistonLeg({footX = stage#pos#x - 4.0, baseY = 0.0, footLift = 0.0, hullBottom = hullBottom}) ::
            (puff :: Nil) :: Nil)
}
