// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 流れるコース（草の土台 → 路面のマス → レーンの破線）・ライバル 2 台・自機の車・
// HUD（順位・周回・スコア）・場面ごとの幕（Title/Finish）を、World を読むだけで（変えずに）
// 絵にする。幾何はここに閉じる。
//
// ── z 層（重なり順。大きいほど手前）──
//   草=0 / 路面=1 / レーン線=2 / ライバル=10 / 自機=12 / 追い抜きの閃光=15 / HUD=30 / overlay=40
//
// ── コースの描き方（縦スクロール）──
//   コースは格子（CourseDoc.rows）。画面を下から上へ rowScreenH 刻みの「段」に割り、
//   各段に「いまの距離 + その段ぶん先」の格子行を写して路面マスを描く。距離が rowPitch
//   進むごとに段が 1 つ繰り上がるので、行内の端数（distance mod rowPitch）ぶん縦にずらすと
//   道が滑らかに下へ流れて見える。
//
// View は fail-open: コースが空でも Doc が既定でも必ず何か描く（プレイヤーの前で白画面にしない）。
mod View {

    // ── z 層 ──
    def zGrass(): Int32 = 0
    def zRoad(): Int32 = 1
    def zLane(): Int32 = 2
    def zRival(): Int32 = 10
    def zFlash(): Int32 = 11         // 自機の下（車を覆い隠さない）
    def zPlayer(): Int32 = 12
    def zHud(): Int32 = 30
    def zOverlay(): Int32 = 40

    /// 画面上でコース 1 段の高さ（px）。段の数はこれで決まる（World.rowPitch と対の見た目側）。
    def rowScreenH(): Float64 = 30.0

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               grass(w#theme)
            :: course(w)
            :: rivals(w)
            :: passFlash(w)
            :: player(w)
            :: hud(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 草の土台・コース ──

    /// 道の外（草）の全面塗り。この上に路面マスを重ねるので、道から外れた所は草のまま残る。
    /// fail-open の土台（常に何か出る）。
    def grass(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
           { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = World.designW(), y = World.designH() }, theme#grass, zGrass()) }
        :: Nil

    /// 流れるコース。画面を下から上へ段に割り、各段の格子行の路面マスを箱で描く。
    /// 一番下の段が「いまの距離の行」。上の段ほど先（遠く）の行。
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
            roadCells(w#theme, row, cols, cellW, bandTop) ::: laneMarks(w#theme, row, cols, cellW, bandTop, seg)
        })

    /// 1 段ぶんの路面マス（'#' のマスだけ箱で塗る。草はすでに下地にある）。
    def roadCells(theme: ThemeDoc.Doc, row: String, cols: Int32, cellW: Float64, bandTop: Float64): List[Render.PlacedItem] =
        List.range(0, cols) |> List.filterMap(c ->
            if (CourseDoc.isRoadCell(row, c))
                Some(Render.boxAt(
                    { x = (Int32.toFloat64(c) + 0.5) * cellW, y = bandTop + rowScreenH() / 2.0 },
                    { x = cellW + 1.0, y = rowScreenH() + 1.0 },   // 1px 重ねて目地を消す
                    theme#road, zRoad()))
            else
                None)

    /// レーンの破線: 路面の中央あたりのマスに、1 段おきに小さな明色の点を置く（走る目安）。
    /// 破線は「その段の路面マスの真ん中の列」に置く（カーブに追随する）。飾りなのでルールには絡まない。
    def laneMarks(theme: ThemeDoc.Doc, row: String, cols: Int32, cellW: Float64, bandTop: Float64, seg: Int32): List[Render.PlacedItem] =
        if (Int32.modulo(seg, 2) != 0) Nil     // 1 段おき = 破線
        else {
            let roadCols = List.range(0, cols) |> List.filter(c -> CourseDoc.isRoadCell(row, c));
            match middleOf(roadCols) {
                case None    => Nil
                case Some(c) =>
                    Render.boxAt(
                        { x = (Int32.toFloat64(c) + 0.5) * cellW, y = bandTop + rowScreenH() / 2.0 },
                        { x = 2.0, y = rowScreenH() * 0.5 },
                        theme#lane, zLane()) :: Nil
            }
        }

    // ── ライバル・自機 ──

    /// ライバル 2 台。前方に見える = 自機との距離差（progress - distance）を画面の上向きの
    /// ずれに写す。抜いた（後ろに下がった）ライバルは自機より下（画面外へ）に流れて消える。
    def rivals(w: World.World): List[Render.PlacedItem] =
        if (w#phase == World.Phase.Title) Nil        // Title は幕が主役 — 車は出さない
        else {
        let colors = w#theme#rivalA :: w#theme#rivalB :: Nil;
        w#rivals |> List.zipWithIndex |> List.filterMap(entry -> {
            let (i, r) = entry;
            // 前方 lead px = 画面で lead / rowPitch 段ぶん上。自機の足元(playerY)を基準にする。
            let lead = r#progress - w#distance;
            let y = World.playerY() - lead / World.rowPitch() * rowScreenH();
            if (y < -World.carSize() or y > World.designH() + World.carSize())
                None                                     // 画面外は描かない
            else {
                let color = List.nth(i, colors) |> Option.getWithDefault(w#theme#rivalA);
                Some(car({ x = r#laneX, y = y }, color, zRival()))
            }
        })
        }

    /// 追い抜きの閃光（控えめに凝る）: ライバルを抜いた瞬間、自機の位置に光球（Add ブレンド）を焚く。
    /// passFlash が減るほど薄く小さくなる。粒子は自前で書かず Render.glowAt（閉形式で安全）に任せる。
    /// glowAt は engine の Render の高抽象 API（同心円で減衰カーブを組む）— 詳細は engine の docs/module-index.md。
    def passFlash(w: World.World): List[Render.PlacedItem] =
        if (w#passFlash <= 0.0 or w#phase != World.Phase.Racing) Nil
        else {
            let t = clampF(0.0, 1.0, w#passFlash / World.flashDuration());
            Render.glowAt({ x = w#playerX, y = World.playerY() }, World.carSize() * (0.7 + 1.1 * t),
                w#theme#lane, { alpha = 0.7 * t, blend = DrawCmd.BlendMode.Add }, zFlash())
        }

    /// 自機の車（Title 以外で画面下部に出す。Title は幕が主役なので車は出さない）。
    def player(w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title => Nil
            case _ => car({ x = w#playerX, y = World.playerY() }, w#theme#player, zPlayer()) :: Nil
        }

    /// 車 1 台の見た目（上から見た縦長の箱）。1 台 = 1 箱に保って初学者が読みやすくする。
    def car(center: Vec2.Vec2, color: Color, z: Int32): Render.PlacedItem =
        let s = World.carSize();
        Render.boxAt(center, { x = s, y = s * 1.3 }, color, z)

    // ── HUD（順位・周回・スコア）──

    def hud(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        // 文言はコードに直書きせず「見出し + 数」を組む。見出しラベルは UI 構造なので固定でよい。
        let lapShow = Int32.min(w#lap + 1, w#rules#totalLaps);       // 1 始まりで見せる（走行中の周）
        let total = w#rules#totalLaps;
           { at = { x = 8.0, y = 6.0 },
             item = Render.textTinted("RANK ${Int32.toString(w#rank)}", atlas, 10.0, w#theme#text, zHud()) }
        :: { at = { x = 8.0, y = 20.0 },
             item = Render.textTinted("LAP ${Int32.toString(lapShow)}/${Int32.toString(total)}",
                 atlas, 9.0, ThemeDoc.darken(w#theme#text, 0.2), zHud()) }
        :: { at = { x = 8.0, y = 32.0 },
             item = Render.textTinted("SCORE ${Int32.toString(w#score)}",
                 atlas, 9.0, ThemeDoc.darken(w#theme#text, 0.2), zHud()) }
        :: Nil

    // ── 場面ごとの幕（Title / Finish）──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title =>
                curtain(w#theme, 0.55f32)
                    :: centered(atlas, "RACE", 26.0, w#theme#player, 120.0)
                    :: centered(atlas, "ARROWS: STEER", 10.0, w#theme#text, 176.0)
                    :: centered(atlas, "PASS RIVALS", 10.0, w#theme#text, 192.0)
                    :: centered(atlas, "PRESS SPACE", 11.0, w#theme#lane, 240.0)
                    :: Nil
            case World.Phase.Finish =>
                // ゴールの祝い: 幕 + 見出し + ゴールラインの帯（finish 色）を上に敷く。
                curtain(w#theme, 0.6f32)
                    :: finishBanner(w#theme)
                    :: centered(atlas, "FINISH!", 24.0, w#theme#finish, 128.0)
                    :: centered(atlas, "RANK ${Int32.toString(w#rank)}", 12.0, w#theme#text, 168.0)
                    :: centered(atlas, "SCORE ${Int32.toString(w#score)}", 12.0, w#theme#text, 188.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, ThemeDoc.darken(w#theme#text, 0.25), 224.0)
                    :: Nil
            case World.Phase.Racing => Nil
        }

    /// ゴールの市松帯（画面上部にゴールラインらしい白帯を 1 本）。演出の飾り。
    def finishBanner(theme: ThemeDoc.Doc): Render.PlacedItem =
        { at = { x = 0.0, y = 96.0 },
          item = Render.box({ x = World.designW(), y = 10.0 }, theme#finish, zOverlay() + 1)
              |> Render.fade(0.85f32) }

    /// 画面全体を暗く覆う幕（幕の上に文字を載せて読みやすくする）。
    def curtain(theme: ThemeDoc.Doc, alpha: Float32): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.designW(), y = World.designH() }, theme#grass, zOverlay())
              |> Render.fade(alpha) }

    /// 画面中央に 1 行のテキストを置く（幅はエンジンが実測して中央へ揃える）。
    def centered(atlas: FontAtlas, s: String, size: Float64, color: Color, y: Float64): Render.PlacedItem =
        TextDraw.centered({ text = s, atlas = atlas, size = size, color = color,
                            z = zOverlay() + 2, centerX = World.designW() / 2.0, y = y })

    /// 切り上げの Int32（段数の見積もり用。非負前提）。
    def ceilI(x: Float64): Int32 =
        Float64.ceil(x) |> Float64.tryToInt32 |> Option.getWithDefault(12)

    /// 昇順リストの中央要素（破線を置く路面マスの列決め）。
    def middleOf(xs: List[Int32]): Option[Int32] =
        let n = List.length(xs);
        if (n == 0) None else List.nth(n / 2, xs)

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
