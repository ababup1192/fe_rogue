// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 流れるコース・ライバル 2 台・自機の車・HUD（順位・周回・スコア）・場面ごとの幕
// （Title/Finish）を、World を読むだけで（変えずに）絵にする。幾何はここに閉じる。
//
// ── この画面の画風（AGENTS.local.md と同じ宣言）──
// 「夜のハイウェイ。遠くは霧に溶け、光っているのはレーン標識と車の灯りだけ」。
//   色は 3 つ: 沈んだ地面 / 濡れたアスファルト / ネオンの黄。
//   やらないこと: 空に星や月を出さない（視線を道から外させない）。
// **これは数ある画風の 1 つでしかない。** 真似してほしいのは「層に分けて、各層に役割を
// 持たせる」組み方の方で、色や効果ではない。別の作り方の例は `.claude/skills/visual-dict`。
//
// ── 画面の層（奥から手前へ。z が大きいほど手前）──
//    0  roadside … 路肩の地面（宣言シェーダーの面。下へ流れる）→ 面に質感・時間が流れる
//    1  road     … 路面のマス（遠い段ほど霧の色に溶かす）      → 面に階調・奥行き
//    2  lane     … レーン標識（手前ほど強く光らせる）           → 主役の道が背景から分離
//    4  speed    … 流れる速度線                                  → 時間が流れている
//   10  rival    … ライバルの車（テールランプが見える）
//   11  flash    … 追い抜きの閃光
//   12  player   … 自機の車（ヘッドライトが前を照らす）        → 主役が背景から分離
//   25  haze     … 上下から画面を締める霧                        → 中央（道）へ視線を寄せる
//   30  hud / 40 overlay
//
// View は fail-open: コースが空でも Doc が既定でも必ず何か描く（プレイヤーの前で白画面にしない）。
mod View {

    // ── z 層 ──
    def zRoadside(): Int32 = 0
    def zRoad(): Int32 = 1
    def zLane(): Int32 = 2
    def zSpeed(): Int32 = 4
    def zRival(): Int32 = 10
    def zFlash(): Int32 = 11         // 自機の下（車を覆い隠さない）
    def zPlayer(): Int32 = 12
    def zHaze(): Int32 = 25
    def zHud(): Int32 = 30
    def zOverlay(): Int32 = 40

    /// 画面上でコース 1 段の高さ（px）。段の数はこれで決まる（World.rowPitch と対の見た目側）。
    def rowScreenH(): Float64 = 30.0

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               roadside(w)
            :: course(w)
            :: speedLines(w)
            :: rivals(w)
            :: passFlash(w)
            :: player(w)
            :: haze(w#theme)
            :: hud(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 0. 路肩（宣言シェーダーの面） ──

    /// 画素ごとの計算で塗る面。単色の四角の代わりで、粗い粒が段になって下へ流れる。
    /// この上に路面マスを重ねるので、道から外れた所は路肩のまま残る（fail-open の土台）。
    /// 何がどう効くかは Doc の note と engine の `docs/shader-doc.md` を参照。
    def roadside(w: World.World): List[Render.PlacedItem] =
        Render.shaderFill(w#shader,
            { position = { x = 0.0, y = 0.0 },
              size = { x = World.designW(), y = World.designH() } },
            w#t, zRoadside()) :: Nil

    // ── 1〜2. コース（路面と標識） ──

    /// 流れるコース。画面を下から上へ段に割り、各段の格子行の路面マスを描く。
    /// 一番下の段が「いまの距離の行」。上の段ほど先（遠く）の行で、遠いほど霧に溶ける。
    def course(w: World.World): List[Render.PlacedItem] =
        let cols = CourseDoc.colCount(w#course);
        let cellW = World.designW() / Int32.toFloat64(cols);
        // 画面を埋めるのに要る段数（下端から上端まで）+ 予備 1 段（スクロールの端数ぶん）。
        let rowsOnScreen = ceilI(World.designH() / rowScreenH()) + 1;
        let baseRow = World.roadRowAt(w#distance);                     // 一番下の段が写す格子行
        let frac = w#distance - Int32.toFloat64(baseRow) * World.rowPitch();
        let scrollY = frac / World.rowPitch() * rowScreenH();          // 行内の端数ぶんのずれ
        List.range(0, rowsOnScreen) |> List.flatMap(seg -> {
            // seg 段目（0 = 一番下）の画面上の帯の上端 y。距離が進むと下へ流れる。
            let bandTop = World.designH() - Int32.toFloat64(seg + 1) * rowScreenH() + scrollY;
            let row = CourseDoc.rowAt(baseRow + seg, w#course);
            // 0 = 足元 / 1 = 画面の一番奥。奥ほど霧に溶かし、標識の光も弱める。
            let far = Num.clamp01(Int32.toFloat64(seg) / Int32.toFloat64(rowsOnScreen - 1));
            let band = { row = row, cols = cols, cellW = cellW, bandTop = bandTop };
            roadCells(w#theme, far, band)
                ::: edgeLines(w#theme, far, band)
                ::: laneMarks(w#theme, far, seg, band)
        })

    /// 1 段ぶんの格子の位置決め（同じ型の値が並ぶので名前で渡す）。
    type alias Band = { row = String, cols = Int32, cellW = Float64, bandTop = Float64 }

    /// 1 段ぶんの路面マス（'#' のマスだけ塗る。路肩はすでに下地にある）。
    /// far（0=足元 / 1=奥）で霧の色へ混ぜるので、平らな路面に奥行きが出る。
    def roadCells(theme: ThemeDoc.Doc, far: Float64, band: Band): List[Render.PlacedItem] =
        let color = Color.mix(theme#road, ThemeDoc.haze(theme), far * 0.7);
        List.range(0, band#cols) |> List.filterMap(c ->
            if (CourseDoc.isRoadCell(band#row, c))
                Some(Render.boxAt(
                    { x = (Int32.toFloat64(c) + 0.5) * band#cellW,
                      y = band#bandTop + rowScreenH() / 2.0 },
                    { x = band#cellW + 1.0, y = rowScreenH() + 1.0 },   // 1px 重ねて目地を消す
                    color, zRoad()))
            else
                None)

    /// 路肩の白線: その段の路面の左端と右端に切れ目なく線を引く。道と地面の境が
    /// 1 本の線でつながるので、マスの階段が「道の縁」に見える（形は変えずに読み方を変える）。
    def edgeLines(theme: ThemeDoc.Doc, far: Float64, band: Band): List[Render.PlacedItem] =
        let roadCols = List.range(0, band#cols) |> List.filter(c -> CourseDoc.isRoadCell(band#row, c));
        let color = Color.mix(ThemeDoc.haze(theme), Color.darken(theme#finish, 0.15), 1.0 - far * 0.8);
        let mark = x -> Render.boxAt({ x = x, y = band#bandTop + rowScreenH() / 2.0 },
                                     { x = 1.5, y = rowScreenH() + 1.0 }, color, zLane());
        match (List.head(roadCols), List.last(roadCols)) {
            case (Some(lo), Some(hi)) =>
                mark(Int32.toFloat64(lo) * band#cellW + 1.0)
                    :: mark(Int32.toFloat64(hi + 1) * band#cellW - 1.0) :: Nil
            case _ => Nil
        }

    /// レーン標識: 路面の真ん中の列に 1 段おきの明るい点を置き、手前ほど強く光らせる
    /// （足元だけ光ると「いまどこを走っているか」が一目で判る）。飾りなのでルールには絡まない。
    def laneMarks(theme: ThemeDoc.Doc, far: Float64, seg: Int32, band: Band): List[Render.PlacedItem] =
        if (Int32.modulo(seg, 2) != 0) Nil     // 1 段おき = 破線
        else {
            let roadCols = List.range(0, band#cols) |> List.filter(c -> CourseDoc.isRoadCell(band#row, c));
            match middleOf(roadCols) {
                case None    => Nil
                case Some(c) =>
                    let at = { x = (Int32.toFloat64(c) + 0.5) * band#cellW,
                               y = band#bandTop + rowScreenH() / 2.0 };
                    let near = 1.0 - far;
                    Render.boxAt(at, { x = 2.0, y = rowScreenH() * 0.5 },
                        Color.mix(ThemeDoc.haze(theme), theme#lane, near), zLane())
                        :: Render.glowAt(at, 5.0 + 5.0 * near, theme#lane,
                               { alpha = 0.30 * near, blend = DrawCmd.BlendMode.Add }, zLane())
            }
        }

    // ── 4. 速度線 ──

    /// 下へ流れる細い光の筋。どこにも保存せず、番号と時刻だけから計算する
    /// （巻き戻しても同じ絵）。走っていない場面では薄くする — 止めはしない。
    def speedLines(w: World.World): List[Render.PlacedItem] =
        let strength = if (World.isRacing(w)) 1.0 else 0.4;
        let span = World.designH() + 80.0;
        Fx.derive(18, w#t, (_i, rand, t) -> {
            let x = rand(0) * World.designW();
            let speed = 200.0 + rand(1) * 320.0;
            let top = Num.wrapTo(span, rand(2) * span + t * speed) - 40.0;
            let len = 12.0 + rand(3) * 26.0;
            Render.lineSeg({ x = x, y = top }, { x = x, y = top + len }, 1.0,
                    Color.lighten(ThemeDoc.haze(w#theme), 0.55), zSpeed())
                |> Render.overItem(item -> item
                    |> Render.fade(Float64.truncateToFloat32(strength * (0.10 + rand(4) * 0.16)))
                    |> Render.blended(DrawCmd.BlendMode.Add))
        })

    // ── 10〜12. ライバル・自機 ──

    /// ライバル 2 台。前方に見える = 自機との距離差（progress - distance）を画面の上向きの
    /// ずれに写す。抜いた（後ろに下がった）ライバルは自機より下（画面外へ）に流れて消える。
    def rivals(w: World.World): List[Render.PlacedItem] =
        let colors = w#theme#rivalA :: w#theme#rivalB :: Nil;
        w#rivals |> List.zipWithIndex |> List.flatMap(entry -> {
            let (i, r) = entry;
            // 前方 lead px = 画面で lead / rowPitch 段ぶん上。自機の足元(playerY)を基準にする。
            let lead = r#progress - w#distance;
            let y = World.playerY() - lead / World.rowPitch() * rowScreenH();
            if (y < -World.carSize() or y > World.designH() + World.carSize())
                Nil                                      // 画面外は描かない
            else {
                let color = List.nth(i, colors) |> Option.getWithDefault(w#theme#rivalA);
                // 前を走る車は「後ろ姿」— こちらから見えるのはテールランプ。
                car({ center = { x = r#laneX, y = y }, color = color,
                      z = zRival(), lamp = Lamp.Tail })
            }
        })

    /// 自機の車（画面下部に固定）。タイトルでも出す — この絵がジャンル札のサムネになるので、
    /// 「夜の道を車が走っている」が一目で伝わる必要がある。
    def player(w: World.World): List[Render.PlacedItem] =
        car({ center = { x = w#playerX, y = World.playerY() },
              color = w#theme#player, z = zPlayer(), lamp = Lamp.Head })

    /// 車の灯りをどちら向きに焚くか。前を照らす（自機）か、後ろに灯る（前を走る車）か。
    enum Lamp with Eq {
        case Head
        case Tail
    }

    /// 車 1 台。上から見た形（前が狭い六角形）+ 窓 + 灯り の 3 枚。
    /// 頂点は中心からの相対で書く（Render.polygon の頂点は置き場所からの相対）。
    /// 箱 1 つで済ませないのは、向き（どちらが前か）が形で判るようにするため。
    def car(spec: { center = Vec2.Vec2, color = Color, z = Int32, lamp = Lamp }): List[Render.PlacedItem] =
        let hw = World.carSize() / 2.0;
        let hh = World.carSize() * 0.65;
        let body =
               { x = -hw * 0.60, y = -hh }        :: { x = hw * 0.60, y = -hh }
            :: { x = hw, y = hh * 0.35 }          :: { x = hw * 0.85, y = hh }
            :: { x = -hw * 0.85, y = hh }         :: { x = -hw, y = hh * 0.35 } :: Nil;
        let (lampAt, lampColor, lampSpread) = match spec#lamp {
            case Lamp.Head => ({ x = spec#center#x, y = spec#center#y - hh },
                               Color.lighten(spec#color, 0.55), 1.05)
            case Lamp.Tail => ({ x = spec#center#x, y = spec#center#y + hh },
                               Color.warm(spec#color, 0.25), 0.8)
        };
           { at = spec#center, item = Render.polygon(body, spec#color, spec#z) }
        :: Render.boxAt({ x = spec#center#x, y = spec#center#y - hh * 0.15 },
               { x = World.carSize() * 0.52, y = World.carSize() * 0.34 },
               Color.cool(Color.darken(spec#color, 0.55), 0.15), spec#z + 1)
        :: Render.glowAt(lampAt, World.carSize() * lampSpread, lampColor,
               { alpha = 0.42, blend = DrawCmd.BlendMode.Add }, spec#z - 1)

    /// 追い抜きの閃光（控えめに凝る）: ライバルを抜いた瞬間、自機の位置に光球（Add ブレンド）を焚く。
    /// passFlash が減るほど薄く小さくなる。粒子は自前で書かず Render.glowAt（閉形式で安全）に任せる。
    def passFlash(w: World.World): List[Render.PlacedItem] =
        if (w#passFlash <= 0.0 or w#phase != World.Phase.Racing) Nil
        else {
            let t = Num.clamp01(w#passFlash / World.flashDuration());
            Render.glowAt({ x = w#playerX, y = World.playerY() }, World.carSize() * (0.7 + 1.1 * t),
                w#theme#lane, { alpha = 0.7 * t, blend = DrawCmd.BlendMode.Add }, zFlash())
        }

    // ── 25. 霧（上下から画面を締める） ──

    /// 上下の縁を暗く落とす帯。中央（走っている道）へ視線が寄り、遠くが霧に消えて見える。
    /// 濃さが縦に変わるので頂点色つきの多角形で 1 枚ずつ描く（1px の帯を積まない）。
    def haze(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let fog = Color.darken(ThemeDoc.haze(theme), 0.45);
        band(fog, { top = 0.0, bottom = 110.0 }, { top = 0.80f32, bottom = 0.0f32 })
            :: band(fog, { top = World.designH() - 70.0, bottom = World.designH() },
                    { top = 0.0f32, bottom = 0.55f32 })
            :: Nil

    /// 上端 span#top から下端 span#bottom へ、濃さが alpha#top → alpha#bottom へ変わる帯。
    def band(color: Color, span: { top = Float64, bottom = Float64 },
             alpha: { top = Float32, bottom = Float32 }): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.gradPolygon(
                 { pos = { x = 0.0, y = span#top },              color = color, alpha = alpha#top }
              :: { pos = { x = World.designW(), y = span#top },   color = color, alpha = alpha#top }
              :: { pos = { x = World.designW(), y = span#bottom },color = color, alpha = alpha#bottom }
              :: { pos = { x = 0.0, y = span#bottom },            color = color, alpha = alpha#bottom }
              :: Nil, zHaze()) }

    // ── 30. HUD（順位・周回・スコア）──

    /// Title では出さない（まだ順位も得点も無い — 意味の無い数を置かない）。
    def hud(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        if (w#phase == World.Phase.Title) Nil else
        // 文言はコードに直書きせず「見出し + 数」を組む。見出しラベルは UI 構造なので固定でよい。
        let lapShow = Int32.min(w#lap + 1, w#rules#totalLaps);       // 1 始まりで見せる（走行中の周）
        let total = w#rules#totalLaps;
        let sub = Color.darken(w#theme#text, 0.2);
           { at = { x = 8.0, y = 6.0 },
             item = Render.textTinted("RANK ${Int32.toString(w#rank)}", atlas, 10.0, w#theme#text, zHud()) }
        :: { at = { x = 8.0, y = 20.0 },
             item = Render.textTinted("LAP ${Int32.toString(lapShow)}/${Int32.toString(total)}",
                 atlas, 9.0, sub, zHud()) }
        :: { at = { x = 8.0, y = 32.0 },
             item = Render.textTinted("SCORE ${Int32.toString(w#score)}", atlas, 9.0, sub, zHud()) }
        :: Nil

    // ── 40. 場面ごとの幕（Title / Finish）──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title =>
                // 題は 1 拍ごとに息をする（待っている画面でも止めない）。
                let pulse = 0.5 + 0.5 * Sway.wave(w#t, 0.0, 0.5);
                curtain(w#theme, 0.38f32)
                    :: centered(atlas, "RACE", 26.0, w#theme#player, 120.0)
                    :: centered(atlas, "ARROWS: STEER", 10.0, w#theme#text, 176.0)
                    :: centered(atlas, "PASS RIVALS", 10.0, w#theme#text, 192.0)
                    :: (centered(atlas, "PRESS SPACE", 11.0,
                            Color.mix(ThemeDoc.haze(w#theme), w#theme#lane, 0.35 + 0.65 * pulse), 240.0))
                    :: Nil
            case World.Phase.Finish =>
                // ゴールの祝い: 幕 + 見出し + ゴールラインの帯（finish 色）を上に敷く。
                curtain(w#theme, 0.5f32)
                    :: finishBanner(w#theme)
                    :: centered(atlas, "FINISH!", 24.0, w#theme#finish, 128.0)
                    :: centered(atlas, "RANK ${Int32.toString(w#rank)}", 12.0, w#theme#text, 168.0)
                    :: centered(atlas, "SCORE ${Int32.toString(w#score)}", 12.0, w#theme#text, 188.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, Color.darken(w#theme#text, 0.25), 224.0)
                    :: Nil
            case World.Phase.Racing => Nil
        }

    /// ゴールの市松帯（画面上部にゴールラインを 1 本）。白帯に市松の穴を開けるだけで
    /// 「ゴール」と読めるようになる（Render.checker が升目を抜く）。演出の飾り。
    def finishBanner(theme: ThemeDoc.Doc): Render.PlacedItem =
        { at = { x = 0.0, y = 96.0 },
          item = Render.box({ x = World.designW(), y = 12.0 }, theme#finish, zOverlay() + 1)
              |> Render.checker({ color = Color.darken(theme#grass, 0.4), alpha = 1.0f32, cell = 6.0 })
              |> Render.fade(0.92f32) }

    /// 画面全体を暗く覆う幕（幕の上に文字を載せて読みやすくする）。
    def curtain(theme: ThemeDoc.Doc, alpha: Float32): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.designW(), y = World.designH() },
                     Color.darken(theme#grass, 0.35), zOverlay())
              |> Render.fade(alpha) }

    /// 画面中央に 1 行のテキストを置く（幅はエンジンが実測して中央へ揃える）。
    def centered(atlas: FontAtlas, s: String, size: Float64, color: Color, y: Float64): Render.PlacedItem =
        TextDraw.centered({ text = s, atlas = atlas, size = size, color = color,
                            z = zOverlay() + 2, centerX = World.designW() / 2.0, y = y })

    /// 切り上げの Int32（段数の見積もり用。非負前提）。
    def ceilI(x: Float64): Int32 =
        Float64.ceil(x) |> Float64.tryToInt32 |> Option.getWithDefault(12)

    /// 昇順リストの中央要素（標識を置く路面マスの列決め）。
    def middleOf(xs: List[Int32]): Option[Int32] =
        let n = List.length(xs);
        if (n == 0) None else List.nth(n / 2, xs)
}
