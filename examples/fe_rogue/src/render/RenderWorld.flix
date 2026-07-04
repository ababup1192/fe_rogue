// RenderWorld — fe_rogue の render-from-World（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
mod RenderWorld {
    use Render.RenderItem
    use Vec2.Vec2

    /// ユニット本体を **sprite ノード無し**で直描きする。見た目=resource（catalog）、
    /// アニメ frame=unitAnim store（elapsed→frame を純関数導出）、flipH/暗転=unitFlipH/unitModulate
    /// store、死亡点滅 alpha=dyingElapsed→`EnemyScene.deathBlinkAlpha`。位置は marker global
    /// （移動 tween/lunge の位置権威は marker のまま）。存在 gate=World.posOf、
    /// フォグ可視=敵 marker の isVisible（applyFog の真実源）、味方 hidden=Data#hidden。
    pub def renderUnits(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let players = PlayerScene.getAll(scene)
            |> List.filter(d -> not d#hidden)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Player(d#id), PlayerScene.playerPath(d#id),
                                           d#resource#sprite, d#resource#spriteFrames, world, transform, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.filter(d -> EnemyScene.isVisible(d#id, scene))
            |> List.flatMap(d -> unitDraw(World.EntityRef.Enemy(d#id), EnemyScene.enemyPath(d#id),
                                           d#resource#sprite, None, world, transform, scene));
        List.append(players, enemies)

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

    /// カメラの ViewTransform（描画変換）。視点は `CameraState` resource（scene ノードなし）が権威。
    /// Game.flix が**フレーム 1 回**計算して全 render 関数へ渡す（各 render 関数が個別に呼ばずに共有する）。
    pub def viewTransform(_scene: Scene[NodeTag]): Camera2D.ViewTransform \ {GameEngine.Game, CameraState.State} =
        let vp = GameEngine.Game.getViewportRect();
        CameraState.viewTransform({viewportWidth = vp#size#x, viewportHeight = vp#size#y})

    /// 1 ユニット → Drawable list（resource + store から Sprite2D 値を直組み）。
    def unitDraw(ref: World.EntityRef, unitPath: NodePath,
                 spriteRes: Sprite.SpriteResource, spriteFrames: Option[SpriteFrames],
                 world: World, transform: Camera2D.ViewTransform,
                 scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        // 存在 gate = World.posOf（World が論理位置を持つユニットのみ描く）。
        match World.posOf(ref, world) {
            case None    => Nil
            case Some(_) =>
                // marker が視覚位置の単一権威（移動=`syncMarkers` の renderPos / lunge=AnimationPlayer /
                // 静止=setGlobalPositionAt）。
                let worldPos = Scene.globalPositionAt(unitPath, scene);
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

    /// 移動（Position tween）した entity の実 scene marker を renderPos に合わせる（marker 単一権威）。
    /// `stepWorld` が返す active∪done の `MarkerMove` を畳み、marker を pos へ置く。marker の子（sprite/武器/HPバー）は
    /// これで一斉に同じ値へ追従＝適用点が揃い、敵の武器アイコン 1 フレームラグが解消（engine tween 退役の受け皿）。
    /// faction 分岐は `EntityScene.path` に閉じ、world→local 変換は engine（`setGlobalPositionAt`）へ委譲（snapTo と同じ）。
    pub def syncMarkers(moved: List[MarkerMove], scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((sc, m) -> Scene.setGlobalPositionAt(EntityScene.path(m#ref), m#pos, sc), scene, moved)

    /// ミニマップ（探索済みマップ）を World render System で直描きする。scene にノードを積まず、
    /// World の訪問記憶 / 階段 / 床アイテムと、Map の module 配置 / 地形、味方・敵の World 位置から、
    /// 部屋/床の矩形（Drawable）とプレイヤー/階段/アイテム/敵のマーカー円（Polygon）を組む。画面固定 HUD
    /// なので camera 変換は掛けない（座標は既に screen px）。表示可否は `MinimapState`（M トグル）と
    /// フェーズ（LevelUpView / EnemyTurn は強制非表示）で決める。ダンジョン外（Map 不在）は空。
    /// 訪問記憶の蓄積・M トグルの反転は `MinimapScene.step` が同一フレームで済ませ、ここは描画のみ。
    pub def renderMinimap(scene: Scene[NodeTag]):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
            \ {SelectedPlayer.State, World.WorldQuery, TurnPhase.State, MinimapState.State} =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => {drawables = Nil, polygons = Nil}
            case Some(_) =>
                let phase   = TurnPhase.State.get();
                // レベルアップ画面・敵ターン中は隠す（M トグルの記憶 visible は維持）。
                let hidden  = phase == TurnPhase.Phase.LevelUpView or phase == TurnPhase.Phase.EnemyTurn;
                let visible = MinimapState.State.get()#visible;
                if (not (visible and not hidden)) {drawables = Nil, polygons = Nil}
                else {
                    let world      = World.WorldQuery.get();
                    let visited    = World.visitedModulesOf(world);
                    let placements = MapScene.getPlacements(scene);
                    let roomCount  = MapScene.getRoomCount(scene);
                    // litRooms（敵赤丸の絞り込み）は fog と同じく origin 基準。移動ドラフト中に新しく
                    // 踏み込んだ部屋は確定まで数えない。live 位置は World 権威。
                    let drafts     = SelectedPlayer.State.get()#drafts;
                    let units      = PlayerScene.getAllWithWorldPos(scene)
                        |> List.map(d -> {id = d#id, gridPos = d#gridPos, hidden = d#hidden,
                                          origin = MoveDraft.originOf(d#id, drafts) |> Option.getWithDefault(d#gridPos)});
                    let litRooms   = MinimapScene.litRoomsDrafted(units, placements, roomCount);
                    let stairsSeen = MinimapScene.stairsDiscovered(visited, placements);
                    let markers    = MinimapScene.collectMarkers(visited, stairsSeen, placements, roomCount, litRooms, scene);
                    MinimapScene.minimapDrawList(({visited = visited, placements = placements,
                        roomCount = roomCount, snapshot = MinimapScene.mapSnapshot(scene),
                        markers = markers}: MinimapScene.RenderInput))
                }
        }

    /// tiles: World の tileLayers（bake 済ハンドル）を camera 適用して engine の instanced tile 描画コマンドにする。
    /// renderArgs のタイル経路（`globalPositionAt`→`applyToWorldPos` + `transform#scale`）と同一 spine。
    /// `TileMapRenderCmd` は pub type alias ゆえ直組み（engine 追加なし）。個別 Drawable にせず instanced 維持
    /// （数百〜千セルでも 1 レイヤー 1 draw call）。renderArgs 由来 tileMaps の代わりにこれを renderCommands へ渡す。
    pub def renderTileMaps(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.TileMapRenderCmd] =
        // ダンジョン以外（Title/CharacterSelect・中断後）は Map ノードが無い＝タイルなし。`renderFog` と同じ存在
        // ガードで早期 Nil。tileLayers は rebuild-gen 変化時にしか bake されず world 越しに残留するため、この画面
        // ガードが無いと Title 等に前フロアのタイルが残留描画される（gen-gate だけでは防げない）。
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => Nil
            case Some(_) =>
                World.tileLayersOf(world)
                    |> List.map(h -> ({
                        textureName = h#textureName,
                        tileSize    = h#tileSize,
                        position    = Camera2D.applyToWorldPos(transform, h#worldPos),
                        tileScale   = transform#scale,
                        color       = h#color,
                        zIndex      = h#zIndex,
                        tileVaoId   = h#tileVaoId,
                        tileCount   = h#tileCount
                    }: GameEngine.TileMapRenderCmd))
        }

    /// fog の暗幕（haze）を World render System で描く。scene の Fog ColorRect プールを使わず、
    /// FogScene の純粋な補集合計算（holesForDraft/mapRegion/bandDecompose）を再利用して暗幕矩形を
    /// solidBox の Drawable にする。敵/アイテムの点灯（可視性）制御は従来どおり FogScene が担い、ここは
    /// 暗幕の描画のみ。scene 側の haze プールは持たず、この直描きが唯一の暗幕経路。
    /// 入力（origin 基準の部屋点灯・通路 torch）は `FogScene.process` と同一＝挙動不変。
    pub def renderFog(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ {SelectedPlayer.State, World.WorldQuery} =
        // ダンジョン以外（タイトル/パーティ選択/メニュー等）は Map ノードが無い＝暗幕なし。
        // `MapScene.getPlacements` は Map 不在で bug! するので、`World.mapSnapshotOpt` と同じ存在ガードで早期 Nil。
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => Nil
            case Some(_) =>
                let drafts     = SelectedPlayer.State.get()#drafts;
                // live 位置は World 上書き Data（scene gridPos twin は退役）。
                let units      = PlayerScene.getAllWithWorldPos(scene)
                    |> List.map(d -> {gridPos = d#gridPos, hidden = d#hidden,
                                      origin = MoveDraft.originOf(d#id, drafts) |> Option.getWithDefault(d#gridPos)});
                let placements = MapScene.getPlacements(scene);
                let roomCount  = MapScene.getRoomCount(scene);
                let holes      = FogScene.holesForDraft(units, placements, roomCount, true);
                let hazeRects  = FogScene.bandDecompose(FogScene.mapRegion(placements), holes);
                List.flatMap(r -> fogRectDrawables(r, transform), hazeRects)
        }

    /// fog の「明るい穴」を frame に 1 回計算し、配置物の直描き（renderStairs/renderChests…）
    /// で共有する lit ゲート入力。Map 不在（タイトル/選択画面）は None＝配置物を描かない。
    pub def fogHolesOpt(scene: Scene[NodeTag]): Option[List[GridRect]] \ {SelectedPlayer.State, World.WorldQuery} =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => None
            case Some(_) =>
                let drafts = SelectedPlayer.State.get()#drafts;
                // live 位置は World 上書き Data（scene gridPos twin は退役）。
                let units  = PlayerScene.getAllWithWorldPos(scene)
                    |> List.map(d -> {gridPos = d#gridPos, hidden = d#hidden,
                                      origin = MoveDraft.originOf(d#id, drafts) |> Option.getWithDefault(d#gridPos)});
                Some(FogScene.holesForDraft(units, MapScene.getPlacements(scene),
                                             MapScene.getRoomCount(scene), true))
        }

    /// tree に積まない Sprite2D 値 1 枚を screen 座標へ Drawable 化する共通 spine
    /// （P6 直描きの共有ヘルパー。zIndex は呼び側の定数で上書き）。
    def standaloneSprite(sprite: Sprite2D, worldPos: Vec2.Vec2, z: Int32,
                          transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        let screenPos = Camera2D.applyToWorldPos(transform, worldPos);
        GameEngine.Renderable.toDrawables(EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {zIndex = z | d})

    /// 階段を World store + 見た目定数から直描きする。
    ///   存在 = `World.stairsPosOf`（None=未配置）、見た目 = `Stairs.texture/spriteScale/spriteZIndex`、
    ///   fog の lit ゲート = `fogHolesOpt`（可視制御を描画時に判定・origin 基準は fog 本体と同一）。holes=None（Map 不在）は Nil。
    pub def renderStairs(world: World, holesOpt: Option[List[GridRect]],
                          transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
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
                          transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
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
                         transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
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
    /// Map 不在（タイトル等）は早期 Nil（フロア跨ぎ残骸の誤描画防止）。
    pub def renderPopups(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
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
                        let screenPos = Camera2D.applyToWorldPos(transform, pos);
                        GameEngine.Renderable.toDrawables(
                            EngineNode.Label2DWithState(label, NodeTag.NoTag), screenPos)
                            |> Render.applyCameraScale(transform)
                            |> List.map(dr -> {zIndex = DamagePopupFx.popupZIndex() | dr})
                    })
        }

    /// 爆発 fx を World.explosionFx store から直描きする（コマ番号は経過比率から導出）。
    pub def renderExplosions(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
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

    /// 全 grid 範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険範囲）を World render
    /// System で描く。各 mod は「描画セル・色・α」だけ持ち、描画は `RangeOverlay.tileDrawables` の 1 経路に集約
    /// ＝law の汎用化。非表示のオーバーレイはセルが空ゆえ Drawable も空（毎フレーム全種を引いても無害）。
    /// 表示専用ゆえ格納セルがそのまま描画セル（EnemyRange は reachable・MoveRange は drawCells・他は cells）。
    pub def renderRangeOverlays(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ RangeOverlayState.State =
        let tiles = (cells, color, alpha) -> RangeOverlay.tileDrawables(cells, color, alpha, transform);
        List.flatten(
            tiles(MoveRangeScene.drawCells(scene),     MoveRangeScene.color(),         MoveRangeScene.alpha()) ::
            tiles(MoveAttackRangeScene.cells(scene),   MoveAttackRangeScene.color(),   MoveAttackRangeScene.alpha()) ::
            tiles(EnemyRangeScene.reachable(scene),    EnemyRangeScene.color(),        EnemyRangeScene.alpha()) ::
            tiles(EnemyAttackRangeScene.cells(scene),  EnemyAttackRangeScene.color(),  EnemyAttackRangeScene.alpha()) ::
            tiles(PlayerAttackRangeScene.cells(scene), PlayerAttackRangeScene.color(), PlayerAttackRangeScene.alpha()) ::
            tiles(TradeRangeScene.cells(scene),        TradeRangeScene.color(),        TradeRangeScene.alpha()) ::
            tiles(DangerZoneScene.cells(scene),        DangerZoneScene.color(),        DangerZoneScene.alpha()) ::
            Nil)

    // range の Tile Panel ノードは積まない（renderRangeOverlays が cells から直描きする）。

    /// 選択カーソルの四隅 L字を World render System で直描きする。位置は `CursorState.renderPos`
    /// （スライド補間の視覚位置＝単一権威）、可視は `CursorState.visible`（`CursorScene.setVisible` が
    /// 書く真実源）。L字の並び・色・zIndex は `CursorScene` の定数。非表示のフレームは Nil。
    /// 盤面（Map）が無い画面（Title 等）も Nil — CursorState は常在 resource のため、
    /// visible フラグだけでは盤面レス画面を弾けない（Minimap と同じ Map 存在ゲート）。
    pub def renderCursor(transform: Camera2D.ViewTransform,
                         scene: Scene[NodeTag]): List[GameEngine.Drawable] \ CursorState.State =
        if (not MapScene.isPresent(scene)) Nil
        else if (not CursorState.isVisible()) Nil
        else {
            let center = CursorState.renderPos();
            List.flatMap(box -> cursorCornerDrawables(center, box, transform),
                         CursorScene.cornerBoxes())
        }

    /// 1 枚の四隅ボックス → box Drawable（camera 適用）。box#offset は Marker2D 原点（セル中心）からの
    /// 左上オフセット。world 上の左上を camera 変換し、px サイズを zoom 倍する（fogRectDrawables と対称）。
    def cursorCornerDrawables(center: Vec2, box: {offset = Vec2, size = Vec2},
                               transform: Camera2D.ViewTransform): List[GameEngine.Drawable] =
        let worldTopLeft: Vec2 = {x = center#x + box#offset#x, y = center#y + box#offset#y};
        let screenPos = Camera2D.applyToWorldPos(transform, worldTopLeft);
        Render.toDrawables(Render.solidBox(box#size, CursorScene.cornerColor(), CursorScene.cornerZIndex()), screenPos)
            |> Render.applyCameraScale(transform)

    /// 杖・投擲の照準矢印を World render System で直描きする。表示は `StaffAim` / `ThrowAim` フェーズの間だけ。
    /// 位置＝`ArrowCursorState.gridPos` のセル中心、回転＝`ArrowCursorScene.rotationOf(direction)`。
    /// それ以外のフェーズは Nil。
    pub def renderArrowCursor(transform: Camera2D.ViewTransform):
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
    def fogRectDrawables(r: GridRect, transform: Camera2D.ViewTransform): List[GameEngine.Drawable] =
        let s = MapSnapshot.tileSize();
        let posV  = Vec2i.toVec2(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}));
        let sizeV = Vec2i.toVec2(({x = r#x1 - r#x0, y = r#y1 - r#y0}: {x = Int32, y = Int32}));
        let worldPos: Vec2.Vec2 = {x = posV#x * s, y = posV#y * s};
        let sizePx:   Vec2.Vec2 = {x = sizeV#x * s, y = sizeV#y * s};
        let screenPos = Camera2D.applyToWorldPos(transform, worldPos);
        Render.toDrawables(Render.solidBox(sizePx, FogScene.fogColor(), FogScene.fogZIndex()), screenPos)
            |> Render.applyCameraScale(transform)
            |> List.map(d -> {alpha = FogScene.fogAlpha() | d})

}
