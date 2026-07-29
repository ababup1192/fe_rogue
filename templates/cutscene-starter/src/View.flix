// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 場面は霧の出た夕暮れの段々畑の里: タイルの盤・扉・薬草・灯り・住人・主人公、
// その上に霧、いちばん上に ふきだし と表紙/クリアの文字。
// 盤は「ベース床（道）を全セルに敷き、その上に terrain の表（rpg.terrain.json）を重ねる」—
// 石垣・畑の角の変化形は Terrain（デュアルグリッド）が自動生成し、View は幾何を書かない。
mod View {

    // ── z 層（盤 1..9 / 物 10..29 / 霧 30 / 幕と文字 40.. / ふきだし 50..） ──

    def zSky(): Int32 = 0
    def zTile(): Int32 = 1
    def zDoor(): Int32 = 10
    def zHerb(): Int32 = 12
    def zLamp(): Int32 = 14
    def zVillager(): Int32 = 18
    def zHero(): Int32 = 20
    def zFog(): Int32 = 30
    def zVeil(): Int32 = 40
    def zOverlayText(): Int32 = 42
    def zBubble(): Int32 = 50
    def zWisp(): Int32 = 22
    def zCurtain(): Int32 = 60

    /// スプライトの格子は 1 セル = 2px で描く（8×8 の格子 = 16px。タイル 20px の中に収まる）。
    def px(): Int32 = 2

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               sky(w#theme)
            :: tiles(w)
            :: door(w)
            :: herbs(w)
            :: lamps(w)
            :: villagers(w)
            :: hero(w)
            :: wisp(w)
            :: fogBands(w#theme)
            :: bubble(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: flashVeil(w)
            :: curtain(w)
            :: Nil)

    /// 火の玉(敵)。絵素材を持たず、灯りと同じ glow の二重(淡い外光 + 濃い芯)で描く —
    /// 青白い光が霧の里を漂う。居なければ何も描かない。
    def wisp(w: World.World): List[Render.PlacedItem] =
        match w#wisp {
            case None       => Nil
            case Some(cell) =>
                let center = cellCenter(w, cell);
                let pale = ThemeDoc.lighten(w#theme#sky, 0.45);
                let core = { at = { x = center#x - 2.0, y = center#y - 2.0 },
                             item = Render.box({ x = 4.0, y = 4.0 }, pale, zWisp()) };
                core :: List.append(
                    Render.glowAt(center, 22.0, pale,
                        { alpha = 0.40, blend = DrawCmd.BlendMode.Add }, zWisp() + 1),
                    Render.glowAt(center, 9.0, pale,
                        { alpha = 0.60, blend = DrawCmd.BlendMode.Add }, zWisp() + 2))
        }

    /// 白い瞬き(イベントシーンの flash)。残り秒に比例して明るさが引いていく。
    /// 遊びの間 flash は 0 のままなので、何も描かず画は 1px も変わらない。
    def flashVeil(w: World.World): List[Render.PlacedItem] =
        if (w#flash <= 0.0) Nil
        else
            { at = { x = 0.0, y = 0.0 },
              item = Render.box({ x = World.width(), y = World.height() },
                                ThemeDoc.lighten(w#theme#fog, 0.5), zCurtain() - 1)
                  |> Render.fade(Float64.truncateToFloat32(
                      Float64.max(0.0, Float64.min(1.0, w#flash * 4.0)) * 0.85f64
                          |> Float64.min(0.85))) } :: Nil

    /// イベントシーン(Cutscene の fade)の暗転の幕。すべての上に掛かる。
    /// 遊びの間 curtain は 0 のままなので、何も描かず画は 1px も変わらない。
    def curtain(w: World.World): List[Render.PlacedItem] =
        if (w#curtain <= 0.0) Nil
        else
            { at = { x = 0.0, y = 0.0 },
              item = Render.box({ x = World.width(), y = World.height() }, w#theme#ink,
                                zCurtain())
                  |> Render.fade(Float64.truncateToFloat32(
                      Float64.max(0.0, Float64.min(1.0, w#curtain)))) } :: Nil

    // ── 盤の位置合わせ（小さな間取りでも画面の真ん中に来る） ──

    /// 盤の左上の画面座標。design の真ん中に盤全体を置く（揺れがあれば盤ごと震える）。
    def boardOrigin(w: World.World): Vec2.Vec2 =
        let t = World.tileSize();
        let jolt = quakeOffset(w);
        { x = (World.width() - Int32.toFloat64(MapDoc.cols(w#map)) * t) / 2.0 + jolt#x,
          y = (World.height() - Int32.toFloat64(MapDoc.rowCount(w#map)) * t) / 2.0 + jolt#y }

    /// 画面の揺れ(イベントシーンの shake)。残り秒があるあいだ、盤ごと小さく震わせる。
    /// 揺れは歩数と残り秒のハッシュから引くので乱数を持たず、焼けば毎回同じ。
    /// 遊びの間 quake は 0 のままなので、盤は 1px も動かない。
    def quakeOffset(w: World.World): Vec2.Vec2 =
        if (w#quake <= 0.0) { x = 0.0, y = 0.0 }
        else {
            let power = 2.0 * Float64.min(1.0, w#quake * 2.0);
            let beat = Float64.tryToInt32(Float64.floor(w#quake * 30.0))
                |> Option.getWithDefault(0);
            { x = Float64.round((Hash01.at(beat, 41) - 0.5) * 2.0 * power),
              y = Float64.round((Hash01.at(beat, 43) - 0.5) * 2.0 * power) }
        }

    /// cell の中心の画面座標（盤の位置合わせ込み）。
    def cellCenter(w: World.World, cell: Grid.Cell): Vec2.Vec2 =
        let origin = boardOrigin(w);
        let center = Grid.cellCenterOf(World.tileSize(), cell);
        { x = origin#x + center#x, y = origin#y + center#y }

    /// cell の左上の画面座標（盤の位置合わせ込み）。
    def cellTopLeft(w: World.World, cell: Grid.Cell): Vec2.Vec2 =
        let t = World.tileSize();
        let center = cellCenter(w, cell);
        { x = center#x - t / 2.0, y = center#y - t / 2.0 }

    // ── 空とタイル ──

    def sky(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.width(), y = World.height() }, theme#sky, zSky()) } :: Nil

    /// ベース床（道）を全セルに敷き、その上に terrain の表を重ねる。
    /// entries に無い文字は床のまま = fail-open。
    /// z の秩序: zTile() = 1 < terrain の fill/band/surface（zPlanOf が 2..9 に
    /// 割り付ける）< zDoor() = 10。ベース床は必ず terrain の下、
    /// 扉・薬草・人・ふきだしは必ず terrain の上に出る。
    ///
    /// Terrain.fromRows は「文字の rows + 質感の表」を受け取り、角の埋まり方から
    /// 丸/四角/ひし形を自動生成した地形タイルの並びを返す黒箱（デュアルグリッド）。
    /// 中で何をしているかは engine の docs/module-index.md（Terrain / TerrainDoc）を引く。
    def tiles(w: World.World): List[Render.PlacedItem] =
        let t = World.tileSize();
        let table = w#terrain#entries
            |> List.map(e -> { char = e#char,
                               spec = TerrainDoc.specOf(key -> ThemeDoc.resolver(w#theme, key), e),
                               z = zPlanOf(e) });
        List.append(
            baseFloor(w, t),
            Terrain.fromRows({ tileSize = t, origin = boardOrigin(w),
                               styleMix = w#terrain#styleMix }, table, w#map#rows))

    /// terrain の z 割り付け（2..9 の帯）。平らな地形（畑）は床のすぐ上、
    /// 持ち上げ地形（石垣）はその上 — 持ち上げの立ち上がりが北隣の平ら地形
    /// （畑の裾）に重なって 2.5D に見えるための順序。
    def zPlanOf(e: TerrainDoc.EntryDoc): { fill = Int32, band = Int32, surface = Int32 } =
        match e#height {
            case None    => { fill = 2, band = 3, surface = 3 }
            case Some(_) => { fill = 6, band = 7, surface = 7 }
        }

    /// ベース床（道）を全セルに敷く。色と式は旧 View.tile の道と同一
    /// （theme#path + Hash01 のゆらぎ。Hash01.at の座標順 (y, x) もそのまま）。
    def baseFloor(w: World.World, t: Float64): List[Render.PlacedItem] =
        w#map#rows |> List.zipWithIndex |> List.flatMap(rowEntry -> {
            let (y, row) = rowEntry;
            String.toList(row) |> List.zipWithIndex |> List.map(colEntry -> {
                let (x, _) = colEntry;
                let cell = { x = x, y = y };
                { at = cellTopLeft(w, cell),
                  item = Render.box({ x = t, y = t },
                      ThemeDoc.lighten(w#theme#path, Hash01.at(cell#y, cell#x) * 0.06),
                      zTile()) }
            })
        })

    // ── 扉（約束で開く木戸。閉じている間は通れない） ──

    def door(w: World.World): List[Render.PlacedItem] =
        let t = World.tileSize();
        let at = cellTopLeft(w, w#map#door#cell);
        let plank = ThemeDoc.lighten(w#theme#wall, 0.30);
        if (w#doorOpen)
            // 開いた木戸: 両脇の柱だけ残る。
               { at = at, item = Render.box({ x = 4.0, y = t }, plank, zDoor()) }
            :: { at = { x = at#x + t - 4.0, y = at#y }, item = Render.box({ x = 4.0, y = t }, plank, zDoor()) }
            :: Nil
        else
            // 閉じた木戸: 板戸 + 横木 2 本 + 結び目（灯りの色。ここが約束の印）。
               { at = at, item = Render.box({ x = t, y = t }, plank, zDoor()) }
            :: { at = { x = at#x, y = at#y + 4.0 }, item = Render.box({ x = t, y = 3.0 }, w#theme#ink, zDoor() + 1) }
            :: { at = { x = at#x, y = at#y + t - 7.0 }, item = Render.box({ x = t, y = 3.0 }, w#theme#ink, zDoor() + 1) }
            :: { at = { x = at#x + t / 2.0 - 2.0, y = at#y + t / 2.0 - 2.0 },
                 item = Render.box({ x = 4.0, y = 4.0 }, w#theme#accent, zDoor() + 1) }
            :: Nil

    // ── 薬草・灯り・住人・主人公 ──

    def herbs(w: World.World): List[Render.PlacedItem] =
        w#herbs |> List.flatMap(cell -> sprite(w, "herb", "idle", cell, false, zHerb(),
            ThemeDoc.resolver(w#theme, "leaf")))

    /// 灯り。薬草を拾った数だけ、並び順に点いていく（夕暮れの里に灯がともる）。
    def lamps(w: World.World): List[Render.PlacedItem] =
        let lit = World.lampsLit(w);
        w#map#lamps |> List.zipWithIndex |> List.flatMap(entry -> {
            let (i, cell) = entry;
            lamp(w, cell, i < lit)
        })

    def lamp(w: World.World, cell: Grid.Cell, litNow: Bool): List[Render.PlacedItem] =
        let center = cellCenter(w, cell);
        let theme = w#theme;
        // ポストは背を高くして持ち上げ地形の裾から頭を出す（濃い地形に埋もれない）。
        let post = { at = { x = center#x - 1.0, y = center#y - 11.0 },
                     item = Render.box({ x = 2.0, y = 15.0 }, theme#ink, zLamp()) };
        // 消灯時のヘッドも「灯りの器」として読めるよう少し明るめに（暗い地形で埋もれない）。
        let headColor = if (litNow) theme#accent else ThemeDoc.lighten(theme#sky, 0.24);
        let head = { at = { x = center#x - 3.0, y = center#y - 16.0 },
                     item = Render.box({ x = 6.0, y = 6.0 }, headColor, zLamp() + 1) };
        // 点灯時のグローは大きく暖かく。地形がリッチになった分、halo を強めて「灯がともる」を出す。
        // 外側の淡い光 + 芯の濃い光の二重で、点でありつつ周りへにじむ。
        let glow = if (litNow)
            List.append(
                Render.glowAt({ x = center#x, y = center#y - 13.0 }, 34.0, theme#accent,
                    { alpha = 0.42, blend = DrawCmd.BlendMode.Add }, zLamp() + 2),
                Render.glowAt({ x = center#x, y = center#y - 13.0 }, 14.0, theme#accent,
                    { alpha = 0.55, blend = DrawCmd.BlendMode.Add }, zLamp() + 3))
        else Nil;
        post :: head :: glow

    def villagers(w: World.World): List[Render.PlacedItem] =
        w#map#villagers |> List.flatMap(villager ->
            sprite(w, "villager", "idle", villager#cell, false, zVillager(), w#theme#cloth))

    /// 主人公。歩数の偶奇で idle / walk のコマを切り替え、左向きのときは絵を反転する。
    def hero(w: World.World): List[Render.PlacedItem] =
        let frameName = if (Int32.modulo(w#steps, 2) == 1) "walk" else "idle";
        sprite(w, "hero", frameName, w#hero, w#facing == Dir4.Left, zHero(), w#theme#accent)

    /// ドット絵 1 体をマスの中心に置く。スプライトが読めないときは
    /// 添えられた色の四角に倒す（fail-open）。
    def sprite(w: World.World, name: String, frameName: String, cell: Grid.Cell,
               flipX: Bool, z: Int32, fallbackColor: Color): List[Render.PlacedItem] =
        let side = 8.0 * Int32.toFloat64(px());
        let center = cellCenter(w, cell);
        let topLeft = { x = center#x - side / 2.0, y = center#y - side / 2.0 };
        let items = PxSprite.draw(w#sprites, name, frameName, topLeft,
            flipX, px(), key -> ThemeDoc.resolver(w#theme, key), z);
        if (List.isEmpty(items))
            { at = topLeft, item = Render.box({ x = side, y = side }, fallbackColor, z) } :: Nil
        else
            items

    // ── 霧（決定的なばらつきで横に流れる帯。保存も乱数の種も持たない） ──

    def fogBands(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        List.range(0, 5) |> List.map(i ->
            { at = { x = 0.0, y = Hash01.at(i, 11) * (World.height() - 40.0) },
              item = Render.box({ x = World.width(), y = 30.0 + Hash01.at(i, 12) * 34.0 },
                                theme#fog, zFog())
                  |> Render.fade(Float64.truncateToFloat32(0.10 + Hash01.at(i, 13) * 0.08)) })

    // ── ふきだし（住人の頭の上。本文は文字送りの途中まで） ──
    // 枠は ui.json（UiStore）にしない: ふきだしは話し相手のマスに吸い付く世界側の物で、
    // 画面に固定の窓ではないため。開閉・行送り・文字送りの状態はエンジンの UiDialog が持ち、
    // ここは visibleBody を RichText.place で描くだけ（文字折りも自前で書かない）。

    def bubble(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match (UiDialog.isOpen(w#dialog), w#talkingTo) {
            case (true, Some(cell)) => bubbleAt(atlas, cellCenter(w, cell), w)
            case _                  => Nil
        }

    def bubbleAt(atlas: FontAtlas, speakerCenter: Vec2.Vec2, w: World.World): List[Render.PlacedItem] =
        let spans = UiDialog.visibleBody(w#dialog);
        let fullSpans = UiDialog.currentLine(w#dialog)
            |> Option.map(line -> line#body) |> Option.getWithDefault(Nil);
        // 文字の大きさ・行間・余白・最大幅は手触り（rpg.kind.json）から来る。
        let fontSize = w#kind#bubbleSize;
        let lineGap = w#kind#bubbleGap;
        let pad = w#kind#bubblePad;
        let maxTextW = w#kind#bubbleWidth;
        // 枠の寸法は「全文」で測る — 文字送りの途中で枠がガタつかない。
        let lineCount = RichText.wrapLinesBy(
            ch -> TextDraw.width(Char.toString(ch), atlas, fontSize),
            maxTextW, fullSpans) |> List.length |> Int32.max(1);
        let textW = Float64.min(maxTextW,
            TextDraw.width(RichText.plainText(fullSpans), atlas, fontSize));
        let boxW = textW + pad * 2.0;
        let boxH = Int32.toFloat64(lineCount) * (fontSize + lineGap)
            - lineGap + pad * 2.0;
        let boxX = clampF(4.0, World.width() - boxW - 4.0, speakerCenter#x - boxW / 2.0);
        let boxY = Float64.max(4.0, speakerCenter#y - World.tileSize() / 2.0 - boxH - 8.0);
        List.flatten(
               ({ at = { x = boxX, y = boxY },
                  item = Render.box({ x = boxW, y = boxH }, w#theme#paper, zBubble()) } :: Nil)
            :: tail(speakerCenter, boxY + boxH, w#theme#paper)
            :: RichText.place(
                   { atlas = atlas, size = fontSize, baseTint = w#theme#ink,
                     z = zBubble() + 2, pos = { x = boxX + pad, y = boxY + pad },
                     maxWidth = maxTextW, lineGap = lineGap }, spans)
            :: Nil)

    /// ふきだしの口（枠の下辺から話し手へ落ちる小さな三角）。
    def tail(speakerCenter: Vec2.Vec2, fromY: Float64, color: Color): List[Render.PlacedItem] =
        { at = { x = speakerCenter#x, y = fromY },
          item = Render.polygon(
              { x = -4.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 6.0 } :: Nil,
              color, zBubble() + 1) } :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    // ── 表紙とクリアの幕（文言はすべて間取りの Doc から: 見出し・一行・操作のヒント） ──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Play  => Nil
            case World.Phase.Title =>
                List.append(veil(w#theme, w#theme#titleVeil), banner(atlas, w#theme,
                    { head = w#map#title, headSize = 26.0,
                      body = w#map#subtitle, hint = w#map#hint }))
            case World.Phase.Clear =>
                List.append(veil(w#theme, w#theme#clearVeil), banner(atlas, w#theme,
                    { head = w#map#title, headSize = 16.0,
                      body = w#map#clear, hint = w#map#clearHint }))
        }

    def veil(theme: ThemeDoc.Doc, alpha: Float64): List[Render.PlacedItem] =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.width(), y = World.height() },
                            ThemeDoc.darken(theme#sky, 0.5), zVeil())
              |> Render.fade(Float64.truncateToFloat32(alpha)) } :: Nil

    /// 見出し・一行・操作ヒントを画面の真ん中に積む。
    def banner(atlas: FontAtlas, theme: ThemeDoc.Doc,
               opts: { head = String, headSize = Float64, body = String, hint = String }): List[Render.PlacedItem] =
           TextDraw.centered({ text = opts#head, atlas = atlas, size = opts#headSize,
                               color = theme#paper, z = zOverlayText(),
                               centerX = World.width() / 2.0, y = 112.0 })
        :: TextDraw.centered({ text = opts#body, atlas = atlas, size = 10.0,
                               color = theme#fog, z = zOverlayText(),
                               centerX = World.width() / 2.0, y = 152.0 })
        :: TextDraw.centered({ text = opts#hint, atlas = atlas, size = 9.0,
                               color = ThemeDoc.lighten(theme#sky, 0.4), z = zOverlayText(),
                               centerX = World.width() / 2.0, y = 188.0 })
        :: Nil
}
