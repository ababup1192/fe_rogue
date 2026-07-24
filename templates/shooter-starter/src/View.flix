// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 宇宙の背景・星・自機・弾・敵・撃破の爆発・スコア・場面ごとの幕（Title/Clear/GameOver）を、
// World を読むだけで（変えずに）絵にする。幾何はここに閉じる。
//
// ── z 層（重なり順。大きいほど手前）──
//   space=0 / 星=1 / 弾=10 / 敵=11 / 爆発=20 / 自機=25 / HUD=30 / overlay=40
//
// View は fail-open: 敵が空でも Doc が既定でも必ず何かを描く（プレイヤーの前で白画面にしない）。
mod View {

    // ── z 層 ──
    def zSpace(): Int32 = 0
    def zStar(): Int32 = 1
    def zBullet(): Int32 = 10
    def zEnemy(): Int32 = 11
    def zBoom(): Int32 = 20
    def zPlayer(): Int32 = 25
    def zHud(): Int32 = 30
    def zOverlay(): Int32 = 40

    // ── 見た目の寸法（project.json の design 240×360 と対）──
    def bulletSize(): Float64 = 4.0                 // 弾の 1 辺
    def playerSize(): Float64 = 16.0                // 自機の 1 辺（当たり判定は enemyStep 由来で別）

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               background(w#theme)
            :: stars(w)
            :: bullets(w)
            :: enemies(w)
            :: booms(w)
            :: player(w)
            :: hud(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 背景・星 ──

    /// 宇宙の背景（全面塗り）。fail-open の土台（常に何か出る）。
    def background(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
           { at = { x = 0.0, y = 0.0 },
             item = Render.box({ x = World.designW(), y = World.designH() }, theme#space, zSpace()) }
        :: Nil

    /// 流れる星（小さな点）。宇宙を進んでいる感じを出すだけの飾り。
    def stars(w: World.World): List[Render.PlacedItem] =
        w#stars |> List.map(s ->
            Render.boxAt({ x = s#x, y = s#y }, { x = 1.5, y = 1.5 }, w#theme#star, zStar()))

    // ── 弾・敵・自機 ──

    /// 飛んでいる弾（縦長の小さな箱）。
    def bullets(w: World.World): List[Render.PlacedItem] =
        w#bullets |> List.map(b ->
            Render.boxAt({ x = b#x, y = b#y }, { x = bulletSize(), y = bulletSize() * 2.0 },
                w#theme#bullet, zBullet()))

    /// 生きている敵（それぞれの位置に enemyStep 大の箱）。撃破済みは booms が描く。
    def enemies(w: World.World): List[Render.PlacedItem] =
        let s = w#rules#enemyStep;
        w#enemies |> List.filterMap(e ->
            if (e#alive)
                Some(Render.boxAt({ x = e#pos#x, y = e#pos#y }, { x = s - 2.0, y = s - 2.0 },
                    w#theme#enemy, zEnemy()))
            else
                None)

    /// 撃破の爆発（控えめに凝る）: 撃破済みの敵の位置に、消える瞬間まで光球（Add ブレンド）を描く。
    /// boomTimer が減るほど薄く小さくなる。粒子は自前で書かず Render.glowAt（閉形式で安全）に任せる。
    def booms(w: World.World): List[Render.PlacedItem] =
        let s = w#rules#enemyStep;
        w#enemies |> List.flatMap(e ->
            if (e#alive) Nil
            else {
                // boomTimer（満タン = World.boomDuration）で 1→0 に減衰させる。
                let t = clampF(0.0, 1.0, e#boomTimer / World.boomDuration());
                Render.glowAt({ x = e#pos#x, y = e#pos#y }, s * (0.4 + 0.6 * t), w#theme#boom,
                    { alpha = 0.9 * t, blend = DrawCmd.BlendMode.Add }, zBoom())
            })

    /// 自機（Title 以外で下部に出す。Title は幕が主役なので機体は出さない）。
    /// 三角の機体を polygon で組む（初学者が「頂点で形を作る」を読み取れる素直な形）。
    def player(w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title => Nil
            case _ =>
                let cx = w#playerX;
                let cy = World.playerY();
                let h = playerSize();
                // 上向きの三角（機首が上）。頂点は絶対座標で組む（置き場所は原点）。
                let ship = Render.polygon(
                    { x = cx, y = cy - h / 2.0 }
                        :: { x = cx - h / 2.0, y = cy + h / 2.0 }
                        :: { x = cx + h / 2.0, y = cy + h / 2.0 }
                        :: Nil,
                    w#theme#player, zPlayer());
                { at = Vec2.zero(), item = ship } :: Nil
        }

    // ── HUD（スコア・波）──

    def hud(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        // 文言はコードに直書きせず「見出し + 数」を組む。見出しラベルは UI 構造なので固定でよい。
        let waveNo = w#waveIndex + 1;                         // 1 始まりで見せる
        let waveTotal = WavesDoc.waveCount(w#waves);
           { at = { x = 8.0, y = 6.0 },
             item = Render.textTinted("SCORE ${Int32.toString(w#score)}", atlas, 10.0, w#theme#text, zHud()) }
        :: { at = { x = 8.0, y = 20.0 },
             item = Render.textTinted("WAVE ${Int32.toString(waveNo)}/${Int32.toString(waveTotal)}",
                 atlas, 9.0, ThemeDoc.darken(w#theme#text, 0.25), zHud()) }
        :: Nil

    // ── 場面ごとの幕（Title / Clear / GameOver）──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Title =>
                curtain(w#theme, 0.55f32)
                    :: centered(atlas, "SHOOTER", 22.0, w#theme#player, 130.0)
                    :: centered(atlas, "ARROWS: MOVE", 10.0, w#theme#text, 180.0)
                    :: centered(atlas, "SPACE: SHOOT", 10.0, w#theme#text, 196.0)
                    :: centered(atlas, "PRESS SPACE", 11.0, w#theme#bullet, 240.0)
                    :: Nil
            case World.Phase.Clear =>
                curtain(w#theme, 0.6f32)
                    :: centered(atlas, "CLEAR", 24.0, w#theme#bullet, 150.0)
                    :: centered(atlas, "SCORE ${Int32.toString(w#score)}", 12.0, w#theme#text, 186.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, ThemeDoc.darken(w#theme#text, 0.25), 216.0)
                    :: Nil
            case World.Phase.GameOver =>
                curtain(w#theme, 0.6f32)
                    :: centered(atlas, "GAME OVER", 20.0, w#theme#enemy, 150.0)
                    :: centered(atlas, "SCORE ${Int32.toString(w#score)}", 12.0, w#theme#text, 186.0)
                    :: centered(atlas, "PRESS SPACE", 10.0, ThemeDoc.darken(w#theme#text, 0.25), 216.0)
                    :: Nil
            case World.Phase.Playing => Nil
        }

    /// 画面全体を暗く覆う幕（幕の上に文字を載せて読みやすくする）。
    def curtain(theme: ThemeDoc.Doc, alpha: Float32): Render.PlacedItem =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.designW(), y = World.designH() }, theme#space, zOverlay())
              |> Render.fade(alpha) }

    /// 画面中央に 1 行のテキストを置く（幅はエンジンが実測して中央へ揃える）。
    def centered(atlas: FontAtlas, s: String, size: Float64, color: Color, y: Float64): Render.PlacedItem =
        TextDraw.centered({ text = s, atlas = atlas, size = size, color = color,
                            z = zOverlay() + 1, centerX = World.designW() / 2.0, y = y })

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))
}
