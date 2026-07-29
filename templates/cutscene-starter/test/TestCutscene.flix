// イベントシーン(カットシーン)のテスト。
// JSON 橋渡し(CutsceneDoc: 最大 3 本)と、演じる規則(Cutscene: 進行と終わり方)を見る。
// 期待値は Doc から導き、マスの数値は fixture の脚本そのものから取る(写経しない)。
mod TestCutscene {

    // ══════════════════════════════════════════════════════
    // CutsceneDoc(JSON 橋渡し)
    // ══════════════════════════════════════════════════════

    @Test
    def testCutsceneBrokenJsonFallsBackToDefaults(): Unit \ Assert =
        // 壊れた JSON は「カットの無い空のシーン」へ倒れる(bake は必ず走り切る)。
        let doc = CutsceneDoc.fromJson("{ broken")
            |> Option.getWithDefault(CutsceneDoc.defaults());
        Assert.assertEq(
            expected = (CutsceneDoc.defaults()#id, 0),
            (doc#id, List.length(doc#cuts)))

    @Test
    def testCutsceneOverridesOneField(): Unit \ Assert =
        // 1 フィールドだけ書いた JSON はそこだけ効き、残りは既定のまま。
        let doc = CutsceneDoc.fromJson("{\"version\":1, \"id\": \"yoru\"}")
            |> Option.getWithDefault(CutsceneDoc.defaults());
        Assert.assertEq(
            expected = ("yoru", (CutsceneDoc.defaults()#start#x,
                                 CutsceneDoc.defaults()#start#y)),
            (doc#id, (doc#start#x, doc#start#y)))

    @Test
    def testCutsceneCutsFollowJson(): Unit \ Assert =
        // カットの種類と数は JSON に追随する。知らないカット・形の違うカットは
        // **列から抜けずに Broken の印になる**(通し番号が JSON とずれない —
        // 演じる側が番号つきで報せて飛ばす)。知らない向きの綴りは down に倒れる。
        let text = "{\"version\":1, \"startX\":9, \"startY\":8, \"facing\":\"ななめ\","
            + " \"cuts\":["
            + "  {\"wait\": 0.5},"
            + "  {\"walkTo\": {\"x\": 4, \"y\": 7}, \"run\": true},"
            + "  {\"おどる\": true},"
            + "  {\"walkTo\": \"つづりちがい\"},"
            + "  {\"backTo\": {\"x\": 2, \"y\": 2}},"
            + "  {\"say\": [\"あ\", \"い\"]},"
            + "  {\"talk\": \"left\"},"
            + "  {\"wispAppear\": {\"x\": 3, \"y\": 3}},"
            + "  {\"wispTo\": {\"x\": 4, \"y\": 3}},"
            + "  {\"wispVanish\": true},"
            + "  {\"fade\": \"out\", \"secs\": 0.5}"
            + " ]}";
        let doc = CutsceneDoc.fromJson(text)
            |> Option.getWithDefault(CutsceneDoc.defaults());
        Assert.assertEq(
            expected = ((9, 8), Dir4.Down,
                        "wait" :: "walkTo" :: "broken" :: "broken" :: "backTo"
                            :: "say" :: "talk" :: "wispAppear" :: "wispTo"
                            :: "wispVanish" :: "fade" :: Nil),
            ((doc#start#x, doc#start#y), doc#facing,
             doc#cuts |> List.map(row -> CutsceneDoc.kindOf(row#cut))))

    // ══════════════════════════════════════════════════════
    // Cutscene(演じる規則。間取りは既定の 1 部屋)
    //
    //   #########
    //   #*..@..G#    @ = 脚本の始まりのマス (3,1)   G = 門番
    //   ####D####    D = 木戸(閉)   * = 薬草
    //   #......*#
    //   #########
    // ══════════════════════════════════════════════════════

    /// 既定の間取りで演じる World(火の玉の棲み処だけ試験ごとに差し替える)。
    def world(wisp: Option[Grid.Cell]): World.World =
        World.initial({ map = { wisp = wisp | MapDoc.defaults() },
                        kind = KindDoc.defaults(),
                        theme = ThemeDoc.defaults(), sprites = PxSpriteDoc.empty(),
                        terrain = TerrainDoc.defaults(), scenes = Nil })

    /// 既定の間取りで演じる脚本の土台(マスと向きだけ試験ごとに差し替える)。
    /// カットは守衛なし(only / unless 空)で包む。
    def scene(cuts: List[CutsceneDoc.Cut]): CutsceneDoc.Doc =
        { start = { x = 3, y = 1 },
          cuts = cuts |> List.map(cut -> { only = "", unless = "", cut = cut })
          | CutsceneDoc.defaults() }

    @Test
    def testCutsceneRunsToEnd(): Unit \ Assert =
        // 歩く → 言う、を演じ切ると: 主人公は脚本の目的マスに立ち、ふきだしは閉じている。
        // 期待のマスは脚本の WalkTo そのものから取る(数値を写経しない)。
        let goal = { x = 1, y = 1 };
        let doc = scene(
               CutsceneDoc.Cut.WalkTo({ cell = goal, dash = false, back = false,
                                        waits = true })
            :: CutsceneDoc.Cut.Say("……しずかだ" :: Nil)
            :: Nil);
        let ended = Cutscene.finalWorld(doc, world(None));
        Assert.assertEq(
            expected = ((goal#x, goal#y), false),
            ((ended#hero#x, ended#hero#y), UiDialog.isOpen(ended#dialog)))

    @Test
    def testCutsceneSkipsUnreachableWalk(): Unit \ Assert =
        // 石垣の中を目的地にした歩きは、凍らずにそのカットだけ飛び、次のカットへ進む
        // (fail-open — 主人公は動かず、続く Face は演じられる)。
        let doc = scene(
               CutsceneDoc.Cut.WalkTo({ cell = { x = 0, y = 0 }, dash = false, back = false,
                                        waits = true })
            :: CutsceneDoc.Cut.Face(Dir4.Left)
            :: Nil);
        let ended = Cutscene.finalWorld(doc, world(None));
        Assert.assertEq(
            expected = ((doc#start#x, doc#start#y), Dir4.Left),
            ((ended#hero#x, ended#hero#y), ended#facing))

    @Test
    def testCutsceneMovesWispAndFreezesChase(): Unit \ Assert =
        // 火の玉は脚本の指したマスへ詰め、演じている間は主人公を勝手に追わない —
        // 長い待ちのあとも指した位置に必ず居る(凍結の規則)。
        // 期待のマスは脚本の WispTo そのものから取る。
        let perch = { x = 4, y = 3 };
        let doc = scene(
               CutsceneDoc.Cut.WispTo({ cell = perch, waits = true })
            :: CutsceneDoc.Cut.Wait(6.0)
            :: Nil);
        let ended = Cutscene.finalWorld(doc, world(Some({ x = 1, y = 3 })));
        Assert.assertEq(
            expected = Some((perch#x, perch#y)),
            ended#wisp |> Option.map(cell -> (cell#x, cell#y)))

    @Test
    def testCutsceneGuardFollowsFacts(): Unit \ Assert =
        // 守衛(only / unless)は World の事実(この里では herb = 薬草を持っている)で
        // 効く条件行 — 拾う前は only:"herb" の行が黙り、unless:"herb" の行が演じられる。
        // 分岐ではないので流れは一本道のまま。
        let doc = { start = { x = 3, y = 1 },
                    cuts = { only = "herb", unless = "", cut = CutsceneDoc.Cut.Face(Dir4.Left) }
                        :: { only = "", unless = "herb", cut = CutsceneDoc.Cut.Face(Dir4.Right) }
                        :: Nil
                    | CutsceneDoc.defaults() };
        let ended = Cutscene.finalWorld(doc, world(None));
        Assert.assertEq(expected = Dir4.Right, ended#facing)

    // ══════════════════════════════════════════════════════
    // Director(実機再生: 勝手にキャラクターが動き出し、終わると操作が返る)
    // ══════════════════════════════════════════════════════

    /// 合図とシーンが消えるまで Director を回す(暴走の安全弁つき)。
    def playOut(n: Int32, w: World.World): World.World =
        if (n <= 0 or (Option.isEmpty(w#scene) and w#cue == "")) w
        else playOut(n - 1, Director.tick(1.0 / 30.0, w))

    @Test
    def testOpeningScenePlaysItselfAndReturnsControl(): Unit \ Assert =
        // 間取りが opening にシーンの id を書いていると: 歩き出した拍に合図が立ち、
        // Director が入力なしでキャラクターを動かし(= イベントシーン)、
        // 演じ終わると合図もシーンも消えて操作がプレイヤーへ返る。
        // 期待のマスは脚本の WalkTo そのものから取る。
        let goal = { x = 1, y = 1 };
        let script = { id = "op",
                       cuts = { only = "", unless = "",
                                cut = CutsceneDoc.Cut.WalkTo(
                                    { cell = goal, dash = false, back = false,
                                      waits = true }) } :: Nil
                       | CutsceneDoc.defaults() };
        let w0 = World.initial({ map = { opening = "op" | MapDoc.defaults() },
                                 kind = KindDoc.defaults(),
                                 theme = ThemeDoc.defaults(), sprites = PxSpriteDoc.empty(),
                                 terrain = TerrainDoc.defaults(),
                                 scenes = script :: Nil });
        let ended = playOut(1000, World.confirm(w0));
        Assert.assertEq(
            expected = ((goal#x, goal#y), true, ""),
            ((ended#hero#x, ended#hero#y), Option.isEmpty(ended#scene), ended#cue))

    @Test
    def testDirectorKeepsSceneNotes(): Unit \ Assert =
        // 実機再生でも脚本の誤りは無音にならない — 石垣の中を目的地にした歩きを
        // 演じ終えると、飛ばした報せ(カット1)が World の sceneNotes に残る
        // (bake の println と同じ内容。SceneNotes.step が debug/ へ写す材料)。
        let script = { id = "op",
                       cuts = { only = "", unless = "",
                                cut = CutsceneDoc.Cut.WalkTo(
                                    { cell = { x = 0, y = 0 }, dash = false, back = false,
                                      waits = true }) } :: Nil
                       | CutsceneDoc.defaults() };
        let w0 = World.initial({ map = { opening = "op" | MapDoc.defaults() },
                                 kind = KindDoc.defaults(),
                                 theme = ThemeDoc.defaults(), sprites = PxSpriteDoc.empty(),
                                 terrain = TerrainDoc.defaults(),
                                 scenes = script :: Nil });
        let ended = playOut(1000, World.confirm(w0));
        Assert.assertEq(
            expected = (1, true),
            (List.length(ended#sceneNotes),
             ended#sceneNotes |> List.forAll(String.startsWith(prefix = "カット1"))))
}
