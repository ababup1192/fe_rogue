// View — World から「(置き場所, 見せたい物) のリスト」への投影。
// ここに状態は無い: 地形もプレイヤーも HUD も、渡された World の純粋な関数である。
// 背景は作らない（clearColor の一色）。地形は色分けしたボックス、プレイヤーは
// 15 キャラの名簿（Roster）から charIndex で引いた draw に、World から組んだ
// 演技の舞台情報（CharStage.Stage — 足元中心・速度・向き・演技区分 viewMode）を
// 渡すだけ。描き方はすべて各 Char モジュールが持つ（ラボと本編で同じ絵になる）。
// HUD は運動学の生値を常時表示する: 手触り調整中に「いま何が起きているか」を目で読むため。

mod View {

    // ── 描画レイヤー（下から上へ）──
    def zGround(): Int32 = 0
    def zPlatform(): Int32 = 5
    def zEnemy(): Int32 = 8
    def zPlayer(): Int32 = 10
    def zBurst(): Int32 = 20
    def zText(): Int32 = 100

    /// World をワールド空間の絵へ。地形 → 旗（ゴール・中間地点） → 敵 → プレイヤー → 演出の粒。
    /// カメラのずらしは App.withCamera（cameraCenter）が引き受けるので、ここは world 座標のまま組む。
    /// 動く床は時刻の実位置で描く（静的な床は platformsAt が恒等なので絵は変わらない）。
    pub def frame(_ctx: App.ViewCtx, world: Field.World): List[Render.PlacedItem] =
        List.flatten(
            platformBoxes(Field.platformsAt(world#time, world#platforms)) ::
            goalItems(world) ::
            enemyItems(world#time, world#enemies) ::
            playerItems(world) ::
            burstItems(world#bursts) :: Nil)

    /// スクリーン空間の絵（HUD。カメラを掛けない = スクロールしても動かない）。
    pub def hud(ctx: App.ViewCtx, world: Field.World): List[Render.PlacedItem] =
        hudTexts(ctx#atlas, world)

    /// 画面中央に映したい world 座標（App.withCamera に渡す）。World の camX/camY は
    /// カメラの左上なので、design の半分を足して中央にする。追従・クランプ・先読みは
    /// FollowCam のシステムが World を進めた結果で、ここは読むだけ。
    pub def cameraCenter(world: Field.World): Vec2.Vec2 =
        { x = world#camX + Field.designW() / 2.0,
          y = world#camY + Field.designH() / 2.0 }

    // ── 地形 ──

    /// 地形 1 枚 = 色分けした矩形（坂だけ三角形）。役割は寸法でなくフラグで見分ける:
    /// 坂 → 一方通行 → 動く床 → 縦長（壁）→ それ以外（普通の床）の優先順。
    /// 一方通行は薄い板 + 影線、普通の床は土＋草の 2 枚重ね（flatMap になる理由）。
    /// 動く床は厚い一枚板のまま: 「薄い＝すり抜ける・厚い＝硬い」の記号を守る。
    def platformBoxes(platforms: List[Field.Platform]): List[Render.PlacedItem] =
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
    def oneWayShelf(platform: Field.Platform): List[Render.PlacedItem] =
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
    def groundBoxes(covered: Bool, platform: Field.Platform): List[Render.PlacedItem] =
        let dirt = flatBox(platform#pos, platform#size, Palette.dirtBody(), zOf(platform));
        if (covered) dirt :: Nil
        else {
            let capH = 4.0;
            let capPos = { x = platform#pos#x, y = platform#pos#y - platform#size#y / 2.0 + capH / 2.0 };
            let cap = flatBox(capPos, { x = platform#size#x, y = capH }, Palette.grassTop(), zOf(platform) + 1);
            dirt :: cap :: Nil
        }

    /// 坂 = 直角三角形の polygon。置き場所は外接箱の左上、頂点はそこからの相対座標。
    def slopeTriangle(platform: Field.Platform, riseRight: Bool): Render.PlacedItem =
        let size = platform#size;
        let topLeft = { x = platform#pos#x - size#x / 2.0, y = platform#pos#y - size#y / 2.0 };
        let verts =
            if (riseRight)
                { x = 0.0, y = size#y } :: { x = size#x, y = size#y } :: { x = size#x, y = 0.0 } :: Nil
            else
                { x = 0.0, y = size#y } :: { x = size#x, y = size#y } :: { x = 0.0, y = 0.0 } :: Nil;
        { at = topLeft, item = Render.polygon(verts, Palette.slopeGrass(), zOf(platform)) }

    def zOf(platform: Field.Platform): Int32 =
        if (platform#size#y >= 30.0) zGround() else zPlatform()

    // ── ゴールの旗（world#goalX に立つ・classic のレベルでは範囲外なので映らない）──

    /// 旗竿は細い石柱（4×96px）+ 竿先の三角ペナント。台座はレベルの地面の上面
    /// （下 4 行が地面なので levelH − 64）。クリア判定は Step が goalX で行い、
    /// ここは目印を描くだけ。
    def goalItems(world: Field.World): List[Render.PlacedItem] =
        let checkpointColor =
            if (world#respawnPos#x >= world#checkpointPos#x) Palette.goalFlag()
            else Palette.eyeWhite();
        List.append(
            flagAt(world#goalX, 96.0, Palette.goalFlag(), world),
            flagAt(world#checkpointPos#x, 48.0, checkpointColor, world))

    /// 旗 1 本 = 細い石柱 + 竿先の三角ペナント。台座はレベルの地面の上面
    /// （下 4 行が地面なので levelH − 64）。中間地点の旗は低く、発動すると白 → 緑に変わる。
    def flagAt(x: Float64, poleH: Float64, color: Color, world: Field.World): List[Render.PlacedItem] =
        let poleW = 4.0;
        let baseY = world#levelH - 64.0;
        let pole = flatBox({ x = x, y = baseY - poleH / 2.0 },
                           { x = poleW, y = poleH }, Palette.stoneWall(), zPlatform());
        let pennantVerts =
            { x = 0.0, y = 0.0 } :: { x = 14.0, y = 5.0 } :: { x = 0.0, y = 10.0 } :: Nil;
        let pennant = { at = { x = x + poleW / 2.0, y = baseY - poleH },
                        item = Render.polygon(pennantVerts, color, zPlatform() + 1) };
        pole :: pennant :: Nil

    // ── 敵（生きているものだけ・時刻の実位置で描く）──
    // 縦長のヒーロー自機と混線しないよう、敵は「まんじゅう型」（平らな底 + 丸い上）にする。
    // 当たり判定は従来どおり半径 10 の円のまま（enemyRadius）— 見た目だけがドームに変わる。

    /// 敵は全種ともドーム型が本体。歩く敵は足（歩きの上下）付き、パタパタは同じドーム＋羽
    /// （足なし・浮いている）、トゲはドームの上側だけに大きい棘が並ぶ。目玉は種ごとに大小。
    /// 死んだ敵は描かない（骸は残さない）。
    def enemyItems(t: Float64, enemies: List[Field.Enemy]): List[Render.PlacedItem] =
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
    def dome(pos: Vec2.Vec2, color: Color): List[Render.PlacedItem] =
        domeAt(pos, color, { x = 22.0, y = 16.0 }, 7.0)

    /// トゲの本体は少し低く座った寸法（squat）。
    def spikyDome(pos: Vec2.Vec2): List[Render.PlacedItem] =
        domeAt(pos, Palette.spikyBody(), { x = 22.0, y = 14.0 }, 6.0)

    /// ドーム 1 個の共通形: 角丸ボックス + 底を均す平らな帯。底辺は enemyRadius の位置で揃える
    /// （size#y の半分より浅い帯なら、底だけ角丸の丸みを覆い隠せる）。
    def domeAt(pos: Vec2.Vec2, color: Color, size: Vec2.Vec2, radius: Float64): List[Render.PlacedItem] =
        let bottom = pos#y + Field.enemyRadius();
        let bodyTopLeft = { x = pos#x - size#x / 2.0, y = bottom - size#y };
        let body = { at = bodyTopLeft, item = Render.box(size, color, zEnemy()) |> Render.rounded(radius) };
        let squareH = 6.0;
        let squarePos = { x = pos#x - size#x / 2.0, y = bottom - squareH };
        let square = { at = squarePos, item = Render.box({ x = size#x, y = squareH }, color, zEnemy()) };
        body :: square :: Nil

    /// 歩く敵の足 2 本（4×3 の小箱・ドーム底のすぐ下・本体より暗い色 = plankShadow 流用）。
    /// triWave(t×2) の符号で左右交互に ±1px だけ前後にずれ、歩く揺れを表す（状態は持たない）。
    def feet(t: Float64, pos: Vec2.Vec2): List[Render.PlacedItem] =
        let bottom = pos#y + Field.enemyRadius();
        let wobble = Field.triWave(t * 2.0) - 0.5; // -0.5..0.5 の揺れ幅
        let footSize = { x = 4.0, y = 3.0 };
        { at = { x = pos#x - 6.0 + wobble, y = bottom }, item = Render.box(footSize, Palette.plankShadow(), zEnemy()) } ::
        { at = { x = pos#x + 2.0 - wobble, y = bottom }, item = Render.box(footSize, Palette.plankShadow(), zEnemy()) } :: Nil

    /// パタパタの羽 2 枚（6×3 の小箱・ドームの左右側面）。上下 ±2px の羽ばたきは
    /// triWave(t×2) から毎フレーム導く — 位置は保存しない（閉形式）。
    def wings(t: Float64, pos: Vec2.Vec2): List[Render.PlacedItem] =
        let r = Field.enemyRadius();
        let flap = Field.triWave(t * 2.0) * 2.0;
        let size = { x = 6.0, y = 3.0 };
        { at = { x = pos#x - r - 5.0, y = pos#y - 2.0 + flap }, item = Render.box(size, Palette.flyerWing(), zEnemy()) } ::
        { at = { x = pos#x + r - 1.0, y = pos#y - 2.0 + flap }, item = Render.box(size, Palette.flyerWing(), zEnemy()) } :: Nil

    /// ドーム上部の弧に沿って並ぶ、上向きの大きい棘 7 本（「踏むな」の記号）。
    /// -60°〜+60° を 7 等分した角度（ラジアンでなく単位ベクトルの定数表）で、
    /// 頂点はドーム上端よりさらに外へ 7px 突き出る。
    def topSpikeDirs(): List[Vec2.Vec2] =
        { x = -0.866, y = -0.5 } :: { x = -0.643, y = -0.766 } :: { x = -0.342, y = -0.940 } ::
        { x = 0.0, y = -1.0 } ::
        { x = 0.342, y = -0.940 } :: { x = 0.643, y = -0.766 } :: { x = 0.866, y = -0.5 } :: Nil

    /// トゲ 1 本 = 本体の縁から上方向へ 7px 突き出る三角形。polygon の頂点は置き場所
    /// （外接箱の左上）からの相対座標で組む。
    def topSpikes(pos: Vec2.Vec2): List[Render.PlacedItem] =
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
            { at = topLeft, item = Render.polygon(baseA :: baseB :: tip :: Nil, Palette.spikeTip(), zEnemy()) }
        })

    /// 側面の小さい棘 2 本（左右に 1 本ずつ・見分けの飾り）。
    def sideSpikeDirs(): List[Vec2.Vec2] =
        { x = -1.0, y = 0.0 } :: { x = 1.0, y = 0.0 } :: Nil

    def sideSpikes(pos: Vec2.Vec2): List[Render.PlacedItem] =
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
            { at = topLeft, item = Render.polygon(baseA :: baseB :: tip :: Nil, Palette.spikeTip(), zEnemy()) }
        })

    /// 目玉 2 個（本体中心から ±4, -3px・白目 r=eyeR + 黒目 r=eyeR×0.5 を中心に重ねる）。
    /// 自機と見分けるのはシルエット（敵 = ずんぐりドーム / 自機 = 縦長）が担い、
    /// 目玉の文法（白目 + 瞳）は自機と共通でよい。
    def eyes(pos: Vec2.Vec2, eyeR: Float64): List[Render.PlacedItem] =
        let leftCenter = { x = pos#x - 4.0, y = pos#y - 3.0 };
        let rightCenter = { x = pos#x + 4.0, y = pos#y - 3.0 };
        List.flatten(eyeAt(leftCenter, eyeR) :: eyeAt(rightCenter, eyeR) :: Nil)

    /// 目玉 1 個 = 白目（円・zEnemy+1）+ 黒い瞳（円・zEnemy+2・白目より小さく前面）。
    def eyeAt(center: Vec2.Vec2, eyeR: Float64): List[Render.PlacedItem] =
        let pupilR = eyeR * 0.5;
        { at = { x = center#x - eyeR, y = center#y - eyeR }, item = Render.circle(eyeR, Palette.eyeWhite(), zEnemy() + 1) } ::
        { at = { x = center#x - pupilR, y = center#y - pupilR }, item = Render.circle(pupilR, Palette.eyePupil(), zEnemy() + 2) } :: Nil

    // ── プレイヤー（15 キャラの名簿 Roster 経由・演技情報はラボと同じ Stage）──

    /// キャラ本体 + 最高速の残像 + ガードの盾 + 無敵の点滅。描き方は Char01..15 が持ち、
    /// ここは Stage を World から組んで渡す。座標の取り決めはラボ（CharGallery）と同じ:
    /// キャラは「地面ローカル」（足元 y=0）で描き、縦位置はここで出力を平行移動して与える
    /// （キャラ側は pos#y を出力に足さない前提で書かれている — 試着室では常に 0 だった）。
    /// 無敵中（ガード直後）は floor(t×16) の偶奇で本体を描いたり消したりする（決定的な点滅）。
    def playerItems(world: Field.World): List[Render.PlacedItem] =
        let player = world#player;
        let feetY = player#pos#y + Field.playerRadius();
        let stage = stageOf(world#time, player);
        let drawFn = Roster.drawOf(world#charIndex);
        let blinkHidden = player#invulnLeft > 0.0
            and Int32.modulo(RenderUtil.floatToInt32(Float64.floor(world#time * 16.0)), 2) == 1;
        let body = if (blinkHidden) Nil else drawFn(stage) |> List.map(shiftY(feetY));
        List.flatten(guardRing(world#time, player) :: ghostItems(drawFn, stage, feetY, player) :: body :: Nil)

    /// 描画物の縦位置を平行移動する（ラボの laneItems と同じ役目）。
    def shiftY(dy: Float64, placed: Render.PlacedItem): Render.PlacedItem =
        { at = { x = placed#at#x, y = placed#at#y + dy }, item = placed#item }

    /// World の状態を演技の舞台情報（CharStage.Stage）へ写す。pos#x は世界座標
    /// （キャラは走りの歩幅位相を pos#x の移動距離から導く）、pos#y は常に 0
    /// （ラボの接地時と同じ「地面ローカル」— 縦位置は playerItems が出力を平行移動して与える）。
    def stageOf(t: Float64, player: Field.Player): CharStage.Stage =
        { t = t,
          pos = { x = player#pos#x, y = 0.0 },
          vx = player#vel#x,
          facing = player#facing,
          mode = player#viewMode,
          modeT = player#viewModeT }

    /// 最高速域の |vx| のしきい値。approach は 280.0 ちょうどに達するが、離した直後の
    /// 減衰帯（279.x）でも残像がちらつかないよう 0.5 だけ手前に取る。
    def maxBandSpeed(): Float64 = Jump.maxRunSpeed() * Jump.dashMult() - 0.5

    /// 最高速域だけの残像: 3 フレーム前・6 フレーム前の位置（pos − vel×n×dt）に
    /// 同じ演技のキャラを薄く 2 体置く。位置は速度から導くので状態は増えない。
    /// 縦は本体と同じく「出力の平行移動」で与える（stage#pos#y は地面ローカルの 0 のまま）。
    def ghostItems(drawFn: CharStage.Stage -> List[Render.PlacedItem],
                   stage: CharStage.Stage, feetY: Float64, player: Field.Player): List[Render.PlacedItem] =
        if (Float64.abs(player#vel#x) < maxBandSpeed()) Nil
        else {
            let dt = 1.0 / 64.0;
            let ghost = (framesBack: Float64, alpha: Float32) -> {
                let pos = { x = stage#pos#x - player#vel#x * framesBack * dt, y = 0.0 };
                let ghostFeetY = feetY - player#vel#y * framesBack * dt;
                drawFn({ pos = pos | stage })
                    |> List.map(shiftY(ghostFeetY))
                    |> List.map(fadePlaced(alpha))
            };
            List.append(ghost(3.0, 0.35f32), ghost(6.0, 0.18f32))
        }

    /// ガードが残っているキャラの盾: 体の周りをゆっくり周回する小さな光点 6 個
    /// （「1 回耐えられる」の視覚記号・ガードを使うと消える）。
    /// 塗り円で体を覆うと暗色のキャラが見えなくなるため、点の輪で「囲うが隠さない」。
    def guardRing(t: Float64, player: Field.Player): List[Render.PlacedItem] =
        if (player#guardLeft <= 0) Nil
        else {
            let orbitR = Field.playerRadius() + 7.0;
            let dotR = 2.5;
            List.range(0, 6) |> List.map(i -> {
                let angle = t * 1.2 + Int32.toFloat64(i) * 1.0471975511965976;  // 60° 刻みで周回
                let cx = player#pos#x + orbitR * Vec2.cos(angle);
                let cy = player#pos#y - 2.0 + orbitR * 0.55 * Vec2.sin(angle);  // 楕円軌道(奥行き感)
                { at = { x = cx - dotR, y = cy - dotR },
                  item = Render.circle(dotR, Palette.eyeWhite(), zPlayer() - 5) |> Render.fade(0.7f32) }
            })
        }

    /// PlacedItem の中身だけ半透明にする（置き場所は保つ）。
    def fadePlaced(alpha: Float32, placed: Render.PlacedItem): Render.PlacedItem =
        { item = Render.fade(alpha, placed#item) | placed }

    // ── 演出の粒（土埃・ジャンプ噴射）──

    /// World の bursts から、いまの粒を毎フレーム閉形式で導いて描く。状態は持たない。
    def burstItems(bursts: List[Field.Burst]): List[Render.PlacedItem] =
        bursts |> List.flatMap(burst ->
            GameFx.particles(burst) |> List.map(triple -> {
                let (pos, radius, alpha) = triple;
                { at = { x = pos#x - radius, y = pos#y - radius },
                  item = Render.circle(radius, burstColor(burst), zBurst()) |> Render.fade(alpha) }
            }))

    /// 粒の色。花火だけは発番号（seed）で 4 色を巡回する。
    def burstColor(burst: Field.Burst): Color = match burst#kind {
        case Field.FxKind.DustKind     => Palette.dustPuff()
        case Field.FxKind.JetKind      => Palette.jetPuff()
        case Field.FxKind.FireworkKind => Palette.fireworkColor(burst#seed)
    }

    // ── HUD（運動学の生値と操作の案内）──

    def hudTexts(atlas: FontAtlas, world: Field.World): List[Render.PlacedItem] =
        let player = world#player;
        let status =
            "v=(${fmt(player#vel#x)},${fmt(player#vel#y)})"
            + " grd=${if (player#grounded) "T" else "F"}"
            + " coy=${fmt(player#coyoteLeft * 1000.0)}"
            + " buf=${fmt(player#bufferLeft * 1000.0)}"
            + " deaths=${world#deaths}";
        { at = { x = 6.0, y = 4.0 },
          item = Render.textTinted(status, atlas, 8.0, Palette.hudText(), zText()) } ::
        { at = { x = Field.designW() - 150.0, y = 4.0 },
          item = Render.textTinted(Roster.nameOf(world#charIndex), atlas, 8.0, Palette.hudText(), zText()) } ::
        { at = { x = 6.0, y = Field.designH() - 12.0 },
          item = Render.textTinted("ARROWS move / Z dash / X jump / SHIFT char / F1 reload", atlas, 8.0,
                            Palette.hintText(), zText()) } ::
        clearBanner(atlas, world)

    /// クリア後は画面中央に「CLEAR!」を出し続ける（ゲームは止めない・検証台なので）。
    def clearBanner(atlas: FontAtlas, world: Field.World): List[Render.PlacedItem] =
        if (Option.isEmpty(world#clearedAt)) Nil
        else { at = { x = Field.designW() / 2.0 - 30.0, y = 80.0 },
               item = Render.textTinted("CLEAR!", atlas, 16.0, Palette.hudText(), zText()) } :: Nil

    /// HUD 用に 1 桁小数へ丸める（RemoteDebug の書式を共用）。
    def fmt(v: Float64): String = RemoteDebug.fmt1(v)

    // ── 形の補助 ──

    /// 中心座標とサイズから中心指定の Box を置く（Render.boxAt に委譲）。
    def flatBox(center: Vec2.Vec2, size: Vec2.Vec2, color: Color, z: Int32): Render.PlacedItem =
        Render.boxAt(center, size, color, z)
}
