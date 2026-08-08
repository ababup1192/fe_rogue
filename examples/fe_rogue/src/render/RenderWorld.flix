// RenderWorld — fe_rogue の render-from-World（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
mod RenderWorld {
    use Render.Item
    use Vec2.Vec2

    /// ユニット本体を **sprite ノード無し**で直描きする。在籍・見た目・位置の全てが World 由来
    /// （scene を読まない）: 在籍=playerIds/enemyIds、見た目=resource store（playerResource/enemyResource）、
    /// アニメ frame=unitAnim store（elapsed→frame を純関数導出）、flipH/暗転=unitFlipH/unitModulate
    /// store、死亡点滅 alpha=dyingElapsed→`EnemyDriver.deathBlinkAlpha`。
    /// 位置は `World.visualPosOf`（静止=セル中心／移動=renderPos 補間／lunge=往復導出）。
    /// 可視ゲート: 味方 hidden=playerHidden store、敵=明るい穴 `holesOpt`（fog 由来の共有 lit ゲート）。
    /// 重なり順は「画面下（y 大）ほど手前」＝足元 y を Depth の帯で zIndex に写す。
    /// 同じ z に丸まった同士は列順が描画順なので、味方（id 昇順）→敵（id 昇順）の列組みが
    /// 同値の順を決定的にする。
    pub def renderUnits(world: World, holesOpt: Option[List[GridRect]],
                         transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let players = World.playerIdsOf(world)
            |> List.filter(id -> not World.playerHiddenOf(World.EntityRef.Player(id), world))
            |> List.flatMap(id ->
                World.playerResourceOf(World.EntityRef.Player(id), world)
                    |> Option.flatMap(res -> unitInput(World.EntityRef.Player(id),
                                                        res#sprite, res#spriteFrames, world))
                    |> Option.toList);
        let enemies = World.enemyIdsOf(world)
            |> List.filter(id -> {
                let lit = holesOpt |> Option.map(holes -> EnemyDriver.isLitIn(id, holes, world));
                lit |> Option.getWithDefault(false)
            })
            |> List.flatMap(id ->
                World.enemyResourceOf(World.EntityRef.Enemy(id), world)
                    |> Option.flatMap(res -> unitInput(World.EntityRef.Enemy(id), res#sprite, None, world))
                    |> Option.toList);
        let band = unitBand(world);
        List.append(players, enemies)
            |> List.flatMap(u -> unitDraw(u#ref, u#pos, u#sprite, u#frames, world, band, transform))

    /// ユニットの前後の帯。盤面の縦幅を z 100..980 に割り当て、足元が下のユニットほど
    /// 手前に出す。y はユニット位置（`visualPosOf`）と同じ `cellCenter` の空間＝グリッド
    /// 原点 0 起点で測る。盤面レス画面は幅ゼロの帯（zAt が常に back を返す）。
    def unitBand(world: World): Depth.Band =
        match World.terrainOf(world) {
            case Some(m) =>
                { back = unitZBack(), front = unitZFront(),
                  top = 0.0,
                  bottom = Int32.toFloat64(m#usedRect#size#y) * m#tileSize }
            case None =>
                { back = unitZBack(), front = unitZBack(), top = 0.0, bottom = 0.0 }
        }

    /// ユニット帯の z 範囲。下は宝箱（6）より上、上は照準矢印（1000）より下に収める。
    def unitZBack(): Int32 = 100
    def unitZFront(): Int32 = 980

    /// 1 ユニットの描画入力（描画位置つき）。未 spawn（pos 導出不能）は None＝描かない。
    def unitInput(ref: World.EntityRef, spriteRes: SpriteRes.SpriteResource,
                   frames: Option[SpriteFrames], world: World):
            Option[{ref = World.EntityRef, pos = Vec2,
                    sprite = SpriteRes.SpriteResource, frames = Option[SpriteFrames]}] =
        World.visualPosOf(ref, world)
            |> Option.map(p -> {ref = ref, pos = p, sprite = spriteRes, frames = frames})

    /// アニメ定義と再生経過秒から現在コマを導出する純関数。
    /// コマ毎 duration 倍率・loop/非 loop（末尾で停止）対応。
    def frameFromElapsed(anim: SpriteFrames.Animation, elapsed: Float64): Int32 =
        let base = 1.0 / anim#speed;
        let durs = anim#frames |> List.map(f -> base * f#duration);
        let cycle = List.foldLeft((acc, x) -> acc + x, 0.0, durs);
        let n = List.length(durs);
        if (n == 0 or cycle <= 0.0) 0
        else {
            let t0 = if (anim#loop) elapsed - cycle * Float64.floor(elapsed / cycle) else elapsed;
            let (idx, _) = List.foldLeft((st, d) -> {
                let (i, remaining) = st;
                if (remaining < 0.0) (i, remaining)                 // 確定済み
                else if (remaining < d) (i, -1.0)                    // このコマ内
                else (i + 1, remaining - d)
            }, (0, t0), durs);
            Int32.min(idx, n - 1)
        }

    /// カメラの ViewTransform（描画変換）。視点は `CameraState` resource（scene ノードなし）が権威。
    /// Game.flix が**フレーム 1 回**計算して全 render 関数へ渡す（各 render 関数が個別に呼ばずに共有する）。
    pub def viewTransform(): Projection.ViewTransform \ {GameEngine.Game, CameraState.State} =
        let vp = GameEngine.Game.getViewportRect();
        CameraState.viewTransform({viewportWidth = vp#size#x, viewportHeight = vp#size#y})

    /// 1 ユニット → Drawable list（resource + store から Sprite 値を直組み）。
    /// worldPos は呼び側が `World.visualPosOf` で導出済み（存在 gate 込み）。
    def unitDraw(ref: World.EntityRef, worldPos: Vec2,
                 spriteRes: SpriteRes.SpriteResource, spriteFrames: Option[SpriteFrames],
                 world: World, band: Depth.Band,
                 transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        {
                let flipH = World.flipHOf(ref, world);
                let modColor = World.modulateOf(ref, world);
                let alpha = World.dyingElapsedOf(ref, world)
                    |> Option.map(EnemyDriver.deathBlinkAlpha)
                    |> Option.getWithDefault(1.0f32);
                // アニメ個体は unitAnim store の (name, elapsed) から現在コマの texture/region を導出、
                // 静止個体は resource の hframes/vframes/定数 frame をそのまま使う。
                let base = match (spriteFrames, World.unitAnimOf(ref, world)) {
                    case (Some(sf), Some(a)) =>
                        match SpriteFrames.getAnimation(a#name, sf) {
                            case Some(animDef) =>
                                let fr = frameFromElapsed(animDef, a#elapsed);
                                let tex = SpriteFrames.frameTexture(a#name, fr, sf)
                                    |> Option.getWithDefault(spriteRes#texture);
                                Sprite.make(tex, spriteRes#offset, spriteRes#scale)
                                    |> Sprite.setRegionRect(SpriteFrames.frameRegion(a#name, fr, sf))
                            case None =>
                                Sprite.make(spriteRes#texture, spriteRes#offset, spriteRes#scale)
                                    |> Sprite.setHframes(spriteRes#hframes)
                                    |> Sprite.setVframes(spriteRes#vframes)
                                    |> Sprite.setFrame(spriteRes#frame)
                        }
                    case _ =>
                        Sprite.make(spriteRes#texture, spriteRes#offset, spriteRes#scale)
                            |> Sprite.setHframes(spriteRes#hframes)
                            |> Sprite.setVframes(spriteRes#vframes)
                            |> Sprite.setFrame(spriteRes#frame)
                };
                let node = base
                    |> Sprite.setFlipH(flipH)
                    |> Sprite.mapVisual(Visual.setColor(modColor))
                    |> Sprite.setAlpha(alpha);
                standaloneSprite(node, worldPos,
                    Depth.zAt(band, worldPos#y + MapSnapshot.tileSize() / 2.0), transform)
        }

    /// ミニマップ（探索済みマップ）を World render System で直描きする。scene にノードを積まず、
    /// World の訪問記憶 / 階段 / 床アイテムと、Map の module 配置 / 地形、味方・敵の World 位置から、
    /// 部屋/床の矩形（Drawable）とプレイヤー/階段/アイテム/敵のマーカー円（Polygon）を組む。画面固定 HUD
    /// なので camera 変換は掛けない（座標は既に screen px）。表示可否は `MinimapState`（M トグル）と
    /// フェーズ（LevelUpView / EnemyTurn は強制非表示）で決める。ダンジョン外（Map 不在）は空。
    /// 訪問記憶の蓄積・M トグルの反転は `MinimapDriver.step` が同一フレームで済ませ、ここは描画のみ。
    pub def renderMinimap():
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
            \ {SelectedPlayer.State, World.WorldQuery, TurnPhase.State, MinimapState.State} =
        let world = World.WorldQuery.get();
        match World.terrainOf(world) {
            case None    => {drawables = Nil, polygons = Nil}
            case Some(terrain) =>
                let phase   = TurnPhase.State.get();
                // レベルアップ画面・敵ターン中は隠す（M トグルの記憶 visible は維持）。
                let hidden  = phase == TurnPhase.Phase.LevelUpView or phase == TurnPhase.Phase.EnemyTurn;
                let visible = MinimapState.State.get()#visible;
                if (not (visible and not hidden)) {drawables = Nil, polygons = Nil}
                else {
                    let visited    = World.visitedModulesOf(world);
                    let placements = World.placementsOf(world);
                    let roomCount  = World.roomCountOf(world);
                    // litRooms（敵赤丸の絞り込み）は fog と同じく origin 基準。移動ドラフト中に新しく
                    // 踏み込んだ部屋は確定まで数えない。在籍・live 位置とも World 権威。
                    let drafts     = SelectedPlayer.State.get()#drafts;
                    let units      = World.fogUnitsOf(world)
                        |> List.map(d -> {+origin = MoveDraft.originOf(d#id, drafts)
                                                        |> Option.getWithDefault(d#gridPos) | d});
                    let litRooms   = MinimapDriver.litRoomsDrafted(units, placements, roomCount);
                    let stairsSeen = MinimapDriver.stairsDiscovered(visited, placements);
                    let markers    = MinimapDriver.collectMarkers(visited, stairsSeen, placements, roomCount, litRooms);
                    MinimapDriver.minimapDrawList(({visited = visited, placements = placements,
                        roomCount = roomCount, snapshot = terrain,
                        markers = markers}: MinimapDriver.RenderInput))
                }
        }

    /// tiles: World の tileLayers（bake 済ハンドル）を camera 適用して engine の instanced tile 描画コマンドにする。
    /// renderArgs のタイル経路（world 座標→`applyToWorldPos` + `transform#scale`）と同一 spine。
    /// `TileMapRenderCmd` は pub type alias ゆえ直組み（engine 追加なし）。個別 Drawable にせず instanced 維持
    /// （数百〜千セルでも 1 レイヤー 1 draw call）。renderArgs 由来 tileMaps の代わりにこれを renderCommands へ渡す。
    pub def renderTileMaps(world: World, transform: Projection.ViewTransform): List[GameEngine.TileMapRenderCmd] =
        // ダンジョン以外（Title/CharacterSelect・中断後）は盤面未 seed＝タイルなし。`renderFog` と同じ存在
        // ガードで早期 Nil（ダンジョン退場時は MapSetup.clear が tileLayers も空にするので二重の防御）。
        match World.terrainOf(world) {
            case None    => Nil
            case Some(_) =>
                World.tileLayersOf(world)
                    |> List.map(h -> ({
                        textureName = h#textureName,
                        tileSize    = h#tileSize,
                        position    = Projection.applyToWorldPos(transform, h#worldPos),
                        tileScale   = transform#scale,
                        color       = h#color,
                        zIndex      = h#zIndex,
                        tileVaoId   = h#tileVaoId,
                        tileCount   = h#tileCount
                    }: GameEngine.TileMapRenderCmd))
        }

    /// fog の暗幕（haze）を World render System で描く。frame 共有の「明るい穴」`holesOpt`
    /// （`Fog.holesNow`）から補集合の矩形（mapRegion/bandDecompose）を組み、box の
    /// Drawable にする。この直描きが唯一の暗幕経路。穴 None（盤面レス画面）は暗幕なし。
    pub def renderFog(holesOpt: Option[List[GridRect]],
                       transform: Projection.ViewTransform): List[GameEngine.Drawable] \ World.WorldQuery =
        match holesOpt {
            case None        => Nil
            case Some(holes) =>
                let placements = World.placementsOf(World.WorldQuery.get());
                let hazeRects  = Fog.bandDecompose(Fog.mapRegion(placements), holes);
                List.flatMap(r -> fogRectDrawables(r, transform), hazeRects)
        }

    /// tree に積まない Sprite 値 1 枚を screen 座標へ Drawable 化する共通 spine
    /// （P6 直描きの共有ヘルパー。zIndex は呼び側の定数で上書き）。
    def standaloneSprite(sprite: Sprite, worldPos: Vec2.Vec2, z: Int32,
                          transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Projection.applyToWorldPos(transform, worldPos);
        GameEngine.Renderable.toDrawables(sprite, screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {zIndex = z | d})

    /// 階段を World store + 見た目定数から直描きする。
    ///   存在 = `World.stairsPosOf`（None=未配置）、見た目 = `Stairs.texture/spriteScale/spriteZIndex`、
    ///   fog の lit ゲート = `fogHolesOpt`（可視制御を描画時に判定・origin 基準は fog 本体と同一）。holes=None（Map 不在）は Nil。
    pub def renderStairs(world: World, holesOpt: Option[List[GridRect]],
                          transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        match (holesOpt, World.stairsPosOf(world)) {
            case (Some(holes), Some(cell)) =>
                if (not Fog.insideAny(cell, holes)) Nil
                else standaloneSprite(
                    Sprite.make(Stairs.texture(), Vec2.zero(), Stairs.spriteScale()),
                    MapSnapshot.cellCenter(cell), Stairs.spriteZIndex(), transform)
            case _ => Nil
        }

    /// 宝箱を World.chests store + ChestCatalog の sprite から直描きする。
    /// 位置 = cellCenter + sprite#offset・scale は 1.0 固定（sprite#scale 非適用）。
    pub def renderChests(chestCatalog: ChestCatalog.ChestCatalog, world: World,
                          holesOpt: Option[List[GridRect]],
                          transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        match holesOpt {
            case None => Nil
            case Some(holes) =>
                World.chestsOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d ->
                        if (not Fog.insideAny(d#gridPos, holes)) Nil
                        else {
                            let sprite = ChestCatalog.lookup(d#chestKey, chestCatalog)#sprite;
                            let center = MapSnapshot.cellCenter(d#gridPos);
                            let pos: Vec2.Vec2 = {x = center#x + sprite#offset#x, y = center#y + sprite#offset#y};
                            let node = Sprite.make(sprite#texture, Vec2.zero(), Vec2.one())
                                |> Sprite.setHframes(sprite#hframes)
                                |> Sprite.setVframes(sprite#vframes)
                                |> Sprite.setFrame(sprite#frame);
                            standaloneSprite(node, pos, Chests.chestZIndex(), transform)
                        })
        }

    /// 床アイテムを World.groundItems store + `GroundItems.spriteOf` から直描きする。
    /// 本体（z=5）＋4 方向 1px シフトの縁取り（z=4・薄青・点滅 alpha=pulseAlpha(elapsed)）。
    /// elapsed は stepWorld が tick 済み。lit ゲートは fogHolesOpt（stairs/chests と同型）。
    pub def renderItems(world: World, holesOpt: Option[List[GridRect]],
                         transform: Projection.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        match holesOpt {
            case None => Nil
            case Some(holes) =>
                World.groundItemsOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d ->
                        if (not Fog.insideAny(d#gridPos, holes)) Nil
                        else {
                            let sprite0 = GroundItems.spriteOf(d#item);
                            let center = MapSnapshot.cellCenter(d#gridPos);
                            let pos: Vec2.Vec2 = {x = center#x + sprite0#offset#x, y = center#y + sprite0#offset#y};
                            let makeFramed = () ->
                                Sprite.make(sprite0#texture, Vec2.zero(), Vec2.one())
                                    |> Sprite.setHframes(sprite0#hframes)
                                    |> Sprite.setVframes(sprite0#vframes)
                                    |> Sprite.setFrame(sprite0#frame);
                            let alpha = GroundItems.pulseAlpha(d#elapsed);
                            let outlines = List.flatMap(entry -> {
                                let (_, delta) = entry;
                                let opos: Vec2.Vec2 = {x = pos#x + delta#x, y = pos#y + delta#y};
                                let node = makeFramed()
                                    |> Sprite.setAlpha(alpha)
                                    |> Sprite.mapVisual(Visual.setColor(GroundItems.outlineColor()));
                                standaloneSprite(node, opos, GroundItems.outlineZIndex(), transform)
                            }, GroundItems.outlineDeltas());
                            List.append(outlines,
                                standaloneSprite(makeFramed(), pos, GroundItems.spriteZIndex(), transform))
                        })
        }

    /// ダメージ数字 fx を World.popupFx store から直描きする（Text 値を組む＝tree に積まない）。
    /// 上方向 float は経過比率から導出。fog ゲートは掛けない（戦闘発生セル＝点灯前提）。
    /// 盤面未 seed（タイトル等）は早期 Nil（フロア跨ぎ残骸の誤描画防止）。
    pub def renderPopups(world: World, transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match World.terrainOf(world) {
            case None    => Nil
            case Some(_) =>
                let atlas = GameEngine.Game.getFontAtlas(DamagePopupFx.fontName());
                World.popupFxOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d -> {
                        let ratio = (d#total - d#remaining) / d#total;
                        let pos: Vec2.Vec2 = {x = d#pos#x, y = d#pos#y - DamagePopupFx.floatDistancePx() * ratio};
                        let label = Text.make(d#text, atlas, DamagePopupFx.fontSize())
                            |> Text.setHorizontalAlignment(HorizontalAlignment.Center)
                            |> Text.setVerticalAlignment(VerticalAlignment.Bottom)
                            |> Text.mapVisual(Visual.setColor(d#color));
                        let screenPos = Projection.applyToWorldPos(transform, pos);
                        GameEngine.Renderable.toDrawables(label, screenPos)
                            |> Render.applyCameraScale(transform)
                            |> List.map(dr -> {zIndex = DamagePopupFx.popupZIndex() | dr})
                    })
        }

    /// 爆発 fx を World.explosionFx store から直描きする（コマ番号は経過比率から導出）。
    pub def renderExplosions(world: World, transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match World.terrainOf(world) {
            case None    => Nil
            case Some(_) =>
                World.explosionFxOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d -> {
                        let ratio = (d#total - d#remaining) / d#total;
                        let raw = Float64.truncateToInt32(
                                    Float64.floor(ratio * Int32.toFloat64(ExplosionFx.frameCount())));
                        let frame = Int32.max(0, Int32.min(ExplosionFx.frameCount() - 1, raw));
                        let sprite = Sprite.make(ExplosionFx.texture(), Vec2.zero(),
                                        ({x = d#scale, y = d#scale}: Vec2.Vec2))
                            |> Sprite.setHframes(ExplosionFx.hframes())
                            |> Sprite.setVframes(ExplosionFx.vframes())
                            |> Sprite.setFrame(frame);
                        standaloneSprite(sprite, d#pos, ExplosionFx.zIndex(), transform)
                    })
        }

    /// 魔導書攻撃の炎 3 幕 fx を World.fireShots store から polygon 直描きする（幕・位置・スケールは
    /// elapsed から `FireShotFx` が純関数で導出）。頂点はワールド px ゆえ camera を各頂点に掛けて screen 化する
    /// （`Projection.applyToWorldPos` は screen = world*scale - offset のアフィン変換ゆえ頂点直変換で zoom も乗る）。
    /// 盤面（Map）が無い画面（Title 等・フロア跨ぎ残骸）は Nil。
    pub def renderFireShots(world: World, transform: Projection.ViewTransform):
            List[GameEngine.PolygonRenderCmd] =
        if (not World.hasBoard(world)) Nil
        else
            World.fireShotsOf(world)
                |> Map.valuesOf
                |> List.flatMap(d -> {
                    let elapsed = d#total - d#remaining;
                    FireShotFx.quads(d#caster, d#target, d#seed, elapsed)
                        |> List.map(cmd -> screenPoly(transform, cmd))
                })

    /// ワールド座標の polygon 1 枚を screen 座標へ（各頂点に camera を掛けるだけ）。
    def screenPoly(transform: Projection.ViewTransform, cmd: GameEngine.PolygonRenderCmd):
            GameEngine.PolygonRenderCmd =
        {vertices = List.map(v -> Projection.applyToWorldPos(transform, v), cmd#vertices) | cmd}

    /// 全 grid 範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険範囲）を World render
    /// System で描く。各 mod は「描画セル・色・α」だけ持ち、描画は `RangeOverlay.tileDrawables` の 1 経路に集約
    /// ＝law の汎用化。非表示のオーバーレイはセルが空ゆえ Drawable も空（毎フレーム全種を引いても無害）。
    /// 表示専用ゆえ格納セルがそのまま描画セル（EnemyRange は reachable・MoveRange は drawCells・他は cells）。
    pub def renderRangeOverlays(transform: Projection.ViewTransform): List[GameEngine.Drawable] \ RangeOverlayState.State =
        let tiles = (cells, color, alpha) -> RangeOverlay.tileDrawables(cells, color, alpha, transform);
        List.flatten(
            tiles(MoveRange.drawCells(),     MoveRange.color(),         MoveRange.alpha()) ::
            tiles(MoveAttackRange.cells(),    MoveAttackRange.color(),   MoveAttackRange.alpha()) ::
            tiles(EnemyRange.reachable(),     EnemyRange.color(),        EnemyRange.alpha()) ::
            tiles(EnemyAttackRange.cells(),   EnemyAttackRange.color(),  EnemyAttackRange.alpha()) ::
            tiles(PlayerAttackRange.cells(),  PlayerAttackRange.color(), PlayerAttackRange.alpha()) ::
            tiles(TradeRange.cells(),         TradeRange.color(),        TradeRange.alpha()) ::
            tiles(DangerZone.cells(),         DangerZone.color(),        DangerZone.alpha()) ::
            Nil)

    // range の Tile は描画物として積まない（renderRangeOverlays が cells から直描きする）。

    /// 選択カーソルの四隅 L字を World render System で直描きする。位置は `CursorState.renderPos`
    /// （スライド補間の視覚位置＝単一権威）、可視は `CursorState.visible`（`CursorDriver.setVisible` が
    /// 書く真実源）。L字の並び・色・zIndex は `CursorDriver` の定数。非表示のフレームは Nil。
    /// 盤面（Map）が無い画面（Title 等）も Nil — CursorState は常在 resource のため、
    /// visible フラグだけでは盤面レス画面を弾けない（Minimap と同じ Map 存在ゲート）。
    pub def renderCursor(world: World, transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ CursorState.State =
        if (not World.hasBoard(world)) Nil
        else if (not CursorState.isVisible()) Nil
        else {
            let center = CursorState.renderPos();
            List.flatMap(box -> cursorCornerDrawables(center, box, transform),
                         CursorDriver.cornerBoxes())
        }

    /// 1 枚の四隅ボックス → box Drawable（camera 適用）。box#offset はセル中心からの
    /// 左上オフセット。world 上の左上を camera 変換し、px サイズを zoom 倍する（fogRectDrawables と対称）。
    def cursorCornerDrawables(center: Vec2, box: {offset = Vec2, size = Vec2},
                               transform: Projection.ViewTransform): List[GameEngine.Drawable] =
        let worldTopLeft: Vec2 = {x = center#x + box#offset#x, y = center#y + box#offset#y};
        let screenPos = Projection.applyToWorldPos(transform, worldTopLeft);
        Render.toDrawables(Render.box(box#size, CursorDriver.cornerColor(), CursorDriver.cornerZIndex()), screenPos)
            |> Render.applyCameraScale(transform)

    /// 杖・投擲の照準矢印を World render System で直描きする。表示は `StaffAim` / `ThrowAim` フェーズの間だけ。
    /// 位置＝`ArrowCursorState.gridPos` のセル中心、回転＝`ArrowCursorDriver.rotationOf(direction)`。
    /// それ以外のフェーズは Nil。
    pub def renderArrowCursor(transform: Projection.ViewTransform):
            List[GameEngine.Drawable] \ {GameEngine.Game, TurnPhase.State, ArrowCursorState.State} =
        let phase = TurnPhase.State.get();
        if (phase != TurnPhase.Phase.StaffAim and phase != TurnPhase.Phase.ThrowAim) Nil
        else {
            let data = ArrowCursorState.State.get();
            let sprite = Sprite.make(ArrowCursorDriver.texture(), Vec2.zero(), ArrowCursorDriver.spriteScale())
                |> Sprite.mapTransform(Transform.setRotation(ArrowCursorDriver.rotationOf(data#direction)));
            standaloneSprite(sprite, MapSnapshot.cellCenter(data#gridPos), ArrowCursorDriver.spriteZIndex(), transform)
        }

    /// 1 つの暗幕グリッド矩形 → box Drawable（camera 適用）。位置・サイズ変換は grid × tileSize。
    /// box は alpha=1.0 ゆえ fog 用 alpha に上書きし、scale（=ピクセルサイズ）を
    /// zoom 倍する（unitDraw のスケール処理と対称）。
    def fogRectDrawables(r: GridRect, transform: Projection.ViewTransform): List[GameEngine.Drawable] =
        let s = MapSnapshot.tileSize();
        let posV  = Vec2i.toVec2(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}));
        let sizeV = Vec2i.toVec2(({x = r#x1 - r#x0, y = r#y1 - r#y0}: {x = Int32, y = Int32}));
        let worldPos: Vec2.Vec2 = {x = posV#x * s, y = posV#y * s};
        let sizePx:   Vec2.Vec2 = {x = sizeV#x * s, y = sizeV#y * s};
        let screenPos = Projection.applyToWorldPos(transform, worldPos);
        Render.toDrawables(Render.box(sizePx, Fog.fogColor(), Fog.fogZIndex()), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {alpha = Fog.fogAlpha() | d})

}
