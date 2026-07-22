// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 場面は霧の出た夕暮れの段々畑の里: タイルの盤・扉・薬草・灯り・住人・主人公、
// その上に霧、いちばん上に ふきだし と表紙/クリアの文字。
// タイルの色分け・段差の陰・霧のばらつきは全部ここで導く（Doc は基準色と配置だけ持つ）。
mod View {

    // ── z 層（盤 1..9 / 物 10..29 / 霧 30 / 幕と文字 40.. / ふきだし 50..） ──

    def zSky(): Int32 = 0
    def zTile(): Int32 = 1
    def zTileEdge(): Int32 = 2
    def zDoor(): Int32 = 10
    def zHerb(): Int32 = 12
    def zLamp(): Int32 = 14
    def zVillager(): Int32 = 18
    def zHero(): Int32 = 20
    def zFog(): Int32 = 30
    def zVeil(): Int32 = 40
    def zOverlayText(): Int32 = 42
    def zBubble(): Int32 = 50

    /// スプライトの格子は 1 セル = 2px で描く（8×8 の格子 = 16px。タイル 20px の中に収まる）。
    def px(): Int32 = 2

    /// ふきだし本文の文字の大きさと行間。
    def bubbleFontSize(): Float64 = 10.0
    def bubbleLineGap(): Float64 = 3.0

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               sky(w#theme)
            :: tiles(w)
            :: door(w)
            :: herbs(w)
            :: lamps(w)
            :: villagers(w)
            :: hero(w)
            :: fogBands(w#theme)
            :: bubble(ctx#atlas, w)
            :: overlay(ctx#atlas, w)
            :: Nil)

    // ── 盤の位置合わせ（小さな間取りでも画面の真ん中に来る） ──

    /// 盤の左上の画面座標。design の真ん中に盤全体を置く。
    def boardOrigin(w: World.World): Vec2.Vec2 =
        let t = World.tileSize();
        { x = (World.width() - Int32.toFloat64(MapDoc.cols(w#map)) * t) / 2.0,
          y = (World.height() - Int32.toFloat64(MapDoc.rowCount(w#map)) * t) / 2.0 }

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

    /// rows の文字格子をそのまま塗る。'#' = 石垣、',' = 畑、'.'（と知らない文字） = 道。
    /// 畑は Hash01 でわずかに明るさを散らし（毎回同じ = bake が決定的）、
    /// 下が畑でないマスの裾に陰を落として段々に見せる。
    def tiles(w: World.World): List[Render.PlacedItem] =
        w#map#rows |> List.zipWithIndex |> List.flatMap(rowEntry -> {
            let (y, row) = rowEntry;
            String.toList(row) |> List.zipWithIndex |> List.flatMap(colEntry -> {
                let (x, ch) = colEntry;
                tile(w, { x = x, y = y }, ch)
            })
        })

    def tile(w: World.World, cell: Grid.Cell, ch: Char): List[Render.PlacedItem] =
        let t = World.tileSize();
        let at = cellTopLeft(w, cell);
        let theme = w#theme;
        match ch {
            case '#' =>
                // 石垣: 本体 + 上辺のハイライト（霧の里の低い石積み）。
                   { at = at, item = Render.box({ x = t, y = t }, theme#wall, zTile()) }
                :: { at = at, item = Render.box({ x = t, y = 3.0 },
                        ThemeDoc.lighten(theme#wall, 0.18), zTileEdge()) }
                :: Nil
            case ',' =>
                // 畑: マスごとに明るさを散らす。下のマスが畑でなければ裾に段の陰。
                let tint = ThemeDoc.lighten(theme#field, Hash01.at(cell#x, cell#y) * 0.10);
                let body = { at = at, item = Render.box({ x = t, y = t }, tint, zTile()) };
                if (MapDoc.tileAt(Grid.neighborOf(cell, Dir4.Down), w#map) != ',')
                    body :: { at = { x = at#x, y = at#y + t - 4.0 },
                              item = Render.box({ x = t, y = 4.0 },
                                  ThemeDoc.darken(theme#field, 0.35), zTileEdge()) } :: Nil
                else
                    body :: Nil
            case _ =>
                // 道（知らない文字も道に倒す = MapDoc.solidAt と同じ読み方）。
                { at = at, item = Render.box({ x = t, y = t },
                    ThemeDoc.lighten(theme#path, Hash01.at(cell#y, cell#x) * 0.06), zTile()) } :: Nil
        }

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
        let post = { at = { x = center#x - 1.0, y = center#y - 8.0 },
                     item = Render.box({ x = 2.0, y = 12.0 }, theme#ink, zLamp()) };
        let headColor = if (litNow) theme#accent else ThemeDoc.lighten(theme#sky, 0.12);
        let head = { at = { x = center#x - 3.0, y = center#y - 13.0 },
                     item = Render.box({ x = 6.0, y = 6.0 }, headColor, zLamp() + 1) };
        let glow = if (litNow)
            Render.glowAt({ x = center#x, y = center#y - 10.0 }, 22.0, theme#accent,
                { alpha = 0.30, blend = DrawCmd.BlendMode.Add }, zLamp() + 2)
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
        let pad = 6.0;
        let maxTextW = 200.0;
        // 枠の寸法は「全文」で測る — 文字送りの途中で枠がガタつかない。
        let lineCount = RichText.wrapLinesBy(
            ch -> TextDraw.width(Char.toString(ch), atlas, bubbleFontSize()),
            maxTextW, fullSpans) |> List.length |> Int32.max(1);
        let textW = Float64.min(maxTextW,
            TextDraw.width(RichText.plainText(fullSpans), atlas, bubbleFontSize()));
        let boxW = textW + pad * 2.0;
        let boxH = Int32.toFloat64(lineCount) * (bubbleFontSize() + bubbleLineGap())
            - bubbleLineGap() + pad * 2.0;
        let boxX = clampF(4.0, World.width() - boxW - 4.0, speakerCenter#x - boxW / 2.0);
        let boxY = Float64.max(4.0, speakerCenter#y - World.tileSize() / 2.0 - boxH - 8.0);
        List.flatten(
               ({ at = { x = boxX, y = boxY },
                  item = Render.box({ x = boxW, y = boxH }, w#theme#paper, zBubble()) } :: Nil)
            :: tail(speakerCenter, boxY + boxH, w#theme#paper)
            :: RichText.place(
                   { atlas = atlas, size = bubbleFontSize(), baseTint = w#theme#ink,
                     z = zBubble() + 2, pos = { x = boxX + pad, y = boxY + pad },
                     maxWidth = maxTextW, lineGap = bubbleLineGap() }, spans)
            :: Nil)

    /// ふきだしの口（枠の下辺から話し手へ落ちる小さな三角）。
    def tail(speakerCenter: Vec2.Vec2, fromY: Float64, color: Color): List[Render.PlacedItem] =
        { at = { x = speakerCenter#x, y = fromY },
          item = Render.polygon(
              { x = -4.0, y = 0.0 } :: { x = 4.0, y = 0.0 } :: { x = 0.0, y = 6.0 } :: Nil,
              color, zBubble() + 1) } :: Nil

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    // ── 表紙とクリアの幕（文言は間取りの Doc から。操作のヒントだけコード） ──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Play  => Nil
            case World.Phase.Title =>
                List.append(veil(w#theme, 0.45), banner(atlas, w#theme,
                    { head = w#map#title, headSize = 26.0,
                      body = w#map#subtitle, hint = "Zキーではじめる" }))
            case World.Phase.Clear =>
                List.append(veil(w#theme, 0.55), banner(atlas, w#theme,
                    { head = w#map#title, headSize = 16.0,
                      body = w#map#clear, hint = "Zキーではじめにもどる" }))
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
