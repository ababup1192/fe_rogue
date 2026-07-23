// World — ゲームの状態そのものと、次の状態を作る規則（すべて純粋）。
// 主人公を矢印キーで動かすだけの最小の骨組み。数値の初期値（速さ）は SampleDoc、
// 色は ThemeDoc、絵の格子は PxSpriteDoc — 実行中の状態はこの World だけが持つ。
mod World {

    /// このフレームの入力（横・縦の軸値。-1 / 0 / +1）。
    pub type alias Input = { x = Float64, y = Float64 }

    pub type alias World = {
        doc = SampleDoc.Doc,
        theme = ThemeDoc.Doc,
        sprites = PxSpriteDoc.Doc,
        x = Float64,
        y = Float64,
        activeDocsWritten = String
    }

    // ── 盤の寸法（design __W__×__H__ の中の定数。project.json と同じ値） ──

    pub def width(): Float64 = __W__.0
    pub def height(): Float64 = __H__.0

    /// 主人公の1辺（8×8 の格子を scale 2 で描く = 16px）。
    pub def heroSize(): Float64 = 16.0

    pub def spritePath(): String = "assets/__NAME__.sprite.json"

    /// ゲーム開始時の状態。主人公は画面の真ん中。
    pub def initial(doc: SampleDoc.Doc, theme: ThemeDoc.Doc, sprites: PxSpriteDoc.Doc): World =
        { doc = doc, theme = theme, sprites = sprites,
          x = width() / 2.0, y = height() / 2.0, activeDocsWritten = "" }

    /// いま画面に出ている Doc（project.json の editor 宣言 id → パス）。
    /// Studio の「表示中」バッジの材料（ActiveDocs.step が debug/ に名乗る）。
    /// この骨組みは場面が 1 つで、3 つの Doc を常に表示に使っている —
    /// 場面（表紙・クリア等）が増えたら、ここで使っている物だけに絞ること
    /// （全部を常時 active にするとバッジの意味が死ぬ）。
    pub def activeDocs(_w: World): List[(String, List[String])] =
        ("sample", SampleDoc.path() :: Nil)
            :: ("theme", ThemeDoc.path() :: Nil)
            :: ("sprite", spritePath() :: Nil)
            :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    /// 画面の中に主人公全体が収まる可動域（端で止まるのはルール）。
    pub def clampX(v: Float64): Float64 =
        clampF(heroSize() / 2.0, width() - heroSize() / 2.0, v)

    pub def clampY(v: Float64): Float64 =
        clampF(heroSize() / 2.0, height() - heroSize() / 2.0, v)

    /// 入力と経過時間から次の状態を作る。速さは Doc（sample.kind.json）から。
    pub def step(input: Input, dt: Float64, w: World): World =
        { x = clampX(w#x + input#x * w#doc#speed * dt),
          y = clampY(w#y + input#y * w#doc#speed * dt) | w }

    // ── Doc の差し替え（保存即反映） ──

    pub def withDoc(doc: SampleDoc.Doc, w: World): World = { doc = doc | w }

    pub def withTheme(theme: ThemeDoc.Doc, w: World): World = { theme = theme | w }

    pub def withSprites(sprites: PxSpriteDoc.Doc, w: World): World = { sprites = sprites | w }
}
