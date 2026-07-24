// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 背景・パラメータの棒（3 本）・今日のメニュー（Day）・伸びとイベントの見せ物（Reveal）・
// 発表会の結末（Result）・タイトルの幕（Title）を、World を読むだけで（変えずに）絵にする。
// 幾何はここに閉じる。文言は Doc（PlanDoc）から来る — View は UI の構造ラベルだけ固定でよい。
//
// ── z 層（重なり順。大きいほど手前）──
//   背景=0 / パネル=5 / 棒=10 / 文字=20 / メニューのカーソル=25 / きらめき=30 / 幕=40 / 幕の文字=41
//
// View は fail-open: 行動が空でも Doc が既定でも必ず何か描く（プレイヤーの前で白画面にしない）。
mod View {

    // ── z 層 ──
    def zBg(): Int32 = 0
    def zPanel(): Int32 = 5
    def zBar(): Int32 = 10
    def zText(): Int32 = 20
    def zCursor(): Int32 = 25
    def zSpark(): Int32 = 30
    def zOverlay(): Int32 = 40

    // ── レイアウトの寸法（design 320×360 の中の定数）──
    def margin(): Float64 = 16.0                    // 画面の縁の余白
    def barTop(): Float64 = 60.0                    // パラメータ棒の一番上の y
    def barGap(): Float64 = 26.0                    // 棒 1 本ぶんの縦の間隔
    def barHeight(): Float64 = 12.0                 // 棒の高さ
    def barMaxLen(): Float64 = 180.0                // 上限（statCap）まで伸びたときの棒の長さ
    def menuTop(): Float64 = 168.0                  // メニューの一番上の行の y
    def menuGap(): Float64 = 24.0                   // メニュー 1 行ぶんの縦の間隔

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        // Title のあいだは育ちを見せない（まだ 0 なので幕だけが主役）。
        // Day / Reveal / Result では上部にヘッダと 3 本の棒（育ち具合）を常に出す。
        let stage = match w#phase {
            case World.Phase.Title => Nil
            case _ => List.append(header(ctx#atlas, w), statBars(ctx#atlas, w))
        };
        List.flatten(
               background(w#theme)
            :: stage
            :: body(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 背景 ──

    /// 背景（全面塗り）。fail-open の土台（常に何か出る）。
    def background(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
           { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = World.designW(), y = World.designH() }, theme#bg, zBg()) }
        :: Nil

    // ── ヘッダ（何日目 / 残り日数）──

    def header(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        // 見出しラベル（DAY / LEFT）は UI 構造なので固定でよい。数と題は Doc から来る。
        let dayNo = Int32.min(w#day + 1, w#rules#dayCount);   // 1 始まりで見せる（発表会後も上限で止める）
        let left = World.daysLeft(w);
           { at = { x = margin(), y = 20.0 },
             item = Render.textTinted("DAY ${Int32.toString(dayNo)}/${Int32.toString(w#rules#dayCount)}",
                 atlas, 20.0, w#theme#text, zText()) }
        :: { at = { x = margin(), y = 38.0 },
             item = Render.textTinted("LEFT ${Int32.toString(left)}",
                 atlas, 10.0, ThemeDoc.darken(w#theme#text, 0.3), zText()) }
        :: Nil

    // ── パラメータの棒（3 本。長さは値 / statCap に比例）──

    /// 3 本の棒（たいりょく・きあい・わざ）。棒 = 上限までの「土台」+ いまの値の「中身」。
    /// ラベルと数は Doc（PlanDoc.statLabel）と現在値から。棒の色は 3 本で少しずつ変える。
    def statBars(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let cap = Int32.toFloat64(Int32.max(1, w#rules#statCap));   // 0 除算よけ
        let one = (i, label, value, color) -> {
            let y = barTop() + Int32.toFloat64(i) * barGap();
            let ratio = clampF(0.0, 1.0, Int32.toFloat64(value) / cap);
            // 土台（薄いパネル色）→ 中身（値ぶん）→ ラベル → 数、の順で描く。
               { at = { x = margin(), y = y },
                 item = Render.box({ x = barMaxLen(), y = barHeight() }, w#theme#panel, zPanel()) }
            :: Render.boxAt({ x = margin() + (barMaxLen() * ratio) / 2.0, y = y + barHeight() / 2.0 },
                   { x = barMaxLen() * ratio, y = barHeight() }, color, zBar())
            :: { at = { x = margin(), y = y - 12.0 },
                 item = Render.textTinted(label, atlas, 10.0, w#theme#text, zText()) }
            :: { at = { x = margin() + barMaxLen() + 8.0, y = y },
                 item = Render.textTinted(Int32.toString(value), atlas, 10.0, w#theme#text, zText()) }
            :: Nil
        };
        List.flatten(
               one(0, PlanDoc.statLabel(0, w#plan), w#stats#power, ThemeDoc.barColor(0, w#theme))
            :: one(1, PlanDoc.statLabel(1, w#plan), w#stats#spirit, ThemeDoc.barColor(1, w#theme))
            :: one(2, PlanDoc.statLabel(2, w#plan), w#stats#skill, ThemeDoc.barColor(2, w#theme))
            :: Nil)

    // ── 場面ごとの本体（Day のメニュー / Reveal の見せ物）──

    def body(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Day    => menu(atlas, w)
            case World.Phase.Reveal => reveal(atlas, w)
            case _                  => Nil            // Title/Result は overlay が主役
        }

    /// 今日のメニュー。行動を上から並べ、選んでいる行（cursor）にカーソルの帯と説明を出す。
    /// 「選ぶだけ」の UI なので、当たり判定も座標も持たず、ただ番号（cursor）で強調するだけ。
    def menu(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let actions = w#plan#actions;
        let rows = actions |> List.zipWithIndex |> List.flatMap(pair -> {
            let (i, action) = pair;
            let y = menuTop() + Int32.toFloat64(i) * menuGap();
            let selected = i == w#cursor;
            // 選択行だけ帯（cursor 色を薄く敷く）を先に置き、その上に行動名を載せる。
            let band = if (selected)
                { at = { x = margin() - 6.0, y = y - 4.0 },
                  item = Render.box({ x = barMaxLen() + 40.0, y = 20.0 }, w#theme#cursor, zCursor())
                      |> Render.fade(0.35f32) } :: Nil
                else Nil;
            let nameColor = if (selected) w#theme#cursor else w#theme#text;
            List.append(band,
                   { at = { x = margin(), y = y },
                     item = Render.textTinted(action#label, atlas, 10.0, nameColor, zText()) } :: Nil)
        });
        // 選んでいる行動の一言説明（Doc の note）をメニューの下に出す。
        let note = PlanDoc.actionAt(w#cursor, w#plan)#note;
        let hint = { at = { x = margin(), y = menuTop() + Int32.toFloat64(PlanDoc.actionCount(w#plan)) * menuGap() + 6.0 },
                     item = Render.textTinted(note, atlas, 10.0, ThemeDoc.darken(w#theme#text, 0.2), zText()) };
        List.append(rows, hint :: Nil)

    /// 伸びとイベントの見せ物（Reveal）。伸びた値をきらめき（glowAt）とともに出し、
    /// イベントが起きていればその文を添える。数値が育った合図を控えめに凝る場面。
    def reveal(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let g = w#lastGain;
        // 伸びた分を "+n" で 3 行。0 の行も出して「伸びなかった」も分かるようにする。
        let gainLine = (i, label, amount) -> {
            let y = menuTop() + Int32.toFloat64(i) * menuGap();
            { at = { x = margin(), y = y },
              item = Render.textTinted("${label} +${Int32.toString(amount)}", atlas, 10.0, w#theme#text, zText()) }
        };
        // きらめき: 一番大きく伸びたパラメータの棒の右端に光球を 1 つ（伸びた合図）。
        let spark = brightestSpark(w);
        let gains =
               gainLine(0, PlanDoc.statLabel(0, w#plan), g#power)
            :: gainLine(1, PlanDoc.statLabel(1, w#plan), g#spirit)
            :: gainLine(2, PlanDoc.statLabel(2, w#plan), g#skill)
            :: Nil;
        // イベント文（起きたときだけ）。plan の text をそのまま出す。
        let eventLine = match w#lastEvent {
            case Some(ev) =>
                { at = { x = margin(), y = menuTop() + 3.0 * menuGap() + 4.0 },
                  item = Render.textTinted(ev#text, atlas, 10.0, w#theme#spark, zText()) } :: Nil
            case None => Nil
        };
        let prompt = { at = { x = margin(), y = World.designH() - 30.0 },
                       item = Render.textTinted("PRESS SPACE", atlas, 10.0, ThemeDoc.darken(w#theme#text, 0.25), zText()) };
        List.flatten(spark :: gains :: eventLine :: (prompt :: Nil) :: Nil)

    /// 一番大きく伸びたパラメータの棒の右端に、きらめきを 1 つ置く（伸びた合図の演出）。
    /// 伸びが全部 0 なら何も出さない。粒子は自前で書かず Render.glowAt（閉形式で安全）に任せる。
    def brightestSpark(w: World.World): List[Render.PlacedItem] =
        let g = w#lastGain;
        let cap = Int32.toFloat64(Int32.max(1, w#rules#statCap));
        // 3 つの (棒の番号, 伸び, いまの値) から一番伸びた棒を選ぶ。
        let cands = (0, g#power, w#stats#power) :: (1, g#spirit, w#stats#spirit) :: (2, g#skill, w#stats#skill) :: Nil;
        let best = cands |> List.sortBy(t -> { let (_, amount, _) = t; -amount }) |> List.head;
        match best {
            case Some((i, amount, value)) if amount > 0 =>
                let y = barTop() + Int32.toFloat64(i) * barGap() + barHeight() / 2.0;
                let x = margin() + barMaxLen() * clampF(0.0, 1.0, Int32.toFloat64(value) / cap);
                Render.glowAt({ x = x, y = y }, 14.0, w#theme#spark,
                    { alpha = 0.8, blend = DrawCmd.BlendMode.Add }, zSpark())
            case _ => Nil
        }

    // ── 場面ごとの幕（Title / Result）──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title =>
                curtain(w#theme, 0.55f32)
                    :: centered(atlas, w#plan#title, 20.0, w#theme#cursor, 120.0)
                    :: centered(atlas, w#plan#subtitle, 10.0, w#theme#text, 158.0)
                    :: centered(atlas, "UP/DOWN: CHOOSE", 10.0, ThemeDoc.darken(w#theme#text, 0.2), 220.0)
                    :: centered(atlas, "SPACE: DECIDE", 10.0, ThemeDoc.darken(w#theme#text, 0.2), 236.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, w#theme#spark, 280.0)
                    :: Nil
            case World.Phase.Result =>
                let e = World.ending(w);
                let score = PlanDoc.total(w#stats);
                curtain(w#theme, 0.62f32)
                    :: centered(atlas, "RESULT", 10.0, ThemeDoc.darken(w#theme#text, 0.2), 96.0)
                    :: centered(atlas, e#label, 20.0, w#theme#cursor, 130.0)
                    :: centered(atlas, e#text, 10.0, w#theme#text, 178.0)
                    :: centered(atlas, "TOTAL ${Int32.toString(score)}", 10.0, w#theme#spark, 214.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, ThemeDoc.darken(w#theme#text, 0.25), 268.0)
                    :: Nil
            case _ => Nil
        }

    /// 画面全体を暗く覆う幕（幕の上に文字を載せて読みやすくする）。
    def curtain(theme: ThemeDoc.Doc, alpha: Float32): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.designW(), y = World.designH() }, theme#bg, zOverlay())
              |> Render.fade(alpha) }

    /// 画面中央に 1 行のテキストを置く（幅はエンジンが実測して中央へ揃える）。
    def centered(atlas: FontAtlas, s: String, size: Float64, color: Color, y: Float64): Render.PlacedItem =
        TextDraw.centered({ text = s, atlas = atlas, size = size, color = color,
                            z = zOverlay() + 1, centerX = World.designW() / 2.0, y = y })

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
