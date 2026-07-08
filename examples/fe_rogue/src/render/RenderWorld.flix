// RenderWorld — fe_rogue の render-from-World（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
mod RenderWorld {
    use Render.RenderItem
    use Vec2.Vec2

    /// ユニット本体を **sprite ノード無し**で直描きする。在籍・見た目・位置の全てが World 由来
    /// （scene を読まない）: 在籍=playerIds/enemyIds、見た目=resource store（playerResource/enemyResource）、
    /// アニメ frame=unitAnim store（elapsed→frame を純関数導出）、flipH/暗転=unitFlipH/unitModulate
    /// store、死亡点滅 alpha=dyingElapsed→`EnemyScene.deathBlinkAlpha`。
    /// 位置は `World.visualPosOf`（静止=セル中心／移動=renderPos 補間／lunge=往復導出）。
    /// 可視ゲート: 味方 hidden=playerHidden store、敵=明るい穴 `holesOpt`（fog 由来の共有 lit ゲート）。
    /// 重なり順は Godot の Y-sort 準拠「画面下（y 大）ほど手前」＝描画位置 y の昇順に並べて描く
    /// （zIndex は共通の spriteZIndex・同 z 内は列順が描画順。同 y は味方→敵の安定順）。
    pub def renderUnits(world: World, holesOpt: Option[List[GridRect]],
                         transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        let players = World.playerIdsOf(world)
            |> List.filter(id -> not World.playerHiddenOf(World.EntityRef.Player(id), world))
            |> List.flatMap(id ->
                World.playerResourceOf(World.EntityRef.Player(id), world)
                    |> Option.flatMap(res -> unitInput(World.EntityRef.Player(id),
                                                        res#sprite, res#spriteFrames, world))
                    |> Option.toList);
        let enemies = World.enemyIdsOf(world)
            |> List.filter(id -> {
                let lit = holesOpt |> Option.map(holes -> EnemyScene.isLitIn(id, holes, world));
                lit |> Option.getWithDefault(false)
            })
            |> List.flatMap(id ->
                World.enemyResourceOf(World.EntityRef.Enemy(id), world)
                    |> Option.flatMap(res -> unitInput(World.EntityRef.Enemy(id), res#sprite, None, world))
                    |> Option.toList);
        List.append(players, enemies)
            |> List.sortBy(u -> (u#pos#y, drawRank(u#ref)))
            |> List.flatMap(u -> unitDraw(u#ref, u#pos, u#sprite, u#frames, world, transform))

    /// Y-sort の同値タイブレーク（味方→敵、各 faction 内は id 昇順）。sort の安定性に
    /// 依存せず同 y の描画順を決定的にする。
    def drawRank(ref: World.EntityRef): (Int32, Int32) = match ref {
        case World.EntityRef.Player(id) => (0, id)
        case World.EntityRef.Enemy(id)  => (1, id)
    }

    /// 1 ユニットの描画入力（描画位置つき）。未 spawn（pos 導出不能）は None＝描かない。
    def unitInput(ref: World.EntityRef, spriteRes: Sprite.SpriteResource,
                   frames: Option[SpriteFrames], world: World):
            Option[{ref = World.EntityRef, pos = Vec2,
                    sprite = Sprite.SpriteResource, frames = Option[SpriteFrames]}] =
        World.visualPosOf(ref, world)
            |> Option.map(p -> {ref = ref, pos = p, sprite = spriteRes, frames = frames})

    /// アニメ定義と再生経過秒から現在コマを導出する（engine `AnimatedSprite2D.advanceFrame` と同値の
    /// 純関数版）。コマ毎 duration 倍率・loop/非 loop（末尾で停止）対応。
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

    /// カメラの投影（描画変換）。視点は World の cameraSmoothPos（`CameraView.projectionOf`）が権威。
    /// Game.flix が**フレーム 1 回**計算して全 render 関数へ渡す（各 render 関数が個別に呼ばずに共有する）。
    pub def viewTransform(): CameraProjection.Projection \ {GameEngine.Game, World.WorldQuery} =
        let vp = GameEngine.Game.getViewportRect();
        CameraView.projectionOf(World.WorldQuery.get(), {width = vp#size#x, height = vp#size#y})

    /// 1 ユニット → Drawable list（resource + store から Sprite2D 値を直組み）。
    /// worldPos は呼び側が `World.visualPosOf` で導出済み（存在 gate 込み）。
    def unitDraw(ref: World.EntityRef, worldPos: Vec2,
                 spriteRes: Sprite.SpriteResource, spriteFrames: Option[SpriteFrames],
                 world: World, transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        {
                let flipH = World.flipHOf(ref, world);
                let modColor = World.modulateOf(ref, world);
                let alpha = World.dyingElapsedOf(ref, world)
                    |> Option.map(EnemyScene.deathBlinkAlpha)
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
                                Sprite2D.make(tex, spriteRes#offset, spriteRes#scale)
                                    |> Sprite2D.setRegionRect(SpriteFrames.frameRegion(a#name, fr, sf))
                            case None =>
                                Sprite2D.make(spriteRes#texture, spriteRes#offset, spriteRes#scale)
                                    |> Sprite2D.setHframes(spriteRes#hframes)
                                    |> Sprite2D.setVframes(spriteRes#vframes)
                                    |> Sprite2D.setFrame(spriteRes#frame)
                        }
                    case _ =>
                        Sprite2D.make(spriteRes#texture, spriteRes#offset, spriteRes#scale)
                            |> Sprite2D.setHframes(spriteRes#hframes)
                            |> Sprite2D.setVframes(spriteRes#vframes)
                            |> Sprite2D.setFrame(spriteRes#frame)
                };
                let node = base
                    |> Sprite2D.setFlipH(flipH)
                    |> CanvasItem.setModulate(modColor)
                    |> Sprite2D.setAlpha(alpha);
                standaloneSprite(node, worldPos, PlayerScene.spriteZIndex(), transform)
        }

    /// ミニマップ（探索済みマップ）を World render System で直描きする。scene にノードを積まず、
    /// World の訪問記憶 / 階段 / 床アイテムと、Map の module 配置 / 地形、味方・敵の World 位置から、
    /// 部屋/床の矩形（Drawable）とプレイヤー/階段/アイテム/敵のマーカー円（Polygon）を組む。画面固定 HUD
    /// なので camera 変換は掛けない（座標は既に screen px）。表示可否は `MinimapState`（M トグル）と
    /// フェーズ（LevelUpView / EnemyTurn は強制非表示）で決める。ダンジョン外（Map 不在）は空。
    /// 訪問記憶の蓄積・M トグルの反転は `MinimapScene.step` が同一フレームで済ませ、ここは描画のみ。
    pub def renderMinimap():
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
            \ {SelectedPlayer.State, World.WorldQuery, MinimapState.State, TurnPhase.State} =
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
                    let litRooms   = MinimapScene.litRoomsDrafted(units, placements, roomCount);
                    let stairsSeen = MinimapScene.stairsDiscovered(visited, placements);
                    let markers    = MinimapScene.collectMarkers(visited, stairsSeen, placements, roomCount, litRooms);
                    MinimapScene.minimapDrawList(({visited = visited, placements = placements,
                        roomCount = roomCount, snapshot = terrain,
                        markers = markers}: MinimapScene.RenderInput))
                }
        }

    /// tiles: World の tileLayers（bake 済ハンドル）を camera 適用して engine の instanced tile 描画コマンドにする。
    /// renderArgs のタイル経路（world 座標→`applyToWorldPos` + `transform#scale`）と同一 spine。
    /// `TileMapRenderCmd` は pub type alias ゆえ直組み（engine 追加なし）。個別 Drawable にせず instanced 維持
    /// （数百〜千セルでも 1 レイヤー 1 draw call）。renderArgs 由来 tileMaps の代わりにこれを renderCommands へ渡す。
    pub def renderTileMaps(world: World, transform: CameraProjection.Projection): List[GameEngine.TileMapRenderCmd] =
        // ダンジョン以外（Title/CharacterSelect・中断後）は盤面未 seed＝タイルなし。`renderFog` と同じ存在
        // ガードで早期 Nil（ダンジョン退場時は MapSetup.clear が tileLayers も空にするので二重の防御）。
        match World.terrainOf(world) {
            case None    => Nil
            case Some(_) =>
                World.tileLayersOf(world)
                    |> List.map(h -> ({
                        textureName = h#textureName,
                        tileSize    = h#tileSize,
                        position    = CameraProjection.worldToViewport(transform, h#worldPos),
                        tileScale   = transform#scale,
                        color       = h#color,
                        zIndex      = h#zIndex,
                        tileVaoId   = h#tileVaoId,
                        tileCount   = h#tileCount
                    }: GameEngine.TileMapRenderCmd))
        }

    /// fog の暗幕（haze）を World render System で描く。frame 共有の「明るい穴」`holesOpt`
    /// （`FogScene.holesNow`）から補集合の矩形（mapRegion/bandDecompose）を組み、solidBox の
    /// Drawable にする。この直描きが唯一の暗幕経路。穴 None（盤面レス画面）は暗幕なし。
    pub def renderFog(holesOpt: Option[List[GridRect]],
                       transform: CameraProjection.Projection): List[GameEngine.Drawable] \ World.WorldQuery =
        match holesOpt {
            case None        => Nil
            case Some(holes) =>
                let placements = World.placementsOf(World.WorldQuery.get());
                let hazeRects  = FogScene.bandDecompose(FogScene.mapRegion(placements), holes);
                List.flatMap(r -> fogRectDrawables(r, transform), hazeRects)
        }

    /// tree に積まない Sprite2D 値 1 枚を screen 座標へ Drawable 化する共通 spine
    /// （P6 直描きの共有ヘルパー。zIndex は呼び側の定数で上書き）。
    def standaloneSprite(sprite: Sprite2D, worldPos: Vec2.Vec2, z: Int32,
                          transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = CameraProjection.worldToViewport(transform, worldPos);
        GameEngine.Renderable.toDrawables(EngineNode.Sprite2DWithState(sprite, ()), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {zIndex = z | d})

    /// 階段を World store + 見た目定数から直描きする。
    ///   存在 = `World.stairsPosOf`（None=未配置）、見た目 = `Stairs.texture/spriteScale/spriteZIndex`、
    ///   fog の lit ゲート = `fogHolesOpt`（可視制御を描画時に判定・origin 基準は fog 本体と同一）。holes=None（Map 不在）は Nil。
    pub def renderStairs(world: World, holesOpt: Option[List[GridRect]],
                          transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        match (holesOpt, World.stairsPosOf(world)) {
            case (Some(holes), Some(cell)) =>
                if (not FogScene.insideAny(cell, holes)) Nil
                else standaloneSprite(
                    Sprite2D.make(Stairs.texture(), Vec2.zero(), Stairs.spriteScale()),
                    MapSnapshot.cellCenter(cell), Stairs.spriteZIndex(), transform)
            case _ => Nil
        }

    /// 宝箱を World.chests store + ChestCatalog の sprite から直描きする。
    /// 位置 = cellCenter + sprite#offset・scale は 1.0 固定（sprite#scale 非適用）。
    pub def renderChests(chestCatalog: ChestCatalog.ChestCatalog, world: World,
                          holesOpt: Option[List[GridRect]],
                          transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        match holesOpt {
            case None => Nil
            case Some(holes) =>
                World.chestsOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d ->
                        if (not FogScene.insideAny(d#gridPos, holes)) Nil
                        else {
                            let sprite = ChestCatalog.lookup(d#chestKey, chestCatalog)#sprite;
                            let center = MapSnapshot.cellCenter(d#gridPos);
                            let pos: Vec2.Vec2 = {x = center#x + sprite#offset#x, y = center#y + sprite#offset#y};
                            let node = Sprite2D.make(sprite#texture, Vec2.zero(), Vec2.one())
                                |> Sprite2D.setHframes(sprite#hframes)
                                |> Sprite2D.setVframes(sprite#vframes)
                                |> Sprite2D.setFrame(sprite#frame);
                            standaloneSprite(node, pos, Chests.chestZIndex(), transform)
                        })
        }

    /// 床アイテムを World.groundItems store + `GroundItems.spriteOf` から直描きする。
    /// 本体（z=5）＋4 方向 1px シフトの縁取り（z=4・薄青・点滅 alpha=pulseAlpha(elapsed)）。
    /// elapsed は stepWorld が tick 済み。lit ゲートは fogHolesOpt（stairs/chests と同型）。
    pub def renderItems(world: World, holesOpt: Option[List[GridRect]],
                         transform: CameraProjection.Projection): List[GameEngine.Drawable] \ GameEngine.Game =
        match holesOpt {
            case None => Nil
            case Some(holes) =>
                World.groundItemsOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d ->
                        if (not FogScene.insideAny(d#gridPos, holes)) Nil
                        else {
                            let sprite0 = GroundItems.spriteOf(d#item);
                            let center = MapSnapshot.cellCenter(d#gridPos);
                            let pos: Vec2.Vec2 = {x = center#x + sprite0#offset#x, y = center#y + sprite0#offset#y};
                            let makeFramed = () ->
                                Sprite2D.make(sprite0#texture, Vec2.zero(), Vec2.one())
                                    |> Sprite2D.setHframes(sprite0#hframes)
                                    |> Sprite2D.setVframes(sprite0#vframes)
                                    |> Sprite2D.setFrame(sprite0#frame);
                            let alpha = GroundItems.pulseAlpha(d#elapsed);
                            let outlines = List.flatMap(entry -> {
                                let (_, delta) = entry;
                                let opos: Vec2.Vec2 = {x = pos#x + delta#x, y = pos#y + delta#y};
                                let node = makeFramed()
                                    |> Sprite2D.setAlpha(alpha)
                                    |> CanvasItem.setModulate(GroundItems.outlineColor());
                                standaloneSprite(node, opos, GroundItems.outlineZIndex(), transform)
                            }, GroundItems.outlineDeltas());
                            List.append(outlines,
                                standaloneSprite(makeFramed(), pos, GroundItems.spriteZIndex(), transform))
                        })
        }

    /// ダメージ数字 fx を World.popupFx store から直描きする（Label2D 値を組む＝tree に積まない）。
    /// 上方向 float は経過比率から導出。fog ゲートは掛けない（戦闘発生セル＝点灯前提）。
    /// 盤面未 seed（タイトル等）は早期 Nil（フロア跨ぎ残骸の誤描画防止）。
    pub def renderPopups(world: World, transform: CameraProjection.Projection):
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
                        let label = Label2D.make(d#text, atlas, DamagePopupFx.fontSize())
                            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
                            |> Label2D.setVerticalAlignment(VerticalAlignment.Bottom)
                            |> CanvasItem.setModulate(d#color);
                        let screenPos = CameraProjection.worldToViewport(transform, pos);
                        GameEngine.Renderable.toDrawables(
                            EngineNode.Label2DWithState(label, ()), screenPos)
                            |> Render.applyCameraScale(transform)
                            |> List.map(dr -> {zIndex = DamagePopupFx.popupZIndex() | dr})
                    })
        }

    /// 爆発 fx を World.explosionFx store から直描きする（コマ番号は経過比率から導出）。
    pub def renderExplosions(world: World, transform: CameraProjection.Projection):
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
                        let sprite = Sprite2D.make(ExplosionFx.texture(), Vec2.zero(),
                                        ({x = d#scale, y = d#scale}: Vec2.Vec2))
                            |> Sprite2D.setHframes(ExplosionFx.hframes())
                            |> Sprite2D.setVframes(ExplosionFx.vframes())
                            |> Sprite2D.setFrame(frame);
                        standaloneSprite(sprite, d#pos, ExplosionFx.zIndex(), transform)
                    })
        }

    /// 魔導書攻撃の炎 3 幕 fx を World.fireShots store から polygon 直描きする（幕・位置・スケールは
    /// elapsed から `FireShotFx` が純関数で導出）。頂点はワールド px ゆえ camera を各頂点に掛けて screen 化する
    /// （`CameraProjection.worldToViewport` は screen = world*scale - offset のアフィン変換ゆえ頂点直変換で zoom も乗る）。
    /// 盤面（Map）が無い画面（Title 等・フロア跨ぎ残骸）は Nil。
    pub def renderFireShots(world: World, transform: CameraProjection.Projection):
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
    def screenPoly(transform: CameraProjection.Projection, cmd: GameEngine.PolygonRenderCmd):
            GameEngine.PolygonRenderCmd =
        {vertices = List.map(v -> CameraProjection.worldToViewport(transform, v), cmd#vertices) | cmd}

    /// 全 grid 範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険範囲）を World render
    /// System で描く。各 mod は「描画セル・色・α」だけ持ち、描画は `RangeOverlay.tileDrawables` の 1 経路に集約
    /// ＝law の汎用化。非表示のオーバーレイはセルが空ゆえ Drawable も空（毎フレーム全種を引いても無害）。
    /// 表示専用ゆえ格納セルがそのまま描画セル（EnemyRange は reachable・MoveRange は drawCells・他は cells）。
    pub def renderRangeOverlays(transform: CameraProjection.Projection): List[GameEngine.Drawable] \ RangeOverlayState.State =
        let tiles = (cells, color, alpha) -> RangeOverlay.tileDrawables(cells, color, alpha, transform);
        List.flatten(
            tiles(MoveRangeScene.drawCells(),     MoveRangeScene.color(),         MoveRangeScene.alpha()) ::
            tiles(MoveAttackRangeScene.cells(),    MoveAttackRangeScene.color(),   MoveAttackRangeScene.alpha()) ::
            tiles(EnemyRangeScene.reachable(),     EnemyRangeScene.color(),        EnemyRangeScene.alpha()) ::
            tiles(EnemyAttackRangeScene.cells(),   EnemyAttackRangeScene.color(),  EnemyAttackRangeScene.alpha()) ::
            tiles(PlayerAttackRangeScene.cells(),  PlayerAttackRangeScene.color(), PlayerAttackRangeScene.alpha()) ::
            tiles(TradeRangeScene.cells(),         TradeRangeScene.color(),        TradeRangeScene.alpha()) ::
            tiles(DangerZoneScene.cells(),         DangerZoneScene.color(),        DangerZoneScene.alpha()) ::
            Nil)

    // range の Tile Panel ノードは積まない（renderRangeOverlays が cells から直描きする）。

    /// 選択カーソルの四隅 L字を World render System で直描きする。位置は `CursorState.renderPos`
    /// （スライド補間の視覚位置＝単一権威）、可視は `CursorState.visible`（`CursorScene.setVisible` が
    /// 書く真実源）。L字の並び・色・zIndex は `CursorScene` の定数。非表示のフレームは Nil。
    /// 盤面（Map）が無い画面（Title 等）も Nil — CursorState は常在 resource のため、
    /// visible フラグだけでは盤面レス画面を弾けない（Minimap と同じ Map 存在ゲート）。
    pub def renderCursor(world: World, transform: CameraProjection.Projection):
            List[GameEngine.Drawable] \ CursorState.State =
        if (not World.hasBoard(world)) Nil
        else if (not CursorState.isVisible()) Nil
        else {
            let center = CursorState.renderPos();
            List.flatMap(box -> cursorCornerDrawables(center, box, transform),
                         CursorScene.cornerBoxes())
        }

    /// 1 枚の四隅ボックス → box Drawable（camera 適用）。box#offset はセル中心からの
    /// 左上オフセット。world 上の左上を camera 変換し、px サイズを zoom 倍する（fogRectDrawables と対称）。
    def cursorCornerDrawables(center: Vec2, box: {offset = Vec2, size = Vec2},
                               transform: CameraProjection.Projection): List[GameEngine.Drawable] =
        let worldTopLeft: Vec2 = {x = center#x + box#offset#x, y = center#y + box#offset#y};
        let screenPos = CameraProjection.worldToViewport(transform, worldTopLeft);
        Render.toDrawables(Render.solidBox(box#size, CursorScene.cornerColor(), CursorScene.cornerZIndex()), screenPos)
            |> Render.applyCameraScale(transform)

    /// 杖・投擲の照準矢印を World render System で直描きする。表示は `StaffAim` / `ThrowAim` フェーズの間だけ。
    /// 位置＝`ArrowCursorState.gridPos` のセル中心、回転＝`ArrowCursorScene.rotationOf(direction)`。
    /// それ以外のフェーズは Nil。
    pub def renderArrowCursor(transform: CameraProjection.Projection):
            List[GameEngine.Drawable] \ {GameEngine.Game, TurnPhase.State, ArrowCursorState.State} =
        let phase = TurnPhase.State.get();
        if (phase != TurnPhase.Phase.StaffAim and phase != TurnPhase.Phase.ThrowAim) Nil
        else {
            let data = ArrowCursorState.State.get();
            let sprite = Sprite2D.make(ArrowCursorScene.texture(), Vec2.zero(), ArrowCursorScene.spriteScale())
                |> Node2D.setRotation(ArrowCursorScene.rotationOf(data#direction));
            standaloneSprite(sprite, MapSnapshot.cellCenter(data#gridPos), ArrowCursorScene.spriteZIndex(), transform)
        }

    /// 1 つの暗幕グリッド矩形 → box Drawable（camera 適用）。位置・サイズ変換は grid × tileSize。
    /// solidBox は alpha=1.0 ゆえ fog 用 alpha に上書きし、scale（=ピクセルサイズ）を
    /// zoom 倍する（unitDraw のスケール処理と対称）。
    def fogRectDrawables(r: GridRect, transform: CameraProjection.Projection): List[GameEngine.Drawable] =
        let s = MapSnapshot.tileSize();
        let posV  = Vec2i.toVec2(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}));
        let sizeV = Vec2i.toVec2(({x = r#x1 - r#x0, y = r#y1 - r#y0}: {x = Int32, y = Int32}));
        let worldPos: Vec2.Vec2 = {x = posV#x * s, y = posV#y * s};
        let sizePx:   Vec2.Vec2 = {x = sizeV#x * s, y = sizeV#y * s};
        let screenPos = CameraProjection.worldToViewport(transform, worldPos);
        Render.toDrawables(Render.solidBox(sizePx, FogScene.fogColor(), FogScene.fogZIndex()), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {alpha = FogScene.fogAlpha() | d})

}
