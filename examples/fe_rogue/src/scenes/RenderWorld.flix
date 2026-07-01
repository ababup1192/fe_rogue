// RenderWorld — B1: fe_rogue の render-from-World extract（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
//
// m1a（このファイルの現状）: 配線実証。ユニットを World 位置に solidBox で描く（camera 無し・固定視点）。
//   目的＝「World 位置 → Render.draw → GameEngine.renderCommands」が fe_rogue ループで動くことの証明。
// m1b（次）: box → 実 sprite（resource 由来 texture・region atlas は Render.drawAtlas で）。
mod RenderWorld {
    use Render.RenderItem
    use Vec2.Vec2

    /// m1 toggle: true で render-from-World（box）・false で従来 scene-tree 描画。実機で切替検証。
    pub def useRenderFromWorld(): Bool = true

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
    pub def renderUnits(world: World, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let transform = viewTransform(scene);
        let players = PlayerScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Player(d#id), PlayerScene.spritePath(d#id), world, transform, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Enemy(d#id), EnemyScene.spritePath(d#id), world, transform, scene));
        List.append(players, enemies)

    /// アクティブ camera の ViewTransform（render() と同じ算出）。camera 無しは identity。
    def viewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, gp)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, gp, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// 1 ユニット → Drawable list。`pathToDrawables` と同手順（globalPositionAt→camera→Renderable.toDrawables→
    /// applyZoomScale）。視覚位置・modulate・z は scene 由来（兄弟ノードと同期）、存在のみ World.posOf で gate。
    /// posOf×getEngineNode は forM で 1 段に畳む。
    def unitDraw(ref: World.EntityRef, spritePath: NodePath, world: World,
                 transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        if (not Scene.effectiveVisibleAt(spritePath, scene)) Nil
        else
            (forM (
                _pos <- World.posOf(ref, world);
                node <- Scene.getEngineNode(spritePath, scene)
            ) yield {
                // B/m2: **移動アニメ中だけ** World.renderPos（tween を World が回す）を使う。それ以外（静止・攻撃 lunge
                // 等の marker アニメ中）は scene marker を読む＝lunge/knockback 等を正しく捕捉。renderPos は移動しか
                // 持たないため、攻撃モーションは marker から。move/lunge を全部 World 化するのは将来（全アニメ World 化）。
                let worldPos =
                    if (World.isAnimating(ref, world))
                        World.renderPosOf(ref, world) |> Option.getWithDefault(Scene.globalPositionAt(spritePath, scene))
                    else
                        Scene.globalPositionAt(spritePath, scene);
                let screenPos = Camera2D.applyToWorldPos(transform, worldPos);
                // effectiveModulateAt は node 自身の modulate を含む（fog×待機暗転）＝単一適用。d#color へ再掛けしない。
                let color = Scene.effectiveModulateAt(spritePath, scene);
                let z = Scene.effectiveZIndexAt(spritePath, scene);
                GameEngine.Renderable.toDrawables(node, screenPos)
                    |> Render.applyCameraScale(transform)
                    |> List.map(d -> {color = color, zIndex = z | d})
            }) |> Option.getWithDefault(Nil)

    /// B: fog の暗幕（haze）を World render System で描く。scene の Fog ColorRect プールを使わず、
    /// FogScene の純粋な補集合計算（holesForDraft/mapRegion/bandDecompose）を再利用して暗幕矩形を
    /// solidBox の Drawable にする。敵/アイテムの点灯（可視性）制御は従来どおり FogScene が担い、ここは
    /// 暗幕の描画のみ。二重描画は Game.flix が `FogScene.hideHaze` で scene プールを隠して防ぐ（hideUnitSprites 対称）。
    /// 入力（origin 基準の部屋点灯・通路 torch）は `FogScene.process` と同一＝挙動不変。
    pub def renderFog(scene: Scene[NodeTag]): List[GameEngine.Drawable] \ {GameEngine.Game, SelectedPlayer.State} =
        // ダンジョン以外（タイトル/パーティ選択/メニュー等）は Map ノードが無い＝暗幕なし。
        // `MapScene.getPlacements` は Map 不在で bug! するので、`World.mapSnapshotOpt` と同じ存在ガードで早期 Nil。
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case None    => Nil
            case Some(_) =>
                let transform  = viewTransform(scene);
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

    /// B: 全 grid 範囲オーバーレイ（移動 / 攻撃 / 敵移動 / 敵攻撃 / 味方攻撃 / 交換 / 危険範囲）を World render
    /// System で描く。各 mod は「描画セル・色・α」だけ持ち、描画は `RangeOverlay.tileDrawables` の 1 経路に集約
    /// ＝law の汎用化。非表示のオーバーレイはセルが空ゆえ Drawable も空（毎フレーム全種を引いても無害）。
    /// 表示専用ゆえ格納セルがそのまま描画セル（EnemyRange は reachable・MoveRange は drawCells・他は cells）。
    pub def renderRangeOverlays(scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let t = viewTransform(scene);
        let tiles = (cells, color, alpha) -> RangeOverlay.tileDrawables(cells, color, alpha, t);
        List.flatten(
            tiles(MoveRangeScene.drawCells(scene),     MoveRangeScene.color(),         MoveRangeScene.alpha()) ::
            tiles(MoveAttackRangeScene.cells(scene),   MoveAttackRangeScene.color(),   MoveAttackRangeScene.alpha()) ::
            tiles(EnemyRangeScene.reachable(scene),    EnemyRangeScene.color(),        EnemyRangeScene.alpha()) ::
            tiles(EnemyAttackRangeScene.cells(scene),  EnemyAttackRangeScene.color(),  EnemyAttackRangeScene.alpha()) ::
            tiles(PlayerAttackRangeScene.cells(scene), PlayerAttackRangeScene.color(), PlayerAttackRangeScene.alpha()) ::
            tiles(TradeRangeScene.cells(scene),        TradeRangeScene.color(),        TradeRangeScene.alpha()) ::
            tiles(DangerZoneScene.cells(scene),        DangerZoneScene.color(),        DangerZoneScene.alpha()) ::
            Nil)

    /// B: 全 range オーバーレイの scene 側 Tile Panel を隠す（World 描画へ切替時の二重描画防止）。
    pub def hideRangeTiles(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> MoveRangeScene.hideTiles         |> MoveAttackRangeScene.hideTiles
            |> EnemyRangeScene.hideTiles        |> EnemyAttackRangeScene.hideTiles
            |> PlayerAttackRangeScene.hideTiles |> TradeRangeScene.hideTiles
            |> DangerZoneScene.hideTiles

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
