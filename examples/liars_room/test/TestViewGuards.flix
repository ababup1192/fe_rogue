// TestViewGuards — 絵の健全性を fail で守る検査（生成はしない）。
// 代表的な画面の UiWorld を幾何リンタにかけ、違反（非抑制 Finding）があれば
// その説明文が差分にそのまま並ぶ。末尾の bool は「リンタがちゃんと要素を見た」保証。
// シルエットのパーツ数と部屋の到達性も同じ思想の下限ガード。
mod TestViewGuards {

    /// World の見た目を投影した UiWorld を lint にかけ、非抑制違反の説明行を返す。
    def lintFor(name: String, w: Room.World, atlas: FontAtlas,
                ui: UiStore.UiWorld): (List[String], Bool) =
        let projected = GameUi.projectUi(w, ui);
        let input = LiarsLint.buildInput(
            { sceneName = name, allow = Nil, screen = GameUi.designSize(), atlas = atlas },
            projected);
        (LiarsLint.activeDetails(RenderLint.check(input)), not List.isEmpty(input#elements))

    /// 会話ウィンドウを全文表示まで進めた状態（ステージ 1 シード 1 で NPC1 と話す）。
    def talkingWorld(): Room.World =
        Room.stageWorld(1, Map.empty(), 1i64)
            |> Trace.facingNpcBelow(1)
            |> Trace.step(Trace.talkTap())
            |> Trace.step(Trace.talkTap())

    /// メモが全員ぶん正解で埋まって開いている状態（提出プロンプトが点灯する回答画面）。
    def answerWorld(): Room.World =
        let Room.World.World(s) = Room.stageWorld(1, Map.empty(), 1i64);
        Room.World.World(Room.debugFillMemo({ memoOpen = true | s }))

    @Test
    def testUiPagesPassRenderLint(): Unit \ {Assert, IO} =
        let atlas = Harness.atlas();
        let ui = Harness.ui();
        let stage1 = Room.stageWorld(1, Map.empty(), 1i64);
        let clean = (Nil: List[String]);
        Assert.assertEq(
            expected = ((clean, true), (clean, true), (clean, true), (clean, true), (clean, true)),
            (lintFor("title", Room.titleWorld(), atlas, ui),
             lintFor("exploring_memo", stage1 |> Trace.step(Trace.memoTap()), atlas, ui),
             lintFor("talking", talkingWorld(), atlas, ui),
             lintFor("answer", answerWorld(), atlas, ui),
             lintFor("wrong", answerWorld()
                 |> Trace.step(Trace.talkTap())
                 |> Trace.step(Trace.talkTap())
                 |> Trace.step(Trace.enterTap()), atlas, ui)))

    @Test
    def testHumanDrawingsProvideParts(): Unit \ {Assert, IO} =
        // 8 人 × 4 方向 + ラベル（1 体 4〜9 パーツ）。描画関数が空を返す退行の検出（下限ガード）。
        Assert.assertEq(expected = true, NpcGallery.partCount() > 150)

    @Test
    def testEveryNpcIsReachableInAllStages(): Unit \ Assert =
        // 全ステージで、プレイヤーの初期位置から各 NPC の隣（話しかけられるセル）まで
        // 歩いて行ける（Datalog の到達閉包で証明）。
        let unreachable = List.range(1, Stage.stageCount() + 1) |> List.flatMap(n -> {
            let Room.World.World(s) = Room.stageWorld(n, Map.empty(), Stage.pickSeed(n, 0));
            let blocked = Set.union(s#walls, Room.npcCells(s));
            let floors = List.flatMap(y -> List.map(x -> (x, y), List.range(0, s#cols)),
                    List.range(0, s#rows))
                |> List.filter(cell -> not Set.memberOf(cell, blocked))
                |> List.toSet;
            let reach = Rules.reachable(s#player, floors);
            s#npcs |> List.filterMap(npc -> {
                let (nx, ny) = npc#cell;
                let doorstep = ((nx + 1, ny) :: (nx - 1, ny) :: (nx, ny + 1) :: (nx, ny - 1) :: Nil)
                    |> List.exists(cell -> Set.memberOf(cell, reach));
                if (doorstep) None else Some((n, npc#id))
            })
        });
        Assert.assertEq(expected = (Nil: List[(Int32, Int32)]), unreachable)
}
