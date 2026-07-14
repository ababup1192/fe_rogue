// View — Board から「描くべきものリスト」への投影。ここには状態は何もない:
// すべての位置、バッジ、時計の針、紙吹雪の切れ端は、渡された Board の純粋な関数
// である。Board 自身の絵に関するフィールド（slide、undoFx）はここで読まれてピク
// セルへ変換されるだけで、決して書き換えられない。
//
// 色は Palette（DB32 のロール名）からのみ来る；このファイルには色リテラルを持た
// ない。ここにある生の数値は設計値 —— 描画のサイズや比率 —— であり、色だけを扱う
// Palette ではなく、ここに名前付き定数として置く。

mod View {

    // ── レイアウト、design px 単位（解像度 320x240）──
    // ボードはタイトル行を避けるため、中央よりやや下に配置される。
    def centerX(): Float64 = 160.0
    def boardCenterY(): Float64 = 132.0

    /// ボード1マスの画面上のサイズ、design px 単位。
    def tile(): Float64 = 24.0

    // 描画レイヤー、下から上へ。
    def zBadge(): Int32 = 10
    def zClock(): Int32 = 50
    def zConfetti(): Int32 = 95
    def zTitle(): Int32 = 100

    /// 1回転、およびその半分、ラジアン単位。
    def tau(): Float64 = 6.283185307179586
    def pi(): Float64 = 3.141592653589793

    // ── compose: App の view スロット —— 盤面と UI ページを 1 本のリストへ ──

    /// Session 全体を「(置き場所, 見せたい物) のリスト」へ投影する。盤面の絵
    /// （frame）と UI ページ（Title / Clear パネル）を 1 本のリストに合成して
    /// 返すだけで、描画命令への変換は App が引き受ける。
    pub def compose(atlas: FontAtlas, s: Sokoban.Session): List[Render.PlacedItem] =
        List.append(
            frame(atlas, Worldline.current(s#line)),
            UiRender.itemsWith(_ -> atlas, _ -> None, s#ui, GameUi.designSize()))

    // ── frame: World を「描くべきものリスト」へ投影する ──
    // 挿入順がボードを層にする: 床と壁、次にゴールの印、次にクレート、次にロボッ
    // ト、次にゴール到達バッジとテキスト、最後に多角形（ブレース・時計の針・紙吹
    // 雪）。タイトルページではここでは何も描かない: そこにあるすべては UI Spec
    // （GameUi 参照）であり、compose が UI store から合成する。
    pub def frame(atlas: FontAtlas, w: Board.World): List[Render.PlacedItem] =
        let Board.World.World(b) = w;
        if (b#screen == Board.Screen.Title) Nil
        else
            List.flatten(
                boardTiles(b) ::
                goalMarks(b) ::
                crateBoxes(b) ::
                Robot.parts(robotDrawCenter(b), tile(), drawnFacing(b), b#walkPhase) ::
                onGoalBadges(b) ::
                clockBoxes(b) ::
                texts(atlas) ::
                cratePolys(b) ::
                clockNeedle(b) ::
                confettiQuads(b) :: Nil)

    // ── ボードの幾何: セルから画面座標へ ──

    /// ボードの左上隅。グリッド全体が中央に来るよう選ばれる。
    def origin(b: Board.Board): Vec2.Vec2 =
        { x = centerX() - Int32.toFloat64(b#cols) * tile() / 2.0,
          y = boardCenterY() - Int32.toFloat64(b#rows) * tile() / 2.0 }

    /// あるセルの画面上の中心: グリッド内での中心（Grid）を、このボードの左上が
    /// 位置する場所（origin）だけずらしたもの。グリッドの計算は共有され、ボード
    /// の配置だけが自前である。
    def cellCenter(b: Board.Board, p: (Int32, Int32)): Vec2.Vec2 =
        Vec2.add(origin(b), Grid.cellCenter(tile(), p))

    def cells(b: Board.Board): List[(Int32, Int32)] =
        List.flatMap(y -> List.map(x -> (x, y), List.range(0, b#cols)), List.range(0, b#rows))

    def lerp(a: Vec2.Vec2, z: Vec2.Vec2, t: Float64): Vec2.Vec2 =
        { x = a#x + (z#x - a#x) * t, y = a#y + (z#y - a#y) * t }

    // ── タイル: 床、壁、ゴールの印 ──

    /// 壁ブロックの明るい上端と影の付いた足元のベベルの高さ（マスに対する割合）。
    def wallBevelFactor(): Float64 = 0.16
    /// ゴールマーカーの半径、マスに対する割合。
    def goalMarkRadiusFactor(): Float64 = 0.34
    /// ゴール到達バッジの半径（落ち着いたクレートの上に描かれる、より小さい印）。
    def goalBadgeRadiusFactor(): Float64 = 0.25

    def boardTiles(b: Board.Board): List[Render.PlacedItem] =
        List.flatMap(p ->
            if (Set.memberOf(p, b#walls)) wallTile(cellCenter(b, p))
            else floorTile(cellCenter(b, p)),
            cells(b))

    /// 床: 1マスにつき1つのフラットなボックス；ボードは周囲の暗いクリア色の上に
    /// 明るい領域として読める。
    def floorTile(c: Vec2.Vec2): List[Render.PlacedItem] =
        let t = tile();
        boxAt({ x = c#x - t / 2.0, y = c#y - t / 2.0, w = t, h = t }, Palette.floorTile(), 0) :: Nil

    /// 壁: 石のブロック —— 明るい上端と影の付いた足元を持つフラットな面。
    def wallTile(c: Vec2.Vec2): List[Render.PlacedItem] =
        let t = tile();
        let x0 = c#x - t / 2.0;
        let y0 = c#y - t / 2.0;
        let bevel = t * wallBevelFactor();
        boxAt({ x = x0, y = y0, w = t, h = t }, Palette.wallFace(), 0) ::
        boxAt({ x = x0, y = y0, w = t, h = bevel }, Palette.wallTop(), 1) ::
        boxAt({ x = x0, y = y0 + t - bevel, w = t, h = bevel }, Palette.wallShade(), 1) :: Nil

    /// ゴール: 床の上の小さな丸い印（クレートとロボットがその上に描かれる）。
    def goalMarks(b: Board.Board): List[Render.PlacedItem] =
        List.map(p -> circleAt(cellCenter(b, p), tile() * goalMarkRadiusFactor(), Palette.goalMark(), 0),
                 Set.toList(b#goals))

    /// ゴールに置かれた（あるいは滑り込みつつある）クレートには上に小さなバッジ
    /// が付く: ゴールが応答する。
    def onGoalBadges(b: Board.Board): List[Render.PlacedItem] =
        List.map(p -> circleAt(crateCenter(b, p), tile() * goalBadgeRadiusFactor(), Palette.goalMark(), zBadge()),
                 Set.toList(Set.intersection(b#crates, b#goals)))

    // ── ロボット: どこに、どの向きで描かれるか ──

    /// 前方への押しで絵全体がこのピクセル数だけ下がる —— クレートにかかる重み。
    def pushSinkPx(): Float64 = 1.0

    /// ロボットが描かれる場所: そのセル —— あるいは1つ前のセルから途中まで。
    def robotCenter(b: Board.Board): Vec2.Vec2 =
        match b#slide {
            case None    => cellCenter(b, b#robot)
            case Some(s) => lerp(cellCenter(b, s#fromCell), cellCenter(b, b#robot), s#t)
        }

    /// ロボットは自分の作業に体重をかける: 前方への押しが滑っている間、絵全体が
    /// pushSinkPx だけ下に沈む —— クレートにかかる重み、それ以上でもそれ以下でも
    /// ない。
    def robotDrawCenter(b: Board.Board): Vec2.Vec2 =
        let c = robotCenter(b);
        { x = c#x, y = c#y + pushSink(b) }

    def pushSink(b: Board.Board): Float64 =
        match b#slide {
            case Some(s) => if (s#pushing and not s#reverse) pushSinkPx() else 0.0
            case None    => 0.0
        }

    /// 絵がまとう向き。巻き戻しスライドは巻き戻される手の向きを示す —— その手は
    /// 復元されたセルから fromCell へ向かって進んだので、その線がその向きを名付
    /// ける —— そしてスライドが着地したときにだけ、（すでに Board に入っている）
    /// スナップショット自身の向きが引き継ぐ。
    pub def drawnFacing(b: Board.Board): Dir4.Dir4 =
        match b#slide {
            case Some(s) => if (s#reverse) Board.directionTo(b#robot, s#fromCell) else b#facing
            case None    => b#facing
        }

    // ── クレート: 押されている1つはロボットのスライドに乗る ──

    /// 押しが前方に滑っている間、押されているクレートはロボットの行き先の1マス
    /// 先、ロボットが来た方向に沿って位置する。
    def slidingCrate(b: Board.Board, s: Board.Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * rx - fx, 2 * ry - fy)

    /// 押しが巻き戻されている間、戻ってくるクレートは押しの後にロボットが立って
    /// いた場所（s#fromCell）に今は静止している —— そしてその絵はそこからさらに
    /// 1マス外側から家路につく。
    def crateReturnStart(b: Board.Board, s: Board.Slide): (Int32, Int32) =
        let (fx, fy) = s#fromCell;
        let (rx, ry) = b#robot;
        (2 * fx - rx, 2 * fy - ry)

    /// クレートが描かれる場所: そのセル —— ただし押されている（あるいは押し戻さ
    /// れている）クレートの場合はロボットと歩調を合わせて前方または後方へ移動す
    /// る: 同じスライドの、映像を逆にしたもの。
    def crateCenter(b: Board.Board, p: (Int32, Int32)): Vec2.Vec2 =
        match b#slide {
            case Some(s) =>
                if (s#pushing and not s#reverse and p == slidingCrate(b, s))
                    lerp(cellCenter(b, b#robot), cellCenter(b, p), settle(s#t))
                else if (s#pushing and s#reverse and p == s#fromCell)
                    lerp(cellCenter(b, crateReturnStart(b, s)), cellCenter(b, p), s#t)
                else cellCenter(b, p)
            case None => cellCenter(b, p)
        }

    /// 押されているクレートはロボットの線形スライドに最後の区間まで乗り、そこで
    /// 目標を overshootHeight だけ飛び越えてから、ちょうど 1 で落ち着く。
    def settleOvershootStart(): Float64 = 0.8
    def settleOvershootHeight(): Float64 = 0.06

    pub def settle(t: Float64): Float64 =
        let start = settleOvershootStart();
        if (t < start) t
        else t + settleOvershootHeight() * RenderUtil.sinF(pi() * (t - start) / (1.0 - start))

    def crateBoxes(b: Board.Board): List[Render.PlacedItem] =
        List.flatMap(p -> Crate.boxes(crateCenter(b, p), tile()), Set.toList(b#crates))

    def cratePolys(b: Board.Board): List[Render.PlacedItem] =
        List.flatMap(p -> Crate.polys(crateCenter(b, p), tile()), Set.toList(b#crates))

    // ── 巻き戻し時計: ロボットの頭上のアラーム時計 ──
    // すべてが導出される: 位置はロボットに追従し（ジャンプも含めて）、針の角度は
    // spin から来て、全体は linger と共にフェードする。ルールには一切触れず、記
    // 録もされない。

    /// 文字盤がロボットの頭上に浮かぶ高さ、マス単位。
    def clockRiseTiles(): Float64 = 0.95
    /// 文字盤の直径、マスに対する割合。
    def clockDiameterFactor(): Float64 = 0.8
    /// 白い文字盤面が暗い縁の内側にどれだけ引っ込んでいるか、ピクセル単位。
    def clockRimThickness(): Float64 = 3.0
    // 上部のアラームボタン、すべて文字盤の直径 d に対する割合。
    def clockButtonHalfWidth(): Float64 = 0.1
    def clockButtonRise(): Float64 = 0.12
    def clockButtonWidth(): Float64 = 0.2
    def clockButtonHeight(): Float64 = 0.14
    // 針、ピクセル単位: 文字盤の端手前でどれだけ届くか（先端のインセット）、
    // 中心の後ろのカウンターウェイト（尾）、そして半分の太さ。
    def needleTipInset(): Float64 = 1.2
    def needleTailReach(): Float64 = 1.5
    def needleHalfWidth(): Float64 = 0.7

    def clockDiameter(): Float64 = tile() * clockDiameterFactor()

    def clockCenter(b: Board.Board): Vec2.Vec2 =
        let r = robotCenter(b);
        { x = r#x, y = r#y - tile() * clockRiseTiles() }

    def clockAlpha(f: Board.UndoFx): Float32 =
        RenderUtil.f32(1.0 - f#linger / Board.clockLinger())

    /// 文字盤: 暗い外側の円（縁）、白い内側の円（面）、そして上部の小さな四角い
    /// アラームボタン。
    def clockBoxes(b: Board.Board): List[Render.PlacedItem] =
        match b#undoFx {
            case None    => Nil
            case Some(f) =>
                let c = clockCenter(b);
                let d = clockDiameter();
                let a = clockAlpha(f);
                let button = { x = c#x - d * clockButtonHalfWidth(),
                               y = c#y - d / 2.0 - d * clockButtonRise() };
                let buttonSize = { x = d * clockButtonWidth(), y = d * clockButtonHeight() };
                fxBox(button, buttonSize, Palette.clockRim(), a, zClock()) ::
                fxCircle(c, d, Palette.clockRim(), a, zClock()) ::
                fxCircle(c, d - clockRimThickness(), Palette.clockFace(), a, zClock() + 1) :: Nil
        }

    /// 与えられた spin に対する針の角度（ラジアン）—— 純粋な導出: 巻き戻された
    /// 1手につき反時計回りに1回転。
    pub def needleAngle(spin: Float64): Float64 = spin * tau()

    /// 針: 中心のすぐ後ろから文字盤の縁まで伸びる細いクアッド。（反時計回りに回
    /// る）針の角度に沿って向く。頂点は画面の絶対座標なので、置き場所は原点。
    def clockNeedle(b: Board.Board): List[Render.PlacedItem] =
        match b#undoFx {
            case None    => Nil
            case Some(f) =>
                let c = clockCenter(b);
                let angle = needleAngle(f#spin);
                // 画面上で12時の位置を反時計回りに回す（y は下向き）。
                let dir = { x = -RenderUtil.sinF(angle), y = -RenderUtil.cosF(angle) };
                let reach = (clockDiameter() - clockRimThickness()) / 2.0 - needleTipInset();
                let tail = Vec2.sub(c, Vec2.mul(dir, needleTailReach()));
                let tip = Vec2.add(c, Vec2.mul(dir, reach));
                { at = Vec2.zero(),
                  item = Render.polygon(Quad.strip(tail, tip, -needleHalfWidth(), needleHalfWidth()),
                                Palette.clockRim(), zClock() + 2)
                    |> Render.fade(clockAlpha(f)) } :: Nil
        }

    // ── 紙吹雪: パーティクルシステムなしの雨 ──
    // どの粒子もどこにも保存されない。各切れ端の位置、回転、色は（そのインデック
    // ス、ボードが解かれてからの秒数）の純粋な関数である: 雨全体は World の1つの
    // 数値、clearElapsed からの導出にすぎない。Fx.derive が切れ端たちを展開し、
    // それぞれに自分専用の trait タップを渡す；Curve が時間を落下、揺れ、回転に
    // 変換する。生成も更新も解放も必要ない —— 画面を離れることは、単に問うのを
    // やめることに等しい。

    def confettiCount(): Int32 = 48
    /// 1つの切れ端が上に巻き戻る前に落ちる縦方向の距離（px）。
    def confettiFallSpan(): Float64 = 260.0
    /// 切れ端は上端のこれだけ上（px）から入るので、見えない状態で現れる。
    def confettiSpawnAbove(): Float64 = 10.0
    /// 横方向の広がり（px）: デザイン幅そのままなので、切れ端は画面のどこからで
    /// も始まる。
    def confettiSpreadWidth(): Float64 = 320.0
    // 落下速度（px/秒）: 各切れ端が [min, min+span] から自分の値を引く。
    def confettiFallSpeedMin(): Float64 = 55.0
    def confettiFallSpeedSpan(): Float64 = 50.0
    // 水平方向のサイン波の半幅（px）、切れ端ごとに、およびそのレート（Hz）。
    def confettiSwayMin(): Float64 = 6.0
    def confettiSwaySpan(): Float64 = 10.0
    def confettiSwayRate(): Float64 = 1.5
    // 回転レート（回転/秒）、切れ端ごとに引かれ、左右のどちらかに反転する。
    def confettiSpinMin(): Float64 = 2.0
    def confettiSpinSpan(): Float64 = 4.0
    // 1枚の紙切れは、この半幅・半高さ（px）で回転したクアッドである。
    def confettiPieceHalfWidth(): Float64 = 2.2
    def confettiPieceHalfHeight(): Float64 = 1.4

    /// 切れ端 i、パーティの t 秒目。各特性は自分専用の乱数チャンネルから引かれ
    /// る: 自分の速さで落ち、自分のサイン波で揺れ、自分のレートで回転する。イン
    /// デックス i そのものが色を決める（5つのロールをラウンドロビンで配る）。
    /// 切れ端ごとに保存されるものは何もない —— 雨全体が導出される。
    def confettiPiece(i: Int32, rand: Int32 -> Float64, t: Float64): Render.PlacedItem =
        let fallSpan = confettiFallSpan();
        let fallSpeed = confettiFallSpeedMin() + confettiFallSpeedSpan() * rand(1);
        let sway = confettiSwayMin() + confettiSwaySpan() * rand(2);
        let phase = tau() * rand(3);
        let spinRate = (confettiSpinMin() + confettiSpinSpan() * rand(4)) * (if (rand(5) < 0.5) -1.0 else 1.0);
        let x = confettiSpreadWidth() * rand(6) + Curve.sine(sway, confettiSwayRate(), phase, t);
        let y = Curve.loop(fallSpeed, fallSpan, t + fallSpan * rand(7) / fallSpeed) - confettiSpawnAbove();
        let angle = Curve.spin(spinRate, t) + phase;
        { at = Vec2.zero(),
          item = Render.polygon(Quad.rotated({ x = x, y = y }, confettiPieceHalfWidth(), confettiPieceHalfHeight(), angle),
                        Palette.confetti(i), zConfetti()) }

    /// 雨全体: パーティの時計が動いている間、インデックスごとに1つのクアッド。
    pub def confettiQuads(b: Board.Board): List[Render.PlacedItem] =
        if (b#clearElapsed <= 0.0) Nil
        else Fx.derive(confettiCount(), b#clearElapsed, confettiPiece)

    // ── テキスト ──

    /// ゲーム内のヘッダー。CLEAR パネルは今や UI Spec（assets/Clear.ui.json）で
    /// ある；ボードはタイトル行だけを保持する。
    def texts(atlas: FontAtlas): List[Render.PlacedItem] =
        TextDraw.centered({ text = "Sokoban", atlas = atlas, size = 28.0, color = Palette.titleText(),
                            z = zTitle(), centerX = centerX(), y = 10.0 }) :: Nil

    // ── 描画プリミティブ ──

    /// 塗りつぶし矩形: 左上 (x, y)、サイズ (w, h)、レイヤー z。
    def boxAt(rect: { x = Float64, y = Float64, w = Float64, h = Float64 },
              c: Color, z: Int32): Render.PlacedItem =
        { at = { x = rect#x, y = rect#y }, item = Render.box({ x = rect#w, y = rect#h }, c, z) }

    /// c を中心とする直径 d の塗りつぶし円。
    def circleAt(c: Vec2.Vec2, d: Float64, color: Color, z: Int32): Render.PlacedItem =
        Render.circleAt(c, d / 2.0, color, z)

    /// 半透明の塗りつぶしボックス（時計のパーツは alpha でフェードする）。
    def fxBox(pos: Vec2.Vec2, size: Vec2.Vec2, c: Color, a: Float32,
              z: Int32): Render.PlacedItem =
        { at = pos, item = Render.box(size, c, z) |> Render.fade(a) }

    /// 直径 d の半透明の塗りつぶし円（時計の縁と面）。
    def fxCircle(center: Vec2.Vec2, d: Float64, c: Color, a: Float32,
                 z: Int32): Render.PlacedItem =
        { at = {x = center#x - d / 2.0, y = center#y - d / 2.0},
          item = Render.circle(d / 2.0, c, z) |> Render.fade(a) }
}
