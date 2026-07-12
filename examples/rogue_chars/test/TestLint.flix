// TestLint — Roster 全キャラ × 全クリップ × 全コマの機械検査（純粋・bake しない）。
// 創作エージェントが 23 体を量産するときの安全網: 空コマ・はみ出し・パレット外の色・
// 手抜きコマ（遺体が待機と同じ / 横向きが左右対称）をここで弾く。

mod TestLint {

    // ── 総当たりの足場 ──

    def allFrames(): List[(RogueStage.Clip, Int32)] =
        RogueStage.clips() |> List.flatMap(c ->
            List.range(0, RogueStage.frameCount(c)) |> List.map(f -> (c, f)))

    /// 全キャラの全コマ: (キャラ名, クリップ名, コマ番号, Canvas)。
    def allDrawn(): List[(String, String, Int32, PixelCanvas.Canvas)] =
        Roster.entries() |> List.flatMap(entry -> {
            let (info, drawFn) = entry;
            allFrames() |> List.map(cf -> {
                let (c, f) = cf;
                ("${info#classId}_${info#variant}", "${c}", f, drawFn(c, f))
            })
        })

    /// Canvas の比較・照合用シグネチャ（Color は record なのでタプルに写して Eq を得る）。
    def sig(cv: PixelCanvas.Canvas): List[((Int32, Int32), (Float32, Float32, Float32))] =
        Map.toList(cv) |> List.map(kv -> {
            let (k, c) = kv;
            (k, (c#r, c#g, c#b))
        })

    // ── 検査 ──

    // 全コマが非空（描き忘れコマの検出）。
    @Test
    def testAllFramesNonEmpty(): Unit \ Assert =
        let offenders = allDrawn()
            |> List.filterMap(t -> {
                let (name, clip, f, cv) = t;
                if (Map.isEmpty(cv)) Some((name, clip, f)) else None
            });
        Assert.assertEq(expected = (Nil: List[(String, String, Int32)]), offenders)

    // 全ピクセルが 0..31 の枠内（dot は範囲外を捨てるが、直接 insert する経路の保険）。
    @Test
    def testAllPixelsInBounds(): Unit \ Assert =
        let bad = allDrawn()
            |> List.map(t -> {
                let (_, _, _, cv) = t;
                Map.foldLeftWithKey((acc, k, _) -> {
                    let (x, y) = k;
                    if (x < 0 or x > 31 or y < 0 or y > 31) acc + 1 else acc
                }, 0, cv)
            })
            |> List.sum;
        Assert.assertEq(expected = 0, bad)

    // 全ピクセルの色が DB32（RoguePalette.all()）に属する。
    @Test
    def testAllColorsInPalette(): Unit \ Assert =
        let palette = RoguePalette.all() |> List.map(c -> (c#r, c#g, c#b));
        let bad = allDrawn()
            |> List.map(t -> {
                let (_, _, _, cv) = t;
                Map.foldLeft((acc, c) ->
                    if (List.memberOf((c#r, c#g, c#b), palette)) acc else acc + 1,
                    0, cv)
            })
            |> List.sum;
        Assert.assertEq(expected = 0, bad)

    // Death の最終コマ（前傾がくり）が IdleDown frame0 と別の絵である
    // （死ぬ芝居のないキャラの検出）。
    @Test
    def testDeathFinalDiffersFromIdle(): Unit \ Assert =
        let offenders = Roster.entries()
            |> List.filterMap(entry -> {
                let (info, drawFn) = entry;
                let last = drawFn(RogueStage.Clip.Death, RogueStage.frameCount(RogueStage.Clip.Death) - 1);
                let idle0 = drawFn(RogueStage.Clip.IdleDown, 0);
                if (sig(last) == sig(idle0)) Some(info#displayName) else None
            });
        Assert.assertEq(expected = (Nil: List[String]), offenders)

    // WalkSide frame0 が左右非対称（横向きを正面の使い回しにしていない証明。
    // 対称だと hflip の右向きが意味を失う）。
    @Test
    def testWalkSideAsymmetric(): Unit \ Assert =
        let offenders = Roster.entries()
            |> List.filterMap(entry -> {
                let (info, drawFn) = entry;
                let side0 = drawFn(RogueStage.Clip.WalkSide, 0);
                if (sig(PixelCanvas.hflip(side0)) == sig(side0)) Some(info#displayName) else None
            });
        Assert.assertEq(expected = (Nil: List[String]), offenders)

    // アンカー規約: IdleDown frame0 の足元が y=29 に接地し、頭上に 2px 以上の余白（身長 ≤ 28px）。
    @Test
    def testIdleAnchor(): Unit \ Assert =
        let offenders = Roster.entries()
            |> List.filterMap(entry -> {
                let (info, drawFn) = entry;
                let cv = drawFn(RogueStage.Clip.IdleDown, 0);
                let ys = Map.keysOf(cv) |> Set.toList |> List.map(snd);
                let maxY = ys |> List.maximum |> Option.getWithDefault(-1);
                let minY = ys |> List.minimum |> Option.getWithDefault(-1);
                if (maxY == 29 and minY >= 2) None else Some((info#displayName, minY, maxY))
            });
        Assert.assertEq(expected = (Nil: List[(String, Int32, Int32)]), offenders)

    // 接地の徹底: 全クリップ・全コマで足元が地面（y=29 付近）にある。IdleDown f0 だけ見ると
    // 他コマがまるごと浮いていても気づけない（実際にそういう取りこぼしがあった）ので、
    // ここは総当たりで maxY < 27 のコマ（3px 以上宙に浮いた作画）を弾く。
    @Test
    def testFeetGrounded(): Unit \ Assert =
        let offenders = allDrawn()
            |> List.filterMap(t -> {
                let (name, clip, f, cv) = t;
                let maxY = Map.keysOf(cv) |> Set.toList |> List.map(snd)
                    |> List.maximum |> Option.getWithDefault(-1);
                if (maxY >= 27) None else Some((name, clip, f, maxY))
            });
        Assert.assertEq(expected = (Nil: List[(String, String, Int32, Int32)]), offenders)

    // ── 共通白骨（Skeleton）の検査 ──

    // 白骨 2 コマが非空で、全ピクセルが枠内かつ white/paleBlue の 2 色のみ。
    @Test
    def testSkeletonFrames(): Unit \ Assert =
        let allowed = (RoguePalette.white() :: RoguePalette.paleBlue() :: Nil)
            |> List.map(c -> (c#r, c#g, c#b));
        let offenders = List.range(0, RogueStage.bonesFrameCount())
            |> List.filterMap(f -> {
                let cv = Skeleton.draw(f);
                let outOfBounds = Map.keysOf(cv) |> Set.toList |> List.filter(k -> {
                    let (x, y) = k;
                    x < 0 or x > 31 or y < 0 or y > 31
                }) |> List.length;
                let badColors = Map.foldLeft((acc, c) ->
                    if (List.memberOf((c#r, c#g, c#b), allowed)) acc else acc + 1,
                    0, cv);
                if (Map.isEmpty(cv) or outOfBounds > 0 or badColors > 0)
                    Some((f, outOfBounds, badColors))
                else
                    None
            });
        Assert.assertEq(expected = (Nil: List[(Int32, Int32, Int32)]), offenders)
}
