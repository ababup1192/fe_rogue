// View — Projection の番地: World から「描くべきものリスト」(Drawable) への投影。
// ここに状態は無い: 壁もパドルもボールもブロックも破片も、渡された World の純粋な関数である。
// いまの局面（world#phase）で場合分けし、盤（GameCore）を持つ局面はその盤を、タイトルは
// 文字だけを描く。盤の中で単独者（ballPos・paddle）は型つきフィールドを、群れ（壁・ブロック）は
// 店（positions / shapes）を読んでピクセルへ変換するだけで、書き換えはしない。ボールの残像は
// 飛行中（Moving）だけ在るので、その速度と残像リングから描く。色は Palette（DB32 のロール名）からのみ来る。
//
// ブロックの見た目は durabilities の店から導く: 店に居ない = 壊れない（金属の面シェーディング＋
// リベット）、耐久 2 = 明るい鋼、残り 1 のハード = くすんだ鋼、通常 = 行の色。
// カメラシェイクは trauma からの閉形式の導出（trauma² × Hash01 ノイズ）。ブロックのヒットで
// 積まれた trauma が盤面を数 px オフセットする（HUD と案内文は画面に固定され、揺れない）。
// 破片も同じく、破壊ごとの (種＋原点＋経過秒) から Fx.derive で導出する状態レス演出。

mod View {

    // ── 描画レイヤー（下から上へ）──
    def zWall(): Int32 = 0
    def zBlock(): Int32 = 5
    def zPaddle(): Int32 = 10
    def zTrail(): Int32 = 16
    def zBall(): Int32 = 18
    def zBurst(): Int32 = 20
    def zText(): Int32 = 100

    def tau(): Float64 = 6.283185307179586

    // ── frame: 局面を描画コマンドへ投影する ──
    // タイトルは文字だけ（盤・HUD を出さない）。盤を持つ局面は盤・ボール・HUD を描き、飛行中だけ
    // 残像を、サーブ待ち/クリア/ゲームオーバーはそれぞれの案内文を重ねる（case は網羅）。
    pub def frame(atlas: FontAtlas, world: Field.World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        match world#phase {
            case Field.Phase.Title =>
                (Render.draw(titleTexts(atlas)), Nil)
            case Field.Phase.Playing(core, Field.BallState.Waiting) =>
                boardFrame(atlas, world#params, core, Nil, Vec2.zero(), waitingOverlay(atlas))
            case Field.Phase.Playing(core, Field.BallState.Moving(mv)) =>
                boardFrame(atlas, world#params, core, mv#trail, mv#vel, Nil)
            case Field.Phase.Cleared(core) =>
                boardFrame(atlas, world#params, core, Nil, Vec2.zero(), clearedOverlay(atlas))
            case Field.Phase.GameOver(core) =>
                boardFrame(atlas, world#params, core, Nil, Vec2.zero(), gameOverOverlay(atlas))
        }

    /// 盤ひとそろいを描く（カメラシェイクで盤面をずらす）。trail と vel は飛行中だけ中身があり、
    /// 待機・クリア・ゲームオーバーでは空（残像は出ない）。overlay はその局面の案内文。
    /// シェイクは盤面（世界）の衝撃なので、HUD と案内文（画面に住む文字）は揺らさない。
    def boardFrame(atlas: FontAtlas, params: GameParameters.Params, core: Field.GameCore,
                   trail: List[Vec2.Vec2], vel: Vec2.Vec2, overlay: List[(Vec2.Vec2, Render.RenderItem)]):
                   (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let offset = shakeOffsetOf(core);
        let boardBoxes = List.flatten(
            wallBoxes(core) ::
            blockBoxes(core) ::
            paddleBoxes(core) ::
            trailBoxes(params, vel, trail) ::
            ballBoxes(core) :: Nil);
        let shiftedBoxes = List.map(entry -> { let (pos, item) = entry; (Vec2.add(pos, offset), item) }, boardBoxes);
        let screenBoxes = List.append(hudTexts(atlas, core), overlay);
        let shiftedPolys = List.map(poly -> shiftPoly(offset, poly), burstPolys(core));
        (Render.draw(List.append(shiftedBoxes, screenBoxes)), shiftedPolys)

    def shiftPoly(offset: Vec2.Vec2, poly: GameEngine.PolygonRenderCmd): GameEngine.PolygonRenderCmd =
        { vertices = List.map(v -> Vec2.add(v, offset), poly#vertices) | poly }

    // ── カメラシェイク（trauma からの閉形式の導出）──

    def shakeFreq(): Float64 = 45.0

    /// trauma からの揺れ幅（px）: trauma² × 最大オフセット。二乗なので単発の小さな trauma は
    /// ほとんど揺れず、連打で蓄積すると急に効く。純粋なので単体テストで具体値を固定できる。
    pub def shakeStrength(trauma: Float64): Float64 =
        if (trauma <= 0.0) 0.0
        else trauma * trauma * Field.maxShakeOffset()

    /// カメラシェイクのオフセット（px）。揺れ幅（shakeStrength）× フレームごとの Hash01 ノイズ [-1, 1]。
    /// ノイズの位相は常に進む通し時計 fxClock から刻む。trauma が 0 なら揺れない。
    pub def shakeOffsetOf(core: Field.GameCore): Vec2.Vec2 =
        let strength = shakeStrength(core#trauma);
        if (strength <= 0.0) { x = 0.0, y = 0.0 }
        else {
            let frame = Float64.floor(core#fxClock * shakeFreq()) |> Float64.tryToInt32 |> Option.getWithDefault(0);
            { x = strength * (2.0 * Hash01.at(frame, 0) - 1.0),
              y = strength * (2.0 * Hash01.at(frame, 1) - 1.0) }
        }

    // ── 壁 ──

    def wallBoxes(core: Field.GameCore): List[(Vec2.Vec2, Render.RenderItem)] =
        Field.wallIds() |> List.flatMap(id ->
            match (Map.get(id, core#positions), Map.get(id, core#shapes)) {
                case (Some(pos), Some(shape)) => rectItems(pos, shape, Palette.wallFace(), zWall())
                case _                        => Nil
            })

    // ── ブロック（見た目は durabilities の店から導く）──

    def blockBoxes(core: Field.GameCore): List[(Vec2.Vec2, Render.RenderItem)] =
        Map.toList(core#blocks) |> List.flatMap(entry -> {
            let (id, row) = entry;
            match (Map.get(id, core#positions), Map.get(id, core#shapes)) {
                case (Some(pos), Some(CollisionShape2D.RectShape2D(rect))) =>
                    blockItems(pos, { x = rect#width, y = rect#height }, row,
                               Map.get(id, core#durabilities))
                case _ => Nil
            }
        })

    /// ブロック 1 個の見た目。耐久の在・不在と値が絵を決める:
    /// 店に居ない = 壊れない金属 / 耐久 2 以上 = 明るい鋼 / 残り 1 のハード = くすんだ鋼 /
    /// 通常（1発）= 行の色。
    def blockItems(center: Vec2.Vec2, size: Vec2.Vec2, row: Int32,
                   durability: Option[Field.Durability]): List[(Vec2.Vec2, Render.RenderItem)] =
        match durability {
            case None    => metalItems(center, size)
            case Some(d) =>
                let color =
                    if (d#hp >= 2) Palette.hardFull()
                    else if (d#maxHp >= 2) Palette.hardChipped()
                    else Palette.blockRow(row);
                flatBox(center, size, color, zBlock()) :: Nil
        }

    /// 金属ブロックの面取り高さ（px）とリベットの寸法。
    def metalBevel(): Float64 = 2.0
    def rivetRadius(): Float64 = 1.2
    def rivetInsetX(): Float64 = 4.5
    def rivetInsetY(): Float64 = 3.5

    /// 壊れないブロック: 面シェーディング（上端=明・地=中・下端=影）＋四隅のリベット。
    /// 据え付けられた金属が「ここは崩れない」と一目で語る。
    def metalItems(center: Vec2.Vec2, size: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let bevel = metalBevel();
        let topLeft = { x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 };
        let rivets = List.map(corner -> {
            let (sx, sy) = corner;
            circleItem({ x = center#x + sx * (size#x / 2.0 - rivetInsetX()),
                         y = center#y + sy * (size#y / 2.0 - rivetInsetY()) },
                       rivetRadius() * 2.0, Palette.rivet(), zBlock() + 2)
        }, (-1.0, -1.0) :: (1.0, -1.0) :: (1.0, 1.0) :: (-1.0, 1.0) :: Nil);
        List.append(
            (topLeft, Render.solidBox(size, Palette.metalFace(), zBlock())) ::
            (topLeft, Render.solidBox({ x = size#x, y = bevel }, Palette.metalTop(), zBlock() + 1)) ::
            ({ x = topLeft#x, y = topLeft#y + size#y - bevel },
             Render.solidBox({ x = size#x, y = bevel }, Palette.metalShade(), zBlock() + 1)) :: Nil,
            rivets)

    // ── パドル（面シェーディング＋反射角ゾーンの帯）──
    // 立体の帯: 上端 1px ハイライト・中央 = 地・下端 1px 影、輪郭は丸端。
    // その中央帯に反射角ゾーンを塗る: 中央 = 明るい（真上へ返る）、両端 = アクセント色
    // （鋭角に飛ぶ）。見た目そのものが Bounce の角度規則の説明になる。

    /// 中央の明るいゾーンの半幅（px）。|offsetFraction| がおよそ 1/4 までの「安全地帯」。
    def paddleCenterZoneHalf(): Float64 = 5.0
    /// 両端のアクセントゾーンの幅（px）。ここで受けると鋭角＋追加加速。
    def paddleEdgeZoneWidth(): Float64 = 7.0

    def paddleBoxes(core: Field.GameCore): List[(Vec2.Vec2, Render.RenderItem)] =
        paddleItemsAt(Field.paddlePos(core#paddle#x))

    /// パドルの絵ひとそろい（中心座標指定）。ゲーム本編とギャラリーの扇形図が共有する。
    pub def paddleItemsAt(center: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        let halfW = Field.paddleHalfWidth();
        let halfH = Field.paddleHalfHeight();
        let width = halfW * 2.0;
        let height = halfH * 2.0;
        let topLeft = { x = center#x - halfW, y = center#y - halfH };
        // 面シェーディング: 影の板（全面）→ ハイライトの板（下 1px を残す）→ 地の板（上下 1px を残す）。
        // 上から見ると 上端=ハイライト・中央=地・下端=影 の帯になる。すべて丸端。
        let shadeBand =
            roundedBox(topLeft, { x = width, y = height }, Palette.paddleShadow(), zPaddle()) ::
            roundedBox(topLeft, { x = width, y = height - 1.0 }, Palette.paddleHighlight(), zPaddle() + 1) ::
            roundedBox({ x = topLeft#x, y = topLeft#y + 1.0 }, { x = width, y = height - 2.0 },
                       Palette.paddleBody(), zPaddle() + 2) :: Nil;
        // 反射角ゾーン: 中央帯（上下 1px の間）に、端のアクセントと中央の明るみを重ねる。
        let bandY = topLeft#y + 1.0;
        let bandH = height - 2.0;
        let zones =
            roundedBox({ x = topLeft#x, y = bandY }, { x = paddleEdgeZoneWidth(), y = bandH },
                       Palette.paddleEdge(), zPaddle() + 3) ::
            roundedBox({ x = topLeft#x + width - paddleEdgeZoneWidth(), y = bandY },
                       { x = paddleEdgeZoneWidth(), y = bandH }, Palette.paddleEdge(), zPaddle() + 3) ::
            roundedBox({ x = center#x - paddleCenterZoneHalf(), y = bandY },
                       { x = paddleCenterZoneHalf() * 2.0, y = bandH },
                       Palette.paddleHighlight(), zPaddle() + 3) :: Nil;
        List.append(shadeBand, zones)

    // ── ボール（単独者: 位置は core#ballPos、形は Field の定数）──

    def ballBoxes(core: Field.GameCore): List[(Vec2.Vec2, Render.RenderItem)] =
        circleItem(core#ballPos, Field.ballRadius() * 2.0, Palette.ball(), zBall()) :: Nil

    // ── ボールの残像（飛行中の速度と位置リングからの導出）──
    // 状態はリング（直近の位置列）だけ。各点の大きさと薄さは (age, 加速の道のり) の純関数で、
    // 色はいまの速さのランプ（冷→温→熱）: 尾の色を見れば、どれだけ加速しているかが分かる。

    /// 残像の先頭の点（最新）の直径。古い点ほどここから縮む。
    def trailHeadDiameter(): Float64 = 5.0
    /// 残像の末尾でどこまで縮むか（先頭に対する割合）。
    def trailTailScale(): Float64 = 0.25
    /// 残像全体の濃さ（先頭の点の alpha。古い点ほどさらに薄まる）。
    def trailBaseAlpha(): Float64 = 0.7

    /// 残像の点ひとつの見た目: age（0=最新 … 1=最古）で縮み・薄まり、色は加速ランプから。
    def trailDot(pos: Vec2.Vec2, age: Float64, ratio: Float64): (Vec2.Vec2, Render.RenderItem) =
        let diameter = trailHeadDiameter() * (1.0 - (1.0 - trailTailScale()) * age);
        let alpha = RenderUtil.f32(trailBaseAlpha() * (1.0 - age));
        let color = Palette.trailColor(ratio);
        let style = { cornerRadius = diameter / 2.0, borderWidth = 0.0, borderColor = color,
                      borderAlpha = 0.0f32, stripeColor = color, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({ x = pos#x - diameter / 2.0, y = pos#y - diameter / 2.0 },
         Render.RenderItem.Box({ size = { x = diameter, y = diameter }, color = color, alpha = alpha,
                                 style = Some(style), zIndex = zTrail() }))

    /// 飛行中のボールの残像。速度 vel は色ランプ（冷→温→熱）に、位置リング trail は点の並びになる。
    def trailBoxes(params: GameParameters.Params, vel: Vec2.Vec2,
                   trail: List[Vec2.Vec2]): List[(Vec2.Vec2, Render.RenderItem)] =
        let ratio = Bounce.speedRatioWith(params#maxSpeedFactor, Vec2.length(vel), Field.ballSpeed());
        let count = Int32.max(1, params#trailLength);
        List.zip(List.range(0, count), trail)
            |> List.map(pair -> {
                let (i, pos) = pair;
                trailDot(pos, Int32.toFloat64(i + 1) / Int32.toFloat64(count), ratio)
            })

    // ── 破壊の破片（状態レス: 破壊ごとの種から Fx.derive で導出）──

    def fragCount(): Int32 = 8
    def fragSpeedMin(): Float64 = 40.0
    def fragSpeedSpan(): Float64 = 60.0
    def fragGravity(): Float64 = 90.0      // 破片が少し落ちる見かけの重力（px/秒^2 相当）
    def fragHalf(): Float64 = 1.8          // 破片の半径（縮みながら消える）
    def fragSpinMin(): Float64 = 3.0
    def fragSpinSpan(): Float64 = 5.0

    def burstPolys(core: Field.GameCore): List[GameEngine.PolygonRenderCmd] =
        List.flatMap(burstQuads, core#bursts)

    def burstQuads(burst: Field.Burst): List[GameEngine.PolygonRenderCmd] =
        Fx.deriveSeeded({ seed = burst#seed, count = fragCount() }, burst#elapsed,
                        (i, rand, t) -> fragmentPiece(burst, i, rand, t))

    /// 破片 i、破壊から t 秒目: 自分の方向・速さで飛び散り、少し落ち、回りながら縮んで消える。
    def fragmentPiece(burst: Field.Burst, i: Int32, rand: Int32 -> Float64, t: Float64): GameEngine.PolygonRenderCmd =
        let angle = tau() * rand(0);
        let speed = fragSpeedMin() + fragSpeedSpan() * rand(1);
        let dist = speed * t;
        let fall = fragGravity() * t * t;
        let center = { x = burst#pos#x + RenderUtil.cosF(angle) * dist,
                       y = burst#pos#y + RenderUtil.sinF(angle) * dist + fall };
        let spinDir = if (rand(2) < 0.5) -1.0 else 1.0;
        let spin = Curve.spin((fragSpinMin() + fragSpinSpan() * rand(3)) * spinDir, t);
        let progress = t / Field.burstLifetime();
        let half = fragHalf() * (1.0 - progress);
        { vertices = Quad.rotated(center, half, half, spin),
          color = Palette.fragment(i), alpha = RenderUtil.f32(1.0 - progress), zIndex = zBurst() }

    // ── テキスト（HUD と各局面のオーバーレイ）──

    def hudTexts(atlas: FontAtlas, core: Field.GameCore): List[(Vec2.Vec2, Render.RenderItem)] =
        ({ x = 8.0, y = 13.0 },
         Render.textTinted("SCORE ${core#score}", atlas, 10.0, Palette.scoreText(), zText())) ::
        centeredText("LV ${core#level}", atlas, 10.0, Palette.scoreText(), 13.0) ::
        rightText("LIVES ${core#lives}", atlas, 10.0, Palette.scoreText(), Field.designW() - 8.0, 13.0) :: Nil

    def rightText(text: String, atlas: FontAtlas, size: Float64, color: Color,
                  rightX: Float64, y: Float64): (Vec2.Vec2, Render.RenderItem) =
        ({ x = rightX - TextDraw.width(text, atlas, size), y = y },
         Render.textTinted(text, atlas, size, color, zText()))

    /// タイトル画面のオーバーレイ: 題字と案内だけ（盤・HUD は出さない）。
    def titleTexts(atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        centeredText("BREAKOUT", atlas, 32.0, Palette.titleText(), 92.0) ::
        centeredText("PRESS ENTER", atlas, 12.0, Palette.scoreText(), 138.0) :: Nil

    /// サーブ待ちの案内。
    def waitingOverlay(atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        centeredText("PRESS SPACE TO LAUNCH", atlas, 11.0, Palette.scoreText(), 160.0) :: Nil

    /// クリアのオーバーレイ。
    def clearedOverlay(atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        centeredText("CLEAR!", atlas, 30.0, Palette.clearText(), 104.0) ::
        centeredText("PRESS ENTER", atlas, 12.0, Palette.scoreText(), 146.0) :: Nil

    /// ゲームオーバーのオーバーレイ。
    def gameOverOverlay(atlas: FontAtlas): List[(Vec2.Vec2, Render.RenderItem)] =
        centeredText("GAME OVER", atlas, 26.0, Palette.overText(), 104.0) ::
        centeredText("PRESS ENTER", atlas, 12.0, Palette.scoreText(), 146.0) :: Nil

    def centeredText(text: String, atlas: FontAtlas, size: Float64, color: Color,
                     y: Float64): (Vec2.Vec2, Render.RenderItem) =
        TextDraw.centered({ text = text, atlas = atlas, size = size, color = color,
                            z = zText(), centerX = Field.designW() / 2.0, y = y })

    // ── 描画プリミティブ ──

    /// 中心 center・矩形 shape を塗りつぶすボックス（左上原点へ変換）。円・カプセルは無視。
    def rectItems(center: Vec2.Vec2, shape: CollisionShape2D, color: Color, z: Int32): List[(Vec2.Vec2, Render.RenderItem)] =
        match shape {
            case CollisionShape2D.RectShape2D(rect) =>
                flatBox(center, { x = rect#width, y = rect#height }, color, z) :: Nil
            case _ => Nil
        }

    /// 中心指定の単色ボックス。
    def flatBox(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        ({ x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
         Render.solidBox(size, color, z))

    /// 左上指定・高さの半分まで角を丸めたボックス（パドルの丸端の帯）。
    def roundedBox(topLeft: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        let radius = Float64.min(size#x, size#y) / 2.0;
        let style = { cornerRadius = radius, borderWidth = 0.0, borderColor = color,
                      borderAlpha = 0.0f32, stripeColor = color, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        (topLeft, Render.RenderItem.Box({ size = size, color = color, alpha = 1.0f32,
                                          style = Some(style), zIndex = z }))

    /// center を中心とする直径 d の塗りつぶし円（角丸を最大にしたボックス）。
    def circleItem(center: Vec2.Vec2, d: Float64, color: Color, z: Int32): (Vec2.Vec2, Render.RenderItem) =
        let style = { cornerRadius = d / 2.0, borderWidth = 0.0, borderColor = color,
                      borderAlpha = 0.0f32, stripeColor = color, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({ x = center#x - d / 2.0, y = center#y - d / 2.0 },
         Render.RenderItem.Box({ size = { x = d, y = d }, color = color, alpha = 1.0f32,
                                 style = Some(style), zIndex = z }))
}
