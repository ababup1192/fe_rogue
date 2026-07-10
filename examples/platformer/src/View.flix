// View — World から「(置き場所, 見せたい物) のリスト」への投影。
// ここに状態は無い: 地形もプレイヤーも HUD も、渡された World の純粋な関数である。
// 背景は作らない（clearColor の一色）。地形は色分けしたボックス、プレイヤーは球体（円）。
// 着地の瞬間だけ、squashLeft の残り時間から潰れた楕円（横長の全角丸ボックス）を導いて描く —
// タイマー 1 本だけが状態で、形は毎フレーム計算する。
// HUD は運動学の生値を常時表示する: 手触り調整中に「いま何が起きているか」を目で読むため。

mod View {

    // ── 描画レイヤー（下から上へ）──
    def zGround(): Int32 = 0
    def zPlatform(): Int32 = 5
    def zEnemy(): Int32 = 8
    def zPlayer(): Int32 = 10
    def zBurst(): Int32 = 20
    def zText(): Int32 = 100

    /// World を絵へ。地形 → 旗（ゴール・中間地点） → プレイヤー → 演出の粒 → HUD の順で重ねる。
    /// レイヤーは 2 枚: 地形・プレイヤー・粒はワールド空間（camX/camY ぶんずらす）、
    /// HUD はスクリーン空間（固定カメラ）。動く床は時刻の実位置で描く
    /// （静的な床は platformsAt が恒等なので絵は変わらない）。
    pub def frame(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        let worldCam = { offset = { x = -world#camX, y = -world#camY } };
        let worldItems = List.flatten(
            platformBoxes(Field.platformsAt(world#time, world#platforms)) ::
            goalItems(world) ::
            enemyItems(world#time, world#enemies) ::
            playerItems(world#player) ::
            burstItems(world#bursts) :: Nil);
        let screenItems = hudTexts(atlas, world);
        List.append(CameraRig.apply(worldCam, worldItems),
                    CameraRig.apply(CameraRig.fixed(), screenItems))

    // ── 地形 ──

    /// 地形 1 枚 = 色分けした矩形（坂だけ三角形）。役割は寸法でなくフラグで見分ける:
    /// 坂 → 一方通行 → 動く床 → 縦長（壁）→ それ以外（普通の床）の優先順。
    /// 一方通行は薄い板 + 影線、普通の床は土＋草の 2 枚重ね（flatMap になる理由）。
    /// 動く床は厚い一枚板のまま: 「薄い＝すり抜ける・厚い＝硬い」の記号を守る。
    def platformBoxes(platforms: List[Field.Platform]): List[Render.Placed] =
        platforms |> List.flatMap(platform ->
            match platform#slope {
                case Some(riseRight) => slopeTriangle(platform, riseRight) :: Nil
                case None =>
                    if (platform#oneWay)
                        oneWayShelf(platform)
                    else if (not Option.isEmpty(platform#motion))
                        flatBox(platform#pos, platform#size, Palette.moverPlate(), zOf(platform)) :: Nil
                    else if (platform#size#y > platform#size#x)
                        flatBox(platform#pos, platform#size, Palette.stoneWall(), zOf(platform)) :: Nil
                    else
                        groundBoxes(coveredFromAbove(platforms, platform), platform)
            })

    /// 一方通行は「薄い・下が透ける」= すり抜けの定番記号で描く: 当たり判定の箱
    /// （12〜16px）はそのままに、上端 6px の板 + 直下 1px の影線だけを見せる。
    /// 判定の上面 = 見た目の上面なので、プレイヤーは板の上にぴったり立つ。
    def oneWayShelf(platform: Field.Platform): List[Render.Placed] =
        let top = platform#pos#y - platform#size#y / 2.0;
        let plankH = 6.0;
        let plank = flatBox({ x = platform#pos#x, y = top + plankH / 2.0 },
                            { x = platform#size#x, y = plankH }, Palette.plankOneWay(), zOf(platform));
        let shade = flatBox({ x = platform#pos#x, y = top + plankH + 0.5 },
                            { x = platform#size#x, y = 1.0 }, Palette.plankShadow(), zOf(platform));
        plank :: shade :: Nil

    /// この床の真上に別の硬い矩形が載っているか。16px グリッド整列なので「上の床の下面と
    /// この床の上面がほぼ同じ高さ（< 0.5px）で、横に 1px 超重なる」で正確に判定できる。
    def coveredFromAbove(platforms: List[Field.Platform], platform: Field.Platform): Bool =
        let top = platform#pos#y - platform#size#y / 2.0;
        platforms |> List.exists(p2 ->
            p2#id != platform#id
            and Option.isEmpty(p2#slope) and not p2#oneWay
            and Float64.abs((p2#pos#y + p2#size#y / 2.0) - top) < 0.5
            and xOverlap(p2, platform) > 1.0)

    /// 2 枚の矩形の横方向の重なり幅（重ならなければ負）。
    def xOverlap(a: Field.Platform, b: Field.Platform): Float64 =
        Float64.min(a#pos#x + a#size#x / 2.0, b#pos#x + b#size#x / 2.0)
        - Float64.max(a#pos#x - a#size#x / 2.0, b#pos#x - b#size#x / 2.0)

    /// 普通の床（地面）は土の本体 + 上面の草の 2 枚重ね。草は上面 4px を覆う薄いキャップ。
    /// ただし真上に別の硬い床が積まれている段は空が見えない = 草は生えない（全部土で描く）。
    /// これで 2 行積みの地面が縞にならず、露出した上面だけが緑になる。
    def groundBoxes(covered: Bool, platform: Field.Platform): List[Render.Placed] =
        let dirt = flatBox(platform#pos, platform#size, Palette.dirtBody(), zOf(platform));
        if (covered) dirt :: Nil
        else {
            let capH = 4.0;
            let capPos = { x = platform#pos#x, y = platform#pos#y - platform#size#y / 2.0 + capH / 2.0 };
            let cap = flatBox(capPos, { x = platform#size#x, y = capH }, Palette.grassTop(), zOf(platform) + 1);
            dirt :: cap :: Nil
        }

    /// 坂 = 直角三角形の polygon。置き場所は外接箱の左上、頂点はそこからの相対座標。
    def slopeTriangle(platform: Field.Platform, riseRight: Bool): Render.Placed =
        let size = platform#size;
        let topLeft = { x = platform#pos#x - size#x / 2.0, y = platform#pos#y - size#y / 2.0 };
        let verts =
            if (riseRight)
                { x = 0.0, y = size#y } :: { x = size#x, y = size#y } :: { x = size#x, y = 0.0 } :: Nil
            else
                { x = 0.0, y = size#y } :: { x = size#x, y = size#y } :: { x = 0.0, y = 0.0 } :: Nil;
        (topLeft, Render.polygon(verts, Palette.slopeGrass(), zOf(platform)))

    def zOf(platform: Field.Platform): Int32 =
        if (platform#size#y >= 30.0) zGround() else zPlatform()

    // ── ゴールの旗（world#goalX に立つ・classic のレベルでは範囲外なので映らない）──

    /// 旗竿は細い石柱（4×96px）+ 竿先の三角ペナント。台座はレベルの地面の上面
    /// （下 4 行が地面なので levelH − 64）。クリア判定は Step が goalX で行い、
    /// ここは目印を描くだけ。
    def goalItems(world: Field.World): List[Render.Placed] =
        let checkpointColor =
            if (world#respawnPos#x >= world#checkpointPos#x) Palette.goalFlag()
            else Palette.eyeWhite();
        List.append(
            flagAt(world#goalX, 96.0, Palette.goalFlag(), world),
            flagAt(world#checkpointPos#x, 48.0, checkpointColor, world))

    /// 旗 1 本 = 細い石柱 + 竿先の三角ペナント。台座はレベルの地面の上面
    /// （下 4 行が地面なので levelH − 64）。中間地点の旗は低く、発動すると白 → 緑に変わる。
    def flagAt(x: Float64, poleH: Float64, color: Color, world: Field.World): List[Render.Placed] =
        let poleW = 4.0;
        let baseY = world#levelH - 64.0;
        let pole = flatBox({ x = x, y = baseY - poleH / 2.0 },
                           { x = poleW, y = poleH }, Palette.stoneWall(), zPlatform());
        let pennantVerts =
            { x = 0.0, y = 0.0 } :: { x = 14.0, y = 5.0 } :: { x = 0.0, y = 10.0 } :: Nil;
        let pennant = ({ x = x + poleW / 2.0, y = baseY - poleH },
                       Render.polygon(pennantVerts, color, zPlatform() + 1));
        pole :: pennant :: Nil

    // ── 敵（生きているものだけ・時刻の実位置で描く）──
    // 球体の自機と混線しないよう、敵は「まんじゅう型」（平らな底 + 丸い上）にする。
    // 当たり判定は従来どおり半径 10 の円のまま（enemyRadius）— 見た目だけがドームに変わる。

    /// 敵は全種ともドーム型が本体。歩く敵は足（歩きの上下）付き、パタパタは同じドーム＋羽
    /// （足なし・浮いている）、トゲはドームの上側だけに大きい棘が並ぶ。目玉は種ごとに大小。
    /// 死んだ敵は描かない（骸は残さない）。
    def enemyItems(t: Float64, enemies: List[Field.Enemy]): List[Render.Placed] =
        enemies |> List.filter(e -> e#alive) |> List.flatMap(enemy -> {
            let pos = Field.enemyPosAt(t, enemy);
            match enemy#kind {
                case Field.EnemyKind.WalkerKind =>
                    List.flatten(dome(pos, Palette.walkerBody()) :: feet(t, pos) :: eyes(pos, 3.0) :: Nil)
                case Field.EnemyKind.FlyerKind  =>
                    List.flatten(dome(pos, Palette.flyerBody()) :: wings(t, pos) :: eyes(pos, 3.0) :: Nil)
                case Field.EnemyKind.SpikyKind  =>
                    List.flatten(spikyDome(pos) :: topSpikes(pos) :: sideSpikes(pos) :: eyes(pos, 2.0) :: Nil)
            }
        })

    /// まんじゅう型の本体: 角丸ボックス {22,16} の上に、下半分を覆う平らなボックスを
    /// 同色で重ねて底を四角に均す（rounded は全角を丸めるので、底だけ角丸を打ち消す）。
    /// 中心は当たり判定の円と同じ pos、下端は円の下端（pos#y + enemyRadius）に揃える。
    def dome(pos: Vec2.Vec2, color: Color): List[Render.Placed] =
        domeAt(pos, color, { x = 22.0, y = 16.0 }, 7.0)

    /// トゲの本体は少し低く座った寸法（squat）。
    def spikyDome(pos: Vec2.Vec2): List[Render.Placed] =
        domeAt(pos, Palette.spikyBody(), { x = 22.0, y = 14.0 }, 6.0)

    /// ドーム 1 個の共通形: 角丸ボックス + 底を均す平らな帯。底辺は enemyRadius の位置で揃える
    /// （size#y の半分より浅い帯なら、底だけ角丸の丸みを覆い隠せる）。
    def domeAt(pos: Vec2.Vec2, color: Color, size: Vec2.Vec2, radius: Float64): List[Render.Placed] =
        let bottom = pos#y + Field.enemyRadius();
        let bodyTopLeft = { x = pos#x - size#x / 2.0, y = bottom - size#y };
        let body = (bodyTopLeft, Render.box(size, color, zEnemy()) |> Render.rounded(radius));
        let squareH = 6.0;
        let squarePos = { x = pos#x - size#x / 2.0, y = bottom - squareH };
        let square = (squarePos, Render.box({ x = size#x, y = squareH }, color, zEnemy()));
        body :: square :: Nil

    /// 歩く敵の足 2 本（4×3 の小箱・ドーム底のすぐ下・本体より暗い色 = plankShadow 流用）。
    /// pingPong(t×2) の符号で左右交互に ±1px だけ前後にずれ、歩く揺れを表す（状態は持たない）。
    def feet(t: Float64, pos: Vec2.Vec2): List[Render.Placed] =
        let bottom = pos#y + Field.enemyRadius();
        let wobble = Field.pingPong(t * 2.0) - 0.5; // -0.5..0.5 の揺れ幅
        let footSize = { x = 4.0, y = 3.0 };
        ({ x = pos#x - 6.0 + wobble, y = bottom }, Render.box(footSize, Palette.plankShadow(), zEnemy())) ::
        ({ x = pos#x + 2.0 - wobble, y = bottom }, Render.box(footSize, Palette.plankShadow(), zEnemy())) :: Nil

    /// パタパタの羽 2 枚（6×3 の小箱・ドームの左右側面）。上下 ±2px の羽ばたきは
    /// pingPong(t×2) から毎フレーム導く — 位置は保存しない（閉形式）。
    def wings(t: Float64, pos: Vec2.Vec2): List[Render.Placed] =
        let r = Field.enemyRadius();
        let flap = Field.pingPong(t * 2.0) * 2.0;
        let size = { x = 6.0, y = 3.0 };
        ({ x = pos#x - r - 5.0, y = pos#y - 2.0 + flap }, Render.box(size, Palette.flyerWing(), zEnemy())) ::
        ({ x = pos#x + r - 1.0, y = pos#y - 2.0 + flap }, Render.box(size, Palette.flyerWing(), zEnemy())) :: Nil

    /// ドーム上部の弧に沿って並ぶ、上向きの大きい棘 7 本（「踏むな」の記号）。
    /// -60°〜+60° を 7 等分した角度（ラジアンでなく単位ベクトルの定数表）で、
    /// 頂点はドーム上端よりさらに外へ 7px 突き出る。
    def topSpikeDirs(): List[Vec2.Vec2] =
        { x = -0.866, y = -0.5 } :: { x = -0.643, y = -0.766 } :: { x = -0.342, y = -0.940 } ::
        { x = 0.0, y = -1.0 } ::
        { x = 0.342, y = -0.940 } :: { x = 0.643, y = -0.766 } :: { x = 0.866, y = -0.5 } :: Nil

    /// トゲ 1 本 = 本体の縁から上方向へ 7px 突き出る三角形。polygon の頂点は置き場所
    /// （外接箱の左上）からの相対座標で組む。
    def topSpikes(pos: Vec2.Vec2): List[Render.Placed] =
        let r = Field.enemyRadius();
        let reach = r + 7.0;
        let topLeft = { x = pos#x - reach, y = pos#y - reach };
        topSpikeDirs() |> List.map(dir -> {
            let perp = { x = -dir#y, y = dir#x };
            let tip = { x = reach + dir#x * reach, y = reach + dir#y * reach };
            let baseA = { x = reach + dir#x * (r - 2.0) + perp#x * 3.0,
                          y = reach + dir#y * (r - 2.0) + perp#y * 3.0 };
            let baseB = { x = reach + dir#x * (r - 2.0) - perp#x * 3.0,
                          y = reach + dir#y * (r - 2.0) - perp#y * 3.0 };
            (topLeft, Render.polygon(baseA :: baseB :: tip :: Nil, Palette.spikeTip(), zEnemy()))
        })

    /// 側面の小さい棘 2 本（左右に 1 本ずつ・見分けの飾り）。
    def sideSpikeDirs(): List[Vec2.Vec2] =
        { x = -1.0, y = 0.0 } :: { x = 1.0, y = 0.0 } :: Nil

    def sideSpikes(pos: Vec2.Vec2): List[Render.Placed] =
        let r = Field.enemyRadius();
        let reach = r + 4.0;
        let topLeft = { x = pos#x - reach, y = pos#y - reach };
        sideSpikeDirs() |> List.map(dir -> {
            let perp = { x = -dir#y, y = dir#x };
            let tip = { x = reach + dir#x * reach, y = reach + dir#y * reach };
            let baseA = { x = reach + dir#x * (r - 2.0) + perp#x * 2.5,
                          y = reach + dir#y * (r - 2.0) + perp#y * 2.5 };
            let baseB = { x = reach + dir#x * (r - 2.0) - perp#x * 2.5,
                          y = reach + dir#y * (r - 2.0) - perp#y * 2.5 };
            (topLeft, Render.polygon(baseA :: baseB :: tip :: Nil, Palette.spikeTip(), zEnemy()))
        })

    /// 目玉 2 個（本体中心から ±4, -3px・白目 r=eyeR + 黒目 r=eyeR×0.5 を中心に重ねる）。
    /// プレイヤーの回転ドットと混線しないよう、白目は大きめの円 + はっきりした瞳にする。
    def eyes(pos: Vec2.Vec2, eyeR: Float64): List[Render.Placed] =
        let leftCenter = { x = pos#x - 4.0, y = pos#y - 3.0 };
        let rightCenter = { x = pos#x + 4.0, y = pos#y - 3.0 };
        List.flatten(eyeAt(leftCenter, eyeR) :: eyeAt(rightCenter, eyeR) :: Nil)

    /// 目玉 1 個 = 白目（円・zEnemy+1）+ 黒い瞳（円・zEnemy+2・白目より小さく前面）。
    def eyeAt(center: Vec2.Vec2, eyeR: Float64): List[Render.Placed] =
        let pupilR = eyeR * 0.5;
        ({ x = center#x - eyeR, y = center#y - eyeR }, Render.circle(eyeR, Palette.eyeWhite(), zEnemy() + 1)) ::
        ({ x = center#x - pupilR, y = center#y - pupilR }, Render.circle(pupilR, Palette.eyePupil(), zEnemy() + 2)) :: Nil

    // ── プレイヤー（球体・着地の瞬間だけ潰れる）──

    /// squashLeft が残っている間は横に広く縦に低い全角丸ボックス（= 楕円の近似）を、
    /// 空中で速く上昇している間は縦長（ジャンプ伸びストレッチ = 着地スカッシュの対）を、
    /// それ以外は真円を描く。潰れても足元（下端）は地面に着けたまま。伸びは飛行中なので
    /// 中心基準で上下へ伸ばす。段階演出はすべて |vx| から導く（新しい状態は持たない）:
    /// 色 3 段階 + 転がりの点 3 個（回転）+ 最高速の残像 2 枚。
    def playerItems(player: Field.Player): List[Render.Placed] =
        let r = Field.playerRadius();
        let ratio = if (Field.squashTime() > 0.0) player#squashLeft / Field.squashTime() else 0.0;
        let stretch = stretchAmount(player);
        let w = r * 2.0 * (1.0 + 0.35 * ratio - 0.10 * stretch);
        let h = r * 2.0 * (1.0 - 0.35 * ratio + 0.18 * stretch);
        let topLeft =
            if (stretch > 0.0) { x = player#pos#x - w / 2.0, y = player#pos#y - h / 2.0 }
            else { x = player#pos#x - w / 2.0, y = player#pos#y + r - h };
        let ball = (topLeft, Render.box({ x = w, y = h }, playerColor(player#vel#x), zPlayer())
            |> Render.rounded(Float64.min(w, h) / 2.0));
        List.append(ghostItems(player), ball :: spinDots(player))

    /// ジャンプ伸びの量（0..1）: 空中で vy が −200 を超えて上昇しているほど縦長に描く。
    /// 分母 312 は「立ちジャンプの初速 512 で最大」の実測合わせ（512 − 200）。
    /// 着地スカッシュが残っている間はそちらを優先する（同時には成立させない）。
    /// 接地中・ゆっくりの上昇（vy ≥ −200）では厳密に 0 = 従来の絵とバイト一致。
    def stretchAmount(player: Field.Player): Float64 =
        if (player#grounded or player#squashLeft > 0.0) 0.0
        else Float64.max(0.0, Float64.min(1.0, (-(player#vel#y) - 200.0) / 312.0))

    /// 最高速域の |vx| のしきい値。approach は 280.0 ちょうどに達するが、離した直後の
    /// 減衰帯（279.x）でも白がちらつかないよう 0.5 だけ手前に取る。
    def maxBandSpeed(): Float64 = Jump.maxRunSpeed() * Jump.dashMult() - 0.5

    /// 走り速度から球体の色を選ぶ: 通常（≤160 黄）→ P スピード帯（>160 橙）→
    /// 最高速域（≥279.5 白）の 3 段階。
    def playerColor(vx: Float64): Color =
        let speed = Float64.abs(vx);
        if (speed >= maxBandSpeed()) Palette.playerMax()
        else if (speed > Jump.maxRunSpeed()) Palette.playerDash()
        else Palette.player()

    /// 最高速域だけの残像: 3 フレーム前・6 フレーム前の位置（pos − vel×n×dt）に
    /// 薄い球体を 2 枚置く（z はプレイヤーの 1 つ下）。位置は速度から導くので状態は増えない。
    def ghostItems(player: Field.Player): List[Render.Placed] =
        if (Float64.abs(player#vel#x) < maxBandSpeed()) Nil
        else {
            let dt = 1.0 / 64.0;
            let ghost = (framesBack: Float64, alpha: Float32) -> {
                let pos = { x = player#pos#x - player#vel#x * framesBack * dt,
                            y = player#pos#y - player#vel#y * framesBack * dt };
                ballAt(pos, playerColor(player#vel#x), zPlayer() - 1) |> fadePlaced(alpha)
            };
            ghost(3.0, 0.35f32) :: ghost(6.0, 0.18f32) :: Nil
        }

    /// 転がりの点 3 個（120° 間隔・ソニック風の回転）: 転がり角 θ = x / 半径 から
    /// θ, θ+2π/3, θ+4π/3 の 3 方向に 0.55r 離して濃い点を置く。走るほど速く回って見える。
    /// 2 個（対角 180°）だと敵の目玉に似て自機が顔に見えてしまうため、3 個にして
    /// 「顔」に読めないようにする（E2-1e）。潰れ・伸び演出中は形が崩れるので省略する
    /// （伸びた楕円の中に点が残ると回転に見えず汚い）。
    def spinDots(player: Field.Player): List[Render.Placed] =
        if (player#squashLeft > 0.0 or stretchAmount(player) > 0.0) Nil
        else {
            let r = Field.playerRadius();
            let theta = player#pos#x / r;
            let twoThirdsPi = 2.0943951023931953; // 2π/3
            let dotArm = (angle: Float64) -> {
                let arm = { x = Vec2.cos(angle) * 0.55 * r, y = Vec2.sin(angle) * 0.55 * r };
                dotAt(Vec2.add(player#pos, arm))
            };
            dotArm(theta) :: dotArm(theta + twoThirdsPi) :: dotArm(theta + 2.0 * twoThirdsPi) :: Nil
        }

    /// 転がりの点 1 個（半径 2.5px・z はプレイヤーの 1 つ上）。
    def dotAt(pos: Vec2.Vec2): Render.Placed =
        let dotR = 2.5;
        ({ x = pos#x - dotR, y = pos#y - dotR }, Render.circle(dotR, Palette.ballSpin(), zPlayer() + 1))

    /// 指定の中心に等身大の球体を置く（残像用）。
    def ballAt(pos: Vec2.Vec2, color: Color, z: Int32): Render.Placed =
        let r = Field.playerRadius();
        ({ x = pos#x - r, y = pos#y - r }, Render.circle(r, color, z))

    /// Placed の中身だけ半透明にする（置き場所は保つ）。
    def fadePlaced(alpha: Float32, placed: Render.Placed): Render.Placed =
        let (pos, item) = placed;
        (pos, Render.fade(alpha, item))

    // ── 演出の粒（土埃・ジャンプ噴射）──

    /// World の bursts から、いまの粒を毎フレーム閉形式で導いて描く。状態は持たない。
    def burstItems(bursts: List[Field.Burst]): List[Render.Placed] =
        bursts |> List.flatMap(burst ->
            GameFx.particles(burst) |> List.map(triple -> {
                let (pos, radius, alpha) = triple;
                ({ x = pos#x - radius, y = pos#y - radius },
                 Render.circle(radius, burstColor(burst), zBurst()) |> Render.fade(alpha))
            }))

    /// 粒の色。花火だけは発番号（seed）で 4 色を巡回する。
    def burstColor(burst: Field.Burst): Color = match burst#kind {
        case Field.FxKind.DustKind     => Palette.dustPuff()
        case Field.FxKind.JetKind      => Palette.jetPuff()
        case Field.FxKind.FireworkKind => Palette.fireworkColor(burst#seed)
    }

    // ── HUD（運動学の生値と操作の案内）──

    def hudTexts(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        let player = world#player;
        let status =
            "v=(${fmt(player#vel#x)},${fmt(player#vel#y)})"
            + " grd=${if (player#grounded) "T" else "F"}"
            + " coy=${fmt(player#coyoteLeft * 1000.0)}"
            + " buf=${fmt(player#bufferLeft * 1000.0)}"
            + " deaths=${world#deaths}";
        ({ x = 6.0, y = 4.0 },
         Render.textTinted(status, atlas, 8.0, Palette.hudText(), zText())) ::
        ({ x = 6.0, y = Field.designH() - 12.0 },
         Render.textTinted("ARROWS move / Z dash / SPACE jump / F1 reload", atlas, 8.0,
                           Palette.hintText(), zText())) ::
        clearBanner(atlas, world)

    /// クリア後は画面中央に「CLEAR!」を出し続ける（ゲームは止めない・検証台なので）。
    def clearBanner(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        if (Option.isEmpty(world#clearedAt)) Nil
        else ({ x = Field.designW() / 2.0 - 30.0, y = 80.0 },
              Render.textTinted("CLEAR!", atlas, 16.0, Palette.hudText(), zText())) :: Nil

    /// HUD 用に 1 桁小数へ丸める（RemoteDebug の書式を共用）。
    def fmt(v: Float64): String = RemoteDebug.fmt1(v)

    // ── 形の補助 ──

    /// 中心座標とサイズから左上原点の Box を置く（Render.box は左上原点）。
    def flatBox(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): Render.Placed =
        ({ x = center#x - size#x / 2.0, y = center#y - size#y / 2.0 },
         Render.box(size, color, z))
}
