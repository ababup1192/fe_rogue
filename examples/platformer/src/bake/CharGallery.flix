// CharGallery — キャラクターラボ: 候補キャラ 10 枠が同じ演技（CharStage の 6 秒台本）を
// 横並びで踊る比較ページを焼く。1800×260 の 1 枚に 120px レーン × 15。
// 全レーンが同じ Stage を受け取るので、動きの解釈（ポーズ・伸び潰れ・色）だけが違いになる —
// オーナーはこの 1 枚でキャラを選ぶ。空きスロットは破線の箱 + "?"（後続 Wave が埋める）。
//
// 出力: charparade.gif（6 秒 × 64fps を stride 3 で間引いた 128 コマ）+
//       charlineup.png（t=5.0 の待機で全員整列）。Gallery.bakeAll から呼ばれる。

mod CharGallery {

    // ── 舞台の寸法 ──

    def laneW(): Float64 = 120.0
    def stageW(): Int32 = 1800
    def stageH(): Int32 = 260
    /// レーン内ローカル y=0（足元線）を置く画面 y。
    def groundY(): Float64 = 210.0
    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outDir(): String = "gallery"

    /// z-index の範囲: 地面 0 / レーン仕切り 1 / キャラ 10..(各キャラが自分で指定) / ラベル 50。
    def zLabel(): Int32 = 50

    // ── スロット登録（キャラ = Stage → PlacedItem 列の関数 1 本。共通の型は作らない）──

    /// スロット一覧: (ラベル, draw)。ラベルはレーン上部に描くのでアトラスに載る ASCII で書く
    /// （Xolonium は漢字を持たない）。全 10 枠が実キャラ（候補の設計コンセプトは各 Char モジュール冒頭）。
    pub def slots(_atlas: FontAtlas): List[(String, CharStage.Stage -> List[Render.PlacedItem])] =
        ("01 HERO (CURRENT)", stage -> Char01.draw(stage)) ::
        (Char02.name(), stage -> Char02.draw(stage)) ::
        (Char03.name(), stage -> Char03.draw(stage)) ::
        (Char04.name(), stage -> Char04.draw(stage)) ::
        (Char05.name(), stage -> Char05.draw(stage)) ::
        (Char06.name(), stage -> Char06.draw(stage)) ::
        (Char07.name(), stage -> Char07.draw(stage)) ::
        (Char08.name(), stage -> Char08.draw(stage)) ::
        (Char09.name(), stage -> Char09.draw(stage)) ::
        (Char10.name(), stage -> Char10.draw(stage)) ::
        (Char11.name(), stage -> Char11.draw(stage)) ::
        (Char12.name(), stage -> Char12.draw(stage)) ::
        (Char13.name(), stage -> Char13.draw(stage)) ::
        (Char14.name(), stage -> Char14.draw(stage)) ::
        (Char15.name(), stage -> Char15.draw(stage)) :: Nil

    // ── 1 コマの組み立て ──

    /// 時刻 t の全レーン。地面は 1 本の帯（全レーン共通）、キャラは各レーン中央の
    /// 足元原点に置く — 全員が同じ stageAt(t) を受け取る。
    def frameItems(atlas: FontAtlas, t: Float64): List[Render.PlacedItem] =
        let stage = CharStage.stageAt(t);
        let lanes = List.zipWithIndex(slots(atlas)) |> List.flatMap(pair -> {
            let (i, slot) = pair;
            let (name, drawFn) = slot;
            laneItems(atlas, i, name, drawFn, stage)
        });
        List.append(groundItems(), lanes)

    /// レーン 1 本: ラベル + 仕切り線（左端レーン以外）+ キャラ本体（ローカル → レーン座標へ平行移動）。
    def laneItems(atlas: FontAtlas, idx: Int32, name: String,
                  drawFn: CharStage.Stage -> List[Render.PlacedItem],
                  stage: CharStage.Stage): List[Render.PlacedItem] =
        let left = Int32.toFloat64(idx) * laneW();
        let originX = left + laneW() / 2.0;
        let label = { at = { x = left + 6.0, y = 8.0 },
                      item = Render.textTinted(name, atlas, 8.0, Palette.hudText(), zLabel()) };
        let sep = if (idx == 0) Nil else
            { at = { x = left, y = 0.0 },
              item = RawDraw.box({ x = 1.0, y = Int32.toFloat64(stageH()) }, Palette.wall(), 1) } :: Nil;
        let body = drawFn(stage) |> List.map(placed -> {
            { at = { x = placed#at#x + originX, y = placed#at#y + groundY() }, item = placed#item }
        });
        label :: List.append(sep, body)

    /// 地面: 露出上面の草キャップ 4px + 下は土（本編の地形語彙と同じ配色）。
    def groundItems(): List[Render.PlacedItem] =
        let w = Int32.toFloat64(stageW());
        let dirtH = Int32.toFloat64(stageH()) - groundY() - 4.0;
        { at = { x = 0.0, y = groundY() }, item = RawDraw.box({ x = w, y = 4.0 }, Palette.grassTop(), 0) } ::
        { at = { x = 0.0, y = groundY() + 4.0 }, item = RawDraw.box({ x = w, y = dirtH }, Palette.dirtBody(), 0) } :: Nil

    // ── 焼き込み ──

    /// Bakery に渡す焼き込み設定（舞台は 1800×260・等倍・GIF は 47ms ≒ 実 21fps）。
    def config(atlas: FontAtlas): Bakery.BakeConfig =
        { design = { x = Int32.toFloat64(stageW()), y = Int32.toFloat64(stageH()) }, scale = 1,
          background = Palette.clearColor(), texturePath = Map.empty(),
          fontTtf = ttfPath(), fontAtlas = atlas, outDir = outDir(),
          frameW = stageW(), frameH = stageH(), gifDelayMs = 47, gifFps = 21 }

    /// 時刻 t のコマを engine の描画コマンドへ投影する。
    def frameCmds(atlas: FontAtlas, t: Float64):
            (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        Render.draw(frameItems(atlas, t))

    /// charparade（GIF + コマ別 PNG）と charlineup（PNG 1 枚）を焼き、GIF の
    /// フィルムストリップ情報を返す。6 秒 × 64fps = 384 コマを 3 コマおきに 128 コマへ
    /// 間引く（コマ間 3/64 秒 ≈ 47ms・実時間再生 ≈ 21fps）。時刻を事前に間引くので stride=1。
    pub def bake(atlas: FontAtlas): SnapshotSite.Filmstrip \ IO =
        let dt = 1.0 / 64.0;
        let ts = List.range(0, 384)
            |> List.filter(i -> Int32.modulo(i, 3) == 0)
            |> List.map(i -> Int32.toFloat64(i) * dt);
        let film = Bakery.bakeGif(config(atlas), ts, 1, t -> frameCmds(atlas, t), "charparade");
        // 整列写真: t=5.0（待機の呼吸）で全員を並べた 1 枚。
        let (drawables, polygons) = frameCmds(atlas, 5.0);
        Bakery.renderPng(config(atlas), drawables, polygons, "charlineup");
        film
}
