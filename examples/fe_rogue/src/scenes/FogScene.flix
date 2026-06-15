/// FogScene — フォグ・オブ・ウォー（画面全体モヤ＋現在部屋を矩形で切り抜き）
///
/// 画面全体を薄暗いモヤで覆い、「`hidden` でないパーティメンバーがいる部屋/通路(module)」
/// だけをモヤから矩形に切り抜いて明るくする。毎フレーム再計算するので、部屋を出れば
/// その部屋は再びモヤに沈む（非永続）。敵・アイテム・階段は明るい部屋以外では非表示。
///
/// モヤは加算（暗くする）合成なので「穴」を直接は空けられない。そこで
/// 「マップ全体を覆う領域(area) から 明るい部屋矩形(holes) を除いた補集合」を
/// 矩形で敷き詰める（バンド分割 `bandDecompose`）。敷き詰めた矩形は固定プールの
/// ColorRect に毎フレーム割り当てて再配置する。
///
/// ノード構造:
///   Fog (Marker2D, NoTag)                          ← root 直下。モヤ矩形プールの親
///     ├─ Fog_0 .. Fog_{poolSize-1} (ColorRect)     ← 毎フレーム再配置（補集合の矩形）
///   World/FogDriver (Marker2D, NodeTag.FogDriver)   ← process redef で毎フレーム applyFog

/// グリッド座標の矩形（半開区間 [x0,x1) × [y0,y1)）。
pub type alias GridRect = {x0 = Int32, y0 = Int32, x1 = Int32, y1 = Int32}

mod FogScene {

    def fogName(): String = "Fog"
    def rectChildName(i: Int32): String = "Fog_${i}"
    def rectChildPath(i: Int32): NodePath = fogName() :: rectChildName(i) :: Nil
    def driverName(): String = "FogDriver"

    /// モヤの色（暗い青灰）と不透明度。地形がうっすら見える程度に薄暗くする。
    /// 視認性とパフォーマンスのトレードオフ調整点。
    def fogColor(): Color = {r = 0.04f32, g = 0.05f32, b = 0.10f32}
    def fogAlpha(): Float32 = 0.66f32

    /// モヤ矩形の zIndex。Floor=-1 / Walls=0 の上、Item(4,5)/Unit(10) の下。
    /// 可視性制御は z 順ではなく visible=false で行うため z 競合しない。
    def fogZIndex(): Int32 = 2

    /// 明るい部屋矩形を floorBounds から外側へ広げるタイル数（壁リングまで明るくする）。tunable。
    def edgePad(): Int32 = 1

    /// モヤで覆う領域をマップ bbox の外側へ広げるタイル数（画面端まで確実にモヤで覆うため）。
    def marginTiles(): Int32 = 60

    /// 補集合矩形を割り当てる ColorRect プールのサイズ。bandDecompose が生成する矩形数は
    /// holes 数とバンド分割数の積で増えるが、実ダンジョン規模では経験的にこの値で十分足りる。
    def poolSize(): Int32 = 24

    /// モヤ矩形プール（poolSize 個、初期非表示）と常駐 FogDriver を scene tree に追加する。
    /// `GameLifecycle.buildPlayingScene` で MapScene.add の直後に 1 回だけ呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] =
        let withParent =
            Scene.addNode(fogName(),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.NoTag),
                scene);
        let withPool =
            List.foldLeft((acc, i) -> {
                let rect = ColorRect.make(Vec2.zero(), fogColor())
                            |> ColorRect.setAlpha(fogAlpha())
                            |> CanvasItem.setZIndex(fogZIndex())
                            |> CanvasItem.setVisible(false);
                Scene.addChild(fogName(), rectChildName(i),
                    EngineNode.ColorRectWithState(rect, NodeTag.NoTag), acc)
            }, withParent, List.range(0, poolSize()));
        Scene.addChild(MapScene.worldName(), driverName(),
            EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.FogDriver),
            withPool)

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から `NodeTag.FogDriver`
    /// ノードに対して dispatch される per-frame entry。集合モード中は通路を松明照らしにする。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     _path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) \ TurnPhase.State =
        let torch = isTorchPhase(TurnPhase.State.get());
        (node, applyFog(torch, scene))

    /// 松明照らし（通路では周囲1マスだけ照らす、シレン準拠）にするフェーズか。
    /// 集合（行軍）モード = 主人公が隊列を率いて単独で動き回る状態のみ該当。
    def isTorchPhase(phase: TurnPhase.Phase): Bool =
        phase == TurnPhase.Phase.GatherMove

    /// 画面全体モヤ＋明るい穴の切り抜き、および敵/アイテム/階段の可視性を一括更新する（純粋）。
    /// torchCorridors=true（集合モード）のとき、通路にいるプレイヤーは通路全体ではなく
    /// 周囲1マス（松明）だけを明るい穴にする（シレン準拠）。
    pub def applyFog(torchCorridors: Bool, scene: Scene[NodeTag]): Scene[NodeTag] =
        let placements = MapScene.getPlacements(scene);
        let roomCount  = MapScene.getRoomCount(scene);
        let holes      = holesFor(PlayerScene.getAll(scene), placements, roomCount, torchCorridors);
        let area       = mapRegion(placements);
        let hazeRects  = bandDecompose(area, holes);
        // isLit クロージャは「let 束縛の最後」に置く（Flix 0.71.0 以降、lambda を let で
        // 束縛した後に更に let を続けるとパーサが lambda 本体を貪欲に取り込んで壊れるため）。
        let isLit      = (cell: {x = Int32, y = Int32}) -> insideAny(cell, holes);
        scene
            |> applyHazePool(hazeRects)
            |> EnemyScene.applyFog(isLit)
            |> ItemScene.applyFog(isLit)
            |> StairsScene.applyFog(isLit)
            |> ChestScene.applyFog(isLit)

    /// 非 hidden プレイヤーごとの「明るい穴」矩形リスト（純粋・テスト対象）。
    /// 部屋なら部屋全体、通路は torchCorridors のとき周囲1マスだけ。
    /// 行多相シグネチャにより PlayerScene.Data 以外（CursorScene 等）からも呼べる汎用 API。
    pub def holesFor(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                      placements: List[DungeonComposer.ModulePlacement],
                      roomCount: Int32, torchCorridors: Bool): List[GridRect] =
        units
            |> List.filter(d -> not d#hidden)
            |> List.filterMap(d -> holeFor(d#gridPos, placements, roomCount, torchCorridors))

    /// 1 プレイヤーの明るい穴。通路では module 矩形ではなく周囲1マスに絞るのは、
    /// 通路全体が一気に見えないシレン準拠のサプライズ感を保つため。
    def holeFor(cell: {x = Int32, y = Int32},
                 placements: List[DungeonComposer.ModulePlacement],
                 roomCount: Int32, torch: Bool): Option[GridRect] =
        match MapSnapshot.moduleOfCellIn(cell, placements) {
            case None    => if (torch) Some(torchRect(cell)) else None
            case Some(m) =>
                if (torch and m >= roomCount) Some(torchRect(cell))
                else moduleRectByIdx(m, placements)
        }

    /// module idx → moduleRect。未配置 idx は None（DungeonComposer が idx を連番で振るため通常起きない）。
    def moduleRectByIdx(m: Int32, placements: List[DungeonComposer.ModulePlacement]): Option[GridRect] =
        List.find(p -> p#idx == m, placements) |> Option.map(moduleRect)

    /// セルの周囲 torchRadius マス（半開区間）の矩形。
    def torchRadius(): Int32 = 1
    def torchRect(cell: {x = Int32, y = Int32}): GridRect =
        let rad = torchRadius();
        ({x0 = cell#x - rad, y0 = cell#y - rad,
          x1 = cell#x + rad + 1, y1 = cell#y + rad + 1}: GridRect)

    /// セルがいずれかの矩形の内側か（半開区間 [x0,x1) × [y0,y1)）。
    /// フォグの穴判定と CursorScene の移動可動域判定で共用するため pub に公開する。
    pub def insideAny(cell: {x = Int32, y = Int32}, holes: List[GridRect]): Bool =
        List.exists(h ->
            cell#x >= h#x0 and cell#x < h#x1 and cell#y >= h#y0 and cell#y < h#y1, holes)

    /// GridRect を四方に n タイル広げる（Chebyshev 拡張）。半開区間なので x1/y1 は + n。
    def dilate(r: GridRect, n: Int32): GridRect =
        ({x0 = r#x0 - n, y0 = r#y0 - n, x1 = r#x1 + n, y1 = r#y1 + n}: GridRect)

    /// カーソルが動ける範囲の矩形群。
    ///   - いま明るい部屋（holesFor, torch=false）を radius タイル四方に拡張したもの
    ///   - すでに訪れた module（visited）の矩形（moduleRect, 壁リング込み）
    /// の和。CursorScene が候補セルの可否判定（insideAny）に使う。純粋（テスト対象）。
    /// PlayerCursor フェーズは torchCorridors=false なので holesFor は各非 hidden
    /// プレイヤーの module 矩形を返す。明るい部屋は visited にも含まれるが、litExpanded が
    /// +radius の余白を足す（visited 矩形は余白なし＝「行った部屋まで」）。
    pub def cursorRangeRects(units: List[{gridPos = {x = Int32, y = Int32}, hidden = Bool | r}],
                              placements: List[DungeonComposer.ModulePlacement],
                              roomCount: Int32, visited: Set[Int32],
                              radius: Int32): List[GridRect] =
        let litExpanded  = holesFor(units, placements, roomCount, false)
                            |> List.map(rc -> dilate(rc, radius));
        let visitedRects = placements
                            |> List.filter(p -> Set.memberOf(p#idx, visited))
                            |> List.map(moduleRect);
        List.append(litExpanded, visitedRects)

    /// 補集合矩形リストを ColorRect プールに割り当てる。余ったプールは非表示にする。
    def applyHazePool(rects: List[GridRect], scene: Scene[NodeTag]): Scene[NodeTag] =
        let used = List.length(rects);
        // 先頭 used 個を配置・表示
        let withActive =
            List.foldLeft((acc, entry) -> {
                let (i, r) = entry;
                if (i < poolSize()) setPoolRect(i, r, acc) else acc
            }, scene, List.zipWithIndex(rects));
        // 残りを非表示
        List.foldLeft((acc, i) ->
            if (i >= used) hidePoolRect(i, acc) else acc,
            withActive, List.range(0, poolSize()))

    /// プール i の ColorRect を矩形 r に合わせて配置・表示する。
    def setPoolRect(i: Int32, r: GridRect, scene: Scene[NodeTag]): Scene[NodeTag] =
        let s = MapSnapshot.tileSize();
        let posV  = Vec2i.toVec2(({x = r#x0, y = r#y0}: {x = Int32, y = Int32}));
        let sizeV = Vec2i.toVec2(({x = r#x1 - r#x0, y = r#y1 - r#y0}: {x = Int32, y = Int32}));
        let pos:  Vec2.Vec2 = {x = posV#x * s, y = posV#y * s};
        let size: Vec2.Vec2 = {x = sizeV#x * s, y = sizeV#y * s};
        Scene.mapEngineNode(rectChildPath(i),
            n -> EngineNode.mapColorRect(c ->
                c |> ColorRect.setSize(size)
                  |> Node2D.setPosition(pos)
                  |> CanvasItem.setVisible(true), n),
            scene)

    def hidePoolRect(i: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rectChildPath(i),
            n -> EngineNode.mapColorRect(c -> CanvasItem.setVisible(false, c), n), scene)

    /// module の floorBounds(±edgePad で壁リングまで拡張) を world grid 矩形にする。
    pub def moduleRect(p: DungeonComposer.ModulePlacement): GridRect =
        { x0 = p#offset#x + p#floorBoundsMin#x   - edgePad(),
          y0 = p#offset#y + p#floorBoundsMin#y   - edgePad(),
          x1 = p#offset#x + p#floorBoundsMaxEx#x + edgePad(),
          y1 = p#offset#y + p#floorBoundsMaxEx#y + edgePad() }

    /// モヤで覆う領域 = 全 module の moduleRect の union を marginTiles だけ外へ広げたもの。
    pub def mapRegion(placements: List[DungeonComposer.ModulePlacement]): GridRect =
        match List.map(moduleRect, placements) {
            case Nil          => ({x0 = 0, y0 = 0, x1 = 0, y1 = 0}: GridRect)
            case first :: rest =>
                let u = List.foldLeft((a, r) -> ({
                            x0 = Int32.min(a#x0, r#x0), y0 = Int32.min(a#y0, r#y0),
                            x1 = Int32.max(a#x1, r#x1), y1 = Int32.max(a#y1, r#y1)}: GridRect),
                        first, rest);
                let m = marginTiles();
                ({x0 = u#x0 - m, y0 = u#y0 - m, x1 = u#x1 + m, y1 = u#y1 + m}: GridRect)
        }

    /// `area` から `holes`（明るい部屋の矩形群）を除いた補集合を、重なりのない矩形群へ
    /// 分割する（横バンド分割）。純粋関数（テスト対象）。
    pub def bandDecompose(area: GridRect, holes: List[GridRect]): List[GridRect] =
        // area に clamp して空矩形を除去
        let clamped = holes |> List.filterMap(h -> {
            let x0 = Int32.max(h#x0, area#x0);
            let y0 = Int32.max(h#y0, area#y0);
            let x1 = Int32.min(h#x1, area#x1);
            let y1 = Int32.min(h#y1, area#y1);
            if (x0 < x1 and y0 < y1) Some(({x0 = x0, y0 = y0, x1 = x1, y1 = y1}: GridRect))
            else None
        });
        let ys = sortedDistinct(area#y0 :: area#y1 ::
                    (clamped |> List.flatMap(h -> h#y0 :: h#y1 :: Nil)));
        consecutivePairs(ys) |> List.flatMap(band -> {
            let (ya, yb) = band;
            // このバンド [ya,yb) を縦に跨ぐ hole の x 区間
            let intervals = clamped
                |> List.filter(h -> h#y0 <= ya and h#y1 >= yb)
                |> List.map(h -> (h#x0, h#x1))
                |> List.sortBy(iv -> fst(iv))
                |> mergeIntervals;
            xGaps(area#x0, area#x1, intervals)
                |> List.map(g -> {
                    let (gx0, gx1) = g;
                    ({x0 = gx0, y0 = ya, x1 = gx1, y1 = yb}: GridRect)
                })
        })

    /// 昇順ソート＋重複除去。
    def sortedDistinct(xs: List[Int32]): List[Int32] = dedupSorted(List.sort(xs))

    def dedupSorted(xs: List[Int32]): List[Int32] = match xs {
        case a :: b :: rest => if (a == b) dedupSorted(b :: rest) else a :: dedupSorted(b :: rest)
        case _              => xs
    }

    /// 連続ペア [a,b,c] -> [(a,b),(b,c)]。bandDecompose でバンド境界の y 区間を生成するために使う。
    def consecutivePairs(xs: List[Int32]): List[(Int32, Int32)] = match xs {
        case a :: b :: rest => (a, b) :: consecutivePairs(b :: rest)
        case _              => Nil
    }

    /// x0 昇順ソート済みの区間列を、重なり・隣接を結合する。
    /// 隣接 hole が重なったとき余分な矩形が生まれないよう、xGaps 適用前に呼ぶ。
    def mergeIntervals(xs: List[(Int32, Int32)]): List[(Int32, Int32)] = match xs {
        case Nil               => Nil
        case (a0, a1) :: rest  => mergeGo(a0, a1, rest)
    }

    /// 不変条件: c0 <= c1 を維持しながら現在の区間 [c0,c1) に次の区間を結合または確定させる。
    def mergeGo(c0: Int32, c1: Int32, rest: List[(Int32, Int32)]): List[(Int32, Int32)] = match rest {
        case Nil              => (c0, c1) :: Nil
        case (b0, b1) :: more =>
            if (b0 <= c1) mergeGo(c0, Int32.max(c1, b1), more)
            else (c0, c1) :: mergeGo(b0, b1, more)
    }

    /// [lo,hi) から（マージ済み・昇順の）区間群を除いた隙間を返す。
    def xGaps(lo: Int32, hi: Int32, intervals: List[(Int32, Int32)]): List[(Int32, Int32)] =
        match intervals {
            case Nil              => if (lo < hi) (lo, hi) :: Nil else Nil
            case (a0, a1) :: rest =>
                let gap = if (lo < a0) ((lo, a0): (Int32, Int32)) :: Nil else Nil;
                List.append(gap, xGaps(Int32.max(lo, a1), hi, rest))
        }
}
