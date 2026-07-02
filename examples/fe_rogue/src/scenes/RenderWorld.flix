// RenderWorld — B1: fe_rogue の render-from-World extract（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
//
// m1a（このファイルの現状）: 配線実証。ユニットを World 位置に solidBox で描く（camera 無し・固定視点）。
//   目的＝「World 位置 → Render.draw → GameEngine.renderCommands」が fe_rogue ループで動くことの証明。
// m1b（次）: box → 実 sprite（resource 由来 texture・region atlas は Render.drawAtlas で）。
mod RenderWorld {
    use Render.RenderItem
    use Vec2.Vec2

    /// m1c: renderArgs に渡す前に scene 側のユニット sprite を不可視化＝ユニットは World からのみ描かれる
    /// （重複②の一角を scene-tree から剥がす）。不変 scene のコピーを返す（実 scene 状態は不変）。
    pub def hideUnitSprites(scene: Scene[NodeTag]): Scene[NodeTag] =
        let hideOne = (sc, path) -> Scene.mapEngineNode(path, n -> CanvasItem.setVisible(false, n), sc);
        let afterP = List.foldLeft((sc, d) -> hideOne(sc, PlayerScene.spritePath(d#id)), scene, PlayerScene.getAll(scene));
        List.foldLeft((sc, d) -> hideOne(sc, EnemyScene.spritePath(d#id)), afterP, EnemyScene.getAll(scene))

    /// World + scene → ユニットの実 sprite の Drawable list（scene 側 sprite は hideUnitSprites で隠す）。
    /// m1c: 描画は World render System（この関数）が担い、ユニット sprite を scene auto-render から剥がす。
    /// 存在 gate = World.posOf（World が論理位置を持つユニットのみ描く）。
    /// ⚠ 視覚位置は当面 scene の tween 値（武器/HPバー＝同じ marker 上の兄弟と同期して滑らかに動かすため）。
    ///   真の render-from-World（位置も World 由来＋tween を World component 化）は m2。
    pub def renderUnits(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let players = PlayerScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Player(d#id), PlayerScene.spritePath(d#id), world, transform, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Enemy(d#id), EnemyScene.spritePath(d#id), world, transform, scene));
        List.append(players, enemies)

    /// アクティブ camera の ViewTransform（render() と同じ算出）。camera 無しは identity。
    /// B/perf: `findActiveCamera` が全 scene 走査ゆえ、Game.flix が**フレーム 1 回**計算して全 render 関数へ渡す
    /// （旧: 各 render 関数・各 subtree root が個別に呼び ~30 回/frame 走査していた）。
    pub def viewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, gp)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, gp, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// 1 ユニット → Drawable list。`pathToDrawables` と同手順（globalPositionAt→camera→Renderable.toDrawables→
    /// applyZoomScale）。視覚位置・modulate・z は scene 由来（兄弟ノードと同期）、存在のみ World.posOf で gate。
    /// posOf×getEngineNode は forM で 1 段に畳む。
    /// 共有 spine（units / items / stairs / chests）: scene の 1 sprite ノードを worldPos に置き、camera 適用＋
    /// effectiveModulate/effectiveZIndex を掛けて Drawable 化する（不可視なら Nil）。worldPos は呼び側が決める
    /// （ユニットは移動中 renderPos・静止/他は marker やセル位置）。effectiveModulateAt は node 自身の modulate
    /// を含む（fog×暗転）＝単一適用ゆえ d#color へ再掛けしない。
    def spriteNodeDrawables(spritePath: NodePath, worldPos: Vec2.Vec2,
                            transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        match Scene.getEngineNode(spritePath, scene) {
            case None       => Nil
            // 可視判定は renderArgs と同じく「祖先 AND 自ノード」。effectiveVisibleAt は**祖先のみ**検査するため
            // （drawContextWalk が最終要素=自ノードをスキップ）、fog が葉ノード自身の visible を false にする
            // アイテム等は `CanvasItem.isVisible(node)` を併せて見ないと暗所で描かれてしまう。
            case Some(node) =>
                if (not (Scene.effectiveVisibleAt(spritePath, scene) and CanvasItem.isVisible(node))) Nil
                else {
                    let screenPos = Camera2D.applyToWorldPos(transform, worldPos);
                    let color = Scene.effectiveModulateAt(spritePath, scene);
                    let z = Scene.effectiveZIndexAt(spritePath, scene);
                    GameEngine.Renderable.toDrawables(node, screenPos)
                        |> Render.applyCameraScale(transform)
                        |> List.map(d -> {color = color, zIndex = z | d})
                }
        }

    def unitDraw(ref: World.EntityRef, spritePath: NodePath, world: World,
                 transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        // 存在 gate = World.posOf（World が論理位置を持つユニットのみ描く）。
        match World.posOf(ref, world) {
            case None    => Nil
            case Some(_) =>
                // B/m3: marker が視覚位置の単一権威（移動=`syncMarkers` の renderPos / lunge=AnimationPlayer /
                // 静止=setGlobalPositionAt）。sprite は marker の子・ローカル0 ゆえ globalPositionAt(spritePath)=
                // marker global で全ケースを内包する（engine tween 退役で isAnimating 分岐は不要になった）。
                let worldPos = Scene.globalPositionAt(spritePath, scene);
                spriteNodeDrawables(spritePath, worldPos, transform, scene)
        }

    /// B/m3: 移動（Position tween）した entity の実 scene marker を renderPos に合わせる（marker 単一権威）。
    /// `stepWorld` が返す active∪done の `MarkerMove` を畳み、marker を pos へ置く。marker の子（sprite/武器/HPバー）は
    /// これで一斉に同じ値へ追従＝適用点が揃い、敵の武器アイコン 1 フレームラグが解消（engine tween 退役の受け皿）。
    /// faction 分岐は `EntityScene.path` に閉じ、world→local 変換は engine（`setGlobalPositionAt`）へ委譲（snapTo と同じ）。
    pub def syncMarkers(moved: List[MarkerMove], scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((sc, m) -> Scene.setGlobalPositionAt(EntityScene.path(m#ref), m#pos, sc), scene, moved)

    /// B: パスのノードを隠す（World 描画へ切替時の二重描画防止）。CanvasLayer/親ノードを隠せば祖先可視で
    /// サブツリー全体が renderArgs から外れる（drawContext の祖先 visible 合成）。不在パスは no-op（動的 menu 用）。
    pub def hideNode(path: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        match Scene.getEngineNode(path, scene) {
            case None    => scene
            case Some(_) => Scene.mapEngineNode(path, n -> CanvasItem.setVisible(false, n), scene)
        }

    /// B: World 描画する **in-world（camera 適用）** サブツリー root。配置物（アイテム/宝箱/階段）＋ダメージ数字/
    /// 爆発/カーソル/矢印カーソル。top-level の Cursor/ArrowCursor は World 直下でないため明示列挙。
    def worldSubtreeRoots(): List[NodePath] =
        // P6-1c〜f: 配置物 3 種と fx（ダメージ数字/爆発）はノード廃止＝render* 直描き。
        CursorScene.cursorPath() :: ArrowCursorScene.arrowPath() :: Nil

    /// B: World 描画する **CanvasLayer（camera 免除・画面固定）** サブツリー root。HUD/メニュー/minimap/各種ポップアップ。
    /// 不在（未オープンの動的 menu 等）は `subtreeDrawables`/`hideNode` とも no-op。
    def hudSubtreeRoots(): List[NodePath] =
        TopBarScene.rootPath() :: UnitCardScene.rootPath() ::
        ActionMenuScene.rootPath() :: ItemMenuScene.rootPath() :: WeaponSelectScene.rootPath() ::
        TradeMenuScene.rootPath() :: GameOverMenuScene.rootPath() :: LevelUpPanelScene.rootPath() ::
        MinimapScene.rootPath() ::
        LogScene.logPath() :: EnemyCardScene.rootPath() :: BattlePanelScene.rootPath() ::
        SuspendConfirmScene.rootPath() :: ItemPickupPopupScene.rootPath() :: TurnEndHoldScene.rootPath() :: Nil

    /// B: World 描画する全サブツリー root（world〔camera 適用〕 ++ hud〔CanvasLayer〕）。camera 適用/免除の seam を
    /// 2 サブリストで保持。順序は z-sort/effzIndex で描画に無関係。
    def subtreeRoots(): List[NodePath] = List.append(worldSubtreeRoots(), hudSubtreeRoots())

    // P6-1g: P5-e の per-unit marker 装飾 root（unitMarkerRoots/unitGlyphRoots）は撤去。
    // 武器アイコン/HP バーはノード自体を積まず UnitHPBarScene.renderBars / WeaponIconScene.renderIcons
    // が World store から直描きする。

    /// B: polygon（Polygon2D/Arc2D）を持つ subtree root のみ（minimap マーカー円 / BattlePanel ドット / TurnEndHold リング）。
    /// polygon の無い root を毎フレーム走査しないよう明示。
    def polygonSubtreeRoots(): List[NodePath] =
        MinimapScene.rootPath() :: BattlePanelScene.rootPath() :: TurnEndHoldScene.rootPath() :: Nil

    /// B: 全 subtree（HUD/メニュー/minimap/ポップアップ等）を World render System で描く。
    /// B/perf: `renderOrderPaths` を全 root で 1 回共有する batch API に委譲（旧: root ごと再走査＝O(roots×N)）。
    pub def renderSubtrees(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        Scene.subtreeDrawablesForRoots(transform, subtreeRoots(), scene)

    /// B: polygon を持つ subtree の Polygon2D/Arc2D を polygon チャンネルで描く（`preorderPaths` を 1 回共有）。
    pub def renderSubtreePolygons(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.PolygonRenderCmd] =
        Scene.subtreePolygonsForRoots(transform, polygonSubtreeRoots(), scene)

    /// B: 全 subtree の scene 側 root を隠す（renderArgs から外し二重描画防止）。
    pub def hideSubtrees(scene: Scene[NodeTag]): Scene[NodeTag] =
        subtreeRoots() |> List.foldLeft((acc, root) -> hideNode(root, acc), scene)

    /// B/tiles: World の tileLayers（bake 済ハンドル）を camera 適用して engine の instanced tile 描画コマンドにする。
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

    /// B: fog の暗幕（haze）を World render System で描く。scene の Fog ColorRect プールを使わず、
    /// FogScene の純粋な補集合計算（holesForDraft/mapRegion/bandDecompose）を再利用して暗幕矩形を
    /// solidBox の Drawable にする。敵/アイテムの点灯（可視性）制御は従来どおり FogScene が担い、ここは
    /// 暗幕の描画のみ。P6-1b: scene 側の haze プールは撤去済み＝この直描きが唯一の暗幕経路。
    /// 入力（origin 基準の部屋点灯・通路 torch）は `FogScene.process` と同一＝挙動不変。
    pub def renderFog(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ SelectedPlayer.State =
        // ダンジョン以外（タイトル/パーティ選択/メニュー等）は Map ノードが無い＝暗幕なし。
        // `MapScene.getPlacements` は Map 不在で bug! するので、`World.mapSnapshotOpt` と同じ存在ガードで早期 Nil。
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => Nil
            case Some(_) =>
                let drafts     = SelectedPlayer.State.get()#drafts;
                let units      = PlayerScene.getAll(scene)
                    |> List.map(d -> {gridPos = d#gridPos, hidden = d#hidden,
                                      origin = MoveDraft.originOf(d#id, drafts) |> Option.getWithDefault(d#gridPos)});
                let placements = MapScene.getPlacements(scene);
                let roomCount  = MapScene.getRoomCount(scene);
                let holes      = FogScene.holesForDraft(units, placements, roomCount, true);
                let hazeRects  = FogScene.bandDecompose(FogScene.mapRegion(placements), holes);
                List.flatMap(r -> fogRectDrawables(r, transform), hazeRects)
        }

    /// P6-1c/d: fog の「明るい穴」を frame に 1 回計算し、配置物の直描き（renderStairs/renderChests…）
    /// で共有する lit ゲート入力。Map 不在（タイトル/選択画面）は None＝配置物を描かない。
    pub def fogHolesOpt(scene: Scene[NodeTag]): Option[List[GridRect]] \ SelectedPlayer.State =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => None
            case Some(_) =>
                let drafts = SelectedPlayer.State.get()#drafts;
                let units  = PlayerScene.getAll(scene)
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

    /// P6-1c: 階段を World store + 見た目定数から直描きする（scene ノードなしの第一号）。
    ///   存在 = `World.stairsPosOf`（None=未配置）、見た目 = `StairsScene.texture/spriteScale/spriteZIndex`
    ///   （旧 scene.json 値）、fog の lit ゲート = `fogHolesOpt`（旧 `StairsScene.applyFog` の
    ///   可視制御を描画時判定に置換・origin 基準は fog 本体と同一）。holes=None（Map 不在）は Nil。
    pub def renderStairs(world: World, holesOpt: Option[List[GridRect]],
                          transform: Camera2D.ViewTransform): List[GameEngine.Drawable] \ GameEngine.Game =
        match (holesOpt, World.stairsPosOf(world)) {
            case (Some(holes), Some(cell)) =>
                if (not FogScene.insideAny(cell, holes)) Nil
                else standaloneSprite(
                    Sprite2D.make(StairsScene.texture(), Vec2.zero(), StairsScene.spriteScale()),
                    MapSnapshot.cellCenter(cell), StairsScene.spriteZIndex(), transform)
            case _ => Nil
        }

    /// P6-1d: 宝箱を World.chests store + ChestCatalog の sprite から直描きする。
    /// 位置 = cellCenter + sprite#offset・scale は spawn 時の旧実装どおり 1.0 固定（sprite#scale 非適用）。
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
                            standaloneSprite(node, pos, ChestScene.chestZIndex(), transform)
                        })
        }

    /// P6-1e: 床アイテムを World.groundItems store + `ItemScene.spriteOf` から直描きする。
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
                            let sprite0 = ItemScene.spriteOf(d#item);
                            let center = MapSnapshot.cellCenter(d#gridPos);
                            let pos: Vec2.Vec2 = {x = center#x + sprite0#offset#x, y = center#y + sprite0#offset#y};
                            let makeFramed = () ->
                                Sprite2D.make(sprite0#texture, Vec2.zero(), Vec2.one())
                                    |> Sprite2D.setHframes(sprite0#hframes)
                                    |> Sprite2D.setVframes(sprite0#vframes)
                                    |> Sprite2D.setFrame(sprite0#frame);
                            let alpha = ItemScene.pulseAlpha(d#elapsed);
                            let outlines = List.flatMap(entry -> {
                                let (_, delta) = entry;
                                let opos: Vec2.Vec2 = {x = pos#x + delta#x, y = pos#y + delta#y};
                                let node = makeFramed()
                                    |> Sprite2D.setAlpha(alpha)
                                    |> CanvasItem.setModulate(ItemScene.outlineColor());
                                standaloneSprite(node, opos, ItemScene.outlineZIndex(), transform)
                            }, ItemScene.outlineDeltas());
                            List.append(outlines,
                                standaloneSprite(makeFramed(), pos, ItemScene.spriteZIndex(), transform))
                        })
        }

    /// P6-1f: ダメージ数字 fx を World.popupFx store から直描きする（Label2D 値を組む＝tree に積まない）。
    /// 上方向 float は経過比率から導出。fog ゲートは掛けない（戦闘発生セル＝点灯前提・旧ノード版と同じ）。
    /// Map 不在（タイトル等）は早期 Nil（フロア跨ぎ残骸の誤描画防止）。
    pub def renderPopups(world: World, transform: Camera2D.ViewTransform, scene: Scene[NodeTag]):
            List[GameEngine.Drawable] \ GameEngine.Game =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => Nil
            case Some(_) =>
                let atlas = GameEngine.Game.getFontAtlas(DamagePopupScene.fontName());
                World.popupFxOf(world)
                    |> Map.valuesOf
                    |> List.flatMap(d -> {
                        let ratio = (d#total - d#remaining) / d#total;
                        let pos: Vec2.Vec2 = {x = d#pos#x, y = d#pos#y - DamagePopupScene.floatDistancePx() * ratio};
                        let label = Label2D.make(d#text, atlas, DamagePopupScene.fontSize())
                            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
                            |> Label2D.setVerticalAlignment(VerticalAlignment.Bottom)
                            |> CanvasItem.setModulate(d#color);
                        let screenPos = Camera2D.applyToWorldPos(transform, pos);
                        GameEngine.Renderable.toDrawables(
                            EngineNode.Label2DWithState(label, NodeTag.NoTag), screenPos)
                            |> Render.applyCameraScale(transform)
                            |> List.map(dr -> {zIndex = DamagePopupScene.popupZIndex() | dr})
                    })
        }

    /// P6-1f: 爆発 fx を World.explosionFx store から直描きする（コマ番号は経過比率から導出）。
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
                                    Float64.floor(ratio * Int32.toFloat64(ExplosionScene.frameCount())));
                        let frame = Int32.max(0, Int32.min(ExplosionScene.frameCount() - 1, raw));
                        let sprite = Sprite2D.make(ExplosionScene.texture(), Vec2.zero(),
                                        ({x = d#scale, y = d#scale}: Vec2.Vec2))
                            |> Sprite2D.setHframes(ExplosionScene.hframes())
                            |> Sprite2D.setVframes(ExplosionScene.vframes())
                            |> Sprite2D.setFrame(frame);
                        standaloneSprite(sprite, d#pos, ExplosionScene.zIndex(), transform)
                    })
        }

    /// B: 全 grid 範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険範囲）を World render
    /// System で描く。各 mod は「描画セル・色・α」だけ持ち、描画は `RangeOverlay.tileDrawables` の 1 経路に集約
    /// ＝law の汎用化。非表示のオーバーレイはセルが空ゆえ Drawable も空（毎フレーム全種を引いても無害）。
    /// 表示専用ゆえ格納セルがそのまま描画セル（EnemyRange は reachable・MoveRange は drawCells・他は cells）。
    pub def renderRangeOverlays(transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] =
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

    // P6-1a: `hideRangeTiles` は撤去。range の Tile Panel ノードはもう積まれない
    // （renderRangeOverlays が cells から直描き＝hide-then-render の一角を解消）。

    /// 1 つの暗幕グリッド矩形 → box Drawable（camera 適用）。位置・サイズ変換は `FogScene.setPoolRect` と
    /// 同一（grid × tileSize）。solidBox は alpha=1.0 ゆえ fog 用 alpha に上書きし、scale（=ピクセルサイズ）を
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
