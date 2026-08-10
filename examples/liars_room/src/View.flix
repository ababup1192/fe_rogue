// View — World から「描くべきものリスト」への投影。ここには状態は何もない:
// 床・壁・人・頭上の印はすべて、渡された World の純粋な関数である。
// 色は Palette（ロール名）からのみ来る。ここにある生の数値は設計値（サイズや比率）。
mod View {

    // ── レイアウト、design px 単位（解像度 320x240）──
    def centerX(): Float64 = 160.0
    def boardCenterY(): Float64 = 134.0

    /// 部屋 1 マスの画面上のサイズ。
    def tile(): Float64 = 24.0

    // 描画レイヤー、下から上へ。床/壁 = 0..2、人と頭上の印 = 前後の帯 10..（会話 UI の 120 未満）。
    /// 人の前後の帯の一番奥の zIndex。
    def zBandBack(): Int32 = 10

    /// 帯の 1 行ぶんの zIndex の幅。1 体の部品（体 0..3・印 4・▼ 5）が隣の行の段に
    /// 食い込まない広さにする。
    def zRowStride(): Int32 = 8

    /// 頭上の印の、体の部品（0..3）に対する相対 zIndex。
    def zMarkLift(): Int32 = 4
    def zIndicatorLift(): Int32 = 5

    /// 不正解シェイクの揺れ幅（px）と速さ（Hz 相当）。
    def shakeAmp(): Float64 = 3.0
    def shakeFreq(): Float64 = 55.0

    // ── compose: App の view スロット ──

    /// Session 全体を「(置き場所, 見せたい物) のリスト」へ投影する。
    /// 盤面はシェイク中だけ揺れ、UI ページは揺れない。会話の本文（色付き名前・太字入りの
    /// スパン列）は 1 色テキストの UI ノードでは表せないので、ここで直接描く。
    pub def compose(ctx: App.ViewCtx, s: LiarsRoom.Session): List[Render.PlacedItem] =
        let atlas = ctx#atlas;
        let Room.World.World(state) = s#world;
        List.append(
            frame(atlas, state) |> List.map(shift(shakeOffset(state))),
            List.append(
                UiRender.itemsWith(_ -> atlas, _ -> None, s#ui, GameUi.designSize()),
                dialogBody(atlas, state)))

    /// 会話パネル内の本文位置（パネル abs [8,176] + 余白 + 話者行のぶん下げた左上）。
    def dialogBodyPos(): Vec2.Vec2 = { x = 16.0, y = 195.0 }

    /// 会話本文の z。UI ページは「layer × layerStride」を zIndex に足して描かれるので、
    /// パネル（layer 2 / z 120）の上・確認メニュー（z 126〜）の下に合わせる。
    def zDialogBody(): Int32 = 2 * CanvasLayer.layerStride() + 124

    /// 会話本文のスパン列を、文字送りの見えているぶんだけ折返し付きで描く。
    def dialogBody(atlas: FontAtlas, state: Room.State): List[Render.PlacedItem] =
        RichText.place(
            { atlas = atlas, size = 10.0, baseTint = Palette.dialogText(), z = zDialogBody(),
              pos = dialogBodyPos(), maxWidth = 288.0, lineGap = 3.0 },
            UiDialog.visibleBody(state#dialog))

    /// 不正解の残り時間から揺れを導く（時間の純粋な関数。状態は shakeT だけ）。
    def shakeOffset(state: Room.State): Vec2.Vec2 =
        if (state#shakeT <= 0.0)
            { x = 0.0, y = 0.0 }
        else {
            let strength = state#shakeT / LiarsRoom.shakeDuration();
            { x = RenderUtil.sinF(state#shakeT * shakeFreq()) * shakeAmp() * strength,
              y = RenderUtil.cosF(state#shakeT * shakeFreq() * 0.7) * shakeAmp() * 0.5 * strength }
        }

    def shift(offset: Vec2.Vec2, placed: Render.PlacedItem): Render.PlacedItem =
        { at = Vec2.add(placed#at, offset) | placed }

    // ── frame: World を「描くべきものリスト」へ投影する ──

    /// タイトルとエンディングは UI ページだけの画面なので、盤面は描かない。
    pub def frame(atlas: FontAtlas, state: Room.State): List[Render.PlacedItem] =
        if (state#phase == Room.Phase.Title or state#phase == Room.Phase.Ending)
            Nil
        else
            List.flatten(
                floorTiles(state) ::
                wallTiles(state) ::
                npcBodies(state) ::
                playerParts(state) ::
                headMarks(state) ::
                talkIndicator(atlas, state) :: Nil)

    // ── 部屋の幾何: セルから画面座標へ ──

    /// 部屋の左上隅。グリッド全体が中央（HUD を避けてやや下）に来るよう選ばれる。
    def origin(state: Room.State): Vec2.Vec2 =
        { x = centerX() - Int32.toFloat64(state#cols) * tile() / 2.0,
          y = boardCenterY() - Int32.toFloat64(state#rows) * tile() / 2.0 }

    def cellCenter(state: Room.State, p: (Int32, Int32)): Vec2.Vec2 =
        Vec2.add(origin(state), Grid.cellCenter(tile(), p))

    def cellTopLeft(state: Room.State, p: (Int32, Int32)): Vec2.Vec2 =
        let (x, y) = p;
        Vec2.add(origin(state),
            { x = Int32.toFloat64(x) * tile(), y = Int32.toFloat64(y) * tile() })

    /// 人と頭上の印の前後の帯。足元が下（南）の人ほど手前に出る。
    def band(state: Room.State): Depth.Band =
        { back = zBandBack(),
          front = zBandBack() + (state#rows + 1) * zRowStride(),
          top = origin(state)#y,
          bottom = origin(state)#y + Int32.toFloat64(state#rows) * tile() }

    /// 帯に渡す足元の高さ（立ち位置セルの下端）。
    def footY(center: Vec2.Vec2): Float64 = center#y + tile() / 2.0

    def cells(state: Room.State): List[(Int32, Int32)] =
        List.flatMap(y -> List.map(x -> (x, y), List.range(0, state#cols)),
            List.range(0, state#rows))

    // ── 床と壁 ──

    /// 壁以外のセルを市松 2 色で敷く。
    def floorTiles(state: Room.State): List[Render.PlacedItem] =
        cells(state)
            |> List.filter(p -> not Set.memberOf(p, state#walls))
            |> List.map(p -> {
                let (x, y) = p;
                let color = if (Int32.modulo(x + y, 2) == 0) Palette.floorA() else Palette.floorB();
                { at = cellTopLeft(state, p), item = Render.box({x = tile(), y = tile()}, color, 0) }
            })

    /// 壁セル: 本体 + 上縁のハイライトで立体に見せる。
    def wallTiles(state: Room.State): List[Render.PlacedItem] =
        state#walls |> Set.toList |> List.flatMap(p -> {
            let tl = cellTopLeft(state, p);
            { at = tl, item = Render.box({x = tile(), y = tile()}, Palette.wall(), 1) } ::
            { at = tl, item = Render.box({x = tile(), y = tile() * 0.25}, Palette.wallTop(), 2) } :: Nil
        })

    // ── 人 ──

    /// NPC は立ち姿 + 呼吸のボブ（id で位相をずらして一斉に沈まないようにする）。
    def npcBodies(state: Room.State): List[Render.PlacedItem] =
        state#npcs |> List.flatMap(npc -> {
            let center = cellCenter(state, npc#cell);
            Human.standing(center, tile(), Palette.npcSkin(npc#id),
                           npc#facing, state#idlePhase + Int32.toFloat64(npc#id) * 0.37)
                |> Depth.place(band(state), footY(center))
        })

    /// プレイヤー。スライド中は前のセルから今のセルへ向かう途中の位置に描く。
    def playerParts(state: Room.State): List[Render.PlacedItem] =
        let center = match state#slide {
            case Some(slide) =>
                Vec2.lerp(cellCenter(state, slide#fromCell), cellCenter(state, state#player), slide#t)
            case None => cellCenter(state, state#player)
        };
        Human.walking(center, tile(), Palette.playerSkin(), state#facing, drawnWalkPhase(state))
            |> Depth.place(band(state), footY(center))

    /// 立ち止まっているときは静止コマに寄せ、歩いているときは walkPhase をそのまま使う。
    def drawnWalkPhase(state: Room.State): Float64 =
        match state#slide {
            case Some(_) => state#walkPhase
            case None    => 0.0
        }

    // ── 頭上の印 ──

    /// メモのマークを NPC の頭上に描く。嘘つき = 赤い斜め十字、本物 = 緑の輪。
    /// 持ち主の足元の帯に載せるので、手前（南）に立つ人を貫かない。
    def headMarks(state: Room.State): List[Render.PlacedItem] =
        state#npcs |> List.flatMap(npc ->
            (match Map.get(npc#id, state#memo) |> Option.getWithDefault(Room.Mark.Unknown) {
                case Room.Mark.Unknown    => Nil
                case Room.Mark.LiarMark   => crossMark(markPos(state, npc))
                case Room.Mark.HonestMark => ringMark(markPos(state, npc))
            }) |> Depth.place(band(state), footY(cellCenter(state, npc#cell))))

    /// マークの置き場所: NPC の頭の少し上。
    def markPos(state: Room.State, npc: Room.Npc): Vec2.Vec2 =
        Vec2.add(cellCenter(state, npc#cell), { x = 0.0, y = -(tile() * 0.72) })

    /// 赤い斜め十字（細い平行四辺形 2 枚）。
    def crossMark(center: Vec2.Vec2): List[Render.PlacedItem] =
        let arm = 4.0;
        let thick = 1.4;
        { at = center, item = Render.polygon(
            { x = -arm, y = -arm + thick } :: { x = -arm + thick, y = -arm } ::
            { x = arm, y = arm - thick } :: { x = arm - thick, y = arm } :: Nil,
            Palette.markLiar(), zMarkLift()) } ::
        { at = center, item = Render.polygon(
            { x = arm - thick, y = -arm } :: { x = arm, y = -arm + thick } ::
            { x = -arm + thick, y = arm } :: { x = -arm, y = arm - thick } :: Nil,
            Palette.markLiar(), zMarkLift()) } :: Nil

    /// 緑の輪（塗りなしの丸い箱 = 枠線だけの円）。
    def ringMark(center: Vec2.Vec2): List[Render.PlacedItem] =
        let d = 9.0;
        { at = Vec2.add(center, { x = -d / 2.0, y = -d / 2.0 }),
          item = Render.box({x = d, y = d}, Palette.markHonest(), zMarkLift())
            |> Render.rounded(d / 2.0)
            |> Render.fade(0.0)
            |> Render.outline(Palette.markHonest(), 1.6) } :: Nil

    /// 正面の NPC に話しかけられるとき、その頭上に上下に揺れる「▼」を出す。
    def talkIndicator(atlas: FontAtlas, state: Room.State): List[Render.PlacedItem] =
        if (state#phase != Room.Phase.Exploring or state#memoOpen or not Option.isEmpty(state#slide))
            Nil
        else
            match Room.facingNpc(state) {
                case None      => Nil
                case Some(npc) =>
                    let bobY = RenderUtil.sinF(state#idlePhase * Vec2.tau()) * 1.5;
                    let pos = Vec2.add(cellCenter(state, npc#cell),
                        { x = -4.0, y = -(tile() * 1.15) + bobY });
                    ({ at = pos, item = Render.textTinted("▼", atlas, 8.0, Palette.talkIndicator(), zIndicatorLift()) } :: Nil)
                        |> Depth.place(band(state), footY(cellCenter(state, npc#cell)))
            }
}
