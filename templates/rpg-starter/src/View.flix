// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 画面は 2 つある: 里（歩く画面）と 戦い（魔物と向き合う画面）。frame が phase で振り分ける。
//
// ── この画面の画風（AGENTS.local.md と同じ宣言）──
// 「霧の出た夕暮れの段々畑の里」。空も土も紫みを帯びて沈み、暖かいのは灯りだけ。
//   色は 3 つ: 暮れた紫 / 土の茶 / 灯りの橙。
//   やらないこと: 真っ黒と純白を使わない（霧の中なので、いちばん暗い所も明るい所も濁らせる）。
// **これは数ある画風の 1 つでしかない。** 真似してほしいのは「層に分けて、各層に役割を
// 持たせる」組み方の方で、色や効果ではない。別の作り方の例は `.claude/skills/visual-dict`。
//
// ── 里の層（奥から手前へ）──
//   空 → ベース床 → terrain（石垣・畑）→ 扉・薬草・灯り・住人・主人公 → 霧 → ふきだし → 幕
// 盤は「ベース床（道）を全セルに敷き、その上に terrain の表（rpg.terrain.json）を重ねる」—
// 石垣・畑の角の変化形は Terrain（デュアルグリッド）が自動生成し、View は幾何を書かない。
//
// ── 戦いの層（奥から手前へ）──
//   夜空のグラデ → 霧 → 地面のグラデ → 魔物の影 → 魔物（息をする）→ 窓（体力・コマンド・文）
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

    // ── 戦いの画面の z 層 ──
    def zBattleSky(): Int32 = 0
    def zBattleGround(): Int32 = 5
    def zFoeShadow(): Int32 = 10
    def zFoe(): Int32 = 12
    def zWindow(): Int32 = 20
    def zWindowText(): Int32 = 23

    /// スプライトの格子は 1 セル = 1px で描く（16×16 の格子 = 16px。タイル 20px の中に収まる）。
    def px(): Int32 = 1

    /// 戦いのときだけ、魔物をこの倍率で大きく描く（16×16 → 64px）。
    def foeScale(): Int32 = 5

    pub def frame(ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Battle => battle(ctx#atlas, w)
            case _                  => village(ctx#atlas, w)
        }

    /// 里の画面（歩く・話す・拾う）。
    def village(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               sky(w#theme)
            :: tiles(w)
            :: door(w)
            :: herbs(w)
            :: lamps(w)
            :: villagers(w)
            :: hero(w)
            :: fogBands(w#theme)
            :: bubble(atlas, w)
            :: overlay(atlas, w)
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
        w#map#villagers |> List.flatMap(villager -> {
            // 話しかけている相手だけ口を開けたコマにする（誰と話しているかが絵で分かる）。
            let talking = w#talkingTo
                |> Option.map(cell -> MapDoc.sameCell(cell, villager#cell))
                |> Option.getWithDefault(false);
            sprite(w, "villager", if (talking) "talk" else "idle",
                villager#cell, false, zVillager(), w#theme#cloth)
        })

    /// 主人公。向きごとに絵を持ち、歩数の偶奇で足を入れ替える。
    /// 左向きは右向きの絵の左右反転で済ませる（絵を増やさない）。
    def hero(w: World.World): List[Render.PlacedItem] =
        let (frameName, flipX) = heroFrame(w);
        sprite(w, "hero", frameName, w#hero, flipX, zHero(), w#theme#accent)

    /// 向き + 歩数 → 「どのコマを、反転するか」。
    def heroFrame(w: World.World): (String, Bool) =
        let walking = Int32.modulo(w#steps, 2) == 1;
        match w#facing {
            case Dir4.Up    => (if (walking) "up_walk"   else "up",   false)
            case Dir4.Down  => (if (walking) "down_walk" else "down", false)
            case Dir4.Left  => (if (walking) "side_walk" else "side", true)
            case Dir4.Right => (if (walking) "side_walk" else "side", false)
        }

    /// ドット絵 1 体をマスの中心に置く（里の等倍）。
    def sprite(w: World.World, name: String, frameName: String, cell: Grid.Cell,
               flipX: Bool, z: Int32, fallbackColor: Color): List[Render.PlacedItem] =
        spriteAt(w, { name = name, frame = frameName, center = cellCenter(w, cell),
                      flipX = flipX, scale = px(), z = z, fallback = fallbackColor })

    /// ドット絵 1 体を画面のどこにでも、好きな倍率で置く。大きさは絵から測るので
    /// （PxSprite.sizeOf）、絵を描き替えても置き位置がずれない。
    /// スプライトが読めないときは添えられた色の四角に倒す（fail-open）。
    /// 同じ型の値が並ぶので名前で渡す。
    def spriteAt(w: World.World,
                 spec: { name = String, frame = String, center = Vec2.Vec2, flipX = Bool,
                         scale = Int32, z = Int32, fallback = Color }): List[Render.PlacedItem] =
        let side = 16.0 * Int32.toFloat64(spec#scale);
        let box = PxSprite.sizeOf(w#sprites, spec#name, spec#frame, spec#scale)
            |> Option.getWithDefault({ x = side, y = side });
        let topLeft = { x = spec#center#x - box#x / 2.0, y = spec#center#y - box#y / 2.0 };
        let items = PxSprite.draw(w#sprites, spec#name, spec#frame, topLeft,
            spec#flipX, spec#scale, key -> ThemeDoc.resolver(w#theme, key), spec#z);
        if (List.isEmpty(items))
            { at = topLeft, item = Render.box(box, spec#fallback, spec#z) } :: Nil
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
        let boxX = clampF(edgeMargin(), World.width() - boxW - edgeMargin(),
            speakerCenter#x - boxW / 2.0);
        let boxY = Float64.max(edgeMargin(),
            speakerCenter#y - World.tileSize() / 2.0 - boxH - 8.0);
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

    /// ふきだしの枠を画面の縁から離す幅。0 にすると枠が縁に接して切れて見えるので、
    /// はみ出し止めの最小値ではなく目に見える余白として取る。
    def edgeMargin(): Float64 = 8.0

    def clampF(lo: Float64, hi: Float64, v: Float64): Float64 =
        Float64.max(lo, Float64.min(hi, v))

    // ── 表紙とクリアの幕（文言はすべて間取りの Doc から: 見出し・一行・操作のヒント） ──

    def overlay(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        match w#phase {
            case World.Phase.Play   => Nil
            case World.Phase.Battle => Nil        // 戦いの画面は overlay を通らない
            case World.Phase.Title  =>
                List.append(veil(w#theme, w#theme#titleVeil), banner(atlas, w#theme,
                    { head = w#map#title, headSize = 26.0,
                      body = w#map#subtitle, hint = w#map#hint }))
            case World.Phase.Clear  =>
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

    // ══════════════════════════════════════════════════════
    // 戦いの画面（魔物と向き合う）
    // ══════════════════════════════════════════════════════
    //
    // 里の絵は出さない（盤・霧の帯・ふきだしは village 側の物）。ここは
    // 「夜空 → 霧 → 地面 → 魔物 → 窓」の 5 段だけで、視線が魔物と下の文に集まるようにする。

    def battle(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        List.flatten(
               battleSky(w#theme)
            :: battleMist(w#theme)
            :: battleGround(w#theme)
            :: foe(w)
            :: statusWindow(atlas, w)
            :: commandWindow(atlas, w)
            :: messageWindow(atlas, w)
            :: Nil)

    /// 夜空。上ほど暗く、下ほど地面の色に近づく縦のグラデ（1px の色帯は積まない）。
    def battleSky(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        { at = { x = 0.0, y = 0.0 },
          item = Render.vgrad({ x = World.width(), y = World.height() },
              { top = ThemeDoc.darken(theme#sky, 0.45),
                bottom = ThemeDoc.lighten(theme#sky, 0.10) }, zBattleSky()) } :: Nil

    /// 遠くにかかる霧。濃さが縦に変わる帯を数枚重ねる。里の霧（fogBands）は四角い帯で
    /// よいが、こちらは下地がなめらかなグラデなので、縁が立つと帯の四角が見えてしまう —
    /// 上下で薄れる頂点色つきの帯にして、境目を消す。
    def battleMist(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        List.range(0, 3) |> List.map(i -> {
            let top = 60.0 + Hash01.at(i, 21) * 90.0;
            let height = 26.0 + Hash01.at(i, 22) * 30.0;
            let alpha = Float64.truncateToFloat32(0.07 + Hash01.at(i, 23) * 0.05);
            softBand(theme#fog, { top = top, bottom = top + height }, alpha, zBattleSky() + 1)
        })

    /// 上下の縁が透けて消える横帯（霧・地面のなじませに使う）。
    def softBand(color: Color, span: { top = Float64, bottom = Float64 },
                 peak: Float32, z: Int32): Render.PlacedItem =
        let mid = (span#top + span#bottom) / 2.0;
        { at = { x = 0.0, y = 0.0 },
          item = Render.gradPolygon(
                 { pos = { x = 0.0, y = span#top },            color = color, alpha = 0.0f32 }
              :: { pos = { x = World.width(), y = span#top },  color = color, alpha = 0.0f32 }
              :: { pos = { x = World.width(), y = mid },       color = color, alpha = peak }
              :: { pos = { x = World.width(), y = span#bottom },color = color, alpha = 0.0f32 }
              :: { pos = { x = 0.0, y = span#bottom },         color = color, alpha = 0.0f32 }
              :: { pos = { x = 0.0, y = mid },                 color = color, alpha = peak }
              :: Nil, z) }

    /// 魔物の立っている地面。上端は透けさせて空へなじませ、手前ほど明るくする
    /// （硬い横線が 1 本入ると、そこで絵が 2 枚に割れて見えるため）。
    def battleGround(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let top = 118.0;
        let near = ThemeDoc.darken(theme#path, 0.25);
        let far = ThemeDoc.darken(theme#path, 0.6);
           { at = { x = 0.0, y = 0.0 },
             item = Render.gradPolygon(
                    { pos = { x = 0.0, y = top },              color = far,  alpha = 0.0f32 }
                 :: { pos = { x = World.width(), y = top },    color = far,  alpha = 0.0f32 }
                 :: { pos = { x = World.width(), y = top + 40.0 }, color = far, alpha = 1.0f32 }
                 :: { pos = { x = World.width(), y = World.height() }, color = near, alpha = 1.0f32 }
                 :: { pos = { x = 0.0, y = World.height() },   color = near, alpha = 1.0f32 }
                 :: { pos = { x = 0.0, y = top + 40.0 },       color = far,  alpha = 1.0f32 }
                 :: Nil, zBattleGround()) }
        :: Nil

    /// 魔物と、その足元の影。上下にゆっくり息をする（手を止めても画面が止まらない）。
    /// 殴った直後のコマ（hit）は World が持つ foeHurt が決める。
    def foe(w: World.World): List[Render.PlacedItem] =
        let groundY = 206.0;
        let bob = Sway.wave(w#t, 0.0, 0.55) * 4.0;
        let half = 8.0 * Int32.toFloat64(foeScale());
        let center = { x = World.width() / 2.0, y = groundY - half + bob };
        // 影は本体が浮くほど小さく薄くする（浮き沈みが影で読める）。
        let lift = (bob + 4.0) / 8.0;
        let shadow = Render.ellipseAt({ x = center#x, y = groundY + 3.0 },
            { x = 40.0 - lift * 5.0, y = 10.0 - lift * 2.0 },
            ThemeDoc.darken(w#theme#sky, 0.55), zFoeShadow())
            |> (placed -> { item = Render.fade(0.7f32, placed#item) | placed });
        let frameName = if (w#battle#foeHurt) "hit" else "idle";
        shadow :: spriteAt(w, { name = "foe", frame = frameName, center = center,
                                flipX = false, scale = foeScale(), z = zFoe(),
                                fallback = ThemeDoc.resolver(w#theme, "foe") })

    // ── 窓（ドラクエ風の「紙の縁 + 濃い地」）──

    /// 窓 1 枚。紙色の縁を敷き、その内側を濃い地で塗る。中身は呼び側が上に置く。
    /// 角丸や影を足さないのは、この画風の窓が「紙を切って貼った物」だから。
    def window(rect: Rect2.Rect2, theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        let inset = 2.0;
           { at = rect#position, item = Render.box(rect#size, theme#paper, zWindow()) }
        :: { at = { x = rect#position#x + inset, y = rect#position#y + inset },
             item = Render.box({ x = rect#size#x - inset * 2.0, y = rect#size#y - inset * 2.0 },
                 ThemeDoc.darken(theme#ink, 0.15), zWindow() + 1) }
        :: Nil

    /// 窓の中に 1 行置く。
    def windowLine(atlas: FontAtlas, text: String, at: Vec2.Vec2, color: Color): Render.PlacedItem =
        { at = at, item = Render.textTinted(text, atlas, 12.0, color, zWindowText()) }

    /// 体力の窓（左上）。数だけでなく残りの帯も出す — 数を読まなくても危なさが判る。
    def statusWindow(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let rect = { position = { x = 16.0, y = 14.0 }, size = { x = 132.0, y = 44.0 } };
        let maxHp = Int32.max(1, w#battleDoc#heroMaxHp);
        let ratio = Num.clamp01(Int32.toFloat64(w#heroHp) / Int32.toFloat64(maxHp));
        let barW = 100.0;
        // 減るほど灯りの色から離れて危うい色へ寄る（色でも残りが読める）。
        let barColor = Color.mix(w#theme#cloth, w#theme#accent, ratio);
        List.append(window(rect, w#theme),
               windowLine(atlas, "HP ${Int32.toString(w#heroHp)}/${Int32.toString(maxHp)}",
                   { x = 26.0, y = 22.0 }, w#theme#paper)
            :: { at = { x = 26.0, y = 40.0 },
                 item = Render.box({ x = barW, y = 6.0 },
                     ThemeDoc.darken(w#theme#paper, 0.75), zWindowText()) }
            :: { at = { x = 26.0, y = 40.0 },
                 item = Render.box({ x = barW * ratio, y = 6.0 }, barColor, zWindowText() + 1) }
            :: Nil)

    /// コマンドの窓（左下）。コマンドを選んでいる間だけ出す。
    /// 選んでいる行にはまたたく三角を置く（点滅は「いま入力を待っている」の合図）。
    def commandWindow(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        if (w#battle#step != World.BattleStep.Choosing) Nil
        else {
            let rect = { position = { x = 16.0, y = 156.0 }, size = { x = 108.0, y = 62.0 } };
            let blink = 0.55 + 0.45 * Sway.wave(w#t, 0.0, 1.6);
            let rows = World.battleCommands() |> List.zipWithIndex |> List.flatMap(entry -> {
                let (i, label) = entry;
                let y = 166.0 + Int32.toFloat64(i) * 22.0;
                let chosen = i == w#battle#cursor;
                let mark = if (chosen)
                        { at = { x = 30.0, y = y + 7.0 },
                          item = Render.polygon(
                              { x = 0.0, y = -5.0 } :: { x = 7.0, y = 0.0 } :: { x = 0.0, y = 5.0 } :: Nil,
                              w#theme#accent, zWindowText() + 1)
                              |> Render.fade(Float64.truncateToFloat32(blink)) } :: Nil
                    else Nil;
                windowLine(atlas, label, { x = 44.0, y = y },
                    if (chosen) w#theme#paper else ThemeDoc.darken(w#theme#paper, 0.45)) :: mark
            });
            List.append(window(rect, w#theme), rows)
        }

    /// 文の窓（下）。いま読ませたい行を上から順に並べる。
    /// 行が無いとき（コマンド選び中）は出さない — 空の窓は画面を狭くするだけ。
    def messageWindow(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        if (List.isEmpty(w#battle#lines)) Nil
        else {
            let count = List.length(w#battle#lines);
            let height = 26.0 + Int32.toFloat64(count) * 20.0;
            let top = World.height() - height - 14.0;
            let rect = { position = { x = 132.0, y = top },
                         size = { x = World.width() - 148.0, y = height } };
            let rows = w#battle#lines |> List.zipWithIndex |> List.map(entry -> {
                let (i, line) = entry;
                windowLine(atlas, line, { x = rect#position#x + 14.0,
                                          y = top + 14.0 + Int32.toFloat64(i) * 20.0 },
                    w#theme#paper)
            });
            // 読み終えて次へ進める合図（またたく小さな三角）。
            let blink = 0.5 + 0.5 * Sway.wave(w#t, 0.25, 1.4);
            let more = { at = { x = rect#position#x + rect#size#x - 16.0,
                                y = top + height - 12.0 },
                         item = Render.polygon(
                             { x = -5.0, y = 0.0 } :: { x = 5.0, y = 0.0 } :: { x = 0.0, y = 6.0 } :: Nil,
                             w#theme#accent, zWindowText() + 1)
                             |> Render.fade(Float64.truncateToFloat32(blink)) };
            List.append(window(rect, w#theme), more :: rows)
        }
}
