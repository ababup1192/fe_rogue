// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 主人公を矢印キーで動かすだけの最小の骨組み。数値の初期値（速さ）は SampleDoc、
// 色は ThemeDoc、絵の格子は PxSpriteDoc、空の塗りは ShaderDoc — 実行中の状態は
// この World だけが持つ。
mod World {

    /// このフレームの入力（横・縦の軸値。-1 / 0 / +1）。
    pub type alias Input = { x = Float64, y = Float64 }

    pub type alias World = {
        doc = SampleDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        shader = ShaderDoc.Spec,
        x = Float64,
        y = Float64,
        t = Float64,
        activeDocsWritten = String
    }

    // ── 盤の寸法（design __W__×__H__ の中の定数。project.json と同じ値） ──

    pub def width(): Float64 = __W__.0
    pub def height(): Float64 = __H__.0

    /// ドット絵を何倍の大きさで描くか（1 セル = 何 px か）。
    pub def spriteScale(): Int32 = 2

    /// コマを描いたときの大きさ（px）。読めない・そのコマが無いときは None。
    /// PxSpriteDoc はコマを「文字列の並び」までしか教えてくれないので、ここで測る。
    /// どのゲームでも要る形なので、2 例目が出たらエンジン（PxSprite）へ上げたい
    /// — 上げるときは engine 側と相談してから。
    pub def spriteBox(doc: PxSpriteDoc.Doc, sprite: String, frame: String): Option[Vec2.Vec2] =
        Map.get(sprite, doc#sprites)
            |> Option.flatMap(sp -> Map.get(frame, sp#frames))
            |> Option.flatMap(rows ->
                List.head(rows) |> Option.map(top -> {
                    let s = Int32.toFloat64(spriteScale());
                    ({ x = Int32.toFloat64(String.length(top)) * s,
                       y = Int32.toFloat64(List.length(rows)) * s }: Vec2.Vec2)
                }))

    /// 主人公の大きさ = 絵の大きさ。絵を描き替えたら当たりもついてくる
    /// （固定値にすると、絵だけ大きくして当たりが古いまま、という食い違いが出る）。
    /// 絵がまだ読めていないときだけ 16×16 に倒す（fail-open）。
    pub def heroBox(w: World): Vec2.Vec2 =
        spriteBox(w#sprites, "hero", "idle")
            |> Option.getWithDefault({ x = 16.0, y = 16.0 })

    pub def spritePath(): String = "assets/__NAME__.sprite.json"

    pub def shaderPath(): String = "assets/__NAME__.shader.json"

    /// 「中の色 → (明るい色, 暗い色)」の対応。文字は sprite.json の legend に合わせる。
    /// 色そのものでなく文字の並びなので、これは絵の構造 = コード側に置く。
    def shadeRamp(): PxShade.Ramp =
        Map#{ 'a' => ('A', 'd') }

    /// 読み込んだドット絵に仕上げ（ふち光・接地影・ディザ・粒）を掛ける。
    /// 掛かるのは読み込み直後の 1 回だけで、毎フレームの絵づくりには入らない
    /// （何体出しても走行中の負荷は増えない）。強さと光の向きは theme.json から。
    pub def polished(theme: ThemeDoc.Doc, doc: PxSpriteDoc.Doc): PxSpriteDoc.Doc =
        PxShade.polishDoc(theme#shade, shadeRamp(), doc)

    /// ゲーム開始時の状態。主人公は画面の真ん中。
    pub def initial(doc: SampleDoc.Doc, theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc,
                    shader: ShaderDoc.Spec): World =
        { doc = doc, theme = theme, sprites = polished(theme, sprites), shader = shader,
          x = width() / 2.0, y = height() / 2.0, t = 0.0, activeDocsWritten = "" }

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。
    /// Studio の「表示中」バッジの材料（ActiveDocs.step が debug/ に名乗る）。
    /// この骨組みは場面が 1 つで、4 つの Doc を常に表示に使っている —
    /// 場面（表紙・クリア等）が増えたら、ここで使っている物だけに絞ること
    /// （全部を常時 active にするとバッジの意味が死ぬ）。
    pub def activeDocs(_w: World): List[(String, List[String])] =
        ("sample", SampleDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("sprite", spritePath() :: Nil)
            :: ("shader", shaderPath() :: Nil)
            :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    /// 大きさ box の物が画面から出ない位置へ丸める（端で止まるのはルール）。
    pub def clampInside(box: Vec2.Vec2, p: Vec2.Vec2): Vec2.Vec2 =
        { x = clampF(box#x / 2.0, width() - box#x / 2.0, p#x),
          y = clampF(box#y / 2.0, height() - box#y / 2.0, p#y) }

    /// 入力と経過時間から次の状態を作る。速さは Doc（sample.kind.json）から。
    /// t は積み上げた秒。空の流れ・塵・待ち姿の揺れがこれを見る。
    pub def step(input: Input, dt: Float64, w: World): World =
        let speed = w#doc#speed;
        let moved = { x = w#x + input#x * speed * dt, y = w#y + input#y * speed * dt };
        let p = clampInside(heroBox(w), moved);
        { x = p#x, y = p#y, t = w#t + dt | w }

    // ── Doc の差し替え（保存即反映） ──

    pub def withDoc(doc: SampleDoc.Doc, w: World): World = { doc = doc | w }

    /// テーマには仕上げの強さ・光の向きも入っているので、色を変えたら絵も掛け直す。
    pub def withTheme(theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc, w: World): World =
        { theme = theme, sprites = polished(theme, sprites) | w }

    pub def withSprites(sprites: PxSpriteDoc.Doc, w: World): World =
        { sprites = polished(w#theme, sprites) | w }

    pub def withShader(shader: ShaderDoc.Spec, w: World): World = { shader = shader | w }
}
