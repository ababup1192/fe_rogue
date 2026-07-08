/// MinimapScene — 探索済みマップ（ミニマップ）。M キーで表示/非表示を切り替える。
///
/// `FogScene`（霧）は「現在いる部屋だけを毎フレーム明るくする・非永続」だが、ミニマップは
/// 逆に **一度でも訪れた部屋/通路(module)を覚え続ける**（探索が進むほど書き足される）。
/// 訪問記憶（`Set[Int32]` の訪問 module idx）は World 権威で持つ（`World.visitedModulesOf`）。
/// `step` が今フレーム分を `Cmd.AddVisited` で union し、フロア再構築時は `Cmd.ClearVisited` が一掃する。
///
/// 見た目は scene ノードを持たず、`RenderWorld.renderMinimap` が World / Map から Drawable（部屋/床
/// 矩形）とポリゴン（プレイヤー/階段/アイテム/敵のマーカー円）を直接組む。探索マップ全体が画面左下の
/// 固定ボックスに収まるよう一様スケールして描く。表示トグル（`visible`）と押しっぱなし防止の前フレーム
/// キー状態（`mPrev`）は `MinimapState` resource が持つ。M のエッジ検出は `CursorScene` の方向キー検出と
/// 同じ作法。
///
/// このモジュールは訪問記憶の蓄積（`step`）と、描画に必要な純粋な幾何計算（矩形分割・スケール・マーカー
/// 収集・Drawable 化）を担う。実効果つきの描画エントリは `RenderWorld.renderMinimap`。
mod MinimapScene {

    use Vec2.Vec2

    /// fitTransform が返す「grid → minimap ピクセル」のアフィン変換パラメータ。
    pub type alias Fit = { scale = Float64, ox = Float64, oy = Float64 }

    /// `minimapDrawList` の入力。描画に必要なデータをすべて解決済みで束ねる（純粋・効果なし）。
    ///   visited    : 訪問済み module idx（World 権威。今フレーム分も合成済み）。
    ///   placements : フロアの全 module 配置。
    ///   roomCount  : 部屋数（idx < roomCount が部屋・それ以外が通路）。
    ///   snapshot   : 壁/床セル判定に使う地形スナップショット。
    ///   markers    : 描画するマーカー（セル + 色）一覧。
    pub type alias RenderInput = {
        visited    = Set[Int32],
        placements = List[DungeonComposer.ModulePlacement],
        roomCount  = Int32,
        snapshot   = MapSnapshot,
        markers    = List[{cell = {x = Int32, y = Int32}, color = Color}]
    }

    /// 探索マップを収める「左下のボックス」（design 解像度のピクセル座標、y は下向き）。
    /// シレン風に左下隅へ半透明で置く。背景枠は描かず、フロア/通路の矩形だけを描く（29×42 を 2 倍 ≈ 58×84）。
    /// x0=5 で画面左端から約 5px のマージンを空けて左下へ置く（横長キャンバスでの左寄せ）。
    pub def targetRect(): GridRect = ({x0 = 5, y0 = 38, x1 = 63, y1 = 122}: GridRect)

    /// スケール基準となる「参照フロア寸法」（タイル）。実測した最大級フロアの bbox
    /// (おおよそ 47×51) を基準にする。**この1枚を `targetRect` に収める倍率を全フロア
    /// 共通の縮尺とする**ことで、フロアの実寸（部屋数）に依らずミニマップのズーム率を
    /// 一定（= どのフロアでも 3F と同じ見え方）にする。見せ方（左下アンカー・アスペクト
    /// 比維持・フレームレス）は変えない。
    def scaleReferenceRect(): GridRect = ({x0 = 0, y0 = 0, x1 = 47, y1 = 51}: GridRect)

    /// 全フロア共通の縮尺（定数）。`scaleReferenceRect` を `targetRect` に収める倍率。
    pub def referenceScale(): Float64 = fitTransform(scaleReferenceRect(), targetRect())#scale

    /// マーカー（丸）の直径は「セル幅(scale)に比例」させ、隣接セルの円どうしが重ならないよう
    /// セル幅未満に保つ。同時に最大値 `markerMaxPx` で頭打ちにして大きくなりすぎないようにする。
    /// （アイテム・キャラ等は矩形でなく丸 = Polygon2D の 12 角形で表す。）
    def markerCellFraction(): Float64 = 0.85
    def markerMaxPx(): Float64 = 3.9
    /// セル幅 `scale` からマーカー直径（px）を求める。
    def markerDiameter(scale: Float64): Float64 =
        let d = markerCellFraction() * scale;
        if (d < markerMaxPx()) d else markerMaxPx()

    /// zIndex（描画順）。壁(下) < 歩ける床の黒(中) < マーカー(上)。
    /// 探索済みエリアを壁色ブロックで塗り、その上に黒で歩ける床を「くり抜く」2 層構成。
    def roomZIndex(): Int32 = 1     // 壁/構造（拡張した外枠ブロック）
    def floorZIndex(): Int32 = 2    // 歩ける床（黒。壁ブロックから碁盤目をくり抜く）
    def markerZIndex(): Int32 = 3

    /// ミニマップは画面固定 HUD なので、in-world 配置物より手前に出す必要がある。旧経路は
    /// CanvasLayer(layer=6)に載って `layer * layerStride` の実効 zIndex を得ていた。直描きでも
    /// 各 z にこのオフセットを足して描画順を旧経路と一致させる。
    def minimapLayer(): Int32 = 6
    def minimapLayerOffset(): Int32 = minimapLayer() * CanvasLayer.layerStride()

    // 色（半透明で操作の邪魔にならないよう alpha を抑える）
    /// 壁/構造の色（歩ける床を囲む外枠ブロック）。
    def moduleColor(): Color = {r = 0.62f32, g = 0.68f32, b = 0.85f32}
    def moduleAlpha(): Float32 = 0.50f32
    /// 歩ける床は黒（何もなし）でくり抜いて表現する。壁の上に重ねるので不透明寄りに。
    def floorColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def floorAlpha(): Float32 = 0.92f32
    def leaderColor(): Color = {r = 0.95f32, g = 0.85f32, b = 0.20f32}
    def playerColor(): Color = {r = 0.30f32, g = 0.70f32, b = 0.95f32}
    def stairsColor(): Color = {r = 0.90f32, g = 0.30f32, b = 0.85f32}
    def itemColor(): Color = {r = 0.95f32, g = 0.60f32, b = 0.20f32}
    /// 今プレイヤーと同じ部屋に居る敵を示す赤丸。
    def enemyColor(): Color = {r = 0.92f32, g = 0.25f32, b = 0.22f32}
    def markerAlpha(): Float32 = 0.85f32

    /// 訪問済み module idx を World 権威から返す。カーソルの移動可能範囲（既訪エリア）の
    /// 算出に CursorScene が使う。記憶の蓄積は step の `Cmd.AddVisited`、リセットは
    /// `Cmd.ClearVisited`（フロア再構築時）が担う。
    pub def visitedModules(): Set[Int32] \ World.WorldQuery =
        World.visitedModulesOf(World.WorldQuery.get())

    /// gameLoop がパイプライン段で 1 回呼ぶ frame-paced System。今フレームに訪問した module を
    /// World へ蓄積し、M キーのエッジで表示トグルを反転する。描画そのものは行わない（見た目は
    /// `RenderWorld.renderMinimap` が同一フレームの状態を読んで直描きする）。
    /// ダンジョン外（盤面未 seed＝タイトル/選択画面）では何もしない。
    pub def step(input: App.Frame):
                    Unit
                    \ {TurnPhase.State, SelectedPlayer.State,
                       PlayerData.PartyQuery, World.Command, World.WorldQuery, MinimapState.State} =
        if (not World.hasBoard(World.WorldQuery.get())) ()
        else {
            let phase = TurnPhase.State.get();
            let data  = MinimapState.State.get();
            let mDown = App.isDown(GameEngine.Key.M, input);
            // 敵ターン中は M を受け付けない（トグル自体を無視するので、押しても敵ターン明けに
            // 開いたりしない）。
            let acceptsToggle = phase != TurnPhase.Phase.EnemyTurn;
            let visible2 =
                if (InputEdge.pressed(data#mPrev, mDown) and acceptsToggle) not data#visible
                else data#visible;
            let world0     = World.WorldQuery.get();
            let placements = World.placementsOf(world0);
            let roomCount  = World.roomCountOf(world0);
            // 部屋の記憶（visited）は fog と同じく origin 基準にする。移動ドラフト中に新しく踏み込んだ
            // 部屋は確定（drafts クリア）まで地図に出さない。
            let drafts = SelectedPlayer.State.get()#drafts;
            let units  = PlayerData.PartyQuery.getAll()
                |> List.map(d -> {id = d#id, gridPos = d#gridPos, hidden = d#hidden,
                                  origin = MoveDraft.originOf(d#id, drafts)
                                           |> Option.getWithDefault(d#gridPos)});
            let frame  = visitedThisFrameDrafted(units, placements, roomCount);
            // 探索記憶は World 権威。今フレーム訪問分を World へ union する（描画時に読み合わせる）。
            World.Command.emit(World.Cmd.AddVisited(frame));
            MinimapState.State.put({visible = visible2, mPrev = mDown})
        }

    // ════════════════════════════════════════════════════════
    // 純粋な描画リスト生成（RenderWorld.renderMinimap が解決済みデータで呼ぶ）
    // ════════════════════════════════════════════════════════

    /// 解決済みの入力から、ミニマップの Drawable（部屋/床の矩形）と PolygonRenderCmd（マーカー円）を組む。
    /// フレームは「フロア全体の bbox」基準にして、探索しても配置が動かないようにする。描画対象は
    /// 「訪問済み module」＋「訪問済みに隣接する未訪問の通路（出口ヒント）」を union 分割して一体化する
    /// （重なり部分を二重描画しない）。壁/構造を青のベタ塗り（module 床 bbox）、その上に歩ける床セルだけを
    /// 黒くくり抜く。
    pub def minimapDrawList(input: RenderInput):
            {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} =
        let rawRects  = displayedModuleRects(input#visited, input#placements, input#roomCount);
        // 縮尺は全フロア共通の固定値（`referenceScale`）。フロアの実寸に依らず一定。ただし参照より
        // 大きい稀な巨大フロアは画面ボックスからはみ出さないよう、そのフロアの fit 倍率でクランプする。
        let fitScale  = fitTransform(tightRegion(input#placements), targetRect())#scale;
        let scale     = minF(referenceScale(), fitScale);
        let t         = anchorBLWithScale(scale, boundsOf(rawRects), targetRect());
        let disjoint  = unionBands(rawRects);
        let floorRuns = floorRunsIn(disjoint, input#snapshot);
        let roomDrawables  =
            disjoint  |> List.map(r -> boxDrawableOf(mapRect(r, t), moduleColor(), roomZIndex(), moduleAlpha()));
        let floorDrawables =
            floorRuns |> List.map(r -> boxDrawableOf(mapRect(r, t), floorColor(), floorZIndex(), floorAlpha()));
        let markerCmds =
            input#markers |> List.map(marker -> markerCmdOf(marker#cell, marker#color, t));
        {drawables = List.append(roomDrawables, floorDrawables), polygons = markerCmds}

    /// minimap ピクセル矩形 → box Drawable（画面固定。camera 変換なし）。色は modulate、alpha は
    /// レイヤ半透明、zIndex は旧 CanvasLayer 相当のオフセット込み。
    def boxDrawableOf(pr: {pos = Vec2, size = Vec2}, color: Color, z: Int32, alpha: Float32):
            GameEngine.Drawable =
        let rect = ColorRect.make(pr#size, color) |> ColorRect.setAlpha(alpha);
        let drawable = ColorRect.toDrawable(rect, pr#pos);
        {zIndex = z + minimapLayerOffset() | drawable}

    /// セル + 色 → マーカー円の PolygonRenderCmd（画面固定・原点中心の 12 角形）。直径はセル幅に比例。
    def markerCmdOf(cell: {x = Int32, y = Int32}, color: Color, t: Fit): GameEngine.PolygonRenderCmd =
        let c    = mapCell(cell, t);
        let half = t#scale / 2.0;
        // 円は原点中心なので位置はセル中心。直径はセル幅に比例（隣接円が重ならない）。
        let pos: Vec2 = {x = c#x + half, y = c#y + half};
        let d = markerDiameter(t#scale);
        let poly = Polygon2D.circle(0.5, color)
            |> Node2D.setScale({x = d, y = d})
            |> Polygon2D.setAlpha(markerAlpha());
        let cmd = Polygon2D.toRenderCmd(pos, {x = 1.0, y = 1.0}, poly);
        {zIndex = markerZIndex() + minimapLayerOffset() | cmd}

    // ════════════════════════════════════════════════════════
    // 描画に必要なデータの解決（RenderWorld.renderMinimap が呼ぶ純粋/軽効果ヘルパー）
    // ════════════════════════════════════════════════════════

    /// 階段が「発見済み」か。階段セルの属する module が訪問済みなら発見扱い。
    /// 階段位置は World.stairsPos から読む。
    pub def stairsDiscovered(visited: Set[Int32],
                             placements: List[DungeonComposer.ModulePlacement]): Bool \ World.WorldQuery =
        match World.stairsPosOf(World.WorldQuery.get()) {
            case None       => false
            case Some(cell) =>
                match MapSnapshot.moduleOfCellIn(cell, placements) {
                    case Some(idx) => Set.memberOf(idx, visited)
                    case None      => false
                }
        }

    /// 表示すべきマーカー（セル + 色）一覧。プレイヤー（非 hidden、リーダーは別色）+ 発見済み
    /// 階段 + 訪問済み部屋内のアイテム + 点灯部屋に居る敵。在籍・位置とも World 権威
    /// （`fogUnitsOf` / `enemyIdsOf`）、階段/アイテムも World store から読む（scene は読まない）。
    pub def collectMarkers(visited: Set[Int32], stairsSeen: Bool,
                           placements: List[DungeonComposer.ModulePlacement],
                           roomCount: Int32, litRooms: Set[Int32]):
                          List[{cell = {x = Int32, y = Int32}, color = Color}]
                          \ World.WorldQuery =
        let players =
            World.fogUnitsOf(World.WorldQuery.get())
                |> List.filter(d -> not d#hidden)
                |> List.map(d -> {cell = d#gridPos,
                                  color = if (d#id == 0) leaderColor() else playerColor()});
        // 階段位置は World.stairsPos から読む。
        let stairsM =
            if (stairsSeen)
                match World.stairsPosOf(World.WorldQuery.get()) {
                    case Some(cell) => {cell = cell, color = stairsColor()} :: Nil
                    case None       => Nil
                }
            else Nil;
        let itemsM =
            // 床アイテム位置は World store から読む。
            (World.groundItemsOf(World.WorldQuery.get()) |> Map.valuesOf |> List.map(d -> d#gridPos))
                |> List.filter(cell -> inVisitedRoom(cell, placements, roomCount, visited))
                |> List.map(cell -> {cell = cell, color = itemColor()});
        // いま点灯している部屋(litRooms)に居る敵を赤丸で（アイテムより手前＝後ろに連結して上に描く）。
        let enemiesM = enemiesSharingPlayerRoom(litRooms, placements);
        List.append(players, List.append(stairsM, List.append(itemsM, enemiesM)))

    /// 「いま点灯している部屋に居る敵」マーカー（赤丸）。点灯部屋集合 `litRooms`（origin 基準で
    /// 求めた room module）に居る生存敵（hp>0 かつ not isDying）を拾う。点灯している部屋＝霧で照らされ
    /// 既に見えているので別途の可視判定は省く。移動中に踏み込んだだけの暗い新規部屋は litRooms に
    /// 含まれないため、その敵は地図にも出ない（fog と一貫）。在籍・位置とも World 権威。
    def enemiesSharingPlayerRoom(litRooms: Set[Int32],
                                 placements: List[DungeonComposer.ModulePlacement]):
                                List[{cell = {x = Int32, y = Int32}, color = Color}]
                                \ World.WorldQuery =
        let world = World.WorldQuery.get();
        World.enemyIdsOf(world)
            |> List.filter(id -> {
                let ref = World.EntityRef.Enemy(id);
                (World.hpOf(ref, world) |> Option.getWithDefault(0)) > 0
                    and not World.isDyingOf(ref, world)
            })
            |> List.filterMap(id -> World.posOf(World.EntityRef.Enemy(id), world))
            |> List.filter(cell -> match MapSnapshot.moduleOfCellIn(cell, placements) {
                                       case Some(idx) => Set.memberOf(idx, litRooms)
                                       case None      => false
                                   })
            |> List.map(cell -> {cell = cell, color = enemyColor()})

    def inVisitedRoom(cell: {x = Int32, y = Int32},
                       placements: List[DungeonComposer.ModulePlacement],
                       roomCount: Int32, visited: Set[Int32]): Bool =
        match MapSnapshot.moduleOfCellIn(cell, placements) {
            case Some(idx) => idx < roomCount and Set.memberOf(idx, visited)
            case None      => false
        }

    // ════════════════════════════════════════════════════════
    // 歩ける床の黒くり抜き（青ベタ塗りから床セルを横ランで抜く）
    // ════════════════════════════════════════════════════════

    /// 青ベタ塗りバンド群の中から「歩ける床セル」だけを行ごとの横ラン（1 セル高の矩形）に
    /// まとめて返す。これを黒で重ね描きすると、壁セル（内壁・柱・外周）が青のまま残る。
    def floorRunsIn(bands: List[GridRect], m: MapSnapshot): List[GridRect] =
        List.flatMap(b -> bandFloorRuns(b, m), bands)

    def bandFloorRuns(band: GridRect, m: MapSnapshot): List[GridRect] =
        List.flatMap(y -> rowFloorRuns(band#x0, band#x1, y, m), List.range(band#y0, band#y1))

    /// 行 y の x0..x1（排他）を走査し、連続する床セルを 1 本の横ランにまとめる。
    def rowFloorRuns(x0: Int32, x1: Int32, y: Int32, m: MapSnapshot): List[GridRect] =
        let step = (acc, x) -> {
            let (runs, cur) = acc;
            let isF = MapSnapshot.isFloor(({x = x, y = y}: {x = Int32, y = Int32}), m);
            match (cur, isF) {
                case (None,    true)  => (runs, Some(x))
                case (Some(_), true)  => (runs, cur)
                case (Some(s), false) => (closeRun(s, x, y) :: runs, None)
                case (None,    false) => (runs, None)
            }
        };
        let (runs, cur) = List.foldLeft(step, ((Nil, None): (List[GridRect], Option[Int32])),
                                        List.range(x0, x1));
        match cur {
            case Some(s) => closeRun(s, x1, y) :: runs
            case None    => runs
        }

    /// 床ラン [s, e)（行 y, 高さ 1）を GridRect 化する。
    def closeRun(s: Int32, e: Int32, y: Int32): GridRect =
        ({x0 = s, y0 = y, x1 = e, y1 = y + 1}: GridRect)

    // ════════════════════════════════════════════════════════
    // 訪問記憶・スケール・座標変換（純粋関数。テストと描画が共有）
    // ════════════════════════════════════════════════════════

    /// 今フレームに非 hidden ユニットが居る module idx の集合（module 外セルは無視）。
    /// 引数は開いた行多相なので `PlayerScene.Data`（gridPos/hidden を含む）をそのまま渡せる。
    pub def visitedThisFrame(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                              placements: List[DungeonComposer.ModulePlacement]): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> MapSnapshot.moduleOfCellIn(d#gridPos, placements))
            |> List.toSet

    /// `visitedThisFrame` の draft 対応版。room module は origin（ターン開始位置）が同じ部屋に
    /// あるときだけ訪問済みに数え、corridor module はライブ位置で数える。移動中に新しく踏み込んだ
    /// 部屋を確定（drafts クリア）まで地図に記録しない（fog の `holesForDraft` と一貫）。
    pub def visitedThisFrameDrafted(units: List[{gridPos = {x = Int32, y = Int32},
                                                  origin = {x = Int32, y = Int32}, hidden = Bool | r}],
                                     placements: List[DungeonComposer.ModulePlacement],
                                     roomCount: Int32): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> revealedModuleOf(d#gridPos, d#origin, placements, roomCount))
            |> List.toSet

    /// いま点灯している room module の集合（origin 基準）。ミニマップの敵赤丸を「明るい部屋に
    /// 居る敵」だけに絞るために使う（暗い新規部屋の敵は地図にも出さない＝fog と一貫）。
    pub def litRoomsDrafted(units: List[{gridPos = {x = Int32, y = Int32},
                                          origin = {x = Int32, y = Int32}, hidden = Bool | r}],
                             placements: List[DungeonComposer.ModulePlacement],
                             roomCount: Int32): Set[Int32] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> revealedModuleOf(d#gridPos, d#origin, placements, roomCount))
            |> List.filter(idx -> idx < roomCount)
            |> List.toSet

    /// このユニットが現フレームに reveal する module idx（fog の `holeFor` と同じ部屋デファー規則）。
    /// 通路 module はライブ採用、room module は origin が同じ部屋にあるときだけ採用、新規部屋は None。
    def revealedModuleOf(live: {x = Int32, y = Int32}, origin: {x = Int32, y = Int32},
                          placements: List[DungeonComposer.ModulePlacement],
                          roomCount: Int32): Option[Int32] =
        match MapSnapshot.moduleOfCellIn(live, placements) {
            case None    => None
            case Some(m) =>
                if (m >= roomCount) Some(m)
                else if (MapSnapshot.moduleOfCellIn(origin, placements) == Some(m)) Some(m)
                else None
        }

    /// 既存の訪問記憶に今フレーム分を足す（= 記憶。部屋を離れても残る）。
    pub def accumulate(prev: Set[Int32], frame: Set[Int32]): Set[Int32] =
        Set.union(prev, frame)

    /// margin なしの探索マップ bbox（`FogScene.mapRegion` の画面外マージン抜き版）。
    /// 各 module の `FogScene.moduleRect`（壁リング込み）の union。
    pub def tightRegion(placements: List[DungeonComposer.ModulePlacement]): GridRect =
        match List.map(FogScene.moduleRect, placements) {
            case Nil           => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                List.foldLeft((a, r) -> ({
                    x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                    x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                    first, rest)
        }

    /// 探索マップ領域 `area` を全画面ボックス `target` に一様スケール + センタリングで収める
    /// アフィン変換パラメータを返す。退化（幅/高さ 0）時は scale=0。
    /// （`region` は Flix の予約語なので使わない。）
    pub def fitTransform(area: GridRect, target: GridRect): Fit =
        let rw = Int32.toFloat64(area#x1 - area#x0);
        let rh = Int32.toFloat64(area#y1 - area#y0);
        let tw = Int32.toFloat64(target#x1 - target#x0);
        let th = Int32.toFloat64(target#y1 - target#y0);
        let scale = if (rw <= 0.0 or rh <= 0.0) 0.0 else minF(tw / rw, th / rh);
        let ox = Int32.toFloat64(target#x0) + (tw - rw * scale) / 2.0 - Int32.toFloat64(area#x0) * scale;
        let oy = Int32.toFloat64(target#y0) + (th - rh * scale) / 2.0 - Int32.toFloat64(area#y0) * scale;
        {scale = scale, ox = ox, oy = oy}

    def minF(a: Float64, b: Float64): Float64 = if (a < b) a else b

    /// 矩形リストの union bbox（空なら原点ゼロ矩形）。
    pub def boundsOf(rects: List[GridRect]): GridRect =
        match rects {
            case Nil           => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                List.foldLeft((a, r) -> ({
                    x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                    x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                    first, rest)
        }

    /// スケールは `scaleArea`（フロア全体）を `target` に収める倍率で固定し、配置は
    /// `content`（探索済みコンテンツ）の **左下** を `target` の左下に合わせる。
    /// これで「探索しても拡大率は一定」「左下の部屋は常に画面左下（マージン内）」になる。
    pub def anchorBL(scaleArea: GridRect, content: GridRect, target: GridRect): Fit =
        anchorBLWithScale(fitTransform(scaleArea, target)#scale, content, target)

    /// `anchorBL` の **scale 固定版**。倍率を呼び出し側が決め、`content` の左下 (x0, y1) を
    /// `target` の左下 (x0, y1) へ合わせる。mapCell(c) = o + c*scale。
    pub def anchorBLWithScale(scale: Float64, content: GridRect, target: GridRect): Fit =
        let ox = Int32.toFloat64(target#x0) - Int32.toFloat64(content#x0) * scale;
        let oy = Int32.toFloat64(target#y1) - Int32.toFloat64(content#y1) * scale;
        {scale = scale, ox = ox, oy = oy}

    /// grid セル → minimap ピクセル（セル左上）。
    pub def mapCell(cell: {x = Int32, y = Int32}, t: Fit): Vec2 =
        {x = t#ox + Int32.toFloat64(cell#x) * t#scale,
         y = t#oy + Int32.toFloat64(cell#y) * t#scale}

    /// world-grid 矩形 → minimap ピクセル矩形（左上 pos + size）。
    pub def mapRect(r: GridRect, t: Fit): {pos = Vec2, size = Vec2} =
        let pos = mapCell(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}), t);
        let size: Vec2 = {x = Int32.toFloat64(r#x1 - r#x0) * t#scale,
                          y = Int32.toFloat64(r#y1 - r#y0) * t#scale};
        {pos = pos, size = size}

    /// 訪問済み module → 描画すべき矩形リスト（idx < roomCount を部屋、それ以外を通路と判定）。
    pub def visitedRects(visited: Set[Int32],
                          placements: List[DungeonComposer.ModulePlacement],
                          roomCount: Int32): List[{idx = Int32, isRoom = Bool, rect = GridRect}] =
        placements
            |> List.filter(p -> Set.memberOf(p#idx, visited))
            |> List.map(p -> {idx = p#idx, isRoom = p#idx < roomCount,
                              rect = FogScene.moduleRect(p)})

    /// 訪問済み module に隣接する「未訪問の通路」idx の集合（出口ヒント）。
    /// 通路が描かれることで「その先にまだ部屋＝行けるエリアがある」ことをプレイヤーに示す。
    /// 通路だけを出し、その先の未訪問の部屋自体は出さない（探索の楽しみを残す）。
    pub def corridorHints(visited: Set[Int32],
                           placements: List[DungeonComposer.ModulePlacement],
                           roomCount: Int32): Set[Int32] =
        placements
            |> List.filter(p -> p#idx >= roomCount)               // 通路のみ
            |> List.filter(p -> not Set.memberOf(p#idx, visited)) // 未訪問のみ
            |> List.filter(p -> adjacentToVisited(p, visited, placements))
            |> List.map(p -> p#idx)
            |> List.toSet

    def adjacentToVisited(c: DungeonComposer.ModulePlacement,
                           visited: Set[Int32],
                           placements: List[DungeonComposer.ModulePlacement]): Bool =
        placements
            |> List.filter(v -> Set.memberOf(v#idx, visited))
            |> List.exists(v -> bboxesAdjacent(c, v))

    /// 2 つの module の floorBounds bbox が隣接（1 タイル膨張で交差）するか。
    def bboxesAdjacent(a: DungeonComposer.ModulePlacement,
                        b: DungeonComposer.ModulePlacement): Bool =
        let aMinX = a#offset#x + a#floorBoundsMin#x - 1;
        let aMinY = a#offset#y + a#floorBoundsMin#y - 1;
        let aMaxX = a#offset#x + a#floorBoundsMaxEx#x + 1;
        let aMaxY = a#offset#y + a#floorBoundsMaxEx#y + 1;
        let bMinX = b#offset#x + b#floorBoundsMin#x;
        let bMinY = b#offset#y + b#floorBoundsMin#y;
        let bMaxX = b#offset#x + b#floorBoundsMaxEx#x;
        let bMaxY = b#offset#y + b#floorBoundsMaxEx#y;
        aMinX < bMaxX and aMaxX > bMinX and aMinY < bMaxY and aMaxY > bMinY

    /// 描画対象 module（訪問済み ＋ 出口ヒント通路）の moduleRect リスト（壁リング込み）。
    /// 青ベタ塗りは壁リング込みの bbox（`FogScene.moduleRect`）を使う。床だけの bbox では
    /// 通路（1 幅の床）に脇壁が無く全部黒く抜けてしまうため、壁リングまで青で覆ってから
    /// 歩ける床セルを黒くくり抜く（通路にも青い脇壁が残る）。
    pub def displayedModuleRects(visited: Set[Int32],
                                  placements: List[DungeonComposer.ModulePlacement],
                                  roomCount: Int32): List[GridRect] =
        let display = Set.union(visited, corridorHints(visited, placements, roomCount));
        placements
            |> List.filter(p -> Set.memberOf(p#idx, display))
            |> List.map(FogScene.moduleRect)

    /// 矩形群の union を「互いに重ならない矩形群」に分割する（横バンド分割）。
    /// `FogScene.bandDecompose` が補集合を返すのに対し、こちらは union（被覆部）を返す。
    /// 半透明描画でも重なりによる濃淡ムラが出ないよう、部屋・通路を一体化するのに使う。
    pub def unionBands(rects: List[GridRect]): List[GridRect] =
        let ys = sortedDistinct(rects |> List.flatMap(r -> r#y0 :: r#y1 :: Nil));
        consecutivePairs(ys) |> List.flatMap(band -> {
            let (ya, yb) = band;
            // このバンド [ya,yb) を縦に跨ぐ矩形の x 区間をマージ（被覆区間）。
            let intervals = rects
                |> List.filter(r -> r#y0 <= ya and r#y1 >= yb)
                |> List.map(r -> (r#x0, r#x1))
                |> List.sortBy(iv -> fst(iv))
                |> mergeIntervals;
            intervals |> List.map(iv -> {
                let (gx0, gx1) = iv;
                ({x0 = gx0, y0 = ya, x1 = gx1, y1 = yb}: GridRect)
            })
        })

    // FogScene のバンド分割は「霧として覆う補集合」を返すため流用できない。
    // ミニマップは被覆部（union）が必要なので、同一アルゴリズムをここで再実装している。

    def sortedDistinct(xs: List[Int32]): List[Int32] = dedupSorted(List.sort(xs))

    def dedupSorted(xs: List[Int32]): List[Int32] = match xs {
        case a :: b :: rest => if (a == b) dedupSorted(b :: rest) else a :: dedupSorted(b :: rest)
        case _              => xs
    }

    def consecutivePairs(xs: List[Int32]): List[(Int32, Int32)] = match xs {
        case a :: b :: rest => (a, b) :: consecutivePairs(b :: rest)
        case _              => Nil
    }

    /// x0 昇順ソート済みの区間列を、重なり・隣接を結合する。
    def mergeIntervals(xs: List[(Int32, Int32)]): List[(Int32, Int32)] = match xs {
        case Nil               => Nil
        case (a0, a1) :: rest  => mergeGo(a0, a1, rest)
    }

    def mergeGo(c0: Int32, c1: Int32, rest: List[(Int32, Int32)]): List[(Int32, Int32)] = match rest {
        case Nil              => (c0, c1) :: Nil
        case (b0, b1) :: more =>
            if (b0 <= c1) mergeGo(c0, Int32.max(c1, b1), more)
            else (c0, c1) :: mergeGo(b0, b1, more)
    }
}
